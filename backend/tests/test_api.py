import io
import sqlite3
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from PIL import Image
from app.main import create_app


@pytest.fixture
def setup(tmp_path):
    app = create_app(tmp_path, Fernet.generate_key(), ocr_enabled=False)
    with TestClient(app) as client:
        yield client, app.state.store


def register(client, email="patient@example.com"):
    r = client.post(
        "/api/auth/register",
        json={"name": "Patient One", "email": email, "password": "Long-password-123"},
    )
    assert r.status_code == 201, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}, r.json()


def upload(client, headers, client_id="photo-12345678"):
    image = io.BytesIO()
    Image.new("RGB", (100, 100), "white").save(image, format="PNG")
    return client.post(
        "/api/documents",
        headers=headers,
        data={"client_id": client_id, "kind": "Prescription", "language": "eng"},
        files={"file": ("prescription.png", image.getvalue(), "image/png")},
    )


def test_auth_isolation_logout_and_encryption(setup):
    c, store = setup
    h, user = register(c)
    state = c.get("/api/state", headers=h).json()
    assert state["state"]["medicines"] == []
    assert c.get("/api/state").status_code == 401
    other, _ = register(c, "other@example.com")
    changed = state["state"]
    changed["allergies"] = "Private allergy phrase"
    assert (
        c.post(
            "/api/sync",
            headers=h,
            json={"event_id": "change-123456", "base_version": 0, "state": changed},
        ).status_code
        == 200
    )
    assert c.get("/api/state", headers=other).json()["state"]["allergies"] == ""
    with store.db() as db:
        payload = db.execute(
            "SELECT payload FROM states WHERE user_id=?", (user["user_id"],)
        ).fetchone()["payload"]
        assert b"Private allergy phrase" not in payload
    assert c.post("/api/auth/logout", headers=h).status_code == 204
    assert c.get("/api/state", headers=h).status_code == 401


def test_sync_idempotency_conflict_and_validation(setup):
    c, _ = setup
    h, _ = register(c)
    state = c.get("/api/state", headers=h).json()["state"]
    body = {"event_id": "change-123456", "base_version": 0, "state": state}
    assert c.post("/api/sync", headers=h, json=body).json()["version"] == 1
    assert c.post("/api/sync", headers=h, json=body).json()["duplicate"] is True
    assert (
        c.post(
            "/api/sync", headers=h, json={**body, "event_id": "another-123456"}
        ).status_code
        == 409
    )
    changed = {**state, "budget": 900}
    assert (
        c.post("/api/sync", headers=h, json={**body, "state": changed}).status_code
        == 409
    )
    assert (
        c.post(
            "/api/sync",
            headers=h,
            json={
                **body,
                "event_id": "valid-12345678",
                "base_version": 1,
                "state": {**state, "budget": -1},
            },
        ).status_code
        == 422
    )


def test_document_upload_ownership_and_real_ocr_state(setup):
    c, store = setup
    h, _ = register(c)
    other, _ = register(c, "other@example.com")
    r = upload(c, h)
    assert r.status_code == 201, r.text
    doc = r.json()
    assert doc["ocr_text"] == "" and doc["ocr_status"] == "manual_review_required"
    assert (
        c.get("/api/documents/" + doc["id"], headers=h).headers["content-type"]
        == "image/jpeg"
    )
    assert c.get("/api/documents/" + doc["id"], headers=other).status_code == 404
    assert upload(c, h).json()["id"] == doc["id"]
    assert not (store.files / doc["id"]).read_bytes().startswith(b"\xff\xd8")
    bad = c.post(
        "/api/documents",
        headers=h,
        data={"client_id": "bad", "kind": "Prescription"},
        files={"file": ("x.png", b"not-image", "image/png")},
    )
    assert bad.status_code == 415


def test_consented_clinician_review_and_revision(setup):
    c, store = setup
    h, _ = register(c)
    other, _ = register(c, "other@example.com")
    store.create_user("doctor@example.com", "Long-password-123", "Doctor", "clinician")
    login = c.post(
        "/api/auth/login",
        json={"email": "doctor@example.com", "password": "Long-password-123"},
    ).json()
    doctor = {"Authorization": "Bearer " + login["token"]}
    doc = upload(c, h).json()
    assert c.get("/api/documents/" + doc["id"], headers=doctor).status_code == 404
    body = {
        "reason": "Please review my prescription",
        "document_ids": [doc["id"]],
        "consent": False,
    }
    assert c.post("/api/cases", headers=h, json=body).status_code == 422
    r = c.post("/api/cases", headers=h, json={**body, "consent": True})
    assert r.status_code == 201
    case = r.json()
    assert c.get("/api/cases", headers=other).json() == []
    assert c.get("/api/documents/" + doc["id"], headers=doctor).status_code == 200
    assert (
        c.patch(
            "/api/cases/" + case["id"],
            headers=h,
            json={"expected_version": 1, "status": "completed", "note": "test"},
        ).status_code
        == 403
    )
    review = {
        "expected_version": 1,
        "status": "completed",
        "note": "Reviewed source and requested a follow-up visit.",
    }
    r = c.patch("/api/cases/" + case["id"], headers=doctor, json=review)
    assert r.status_code == 200
    assert r.json()["version"] == 2
    assert (
        c.patch("/api/cases/" + case["id"], headers=doctor, json=review).status_code
        == 409
    )
    assert (
        c.get("/api/cases", headers=h).json()[0]["notes"][0]["text"] == review["note"]
    )
    assert c.get("/api/operations", headers=doctor).json()["counts"]["completed"] == 1
    assert c.get("/api/audit", headers=h).status_code == 403
    assert any(
        a["action"] == "case.completed"
        for a in c.get("/api/audit", headers=doctor).json()
    )


def test_source_reference_must_belong_to_patient(setup):
    c, _ = setup
    h, _ = register(c)
    state = c.get("/api/state", headers=h).json()["state"]
    med = {
        "id": "m1",
        "name": "Entered medicine",
        "quantity": 2,
        "unit_price_minor": 125,
        "source_document_id": "missing",
    }
    state["medicines"] = [med]
    r = c.post(
        "/api/sync",
        headers=h,
        json={"event_id": "source-123456", "base_version": 0, "state": state},
    )
    assert r.status_code == 422


def test_dashboard_has_no_public_patient_data(setup):
    c, _ = setup
    assert c.get("/care-team").status_code == 200
    assert c.get("/api/cases").status_code == 401
    assert "script-src 'self'" in c.get("/care-team").headers["content-security-policy"]


def test_records_survive_restart_and_clinician_payload_is_minimized(setup):
    c, store = setup
    h, user = register(c)
    state = c.get("/api/state", headers=h).json()["state"]
    state.update(
        {
            "journal": "Private journal must stay private",
            "mood": "Private mood",
            "budget": 12345,
            "medicines": [
                {
                    "id": "medicine-1",
                    "name": "User entered item",
                    "quantity": 30,
                    "unit_price_minor": 125,
                    "verified": True,
                }
            ],
            "vitals": [
                {
                    "id": "vital-1",
                    "kind": "heart_rate",
                    "value": 76,
                    "unit": "bpm",
                    "measured_at": "2026-01-01T10:00:00+00:00",
                    "source": "manual",
                }
            ],
        }
    )
    assert (
        c.post(
            "/api/sync",
            headers=h,
            json={"event_id": "restart-12345", "base_version": 0, "state": state},
        ).status_code
        == 200
    )
    with TestClient(create_app(store.root, store.key, ocr_enabled=False)) as restarted:
        result = restarted.get("/api/state", headers=h)
        assert result.status_code == 200
        assert result.json()["state"]["vitals"][0]["value"] == 76
    result = c.post(
        "/api/cases",
        headers=h,
        json={
            "reason": "Please review this entered medication",
            "document_ids": [],
            "consent": True,
        },
    )
    assert result.status_code == 201
    shared = c.get("/api/cases", headers=h).json()[0]["snapshot"]["state"]
    assert "journal" not in shared and "mood" not in shared and "budget" not in shared
    assert "unit_price_minor" not in shared["medicines"][0]


def test_reject_mismatched_measurement_units_and_duplicate_medicine_ids(setup):
    c, _ = setup
    h, _ = register(c)
    state = c.get("/api/state", headers=h).json()["state"]
    state["vitals"] = [
        {
            "id": "v1",
            "kind": "heart_rate",
            "value": 76,
            "unit": "mg/dL",
            "measured_at": "2026-01-01T10:00:00+00:00",
        }
    ]
    assert (
        c.post(
            "/api/sync",
            headers=h,
            json={"event_id": "bad-vital-123", "base_version": 0, "state": state},
        ).status_code
        == 422
    )
    state["vitals"] = []
    med = {"id": "same", "name": "Entered item", "quantity": 1, "unit_price_minor": 0}
    state["medicines"] = [med, med]
    assert (
        c.post(
            "/api/sync",
            headers=h,
            json={"event_id": "bad-meds-123", "base_version": 0, "state": state},
        ).status_code
        == 422
    )


def test_patient_cannot_register_as_clinician_or_share_other_users_document(setup):
    c, _ = setup
    assert (
        c.post(
            "/api/auth/register",
            json={
                "name": "User",
                "email": "x@example.com",
                "password": "Long-password-123",
                "role": "clinician",
            },
        ).status_code
        == 422
    )
    h, _ = register(c)
    other, _ = register(c, "other@example.com")
    doc = upload(c, h).json()
    assert (
        c.post(
            "/api/cases",
            headers=other,
            json={
                "reason": "Attempting to share wrong document",
                "document_ids": [doc["id"]],
                "consent": True,
            },
        ).status_code
        == 422
    )


def test_optional_ocr_reads_real_printed_image_without_generating_medicines(setup):
    import shutil

    if not shutil.which("tesseract"):
        pytest.skip("Tesseract not installed")
    from PIL import ImageDraw, ImageFont

    c, store = setup
    h, _ = register(c)
    image = Image.new("RGB", (1200, 300), "white")
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 40)
    except OSError:
        font = ImageFont.load_default()
    draw.text(
        (30, 35),
        "MEDICATION REPORT\nMETFORMIN 500 MG\nPHYSICIAN REVIEW REQUIRED",
        font=font,
        fill="black",
        spacing=15,
    )
    data = io.BytesIO()
    image.save(data, format="PNG")
    with TestClient(create_app(store.root, store.key, ocr_enabled=True)) as enabled:
        result = enabled.post(
            "/api/documents",
            headers=h,
            data={
                "client_id": "ocr-real-123456",
                "kind": "Prescription",
                "language": "eng",
            },
            files={"file": ("print.png", data.getvalue(), "image/png")},
        )
        assert result.status_code == 201, result.text
        doc = result.json()
        assert doc["ocr_engine"] == "tesseract"
        assert "500" in doc["ocr_text"]
        assert enabled.get("/api/state", headers=h).json()["state"]["medicines"] == []


def test_patient_can_withdraw_case_sharing(setup):
    c, store = setup
    h, _ = register(c)
    other, _ = register(c, "other@example.com")
    store.create_user("doctor@example.com", "Long-password-123", "Doctor", "clinician")
    token = c.post(
        "/api/auth/login",
        json={"email": "doctor@example.com", "password": "Long-password-123"},
    ).json()["token"]
    doctor = {"Authorization": "Bearer " + token}
    doc = upload(c, h).json()
    case = c.post(
        "/api/cases",
        headers=h,
        json={
            "reason": "Please review this document",
            "document_ids": [doc["id"]],
            "consent": True,
        },
    ).json()
    assert c.get("/api/documents/" + doc["id"], headers=doctor).status_code == 200
    assert (
        c.post("/api/cases/" + case["id"] + "/withdraw", headers=other).status_code
        == 404
    )
    assert (
        c.post("/api/cases/" + case["id"] + "/withdraw", headers=h).status_code == 200
    )
    assert c.get("/api/cases", headers=doctor).json() == []
    assert c.get("/api/documents/" + doc["id"], headers=doctor).status_code == 404
    assert c.get("/api/cases", headers=h).json()[0]["status"] == "withdrawn"
    assert (
        c.patch(
            "/api/cases/" + case["id"],
            headers=doctor,
            json={"expected_version": 2, "status": "completed", "note": "should fail"},
        ).status_code
        == 404
    )
