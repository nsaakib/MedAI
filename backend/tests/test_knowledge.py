from datetime import datetime, timezone, timedelta
import pytest
from fastapi.testclient import TestClient
from cryptography.fernet import Fernet
from app.main import create_app


@pytest.fixture
def setup(tmp_path):
    app = create_app(tmp_path, Fernet.generate_key(), ocr_enabled=False)
    store = app.state.store
    author = store.create_user(
        "author@example.com", "Long-password-123", "Author", "clinician"
    )
    reviewer = store.create_user(
        "reviewer@example.com", "Long-password-123", "Reviewer", "clinician"
    )
    patient = store.create_user("patient@example.com", "Long-password-123", "Patient")
    headers = lambda user: {"Authorization": "Bearer " + store.session(user)}
    with TestClient(app) as client:
        yield client, store, headers(author), headers(reviewer), headers(patient)


def draft(**changes):
    return {
        "title": "Reference testing guide",
        "publisher": "Testing Publisher",
        "source_url": "https://example.org/testing-guide",
        "source_version": "Test edition 1",
        "language": "en",
        "audience": "Software evaluation only",
        "jurisdiction": "Test environment",
        "topics": ["document testing"],
        "content": "This reference is a software test fixture about record testing.\n\nA separate passage concerns offline document review. It contains no clinical advice.",
        "rights_basis": "Original synthetic text written solely for software tests.",
        **changes,
    }


def create(c, h, **changes):
    r = c.post("/api/knowledge/drafts", headers=h, json=draft(**changes))
    assert r.status_code == 201, r.text
    return r.json()


def approve(c, h, item, **changes):
    body = {
        "expected_version": item["version"],
        "action": "approve",
        "note": "Checked source accuracy, audience, jurisdiction and reuse permission.",
        "review_due": (datetime.now(timezone.utc) + timedelta(days=90)).isoformat(),
        "accuracy_checked": True,
        "audience_checked": True,
        "rights_checked": True,
        **changes,
    }
    return c.post("/api/knowledge/" + item["id"] + "/review", headers=h, json=body)


def search(c, h, query="", language="all"):
    r = c.post(
        "/api/knowledge/search", headers=h, json={"query": query, "language": language}
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_draft_invisible_and_publishing_requires_second_reviewer(setup):
    c, _, author, reviewer, patient = setup
    item = create(c, author)
    assert search(c, patient, "record")["results"] == []
    assert c.get("/api/knowledge/" + item["id"], headers=patient).status_code == 404
    assert (
        c.post("/api/knowledge/drafts", headers=patient, json=draft()).status_code
        == 403
    )
    assert approve(c, author, item).status_code == 403
    assert approve(c, reviewer, item, rights_checked=False).status_code == 422
    assert approve(c, reviewer, item).status_code == 200
    result = search(c, patient, "record")["results"][0]
    assert result["reference_id"] == item["id"]
    assert result["citation"]["source_url"] == "https://example.org/testing-guide"
    original = item["content"]
    assert original[result["start_offset"] : result["end_offset"]] == result["excerpt"]
    detail = c.get("/api/knowledge/" + item["id"], headers=patient).json()
    assert "rights_basis" not in detail and "review_notes" not in detail


def test_empty_query_is_browse_but_unmatched_query_abstains(setup):
    c, _, a, r, p = setup
    item = create(c, a)
    assert approve(c, r, item).status_code == 200
    assert search(c, p)["results"]
    missing = search(c, p, "nonexistentclinicalresult")
    assert missing["results"] == []
    assert "No matching approved" in missing["message"]
    assert search(c, p, '" OR * --')["results"] == []


def test_expiry_and_withdrawal_remove_online_and_pack_access(setup):
    c, store, a, r, p = setup
    item = create(c, a)
    approved = approve(c, r, item).json()
    assert c.get("/api/knowledge/pack", headers=p).json()["items"]
    with store.db() as db:
        db.execute("UPDATE knowledge SET review_due=1 WHERE id=?", (item["id"],))
    assert search(c, p, "record")["results"] == []
    assert c.get("/api/knowledge/pack", headers=p).json()["items"] == []
    assert c.get("/api/knowledge/" + item["id"], headers=p).status_code == 404
    response = c.post(
        "/api/knowledge/" + item["id"] + "/review",
        headers=a,
        json={
            "expected_version": approved["version"],
            "action": "withdraw",
            "note": "Withdraw this reference while its content is rechecked.",
        },
    )
    assert response.status_code == 200
    assert c.get("/api/knowledge/" + item["id"], headers=p).status_code == 404


def test_revisions_supersede_old_source_and_stale_review_rejected(setup):
    c, _, a, r, p = setup
    old = create(c, a)
    old_approved = approve(c, r, old).json()
    newer = create(
        c,
        a,
        replaces_id=old["id"],
        source_version="Test edition 2",
        content="Revised software fixture with replacement testing text. It does not provide clinical advice.",
    )
    assert approve(c, r, newer).status_code == 200
    assert c.get("/api/knowledge/" + old["id"], headers=p).status_code == 404
    results = search(c, p, "testing")["results"]
    assert [x["reference_id"] for x in results] == [newer["id"]]
    assert approve(c, r, newer).status_code == 409
    assert (
        c.post(
            "/api/knowledge/" + old["id"] + "/review",
            headers=a,
            json={
                "expected_version": old_approved["version"],
                "action": "withdraw",
                "note": "A stale review must not overwrite a more recent state.",
            },
        ).status_code
        == 409
    )


def test_bengali_words_and_combining_marks_are_searchable(setup):
    c, _, a, r, p = setup
    item = create(
        c,
        a,
        title="নথি পর্যালোচনা নির্দেশিকা",
        language="bn",
        topics=["নথি"],
        content="এটি সফটওয়্যার পরীক্ষার জন্য তৈরি একটি উদাহরণ।\n\nনথি পর্যালোচনা এবং তথ্য সংরক্ষণ এখানে পরীক্ষা করা হচ্ছে। এটি চিকিৎসা নির্দেশনা নয়।",
    )
    assert approve(c, r, item).status_code == 200
    found = search(c, p, "নথি পর্যালোচনা", language="bn")["results"]
    assert found and found[0]["citation"]["language"] == "bn"
    assert search(c, p, "নথি", language="en")["results"] == []


def test_query_not_logged_and_review_notes_not_disclosed(setup):
    c, store, a, r, p = setup
    item = create(c, a)
    assert approve(c, r, item).status_code == 200
    search(c, p, "sensitivepersonalquery")
    with store.db() as db:
        rows = db.execute("SELECT action,target FROM audits").fetchall()
        assert not any("sensitivepersonalquery" in str(tuple(row)) for row in rows)
    pack = c.get("/api/knowledge/pack", headers=p).json()
    assert pack["offline_until"] - pack["generated_at"] == 86400
    assert all(
        "rights_basis" not in i and "review_notes" not in i for i in pack["items"]
    )


def test_url_due_date_and_text_limits(setup):
    c, _, a, r, _ = setup
    for url in [
        "javascript:alert(1)",
        "http://example.org/x",
        "https://127.0.0.1/x",
        "https://user:pass@example.org/x",
        "https://localhost/x",
    ]:
        assert (
            c.post(
                "/api/knowledge/drafts", headers=a, json=draft(source_url=url)
            ).status_code
            == 422
        )
    item = create(c, a)
    assert (
        approve(
            c,
            r,
            item,
            review_due=(datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
        ).status_code
        == 422
    )
    assert (
        approve(
            c,
            r,
            item,
            review_due=(datetime.now(timezone.utc) + timedelta(days=400)).isoformat(),
        ).status_code
        == 422
    )
    assert (
        c.post(
            "/api/knowledge/search", headers=a, json={"query": "x" * 301}
        ).status_code
        == 422
    )


def test_schema_migration_preserves_patient_state(setup):
    c, store, a, r, p = setup
    before = c.get("/api/state", headers=p).json()
    with TestClient(create_app(store.root, store.key, ocr_enabled=False)) as restarted:
        assert restarted.get("/api/state", headers=p).json() == before
        assert restarted.get("/api/knowledge/pack", headers=p).status_code == 200


def test_release_one_database_is_upgraded_without_changing_patient_records(tmp_path):
    from app.core import Store

    key = Fernet.generate_key()
    old = Store(tmp_path, key)
    user = old.create_user(
        "existing@example.org", "Long-password-123", "Existing Patient"
    )
    token = old.session(user)
    with old.db() as db:
        assert (
            db.execute(
                "SELECT name FROM sqlite_master WHERE name='knowledge'"
            ).fetchone()
            is None
        )
        row = db.execute(
            "SELECT payload FROM states WHERE user_id=?", (user,)
        ).fetchone()
        saved = old.decrypt(row["payload"])
        saved["allergies"] = "Existing recorded allergy"
        saved["budget"] = 65000
        db.execute(
            "UPDATE states SET version=4,payload=? WHERE user_id=?",
            (old.encrypt(saved), user),
        )
    with TestClient(create_app(tmp_path, key, ocr_enabled=False)) as upgraded:
        response = upgraded.get(
            "/api/state", headers={"Authorization": "Bearer " + token}
        )
        assert response.status_code == 200
        assert response.json() == {"version": 4, "state": saved}
        assert (
            upgraded.get(
                "/api/knowledge/pack", headers={"Authorization": "Bearer " + token}
            ).json()["items"]
            == []
        )
