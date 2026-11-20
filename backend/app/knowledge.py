"""Reviewed reference retrieval. This module does not generate clinical answers."""

from datetime import datetime
import hashlib
import ipaddress
import re
import unicodedata
from urllib.parse import urlsplit
from typing import Literal
from fastapi import Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from .core import now, uid


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Draft(Strict):
    title: str = Field(min_length=3, max_length=200)
    publisher: str = Field(min_length=2, max_length=160)
    source_url: str = Field(min_length=10, max_length=2000)
    source_version: str = Field(min_length=1, max_length=100)
    language: Literal["en", "bn"]
    audience: str = Field(min_length=3, max_length=300)
    jurisdiction: str = Field(min_length=2, max_length=100)
    topics: list[str] = Field(default_factory=list, max_length=12)
    content: str = Field(min_length=40, max_length=30000)
    rights_basis: str = Field(min_length=10, max_length=1000)
    replaces_id: str | None = Field(default=None, max_length=64)

    @field_validator("topics")
    @classmethod
    def topic_size(cls, value):
        if any(not x.strip() or len(x) > 80 for x in value):
            raise ValueError("Topics must be 1–80 characters")
        return list(dict.fromkeys(x.strip() for x in value))

    @field_validator("source_url")
    @classmethod
    def safe_url(cls, value):
        parts = urlsplit(value)
        if (
            parts.scheme != "https"
            or not parts.hostname
            or parts.username
            or parts.password
            or parts.port not in (None, 443)
        ):
            raise ValueError(
                "Use an HTTPS source URL without credentials or a custom port"
            )
        host = parts.hostname.rstrip(".").lower()
        if (
            host in ("localhost", "localhost.localdomain")
            or "." not in host
            or host.endswith((".localhost", ".local", ".internal"))
        ):
            raise ValueError("Use a public source hostname")
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            address = None
        if address is not None and not address.is_global:
            raise ValueError("Private source addresses are not accepted")
        return value


class Review(Strict):
    expected_version: int = Field(ge=1)
    action: Literal["approve", "reject", "withdraw"]
    note: str = Field(min_length=10, max_length=2000)
    review_due: datetime | None = None
    accuracy_checked: bool = False
    audience_checked: bool = False
    rights_checked: bool = False


class Search(Strict):
    query: str = Field(default="", max_length=300)
    language: Literal["en", "bn", "all"] = "all"
    limit: int = Field(default=5, ge=1, le=10)


def tokens(text):
    # Preserve Bengali combining marks. Only literal word tokens reach MATCH.
    out = []
    word = []
    for ch in text.lower():
        if unicodedata.category(ch)[0] in "LNM":
            word.append(ch)
        elif word:
            out.append("".join(word))
            word = []
    if word:
        out.append("".join(word))
    return list(dict.fromkeys(out))


def passages(content):
    """Yield exact source slices with stable character offsets; no summarization."""
    for match in re.finditer(r"[^\n]+(?:\n(?!\s*\n)[^\n]+)*", content):
        start, end = match.span()
        while start < end:
            finish = min(start + 1200, end)
            if finish < end:
                boundary = content.rfind(" ", start + 600, finish)
                if boundary > start:
                    finish = boundary
            while start < finish and content[start].isspace():
                start += 1
            trimmed = finish
            while trimmed > start and content[trimmed - 1].isspace():
                trimmed -= 1
            if trimmed > start:
                yield start, trimmed, content[start:trimmed]
            start = finish
            while start < end and content[start].isspace():
                start += 1


def register_knowledge(app, store, auth, clinician):
    with store.db() as db:
        db.executescript(
            """
CREATE TABLE IF NOT EXISTS knowledge(id TEXT PRIMARY KEY,version INTEGER NOT NULL,status TEXT NOT NULL,author TEXT NOT NULL REFERENCES users(id),reviewer TEXT REFERENCES users(id),approved INTEGER,review_due INTEGER,payload BLOB NOT NULL,created INTEGER NOT NULL);
CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(reference_id UNINDEXED,section UNINDEXED,start_offset UNINDEXED,end_offset UNINDEXED,title,topics,content,tokenize="unicode61 remove_diacritics 0 categories 'L* N* M*'");
CREATE INDEX IF NOT EXISTS knowledge_status_idx ON knowledge(status,review_due);
"""
        )

    def read_row(row, internal=False):
        data = store.decrypt(row["payload"])
        result = {
            k: v for k, v in data.items() if k not in ("rights_basis", "review_notes")
        }
        result.update(
            {
                "id": row["id"],
                "version": row["version"],
                "status": row["status"],
                "author_id": row["author"],
                "reviewer_id": row["reviewer"],
                "approved_at": row["approved"],
                "review_due": row["review_due"],
                "created": row["created"],
            }
        )
        if internal:
            result.update(
                {
                    "rights_basis": data["rights_basis"],
                    "review_notes": data.get("review_notes", []),
                }
            )
        return result

    @app.post("/api/knowledge/drafts", status_code=201)
    def create_draft(body: Draft, user=Depends(clinician)):
        identifier = uid()
        stamp = now()
        payload = body.model_dump()
        payload["content_sha256"] = hashlib.sha256(body.content.encode()).hexdigest()
        payload["review_notes"] = []
        if len(list(passages(body.content))) > 100:
            raise HTTPException(
                422, "Use at most 100 paragraphs/passages per reference"
            )
        with store.db() as db:
            if db.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0] >= 2000:
                raise HTTPException(
                    409,
                    "Reference history limit reached; administrator maintenance required",
                )
            if body.replaces_id:
                original = db.execute(
                    "SELECT id FROM knowledge WHERE id=?", (body.replaces_id,)
                ).fetchone()
                if not original:
                    raise HTTPException(422, "Referenced prior source does not exist")
            db.execute(
                "INSERT INTO knowledge VALUES(?,?,?,?,?,?,?,?,?)",
                (
                    identifier,
                    1,
                    "draft",
                    user["id"],
                    None,
                    None,
                    None,
                    store.encrypt(payload),
                    stamp,
                ),
            )
            store.audit(db, user["id"], "knowledge.draft_created", identifier)
            return read_row(
                db.execute(
                    "SELECT * FROM knowledge WHERE id=?", (identifier,)
                ).fetchone(),
                True,
            )

    @app.get("/api/knowledge/manage")
    def manage(user=Depends(clinician)):
        with store.db() as db:
            return [
                read_row(r, True)
                for r in db.execute(
                    "SELECT * FROM knowledge ORDER BY created DESC LIMIT 2000"
                )
            ]

    @app.post("/api/knowledge/{identifier}/review")
    def review(identifier: str, body: Review, user=Depends(clinician)):
        with store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM knowledge WHERE id=?", (identifier,)
            ).fetchone()
            if not row:
                raise HTTPException(404, "Reference not found")
            if row["version"] != body.expected_version:
                raise HTTPException(409, "Reference changed; refresh before reviewing")
            data = store.decrypt(row["payload"])
            stamp = now()
            if body.action == "approve":
                if row["status"] != "draft":
                    raise HTTPException(
                        409,
                        "Only drafts can be approved; submit a new revision for changes",
                    )
                if row["author"] == user["id"]:
                    raise HTTPException(
                        403, "A second clinician must approve this source"
                    )
                if not all(
                    (body.accuracy_checked, body.audience_checked, body.rights_checked)
                ):
                    raise HTTPException(
                        422, "Confirm accuracy, intended audience and reuse rights"
                    )
                due = body.review_due
                if due is None or due.tzinfo is None:
                    raise HTTPException(422, "Provide a timezone-aware review due date")
                expires = int(due.timestamp())
                if not stamp < expires <= stamp + 366 * 86400:
                    raise HTTPException(
                        422, "Review due date must be within the next 366 days"
                    )
                if (
                    db.execute(
                        "SELECT COUNT(*) FROM knowledge WHERE status='approved' AND review_due>?",
                        (stamp,),
                    ).fetchone()[0]
                    >= 200
                ):
                    raise HTTPException(409, "Active reference limit reached")
                status = "approved"
                reviewer = user["id"]
                approved = stamp
                if data.get("replaces_id"):
                    previous = db.execute(
                        "SELECT status FROM knowledge WHERE id=?",
                        (data["replaces_id"],),
                    ).fetchone()
                    if previous and previous["status"] in (
                        "withdrawn",
                        "superseded",
                        "rejected",
                    ):
                        raise HTTPException(
                            409,
                            "The prior source is no longer current; create a draft referencing the current source",
                        )
                    db.execute(
                        "UPDATE knowledge SET status='superseded',version=version+1 WHERE id=?",
                        (data["replaces_id"],),
                    )
                    db.execute(
                        "DELETE FROM knowledge_fts WHERE reference_id=?",
                        (data["replaces_id"],),
                    )
                    store.audit(
                        db, user["id"], "knowledge.superseded", data["replaces_id"]
                    )
            elif body.action == "reject":
                if row["status"] != "draft":
                    raise HTTPException(409, "Only drafts can be rejected")
                status = "rejected"
                reviewer = user["id"]
                approved = None
                expires = None
            else:
                if row["status"] not in ("approved", "draft"):
                    raise HTTPException(409, "This source is already inactive")
                status = "withdrawn"
                reviewer = row["reviewer"]
                approved = row["approved"]
                expires = row["review_due"]
            data.setdefault("review_notes", []).append(
                {
                    "reviewer_id": user["id"],
                    "action": body.action,
                    "note": body.note,
                    "created": stamp,
                }
            )
            db.execute(
                "UPDATE knowledge SET status=?,version=version+1,reviewer=?,approved=?,review_due=?,payload=? WHERE id=?",
                (status, reviewer, approved, expires, store.encrypt(data), identifier),
            )
            db.execute("DELETE FROM knowledge_fts WHERE reference_id=?", (identifier,))
            if status == "approved":
                for index, (start, end, text) in enumerate(
                    passages(data["content"]), 1
                ):
                    db.execute(
                        "INSERT INTO knowledge_fts VALUES(?,?,?,?,?,?,?)",
                        (
                            identifier,
                            f"Passage {index}",
                            start,
                            end,
                            data["title"],
                            " ".join(data["topics"]),
                            text,
                        ),
                    )
            store.audit(db, user["id"], "knowledge." + body.action, identifier)
            return read_row(
                db.execute(
                    "SELECT * FROM knowledge WHERE id=?", (identifier,)
                ).fetchone(),
                True,
            )

    @app.post("/api/knowledge/search")
    def search(body: Search, user=Depends(auth)):
        stamp = now()
        terms = tokens(body.query)
        if len(terms) > 20:
            raise HTTPException(422, "Use up to 20 distinct search words")
        if body.query.strip() and not terms:
            return {
                "mode": "exact_retrieval",
                "results": [],
                "message": "Enter words to search the approved library.",
                "generated_at": stamp,
            }
        # Language filtering is performed on decrypted approved metadata, never a query-built SQL fragment.
        with store.db() as db:
            active = {
                r["id"]: r
                for r in db.execute(
                    "SELECT * FROM knowledge WHERE status='approved' AND review_due>?",
                    (stamp,),
                )
            }
            if terms:
                query = " AND ".join('"' + t + '"' for t in terms)
                rows = db.execute(
                    "SELECT f.reference_id,f.section,f.start_offset,f.end_offset,f.content,bm25(knowledge_fts,0,0,0,0,3,2,1) AS rank FROM knowledge_fts f JOIN knowledge k ON k.id=f.reference_id WHERE knowledge_fts MATCH ? AND k.status='approved' AND k.review_due>? ORDER BY rank",
                    (query, stamp),
                ).fetchall()
            else:
                rows = db.execute(
                    "SELECT f.reference_id,f.section,f.start_offset,f.end_offset,f.content,0 AS rank FROM knowledge_fts f JOIN knowledge k ON k.id=f.reference_id WHERE f.section='Passage 1' AND k.status='approved' AND k.review_due>? ORDER BY k.approved DESC",
                    (stamp,),
                ).fetchall()
            results = []
            for result in rows:
                reference = active.get(result["reference_id"])
                if reference is None:
                    continue
                data = read_row(reference)
                if body.language != "all" and data["language"] != body.language:
                    continue
                if any(r["reference_id"] == reference["id"] for r in results):
                    continue
                results.append(
                    {
                        "reference_id": reference["id"],
                        "section": result["section"],
                        "start_offset": int(result["start_offset"]),
                        "end_offset": int(result["end_offset"]),
                        "excerpt": result["content"],
                        "citation": {
                            k: data[k]
                            for k in (
                                "title",
                                "publisher",
                                "source_url",
                                "source_version",
                                "language",
                                "audience",
                                "jurisdiction",
                                "content_sha256",
                                "approved_at",
                                "review_due",
                                "reviewer_id",
                            )
                        },
                        "source_revision": reference["version"],
                    }
                )
                if len(results) >= body.limit:
                    break
            # Do not retain potentially sensitive search text in the audit log.
            store.audit(db, user["id"], "knowledge.searched", "approved-library")
        return {
            "mode": "exact_retrieval",
            "results": results,
            "message": (
                "Exact excerpts from sources reviewed by your care team."
                if results
                else "No matching approved reference. Ask your care team."
            ),
            "generated_at": stamp,
        }

    @app.get("/api/knowledge/pack")
    def pack(user=Depends(auth)):
        stamp = now()
        with store.db() as db:
            items = [
                read_row(r)
                for r in db.execute(
                    "SELECT * FROM knowledge WHERE status='approved' AND review_due>? ORDER BY id",
                    (stamp,),
                )
            ]
            store.audit(db, user["id"], "knowledge.pack_downloaded", "approved-library")
        for item in items:
            content = item.pop("content")
            item["passages"] = [
                {
                    "section": f"Passage {i}",
                    "start_offset": a,
                    "end_offset": b,
                    "excerpt": text,
                }
                for i, (a, b, text) in enumerate(passages(content), 1)
            ]
        return {
            "generated_at": stamp,
            "offline_until": stamp + 86400,
            "items": items,
            "purpose": "reference-reading-only",
        }

    @app.get("/api/knowledge/{identifier}")
    def reference(identifier: str, user=Depends(auth)):
        with store.db() as db:
            row = db.execute(
                "SELECT * FROM knowledge WHERE id=? AND status='approved' AND review_due>?",
                (identifier, now()),
            ).fetchone()
            if not row:
                raise HTTPException(
                    404, "This reference is unavailable, withdrawn or due for review"
                )
            return read_row(row)
