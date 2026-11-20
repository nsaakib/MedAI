import io
from datetime import datetime, timedelta, timezone
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from PIL import Image
from app.main import create_app
from app.live_docs import visible, clean_html


@pytest.fixture
def docs(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDAI_SOS_ENABLED", "0")
    app = create_app(str(tmp_path), Fernet.generate_key().decode(), ocr_enabled=False)
    with TestClient(app) as client:

        def account(email):
            r = client.post(
                "/api/auth/register",
                json={
                    "email": email,
                    "name": "Synthetic docs tester",
                    "password": "Synthetic-pass-2026",
                },
            )
            assert r.status_code == 201, r.text
            return r.json()["user_id"], {"Authorization": "Bearer " + r.json()["token"]}

        owner, h = account("docs-admin@example.test")
        other, patient = account("docs-patient@example.test")
        with app.state.store.db() as db:
            db.execute("INSERT INTO docs_admins VALUES(?,?)", (owner, "super_admin"))
        yield client, app, owner, h, patient


def publish(c, h):
    d = c.get("/api/docs/admin", headers=h).json()
    r = c.post(
        "/api/docs/admin/publish", headers=h, json={"base_revision": d["revision"]}
    )
    assert r.status_code == 200, r.text
    d = c.get("/api/docs/admin", headers=h).json()
    settings = d["settings"]
    settings.update(enabled=True, mode="immediate")
    r = c.put(
        "/api/docs/admin/settings",
        headers=h,
        json={"base_revision": d["revision"], "settings": settings},
    )
    assert r.status_code == 200, r.text


def test_default_off_and_no_private_information(docs):
    c, app, user, h, p = docs
    for path in [
        "/docs",
        "/api/docs/public",
        "/api/docs/export",
        "/docs/team/" + "a" * 32,
    ]:
        assert c.get(path).status_code == 403
    assert c.get("/docs/admin").status_code == 200
    assert c.get("/api/docs/admin").status_code == 401
    assert c.get("/api/docs/admin", headers=p).status_code == 403
    data = c.get("/api/docs/admin", headers=h).json()
    assert data["settings"]["start"].startswith("2027-06-10") and not data["visible"]
    publish(c, h)
    d = c.get("/api/docs/public").json()
    assert d["live"]["metrics"] is None
    text = str(d)
    for secret in [
        "docs-admin@example.test",
        "docs-patient@example.test",
        "Synthetic-pass-2026",
        str(app.state.store.path),
    ]:
        assert secret not in text
    assert c.get("/docs").status_code == 200
    assert c.get("/api/docs/export").status_code == 200


def test_draft_publish_versions_and_stale_updates(docs):
    c, app, user, h, p = docs
    publish(c, h)
    data = c.get("/api/docs/admin", headers=h).json()
    original = c.get("/api/docs/public").json()["document"]["title"]
    data["document"]["title"] = "Verified new document title"
    body = {"base_revision": data["revision"], "document": data["document"]}
    r = c.put("/api/docs/admin/draft", headers=h, json=body)
    assert r.status_code == 200, r.text
    assert c.get("/api/docs/public").json()["document"]["title"] == original
    assert c.put("/api/docs/admin/draft", headers=h, json=body).status_code == 409
    revision = r.json()["revision"]
    assert (
        c.post(
            "/api/docs/admin/publish", headers=h, json={"base_revision": revision}
        ).status_code
        == 200
    )
    assert (
        c.get("/api/docs/public").json()["document"]["title"]
        == "Verified new document title"
    )
    history = c.get("/api/docs/admin/versions", headers=h).json()
    assert len(history) >= 3
    version = history[-1]["id"]
    latest = c.get("/api/docs/admin", headers=h).json()["revision"]
    assert (
        c.post(
            f"/api/docs/admin/versions/{version}/restore",
            headers=h,
            json={"base_revision": latest},
        ).status_code
        == 200
    )
    assert c.get("/api/docs/admin", headers=h).json()["document"]["title"] == original
    assert (
        c.get("/api/docs/public").json()["document"]["title"]
        == "Verified new document title"
    )


def test_publishing_schedule_boundaries_and_off_override():
    start = datetime(2027, 6, 10, tzinfo=timezone(timedelta(hours=6)))
    end = start + timedelta(days=4, hours=23, minutes=59, seconds=59)
    data = {
        "published": {"title": "Synthetic"},
        "settings": {
            "enabled": True,
            "mode": "window",
            "start": start.isoformat(),
            "end": end.isoformat(),
            "duration_minutes": 60,
        },
    }
    for time, result in [
        (start.timestamp() - 1, False),
        (start.timestamp(), True),
        (end.timestamp(), True),
        (end.timestamp() + 1, False),
    ]:
        assert visible(data, time) == result
    data["settings"]["enabled"] = False
    assert not visible(data, start.timestamp() + 1)
    data["settings"].update(enabled=True, mode="duration")
    assert visible(data, start.timestamp() + 3599)
    assert not visible(data, start.timestamp() + 3601)


def test_window_validation_and_instant_switch_off(docs):
    c, app, user, h, p = docs
    publish(c, h)
    d = c.get("/api/docs/admin", headers=h).json()
    s = d["settings"]
    s["enabled"] = False
    assert (
        c.put(
            "/api/docs/admin/settings",
            headers=h,
            json={"base_revision": d["revision"], "settings": s},
        ).status_code
        == 200
    )
    assert (
        c.get("/api/docs/public").status_code == 403
        and c.get("/api/docs/export").status_code == 403
    )
    d = c.get("/api/docs/admin", headers=h).json()
    s = d["settings"]
    s["mode"] = "window"
    s["start"] = "2027-06-15T00:00:00+06:00"
    assert (
        c.put(
            "/api/docs/admin/settings",
            headers=h,
            json={"base_revision": d["revision"], "settings": s},
        ).status_code
        == 422
    )
    s["start"] = "2027-06-10T00:00:00"
    assert (
        c.put(
            "/api/docs/admin/settings",
            headers=h,
            json={"base_revision": d["revision"], "settings": s},
        ).status_code
        == 422
    )


def test_live_counts_routes_and_analytics_opt_in(docs):
    c, app, user, h, p = docs
    publish(c, h)
    before = c.get("/api/docs/admin", headers=h).json()
    assert before["live"]["metrics"]["accounts"] == 2
    assert before["live"]["system"]["api_endpoints"] == len(before["live"]["apis"])
    assert any(
        a["path"] == "/api/documents/{identifier}/classify"
        for a in before["live"]["apis"]
    )
    logout = next(a for a in before["live"]["apis"] if a["path"] == "/api/auth/logout")
    assert logout["access"].startswith("Authenticated")
    app.state.store.create_user(
        "third@example.test", "Synthetic-pass-2026", "Synthetic count"
    )
    after = c.get("/api/docs/admin", headers=h).json()
    assert after["live"]["metrics"]["accounts"] == 3
    settings = after["settings"]
    settings["public_analytics"] = True
    c.put(
        "/api/docs/admin/settings",
        headers=h,
        json={"base_revision": after["revision"], "settings": settings},
    )
    assert c.get("/api/docs/public").json()["live"]["metrics"]["accounts"] == 3
    assert "third@example.test" not in str(c.get("/api/docs/public").json())


def test_html_sanitizing_and_diagram_validation(docs):
    c, app, user, h, p = docs
    d = c.get("/api/docs/admin", headers=h).json()
    d["document"]["sections"][0][
        "body"
    ] = '<p onclick="alert(1)">Hello</p><script>alert(1)</script><a href="javascript:alert(1)">X</a><img src=x onerror=alert(1)>'
    body = {"base_revision": d["revision"], "document": d["document"]}
    assert c.put("/api/docs/admin/draft", headers=h, json=body).status_code == 200
    saved = c.get("/api/docs/admin", headers=h).json()
    html = saved["document"]["sections"][0]["body"]
    assert (
        "onclick" not in html
        and "<script" not in html
        and "javascript:" not in html
        and "<img" not in html
    )
    assert "<p>Hello</p>" in html
    section = next(
        s for s in saved["document"]["sections"] if s["source"] == "architecture"
    )
    section["diagram"]["edges"] = [[0, 100]]
    assert (
        c.put(
            "/api/docs/admin/draft",
            headers=h,
            json={"base_revision": saved["revision"], "document": saved["document"]},
        ).status_code
        == 422
    )


def test_admin_permission_for_every_mutation(docs):
    c, app, user, h, p = docs
    d = c.get("/api/docs/admin", headers=h).json()
    for path, method, body in [
        (
            "/api/docs/admin/draft",
            "PUT",
            {"base_revision": d["revision"], "document": d["document"]},
        ),
        (
            "/api/docs/admin/settings",
            "PUT",
            {"base_revision": d["revision"], "settings": d["settings"]},
        ),
        ("/api/docs/admin/publish", "POST", {"base_revision": d["revision"]}),
        (
            "/api/docs/admin/versions/1/restore",
            "POST",
            {"base_revision": d["revision"]},
        ),
    ]:
        assert c.request(method, path, headers=p, json=body).status_code == 403
    assert c.get("/api/docs/admin/versions", headers=p).status_code == 403
    assert c.get("/api/docs/admin/avatar/" + "a" * 32, headers=p).status_code == 403
    with app.state.store.db() as db:
        db.execute("DELETE FROM docs_admins WHERE user_id=?", (user,))
    assert c.get("/api/docs/admin", headers=h).status_code == 403


def test_avatar_resize_encrypted_and_publication_gate(docs):
    c, app, user, h, p = docs
    image = io.BytesIO()
    Image.new("RGB", (700, 350), "blue").save(image, format="JPEG")
    r = c.post(
        "/api/docs/admin/avatar",
        headers=h,
        files={"file": ("team.jpg", image.getvalue(), "image/jpeg")},
    )
    assert r.status_code == 201, r.text
    id = r.json()["id"]
    private = c.get("/api/docs/admin/avatar/" + id, headers=h)
    assert private.status_code == 200
    im = Image.open(io.BytesIO(private.content))
    assert im.size == (256, 256)
    assert (app.state.store.root / "docs_avatars" / id).read_bytes() != private.content
    publish(c, h)
    assert c.get("/docs/team/" + id).status_code == 404
    d = c.get("/api/docs/admin", headers=h).json()
    d["document"]["members"] = [
        {
            "id": "synthetic",
            "name": "Test Member",
            "role": "Test contributor",
            "email": "team@example.test",
            "avatar": id,
        }
    ]
    saved = c.put(
        "/api/docs/admin/draft",
        headers=h,
        json={"base_revision": d["revision"], "document": d["document"]},
    )
    assert saved.status_code == 200, saved.text
    assert c.get("/docs/team/" + id).status_code == 404
    c.post(
        "/api/docs/admin/publish",
        headers=h,
        json={"base_revision": saved.json()["revision"]},
    )
    assert c.get("/docs/team/" + id).status_code == 200
    assert c.get("/docs/team/" + id).headers["cache-control"] == "no-store"


def test_files_and_script_headers(docs):
    c, app, user, h, p = docs
    for filename in ["docs.js", "admin.js", "docs.css"]:
        r = c.get("/docs/assets/" + filename)
        assert (
            r.status_code == 200
            and "script-src 'self'" in r.headers["content-security-policy"]
        )
    assert c.get("/docs/assets/live_docs.py").status_code == 404
    assert (
        c.post(
            "/api/docs/admin/avatar",
            headers=h,
            files={"file": ("bad.jpg", b"not an image", "image/jpeg")},
        ).status_code
        == 415
    )


def test_read_only_relay_blocks_private_and_admin_paths(monkeypatch):
    from app.docs_public import create_relay
    import httpx

    calls = []

    class Client:
        def __init__(self, **kw):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            pass

        async def get(self, url):
            calls.append(url)
            return httpx.Response(
                403, content=b"Not published", headers={"content-type": "text/plain"}
            )

    monkeypatch.setattr(httpx, "AsyncClient", Client)
    with TestClient(create_relay()) as c:
        for path in [
            "/docs/admin",
            "/api/docs/admin",
            "/api/documents",
            "/health",
            "/docs/assets/admin.js",
            "/openapi.json",
        ]:
            assert c.get(path).status_code == 404
        assert not calls
        assert c.post("/api/docs/public").status_code == 404
        r = c.get(
            "/api/docs/public?token=DO_NOT_FORWARD",
            headers={"Authorization": "Bearer DO_NOT_FORWARD"},
        )
        assert r.status_code == 403 and r.headers["cache-control"] == "no-store"
        assert calls == ["http://127.0.0.1:8000/api/docs/public"]


def test_local_grant_and_revoke_preserve_account_and_password(tmp_path, monkeypatch):
    from app import docs_admin
    from app.core import Store

    root = tmp_path / "sos-local-sandbox"
    root.mkdir()
    key = Fernet.generate_key()
    (root / "sandbox.key").write_bytes(key)
    store = Store(root, key)
    owner = store.create_user(
        "local@example.test", "Existing-password-2026", "Existing account"
    )
    with store.db() as db:
        before = dict(db.execute("SELECT * FROM users WHERE id=?", (owner,)).fetchone())
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr("builtins.input", lambda *args: "local@example.test")
    monkeypatch.setattr("sys.argv", ["docs_admin", "--mode", "sandbox"])
    docs_admin.main()
    with store.db() as db:
        assert (
            dict(db.execute("SELECT * FROM users WHERE id=?", (owner,)).fetchone())
            == before
        )
        assert (
            db.execute(
                "SELECT role FROM docs_admins WHERE user_id=?", (owner,)
            ).fetchone()[0]
            == "super_admin"
        )
    monkeypatch.setattr("sys.argv", ["docs_admin", "--mode", "sandbox", "--revoke"])
    docs_admin.main()
    with store.db() as db:
        assert (
            db.execute("SELECT * FROM docs_admins WHERE user_id=?", (owner,)).fetchone()
            is None
        )
        assert (
            dict(db.execute("SELECT * FROM users WHERE id=?", (owner,)).fetchone())
            == before
        )


def test_demo_url_and_section_contract_validation(docs):
    c, app, user, h, p = docs
    d = c.get("/api/docs/admin", headers=h).json()
    body = {"base_revision": d["revision"], "document": d["document"]}
    body["document"]["demo_url"] = "javascript:alert(1)"
    assert c.put("/api/docs/admin/draft", headers=h, json=body).status_code == 422
    body["document"]["demo_url"] = "https://example.test/demo"
    assert c.put("/api/docs/admin/draft", headers=h, json=body).status_code == 200


def test_duration_starts_immediately_on_apply(docs):
    c, app, user, h, p = docs
    publish(c, h)
    d = c.get("/api/docs/admin", headers=h).json()
    settings = d["settings"]
    settings.update(mode="duration", duration_minutes=5, enabled=True)
    result = c.put(
        "/api/docs/admin/settings",
        headers=h,
        json={"base_revision": d["revision"], "settings": settings},
    )
    assert result.status_code == 200 and result.json()["visible"] is True
    assert c.get("/api/docs/public").status_code == 200


def test_duration_can_be_reapplied_after_unused_window_end(docs, monkeypatch):
    from app import live_docs

    c, app, user, h, p = docs
    publish(c, h)
    monkeypatch.setattr(
        live_docs,
        "now",
        lambda: int(datetime(2028, 1, 1, tzinfo=timezone.utc).timestamp()),
    )
    for _ in range(2):
        d = c.get("/api/docs/admin", headers=h).json()
        settings = d["settings"]
        settings.update(mode="duration", duration_minutes=10, enabled=True)
        r = c.put(
            "/api/docs/admin/settings",
            headers=h,
            json={"base_revision": d["revision"], "settings": settings},
        )
        assert r.status_code == 200 and r.json()["visible"] is True
