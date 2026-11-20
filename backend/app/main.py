import hashlib
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import threading
from collections import defaultdict, deque
from fastapi import FastAPI, HTTPException, Depends, UploadFile, File, Form, Request
from fastapi.responses import Response, FileResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps, UnidentifiedImageError
from .core import Store, now, uid, token_hash, verify_password
from .sos_dispatch import register_sos
from .private_profile import register_private_profile
from .app_guide import register_app_guide
from .brand_options import register_brand_options
from .schemas import Register, Login, Sync, CaseCreate, CaseUpdate
from .knowledge import register_knowledge
from .purchase import register_purchase
from .pharmacies import register_pharmacies
from .extraction import register_extraction
from .assistant import register_assistant
from .ocr_pilot_api import register_ocr_pilot
from .health_statistics import register_statistics
from .report_chat import register_report_chat
from .reports import REPORT_TYPES, ReportEdit, report_fields, with_report_details


def create_app(directory=None, key=None, ocr_enabled=None, *, sos_sandbox=False):
    directory = directory or os.environ.get("MEDAI_DATA_DIR", "./data")
    key = key or os.environ.get("MEDAI_ENCRYPTION_KEY")
    if not key:
        raise RuntimeError(
            "MEDAI_ENCRYPTION_KEY required. Run python -m app.manage init first."
        )
    store = Store(directory, key)
    app = FastAPI(
        title="Med.ai Care API", version="1.2.0", docs_url=None, redoc_url=None
    )
    app.state.store = store
    app.state.sos_sandbox = sos_sandbox
    bearer = HTTPBearer(auto_error=False)
    attempts = defaultdict(deque)
    attempt_lock = threading.Lock()
    ocr = (
        (os.environ.get("MEDAI_OCR_ENABLED", "false").lower() == "true")
        if ocr_enabled is None
        else ocr_enabled
    )

    @app.middleware("http")
    async def security_headers(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
        )
        return response

    def auth(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if not credentials:
            raise HTTPException(401, "Sign in required")
        with store.db() as db:
            user = db.execute(
                "SELECT u.* FROM users u JOIN sessions s ON u.id=s.user_id WHERE s.hash=? AND s.expires>?",
                (token_hash(credentials.credentials), now()),
            ).fetchone()
        if not user:
            raise HTTPException(401, "Session expired or invalid")
        return dict(user)

    def clinician(user=Depends(auth)):
        if user["role"] != "clinician":
            raise HTTPException(403, "Clinician account required")
        return user

    def limit(request):
        address = request.client.host if request.client else "unknown"
        with attempt_lock:
            bucket = attempts[address]
            while bucket and bucket[0] < now() - 60:
                bucket.popleft()
            if len(bucket) >= 10:
                raise HTTPException(429, "Too many attempts. Try again in a minute.")
            bucket.append(now())

    def get_state(db, identifier):
        row = db.execute(
            "SELECT * FROM states WHERE user_id=?", (identifier,)
        ).fetchone()
        return {"version": row["version"], "state": store.decrypt(row["payload"])}

    def document_record(db, identifier, user):
        row = db.execute("SELECT * FROM documents WHERE id=?", (identifier,)).fetchone()
        if not row:
            raise HTTPException(404, "Document not found")
        if row["user_id"] != user["id"]:
            allowed = False
            if user["role"] == "clinician":
                for case in db.execute(
                    "SELECT payload FROM cases WHERE user_id=?", (row["user_id"],)
                ).fetchall():
                    shared = store.decrypt(case["payload"])
                    if shared.get("consent") and identifier in shared["document_ids"]:
                        allowed = True
                        break
            if not allowed:
                raise HTTPException(404, "Document not found")
        return row, store.decrypt(row["payload"])

    @app.get("/health")
    def health():
        return {"status": "ok", "version": "1.2.0", "care_revision": "live-docs-7", "ocr_enabled": ocr,
                "report_rag": __import__("app.report_rag", fromlist=["status"]).status(),
                "prescription_models": app.state.prescription_model_status()
                    if callable(getattr(app.state, "prescription_model_status", None)) else {}}

    @app.post("/api/auth/register", status_code=201)
    def register(body: Register, request: Request):
        limit(request)
        try:
            identifier = store.create_user(body.email, body.password, body.name)
        except sqlite3.IntegrityError:
            raise HTTPException(409, "Unable to register with these details")
        return {
            "token": store.session(identifier),
            "user_id": identifier,
            "role": "patient",
        }

    @app.post("/api/auth/login")
    def login(body: Login, request: Request):
        limit(request)
        with store.db() as db:
            user = db.execute(
                "SELECT * FROM users WHERE email_hash=?", (token_hash(body.email),)
            ).fetchone()
        # Perform a comparable scrypt computation on failed account lookup.
        if user is None:
            from .core import password_hash

            password_hash(body.password)
            raise HTTPException(401, "Invalid email or password")
        if not verify_password(body.password, user["password"]):
            raise HTTPException(401, "Invalid email or password")
        return {
            "token": store.session(user["id"]),
            "user_id": user["id"],
            "role": user["role"],
        }

    @app.post("/api/auth/logout", status_code=204)
    def logout(
        credentials: HTTPAuthorizationCredentials = Depends(bearer), user=Depends(auth)
    ):
        with store.db() as db:
            db.execute(
                "DELETE FROM sessions WHERE hash=?",
                (token_hash(credentials.credentials),),
            )
        return Response(status_code=204)

    @app.get("/api/state")
    def state(user=Depends(auth)):
        with store.db() as db:
            return get_state(db, user["id"])

    @app.post("/api/sync")
    def sync(body: Sync, user=Depends(auth)):
        payload = body.state.model_dump()
        digest = hashlib.sha256(
            json.dumps(
                {"base": body.base_version, "state": payload}, sort_keys=True
            ).encode()
        ).hexdigest()
        medicine_ids = {m["id"] for m in payload["medicines"]}
        if any(x not in medicine_ids for x in payload["selected_ids"]):
            raise HTTPException(422, "Selected medicine does not exist")
        if any(x["medicine_id"] not in medicine_ids for x in payload["reminders"]):
            raise HTTPException(422, "Reminder medicine does not exist")
        verified = {m["id"] for m in payload["medicines"] if m["verified"]}
        if any(
            r["enabled"] and r["medicine_id"] not in verified
            for r in payload["reminders"]
        ):
            raise HTTPException(422, "Review medicine before enabling reminders")
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            previous = db.execute(
                "SELECT * FROM sync_receipts WHERE user_id=? AND event_id=?",
                (user["id"], body.event_id),
            ).fetchone()
            if previous:
                if previous["digest"] != digest:
                    raise HTTPException(
                        409, "Event ID was already used for different data"
                    )
                return {"version": previous["version"], "duplicate": True}
            current = get_state(db, user["id"])
            if current["version"] != body.base_version:
                raise HTTPException(
                    409,
                    {
                        "message": "Another device updated this record. Resolve before syncing.",
                        "server_version": current["version"],
                    },
                )
            # Email is an identity attribute, not editable through a patient snapshot.
            payload["email"] = current["state"]["email"]
            for med in payload["medicines"]:
                if med["source_document_id"]:
                    doc = db.execute(
                        "SELECT user_id FROM documents WHERE id=?",
                        (med["source_document_id"],),
                    ).fetchone()
                    if not doc or doc["user_id"] != user["id"]:
                        raise HTTPException(422, "Invalid source document")
            version = current["version"] + 1
            db.execute(
                "UPDATE states SET version=?,payload=? WHERE user_id=?",
                (version, store.encrypt(payload), user["id"]),
            )
            db.execute(
                "INSERT INTO sync_receipts VALUES(?,?,?,?)",
                (user["id"], body.event_id, digest, version),
            )
            store.audit(db, user["id"], "record.synced", user["id"])
        return {"version": version, "duplicate": False}

    @app.post("/api/documents", status_code=201)
    def upload(
        file: UploadFile = File(...),
        client_id: str = Form(...),
        kind: str = Form("Prescription"),
        language: str = Form("eng"),
        user=Depends(auth),
    ):
        if len(client_id) > 64 or not client_id:
            raise HTTPException(422, "Invalid client ID")
        if language not in ("eng", "ben", "eng+ben"):
            raise HTTPException(422, "Unsupported OCR language")
        data = file.file.read(12 * 1024 * 1024 + 1)
        if len(data) > 12 * 1024 * 1024:
            raise HTTPException(413, "Image exceeds 12 MB")
        try:
            with Image.open(io.BytesIO(data)) as im:
                if im.width * im.height > 25000000:
                    raise HTTPException(413, "Image dimensions too large")
                im.verify()
            with Image.open(io.BytesIO(data)) as im:
                canonical = io.BytesIO()
                ImageOps.exif_transpose(im).convert("RGB").save(
                    canonical, format="JPEG", quality=90
                )
                data = canonical.getvalue()
        except (UnidentifiedImageError, OSError, Image.DecompressionBombError):
            raise HTTPException(415, "Choose a valid JPG or PNG image")
        digest = hashlib.sha256(data).hexdigest()
        identifier = hashlib.sha256(
            (user["id"] + ":" + client_id).encode()
        ).hexdigest()[:32]
        with store.db() as db:
            previous = db.execute(
                "SELECT payload FROM documents WHERE id=?", (identifier,)
            ).fetchone()
            if previous:
                previous = store.decrypt(previous["payload"])
                if previous["sha256"] != digest:
                    raise HTTPException(409, "Upload ID already used for another image")
                return with_report_details(previous)
        text = ""
        status = "manual_review_required"
        engine = "none"
        if ocr:
            try:
                with tempfile.TemporaryDirectory() as tmp:
                    image = Path(tmp) / "input.jpg"
                    image.write_bytes(data)
                    result = subprocess.run(
                        ["tesseract", str(image), "stdout", "-l", language],
                        capture_output=True,
                        encoding="utf-8",
                        errors="replace",
                        timeout=45,
                        check=True,
                    )
                    text = result.stdout[:50000]
                    status = "text_ready" if text.strip() else "manual_review_required"
                    engine = "tesseract"
            except (FileNotFoundError, subprocess.SubprocessError):
                status = "manual_review_required"
        metadata = {
            "id": identifier,
            "kind": kind[:60],
            "language": language,
            "created": now(),
            "ocr_text": text,
            "ocr_status": status,
            "ocr_engine": engine,
            "sha256": digest,
            "mime": "image/jpeg",
        }
        metadata = with_report_details(metadata)
        path = store.files / identifier
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute(
                "SELECT payload FROM documents WHERE id=?", (identifier,)
            ).fetchone()
            if existing:
                old = store.decrypt(existing["payload"])
                if old["sha256"] != digest:
                    raise HTTPException(409, "Upload ID already used")
                return with_report_details(old)
            temporary = path.with_suffix(".tmp")
            temporary.write_bytes(store.cipher.encrypt(data))
            temporary.replace(path)
            db.execute(
                "INSERT INTO documents VALUES(?,?,?,?)",
                (identifier, user["id"], store.encrypt(metadata), now()),
            )
            store.audit(db, user["id"], "document.uploaded", identifier)
        return metadata

    @app.get("/api/documents")
    def documents(user=Depends(auth)):
        with store.db() as db:
            return [
                with_report_details(store.decrypt(r["payload"]))
                for r in db.execute(
                    "SELECT payload FROM documents WHERE user_id=? ORDER BY created DESC",
                    (user["id"],),
                )
            ]

    @app.post("/api/documents/{identifier}/classify")
    def classify_report(identifier: str, user=Depends(auth)):
        from .report_rag import recover_text
        from .reports import DETECTION_VERSION
        with store.db() as db:
            row = db.execute('SELECT payload FROM documents WHERE id=? AND user_id=?',
                             (identifier, user['id'])).fetchone()
            if row is None:
                raise HTTPException(404, 'Document not found')
            metadata = store.decrypt(row['payload'])
        if metadata.get('kind') != 'Lab Report':
            raise HTTPException(422, 'Choose a medical report image.')
        if metadata.get('report_reviewed') is True:
            return metadata
        # Cached text is reused. No report image is sent again on subsequent opens.
        metadata = recover_text(store, user['id'], identifier, metadata)
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            _, current = document_record(db, identifier, user)
            if current.get('report_reviewed') is not True:
                current = with_report_details(current)
                current['report_detection_version'] = DETECTION_VERSION
                current['report_metadata_revision'] = current.get('report_metadata_revision', 0) + 1
                if metadata.get('report_read_error'):
                    current['report_detection_status'] = 'read_failed'
                    current['report_read_error'] = metadata['report_read_error']
                else:
                    current.pop('report_read_error', None)
                db.execute('UPDATE documents SET payload=? WHERE id=? AND user_id=?',
                           (store.encrypt(current), identifier, user['id']))
                store.audit(db, user['id'], 'report.classified', identifier)
            return current

    @app.patch("/api/documents/{identifier}/report")
    def update_report(identifier: str, body: ReportEdit, user=Depends(auth)):
        if body.report_type is not None and body.report_type not in REPORT_TYPES:
            raise HTTPException(422, "Unknown report type")
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT payload FROM documents WHERE id=? AND user_id=?",
                (identifier, user["id"]),
            ).fetchone()
            if not row:
                raise HTTPException(404, "Document not found")
            metadata = store.decrypt(row["payload"])
            if metadata.get("kind") != "Lab Report":
                raise HTTPException(422, "This document is not a lab report")
            metadata.update(report_fields(
                body.report_type,
                (body.requested_by or "").strip() or None,
                body.report_date.isoformat() if body.report_date else None,
                reviewed=True,
            ))
            metadata['report_detection_status'] = 'reviewed'
            metadata['report_metadata_revision'] = metadata.get('report_metadata_revision', 0) + 1
            db.execute(
                "UPDATE documents SET payload=? WHERE id=? AND user_id=?",
                (store.encrypt(metadata), identifier, user["id"]),
            )
            store.audit(db, user["id"], "document.report_reviewed", identifier)
        return metadata

    @app.get("/api/documents/{identifier}")
    def document(identifier: str, user=Depends(auth)):
        with store.db() as db:
            row, metadata = document_record(db, identifier, user)
            store.audit(db, user["id"], "document.viewed", identifier)
        return Response(
            store.cipher.decrypt((store.files / row["id"]).read_bytes()),
            media_type="image/jpeg",
        )

    @app.post("/api/cases", status_code=201)
    def submit_case(body: CaseCreate, user=Depends(auth)):
        with store.db() as db:
            state = get_state(db, user["id"])
            for identifier in body.document_ids:
                row = db.execute(
                    "SELECT user_id FROM documents WHERE id=?", (identifier,)
                ).fetchone()
                if not row or row["user_id"] != user["id"]:
                    raise HTTPException(422, "Invalid document selection")
            identifier = uid()
            stamp = now()
            shared = {
                k: state["state"][k]
                for k in ("name", "phone", "allergies", "medicines", "vitals", "doses")
            }
            shared["medicines"] = [
                {
                    k: v
                    for k, v in m.items()
                    if k
                    in {
                        "id",
                        "name",
                        "strength",
                        "form",
                        "frequency",
                        "meal",
                        "duration",
                        "route",
                        "instruction",
                        "quantity",
                        "verified",
                        "source_document_id",
                        "quantity_unit",
                    }
                }
                for m in shared["medicines"]
            ]
            payload = {
                "reason": body.reason,
                "document_ids": body.document_ids,
                "consent": True,
                "consented_at": stamp,
                "snapshot": {"version": state["version"], "state": shared},
                "notes": [],
            }
            db.execute(
                "INSERT INTO cases VALUES(?,?,?,?,?,?,?)",
                (
                    identifier,
                    user["id"],
                    "submitted",
                    1,
                    store.encrypt(payload),
                    stamp,
                    stamp,
                ),
            )
            store.audit(db, user["id"], "case.submitted", identifier)
        return {"id": identifier, "status": "submitted", "version": 1}

    def case_json(row):
        payload = store.decrypt(row["payload"])
        return {
            "id": row["id"],
            "patient_id": row["user_id"],
            "status": row["status"],
            "version": row["version"],
            "created": row["created"],
            "updated": row["updated"],
            **payload,
        }

    @app.get("/api/cases")
    def cases(user=Depends(auth)):
        with store.db() as db:
            rows = db.execute(
                (
                    "SELECT * FROM cases WHERE status != 'withdrawn' ORDER BY updated DESC"
                    if user["role"] == "clinician"
                    else "SELECT * FROM cases WHERE user_id=? ORDER BY updated DESC"
                ),
                () if user["role"] == "clinician" else (user["id"],),
            ).fetchall()
            return [case_json(row) for row in rows]

    @app.patch("/api/cases/{identifier}")
    def review(identifier: str, body: CaseUpdate, user=Depends(clinician)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM cases WHERE id=?", (identifier,)).fetchone()
            if not row or row["status"] == "withdrawn":
                raise HTTPException(404, "Case not found")
            if row["version"] != body.expected_version:
                raise HTTPException(409, "Case changed; refresh before saving")
            if row["status"] == "completed":
                raise HTTPException(
                    409, "Completed cases are closed. Submit a new review request."
                )
            payload = store.decrypt(row["payload"])
            payload["notes"].append(
                {
                    "author": user["id"],
                    "text": body.note,
                    "created": now(),
                    "status": body.status,
                }
            )
            db.execute(
                "UPDATE cases SET status=?,version=version+1,payload=?,updated=? WHERE id=?",
                (body.status, store.encrypt(payload), now(), identifier),
            )
            store.audit(db, user["id"], "case." + body.status, identifier)
            return case_json(
                db.execute("SELECT * FROM cases WHERE id=?", (identifier,)).fetchone()
            )

    @app.post("/api/cases/{identifier}/withdraw")
    def withdraw(identifier: str, user=Depends(auth)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM cases WHERE id=? AND user_id=?", (identifier, user["id"])
            ).fetchone()
            if not row:
                raise HTTPException(404, "Case not found")
            payload = store.decrypt(row["payload"])
            payload["consent"] = False
            payload["withdrawn_at"] = now()
            db.execute(
                "UPDATE cases SET status='withdrawn',version=version+1,payload=?,updated=? WHERE id=?",
                (store.encrypt(payload), now(), identifier),
            )
            store.audit(db, user["id"], "case.withdrawn", identifier)
        return {"status": "withdrawn"}

    @app.get("/api/operations")
    def operations(user=Depends(clinician)):
        with store.db() as db:
            rows = db.execute(
                "SELECT status,COUNT(*) AS n FROM cases GROUP BY status"
            ).fetchall()
            completed = db.execute(
                "SELECT updated-created AS elapsed FROM cases WHERE status='completed'"
            ).fetchall()
        return {
            "counts": {r["status"]: r["n"] for r in rows},
            "mean_completion_seconds": (
                sum(r["elapsed"] for r in completed) / len(completed)
                if completed
                else None
            ),
        }

    @app.get("/api/audit")
    def audit(user=Depends(clinician)):
        with store.db() as db:
            return [
                dict(r)
                for r in db.execute("SELECT * FROM audits ORDER BY id DESC LIMIT 500")
            ]

    register_report_chat(app, store, auth)
    register_assistant(app, store, auth)
    register_sos(app, store, auth)
    register_private_profile(app, store, auth)
    register_brand_options(app, store, auth)
    register_app_guide(app, auth)
    register_ocr_pilot(app, auth)
    register_statistics(app, store, auth)
    register_knowledge(app, store, auth, clinician)
    register_purchase(app, store, auth, get_state)
    register_pharmacies(app, auth)
    register_extraction(app, store, auth)
    from .live_docs import register_live_docs
    register_live_docs(app, store, auth)
    static = Path(__file__).resolve().parents[1] / "static"
    app.mount("/static", StaticFiles(directory=static), name="static")

    @app.get("/care-team", include_in_schema=False)
    def dashboard():
        return FileResponse(static / "index.html")

    return app
