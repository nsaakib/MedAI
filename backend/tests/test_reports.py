import io
import shutil

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont
from app.main import create_app
from app.reports import detect_report
from test_api import register


def test_detection_does_not_guess_doctor_or_multi_test_type():
    found = detect_report("CBC\nHbA1c\nSigned by: Dr. Signer\nDate of birth: 2020-01-01")
    assert found["report_type"] is None
    assert found["requested_by"] is None
    assert found["report_date"] is None
    found = detect_report("Test name: TSH\nReferred by: Dr. Sample\nReport date: 2026-11-12")
    assert found["report_type"] == "tsh"
    assert found["requested_by"] == "Dr. Sample"
    assert found["report_date"] == "2026-11-12"


def upload_report(client, auth, source, kind="Lab Report"):
    return client.post("/api/documents", headers=auth,
                       data={"client_id": "sample-1", "kind": kind},
                       files={"file": ("report.png", source, "image/png")})


def image_bytes(image):
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def test_edit_persists_is_owner_only_and_keeps_source(tmp_path):
    key = Fernet.generate_key()
    with TestClient(create_app(tmp_path, key, ocr_enabled=False)) as client:
        owner, _ = register(client)
        stranger, _ = register(client, "stranger@example.com")
        source = image_bytes(Image.new("RGB", (100, 100), "white"))
        upload = upload_report(client, owner, source)
        assert upload.status_code == 201
        assert upload.json()["report_title"] == "Untitled report"
        path = "/api/documents/" + upload.json()["id"]
        original = client.get(path, headers=owner).content
        fields = {"report_type": "cbc", "requested_by": "Dr. Private Sample", "report_date": "2026-11-12"}
        assert client.patch(path + "/report", headers=stranger, json=fields).status_code == 404
        assert client.patch(path + "/report", headers=owner, json={**fields, "report_type": "invalid"}).status_code == 422
        assert client.patch(path + "/report", headers=owner, json=fields).json()["report_reviewed"]
        assert client.get(path, headers=owner).content == original
        assert client.get("/api/documents", headers=stranger).json() == []
        with client.app.state.store.db() as db:
            encrypted = db.execute("SELECT payload FROM documents").fetchone()["payload"]
            assert b"Dr. Private Sample" not in encrypted
    with TestClient(create_app(tmp_path, key, ocr_enabled=False)) as restarted:
        saved = restarted.get("/api/documents", headers=owner).json()[0]
        assert saved["report_title"] == "Blood count"
        assert saved["requested_by"] == "Dr. Private Sample"
        assert saved["report_date"] == "2026-11-12"
        assert upload_report(restarted, owner, source).json()["report_reviewed"] is True


@pytest.mark.skipif(not shutil.which("tesseract"), reason="Tesseract not installed")
def test_real_ocr_upload_identifies_lab_report(tmp_path):
    image = Image.new("RGB", (1400, 360), "white")
    font = ImageFont.truetype("DejaVuSans.ttf", 44)
    ImageDraw.Draw(image).multiline_text((25, 30), "Complete Blood Count\nRequested by: Dr. Sample\nReport date: 2026-11-12", font=font, fill="black", spacing=18)
    with TestClient(create_app(tmp_path, Fernet.generate_key(), ocr_enabled=True)) as client:
        owner, _ = register(client)
        result = upload_report(client, owner, image_bytes(image))
        assert result.status_code == 201
        report = result.json()
        assert report["report_type"] == "cbc"
        assert report["requested_by"] == "Dr. Sample"
        assert report["report_date"] == "2026-11-12"
        assert report["report_reviewed"] is False
