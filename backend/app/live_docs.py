"""Live showcase, encrypted drafts and explicit server-enforced publishing."""

import io
import json
import re
from datetime import datetime, timezone, timedelta
from html import escape
from html.parser import HTMLParser
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from fastapi import Depends, HTTPException, UploadFile, File, Response
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import Field, field_validator, model_validator
from PIL import Image, ImageOps, UnidentifiedImageError
from .schemas import Strict
from .core import now, uid

WEB = Path(__file__).parent / "docs_web"
TZ = timezone(timedelta(hours=6), "Asia/Dhaka")
VERSION = "live-docs-7"


class CleanHTML(HTMLParser):
    allowed = {
        "p",
        "br",
        "strong",
        "b",
        "em",
        "i",
        "ul",
        "ol",
        "li",
        "h3",
        "h4",
        "blockquote",
        "a",
    }

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []

    def handle_starttag(self, tag, attrs):
        if tag not in self.allowed:
            return
        attributes = ""
        if tag == "a":
            href = dict(attrs).get("href", "")
            if re.match(r"^(https://|mailto:|/(?!/))", href) and not any(
                c in href for c in "\r\n"
            ):
                attributes = (
                    ' href="' + escape(href, quote=True) + '" rel="noopener noreferrer"'
                )
        self.out.append("<" + tag + attributes + ">")

    def handle_endtag(self, tag):
        if tag in self.allowed and tag != "br":
            self.out.append("</" + tag + ">")

    def handle_data(self, data):
        self.out.append(escape(data))


def clean_html(value):
    parser = CleanHTML()
    parser.feed(value)
    parser.close()
    return "".join(parser.out)


class Diagram(Strict):
    nodes: list[str] = Field(min_length=2, max_length=8)
    edges: list[tuple[int, int]] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def valid(self):
        if any(not n.strip() or len(n) > 90 for n in self.nodes):
            raise ValueError("Use short, nonempty diagram labels.")
        if any(
            a < 0 or b < 0 or a >= len(self.nodes) or b >= len(self.nodes)
            for a, b in self.edges
        ):
            raise ValueError("Invalid diagram connection.")
        return self


class Section(Strict):
    id: str = Field(pattern=r"^[a-z][a-z0-9-]{0,45}$")
    title: str = Field(min_length=2, max_length=90)
    group: Literal["Pitch", "Product", "Engineering", "Operations"]
    body: str = Field(default="", max_length=20000)
    source: Literal[
        "editorial",
        "features",
        "apis",
        "stack",
        "analytics",
        "architecture",
        "data-flow",
        "team",
    ] = "editorial"
    diagram: Diagram | None = None

    @field_validator("body")
    @classmethod
    def sanitize(cls, value):
        return clean_html(value)


class Member(Strict):
    id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,50}$")
    name: str = Field(min_length=2, max_length=100)
    role: str = Field(min_length=2, max_length=120)
    email: str = Field(max_length=180)
    avatar: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")

    @field_validator("email")
    @classmethod
    def email_ok(cls, value):
        if not re.fullmatch(r"[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+", value):
            raise ValueError("Enter a public contact email.")
        return value


class Document(Strict):
    title: str = Field(min_length=2, max_length=100)
    tagline: str = Field(min_length=2, max_length=300)
    team_name: str = Field(default="", max_length=100)
    demo_url: str | None = Field(default=None, max_length=1000)
    sections: list[Section] = Field(min_length=1, max_length=40)
    members: list[Member] = Field(default_factory=list, max_length=20)

    @field_validator("demo_url")
    @classmethod
    def safe_demo(cls, value):
        if not value:
            return None
        parsed = urlsplit(value)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.username
            or parsed.password
        ):
            raise ValueError(
                "Use a public HTTPS demo URL without embedded credentials."
            )
        return value

    @model_validator(mode="after")
    def unique(self):
        if len({s.id for s in self.sections}) != len(self.sections):
            raise ValueError("Section IDs must be unique.")
        if len({s.source for s in self.sections if s.source != "editorial"}) != len(
            [s for s in self.sections if s.source != "editorial"]
        ):
            raise ValueError("Each live block may occur once.")
        required = {
            "features",
            "apis",
            "stack",
            "analytics",
            "architecture",
            "data-flow",
            "team",
        }
        if not required <= {s.source for s in self.sections}:
            raise ValueError("Keep all live documentation blocks.")
        if len({m.id for m in self.members}) != len(self.members):
            raise ValueError("Team member IDs must be unique.")
        return self


class Settings(Strict):
    enabled: bool = False
    mode: Literal["immediate", "window", "duration"] = "window"
    start: datetime = datetime(2027, 6, 10, tzinfo=TZ)
    end: datetime = datetime(2027, 6, 14, 23, 59, 59, tzinfo=TZ)
    duration_minutes: int = Field(default=60, ge=1, le=525600)
    public_analytics: bool = False

    @model_validator(mode="after")
    def window(self):
        if self.start.tzinfo is None or self.end.tzinfo is None:
            raise ValueError("Include a time-zone offset.")
        if self.mode == "window" and self.end <= self.start:
            raise ValueError("End must follow start.")
        return self


class SaveDraft(Strict):
    base_revision: int = Field(ge=0)
    document: Document


class Publish(Strict):
    base_revision: int = Field(ge=0)


class SaveSettings(Strict):
    base_revision: int = Field(ge=0)
    settings: Settings


def seed():
    sections = []

    def add(id, title, group, body, source="editorial", diagram=None):
        sections.append(
            dict(
                id=id,
                title=title,
                group=group,
                body=body,
                source=source,
                diagram=diagram,
            )
        )

    add(
        "problem",
        "The problem",
        "Pitch",
        "<p>Prescriptions, reports, medicine schedules and doctor discovery are often disconnected. Patients and caregivers need a simpler way to understand and organize everyday care.</p>",
    )
    add(
        "solution",
        "One connected care workflow",
        "Pitch",
        "<p>Med.ai combines prescription scanning, source-grounded report explanations, doctor-directory matching, reminders and medicine purchase planning in a Bangla–English mobile app.</p>",
    )
    add(
        "why-now",
        "Why now",
        "Pitch",
        "<p>Mobile access and practical OCR and language models create an opportunity to make medical documents more understandable. Reliable recognition, user review and affordable operation remain essential.</p>",
    )
    add(
        "demo",
        "See the product",
        "Pitch",
        "<ol><li>Upload a prescription and review recognized medicines.</li><li>Upload a report, inspect the detected category and ask about its results.</li><li>Describe symptoms and explore relevant directory entries.</li><li>Manage reminders and prepare a medicine purchase plan.</li></ol><p>A public demo recording has not been added. Ambulance dispatch demonstrations use labeled sandbox records.</p>",
    )
    add(
        "market",
        "Who we serve",
        "Pitch",
        "<p>Initial users are patients and family caregivers in Bangladesh, particularly those managing several medicines or needing Bangla explanations. Market size and willingness to pay have not yet been independently measured.</p>",
    )
    add(
        "business",
        "Business model — proposed",
        "Pitch",
        "<p>Potential models include a free patient experience and optional provider-service partnerships. Pricing, revenue and commercial partnerships are not yet validated.</p>",
    )
    add(
        "traction",
        "Evidence, not inflated traction",
        "Pitch",
        "<p>A working team-test application and automated regression suites exist. Software test counts are validation artifacts, not user adoption or clinical effectiveness. No audited active-user, revenue or clinical outcome claim is made.</p>",
    )
    add(
        "competition",
        "Alternatives and positioning",
        "Pitch",
        "<p>Users can already use pharmacy apps, doctor directories, reminder apps and general AI assistants. Med.ai aims to connect these activities around reviewed medical records and local workflows. A formal competitive study remains future work.</p>",
    )
    add(
        "advantage",
        "Our approach",
        "Pitch",
        "<p>Bangla–English interaction, prescription-specific OCR development, visible report evidence and user-controlled medicine planning are the current focus. This is product differentiation, not a claim of exclusive technology or clinical superiority.</p>",
    )
    add(
        "go-to-market",
        "Go-to-market — planned",
        "Pitch",
        "<p>Begin with supervised team pilots, collect recognition and usability feedback, then validate needs with patients, caregivers and verified healthcare partners before wider rollout.</p>",
    )
    add(
        "team",
        "The team",
        "Pitch",
        "<p>Team members can publish their name, role, photograph and public contact email here. Only intentionally published member details are exposed.</p>",
        "team",
    )
    add(
        "vision",
        "Vision",
        "Pitch",
        "<p>Make everyday healthcare easier to understand, organize and access while keeping professional medical assessment and patient control central.</p>",
    )
    add(
        "overview",
        "Product overview",
        "Product",
        "<p>Patients upload report and prescription images, review extracted information, find relevant directory entries and organize medicine routines. The system supports care coordination; it is not an autonomous diagnostic or prescribing service.</p>",
    )
    add(
        "features",
        "Feature matrix",
        "Product",
        "<p>Implementation and configuration are reported separately. Configured does not mean successful inference or operational availability. Future work is identified explicitly.</p>",
        "features",
    )
    add(
        "architecture",
        "System architecture",
        "Engineering",
        "<p>The current deployment uses a PC-hosted FastAPI backend over a private Tailscale HTTPS origin. SQLite and encrypted files remain on the server. The PC must remain online.</p>",
        "architecture",
        {
            "nodes": [
                "Flutter mobile / web dashboards",
                "Authenticated FastAPI APIs",
                "OCR · report RAG · directory · dispatch services",
                "SQLite + encrypted document storage",
            ],
            "edges": [[0, 1], [1, 2], [2, 3]],
        },
    )
    add(
        "data-flow",
        "Report data flow",
        "Engineering",
        "<p>Relevant report content may reach the configured external AI provider. Cache reuse reduces repeated image transcription. Users can compare the returned evidence with the original document.</p>",
        "data-flow",
        {
            "nodes": [
                "Uploaded report image",
                "Local OCR or configured vision reading",
                "Cached text + lexical excerpt retrieval",
                "Configured text model + source citations",
                "User review and follow-up",
            ],
            "edges": [[0, 1], [1, 2], [2, 3], [3, 4]],
        },
    )
    add(
        "stack",
        "Technology stack",
        "Engineering",
        "<p>Live configuration is read from this running server. Credentials, database paths and patient information are never included in this document.</p>",
        "stack",
    )
    add(
        "apis",
        "API inventory",
        "Engineering",
        "<p>This inventory is generated from registered product API routes; documentation-control endpoints are excluded. Most APIs require a bearer session; organization and role checks further restrict partner operations. Public listing is documentation, not authorization to access data.</p>",
        "apis",
    )
    add(
        "data",
        "Data and privacy",
        "Engineering",
        "<p>Sources include user-uploaded images, user-entered care information, the existing doctor directory and supported medicine catalog. Records are account-scoped and encrypted at rest. Automatic PII redaction is not implemented. Document content may be processed by the configured provider.</p>",
    )
    add(
        "ai",
        "AI and retrieval",
        "Engineering",
        "<p>Prescription recognition uses custom detector and TrOCR checkpoints. Reports use local OCR where available, configured vision transcription where needed, and lexical retrieval-augmented generation. The current implementation does not use vector embeddings, GraphRAG, MCP or an agent framework. Type labels use actual report headings and result markers; unknown types remain unrecognized.</p>",
    )
    add(
        "roadmap",
        "Roadmap",
        "Product",
        "<h3>Short term</h3><p>Validate real report layouts, reminders and usability on phones.</p><h3>Mid term</h3><p>Improve prescription recognition, document coverage and affordable cloud deployment.</p><h3>Long term</h3><p>Validate verified ambulance partnerships, location tracking and lightweight local OCR. Timelines and clinical outcomes are not yet committed.</p>",
    )
    add(
        "performance",
        "Performance and scalability",
        "Operations",
        "<p>Recognized text is cached; model context and output lengths are bounded. Requests have timeouts and retries. Current infrastructure is a PC and SQLite, not a load-tested cloud deployment. Capacity, uptime and latency targets require measured load testing before wider rollout.</p>",
    )
    add(
        "security",
        "Security boundaries",
        "Operations",
        "<p>Bearer authentication, account checks, server-side credentials, encrypted storage and role-restricted partner operations protect application access. This documentation has a separate admin permission, publication gate and versioned drafts. Public analytics are opt-in aggregates. Medical content is not included in this showcase.</p>",
    )
    add(
        "analytics",
        "Live system view",
        "Operations",
        "<p>This block reads real server state at refresh time. Configuration is not an availability promise. Aggregate record counts are withheld publicly unless an administrator opts in. Counts include test accounts when this is a sandbox.</p>",
        "analytics",
    )
    add(
        "changelog",
        "Changelog",
        "Operations",
        "<h3>Live docs</h3><p>Added controlled publishing, editable drafts, team profiles, API inventory, diagrams, exports and live server-state refresh.</p><h3>Previous application update</h3><p>Automatic report identification after upload, preserved manual labels and source-grounded report explanations.</p>",
    )
    return Document(
        title="Med.ai — care, connected",
        tagline="Understand your reports. Organize your medicines. Find the next step in care.",
        team_name="Med.ai",
        sections=sections,
    ).model_dump()


def initialize(store):
    with store.db() as db:
        db.executescript(
            """
CREATE TABLE IF NOT EXISTS docs_admins(user_id TEXT PRIMARY KEY REFERENCES users(id),role TEXT NOT NULL CHECK(role IN ('admin','super_admin')));
CREATE TABLE IF NOT EXISTS docs_state(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,draft BLOB NOT NULL,published BLOB,settings BLOB NOT NULL,updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS docs_versions(id INTEGER PRIMARY KEY AUTOINCREMENT,actor TEXT NOT NULL,created INTEGER NOT NULL,kind TEXT NOT NULL,payload BLOB NOT NULL);
"""
        )
        db.execute(
            "INSERT OR IGNORE INTO docs_state VALUES(1,0,?,NULL,?,?)",
            (
                store.encrypt(seed()),
                store.encrypt(Settings().model_dump(mode="json")),
                now(),
            ),
        )


def state(store, db=None):
    if db is None:
        with store.db() as connection:
            return state(store, connection)
    row = db.execute("SELECT * FROM docs_state WHERE id=1").fetchone()
    return dict(
        revision=row["revision"],
        draft=store.decrypt(row["draft"]),
        published=store.decrypt(row["published"]) if row["published"] else None,
        settings=store.decrypt(row["settings"]),
        updated=row["updated"],
    )


def visible(data, clock=None):
    config = data["settings"]
    t = now() if clock is None else clock
    if not config["enabled"] or data["published"] is None:
        return False
    if config["mode"] == "immediate":
        return True
    start = datetime.fromisoformat(config["start"]).timestamp()
    end = (
        start + config["duration_minutes"] * 60
        if config["mode"] == "duration"
        else datetime.fromisoformat(config["end"]).timestamp()
    )
    return start <= t <= end


def registry(app):
    from . import report_rag
    from .sos_dispatch import enabled
    from .map_policy import map_config

    sandbox = bool(app.state.sos_sandbox)
    status = report_rag.status()
    models = (
        app.state.prescription_model_status()
        if callable(getattr(app.state, "prescription_model_status", None))
        else {}
    )
    features = [
        {
            "name": "Prescription scan",
            "status": (
                "Models present"
                if models and all(models.values())
                else "Model setup required"
            ),
            "basis": "Server checkpoint-file presence only; recognition quality needs image testing.",
        },
        {
            "name": "Report identification",
            "status": "Implemented",
            "basis": "Report headings / result markers; unreadable images can remain unidentified.",
        },
        {
            "name": "Report RAG",
            "status": (
                "Configured"
                if status["generation_configured"]
                else "Provider setup required"
            ),
            "basis": "Runtime provider configuration; successful inference is not probed by this page.",
        },
        {
            "name": "Doctor directory matching",
            "status": "Implemented",
            "basis": "Application directory and symptom-routing logic; not a diagnosis.",
        },
        {
            "name": "Medicine reminders and intake tracking",
            "status": "Implemented",
            "basis": "Phone permissions and device acceptance remain necessary.",
        },
        {
            "name": "Medicine planning and Arogga assistance",
            "status": "Implemented",
            "basis": "Supported catalog and supplier pages; checkout and payment stay manual.",
        },
        {
            "name": "Ambulance dispatch",
            "status": "Sandbox" if sandbox else "Enabled" if enabled() else "Disabled",
            "basis": "No availability is implied without verified partner / ambulance state.",
        },
        {
            "name": "Map basemap",
            "status": "Configured" if map_config()["tiles"] else "Not configured",
            "basis": "Deployer-controlled tile configuration, not GPS accuracy.",
        },
        {
            "name": "Managed cloud and validated offline LLM",
            "status": "Planned",
            "basis": "Not claimed as deployed by the current PC-hosted build.",
        },
    ]
    apis = []
    schema = app.openapi()
    for route in app.routes:
        path = getattr(route, "path", "")
        if not path.startswith("/api/") or path.startswith("/api/docs"):
            continue
        for method in sorted(getattr(route, "methods", []) or []):
            if method in ("HEAD", "OPTIONS"):
                continue
            access = (
                "Public / input validation"
                if path in ("/api/auth/register", "/api/auth/login", "/api/sos/config")
                else "Authenticated; endpoint-specific ownership / role checks"
            )
            operation = schema.get("paths", {}).get(path, {}).get(method.lower(), {})
            request_schema = (
                operation.get("requestBody", {})
                .get("content", {})
                .get("application/json", {})
                .get("schema", {})
            )
            if "$ref" in request_schema:
                request_schema = (
                    schema.get("components", {})
                    .get("schemas", {})
                    .get(request_schema["$ref"].split("/")[-1], request_schema)
                )
            apis.append(
                {
                    "parameters": operation.get("parameters", []),
                    "request_schema": request_schema,
                    "responses": operation.get("responses", {}),
                    "method": method,
                    "path": path,
                    "summary": getattr(route, "summary", None)
                    or (getattr(route, "name", "").replace("_", " ")),
                    "access": access,
                }
            )
    return {
        "features": features,
        "apis": apis,
        "stack": {
            "frontend": "Flutter / Dart + browser documentation UI",
            "backend": "FastAPI / Python",
            "storage": "SQLite + encrypted document files",
            "provider": status["provider"],
            "text_model": status["model"],
            "vision_model": status["vision_model"],
            "retrieval": status["retrieval"],
            "deployment": "PC-hosted; network access depends on configured proxy",
        },
        "system": {
            "docs_revision": VERSION,
            "dispatch_mode": (
                "sandbox" if sandbox else "live" if enabled() else "disabled"
            ),
            "ai_configured": status["generation_configured"],
            "api_endpoints": len(apis),
            "feature_entries": len(features),
            "sampled_at": now(),
        },
    }


def metrics(store):
    with store.db() as db:
        result = {
            name: db.execute("SELECT COUNT(*) FROM " + table).fetchone()[0]
            for name, table in [
                ("accounts", "users"),
                ("uploaded_documents", "documents"),
                ("care_cases", "cases"),
            ]
        }
        result["audit_actions_24h"] = db.execute(
            "SELECT COUNT(*) FROM audits WHERE created>=?", (now() - 86400,)
        ).fetchone()[0]
        tables = {
            r[0]
            for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        for name, table in [
            ("ambulance_requests", "sos_requests"),
            ("registered_organizations", "sos_orgs"),
            ("registered_vehicles", "sos_vehicles"),
        ]:
            result[name] = (
                db.execute("SELECT COUNT(*) FROM " + table).fetchone()[0]
                if table in tables
                else 0
            )
    return result


def register_live_docs(app, store, auth):
    initialize(store)

    def admin(user=Depends(auth)):
        with store.db() as db:
            grant = db.execute(
                "SELECT role FROM docs_admins WHERE user_id=?", (user["id"],)
            ).fetchone()
        if not grant:
            raise HTTPException(403, "Documentation administrator permission required.")
        return {**user, "docs_role": grant["role"]}

    def public_state():
        data = state(store)
        if not visible(data):
            raise HTTPException(
                403, "Documentation is not available in the current publishing window."
            )
        return data

    def payload(data, private=False):
        live = registry(app)
        live["metrics"] = (
            metrics(store) if private or data["settings"]["public_analytics"] else None
        )
        return {
            "document": data["draft"] if private else data["published"],
            "live": live,
            "revision": data["revision"],
            "updated": data["updated"],
        }

    def write_snapshot(db, user, data, kind):
        db.execute(
            "INSERT INTO docs_versions(actor,created,kind,payload) VALUES(?,?,?,?)",
            (user["id"], now(), kind, store.encrypt(data["draft"])),
        )
        db.execute(
            "DELETE FROM docs_versions WHERE id NOT IN (SELECT id FROM docs_versions ORDER BY id DESC LIMIT 40)"
        )
        store.audit(db, user["id"], "docs." + kind, "showcase")

    def check_revision(body, data):
        if body.base_revision != data["revision"]:
            raise HTTPException(
                409,
                "Another administrator changed this document. Reload before saving.",
            )

    def save_state(db, data):
        db.execute(
            "UPDATE docs_state SET revision=revision+1,draft=?,published=?,settings=?,updated=? WHERE id=1",
            (
                store.encrypt(data["draft"]),
                store.encrypt(data["published"]) if data["published"] else None,
                store.encrypt(data["settings"]),
                now(),
            ),
        )

    @app.get("/docs", include_in_schema=False)
    def page():
        if not visible(state(store)):
            return HTMLResponse(
                '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Med.ai — Not available</title><link rel="stylesheet" href="/docs/assets/docs.css"></head><body><main class="unavailable"><p class="brand">Med.ai</p><h1>Not available</h1><p>Documentation is not available in the current publishing window.</p></main></body></html>',
                status_code=403,
            )
        return FileResponse(WEB / "index.html")

    @app.get("/docs/admin", include_in_schema=False)
    def editor():
        return FileResponse(WEB / "admin.html")

    @app.get("/docs/assets/{name}", include_in_schema=False)
    def assets(name: str):
        if name not in ("docs.css", "docs.js", "admin.js"):
            raise HTTPException(404)
        return FileResponse(WEB / name)

    @app.get("/api/docs/public")
    def published():
        return payload(public_state())

    @app.get("/api/docs/admin")
    def draft(user=Depends(admin)):
        data = state(store)
        return {
            **payload(data, True),
            "settings": data["settings"],
            "published": data["published"],
            "visible": visible(data),
            "role": user["docs_role"],
        }

    @app.put("/api/docs/admin/draft")
    def save(body: SaveDraft, user=Depends(admin)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            data = state(store, db)
            check_revision(body, data)
            data["draft"] = body.document.model_dump()
            write_snapshot(db, user, data, "draft_saved")
            save_state(db, data)
        return {"revision": data["revision"] + 1}

    @app.post("/api/docs/admin/publish")
    def publish(body: Publish, user=Depends(admin)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            data = state(store, db)
            check_revision(body, data)
            data["published"] = Document.model_validate(data["draft"]).model_dump()
            write_snapshot(db, user, data, "published")
            save_state(db, data)
        return {"revision": data["revision"] + 1, "visible": visible(data)}

    @app.put("/api/docs/admin/settings")
    def configure(body: SaveSettings, user=Depends(admin)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            data = state(store, db)
            check_revision(body, data)
            data["settings"] = body.settings.model_dump(mode="json")
            if body.settings.mode == "duration":
                data["settings"]["start"] = datetime.fromtimestamp(
                    now(), timezone.utc
                ).isoformat()
            save_state(db, data)
            store.audit(db, user["id"], "docs.visibility_changed", "showcase")
        return {"revision": data["revision"] + 1, "visible": visible(data)}

    @app.get("/api/docs/admin/versions")
    def versions(user=Depends(admin)):
        with store.db() as db:
            return [
                dict(r)
                for r in db.execute(
                    "SELECT id,created,kind FROM docs_versions ORDER BY id DESC LIMIT 40"
                )
            ]

    @app.post("/api/docs/admin/versions/{identifier}/restore")
    def restore(identifier: int, body: Publish, user=Depends(admin)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            data = state(store, db)
            check_revision(body, data)
            row = db.execute(
                "SELECT payload FROM docs_versions WHERE id=?", (identifier,)
            ).fetchone()
            if not row:
                raise HTTPException(404, "Version not found")
            data["draft"] = Document.model_validate(
                store.decrypt(row["payload"])
            ).model_dump()
            write_snapshot(db, user, data, "draft_restored")
            save_state(db, data)
        return {"revision": data["revision"] + 1}

    @app.post("/api/docs/admin/avatar", status_code=201)
    def avatar(file: UploadFile = File(...), user=Depends(admin)):
        raw = file.file.read(6 * 1024 * 1024 + 1)
        if len(raw) > 6 * 1024 * 1024:
            raise HTTPException(413, "Choose a team image smaller than 6 MB.")
        try:
            with Image.open(io.BytesIO(raw)) as im:
                if im.width * im.height > 25000000:
                    raise HTTPException(413, "Image dimensions too large.")
                im = ImageOps.fit(
                    ImageOps.exif_transpose(im).convert("RGB"), (256, 256)
                )
                out = io.BytesIO()
                im.save(out, format="JPEG", quality=87)
        except (OSError, UnidentifiedImageError, Image.DecompressionBombError):
            raise HTTPException(415, "Choose a valid JPG or PNG team image.") from None
        identifier = uid()
        folder = store.root / "docs_avatars"
        folder.mkdir(exist_ok=True)
        (folder / identifier).write_bytes(store.cipher.encrypt(out.getvalue()))
        with store.db() as db:
            store.audit(db, user["id"], "docs.avatar_uploaded", identifier)
        return {"id": identifier, "width": 256, "height": 256}

    def image(identifier):
        if not re.fullmatch(r"[a-f0-9]{32}", identifier):
            raise HTTPException(404)
        path = store.root / "docs_avatars" / identifier
        if not path.is_file():
            raise HTTPException(404)
        return Response(
            store.cipher.decrypt(path.read_bytes()), media_type="image/jpeg"
        )

    @app.get("/docs/team/{identifier}", include_in_schema=False)
    def public_avatar(identifier: str):
        data = public_state()
        if identifier not in {m.get("avatar") for m in data["published"]["members"]}:
            raise HTTPException(404)
        return image(identifier)

    @app.get("/api/docs/admin/avatar/{identifier}")
    def private_avatar(identifier: str, user=Depends(admin)):
        return image(identifier)

    @app.get("/api/docs/export")
    def export():
        data = payload(public_state())
        doc = data["document"]
        live = data["live"]
        parts = [
            "# " + doc["title"],
            doc["tagline"],
            "Demo: " + (doc.get("demo_url") or "Not published"),
            "Sampled at: "
            + datetime.fromtimestamp(
                live["system"]["sampled_at"], timezone.utc
            ).isoformat(),
        ]
        for section in doc["sections"]:
            parts += ["## " + section["title"], re.sub("<[^>]+>", " ", section["body"])]
            source = section["source"]
            if source == "features":
                parts += [
                    f"- {f['name']}: {f['status']} — {f['basis']}"
                    for f in live["features"]
                ]
            if source == "apis":
                parts += [
                    f"- {a['method']} {a['path']} — {a['access']}" for a in live["apis"]
                ]
            if source in ("architecture", "data-flow") and section["diagram"]:
                parts += [
                    "```json",
                    json.dumps(section["diagram"], ensure_ascii=False, indent=2),
                    "```",
                ]
            if source == "stack":
                parts += [f"- {k}: {v}" for k, v in live["stack"].items()]
            if source == "analytics":
                parts += [
                    "```json",
                    json.dumps(
                        {"system": live["system"], "metrics": live["metrics"]}, indent=2
                    ),
                    "```",
                ]
            if source == "team":
                parts += [
                    f"- {m['name']} — {m['role']} — {m['email']}"
                    for m in doc["members"]
                ]
        return Response(
            "\n\n".join(parts),
            media_type="text/markdown; charset=utf-8",
            headers={
                "Content-Disposition": 'attachment; filename="MedAI-documentation.md"'
            },
        )
