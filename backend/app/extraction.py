"""Local OCR extension point. Model candidates are never added without review."""

import importlib
import logging
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Literal
from pydantic import Field, FiniteFloat
from fastapi import Depends, HTTPException
from .schemas import Strict
from .core import now


class Candidate(Strict):
    name: str = Field(default="", max_length=160)
    strength: str = Field(default="", max_length=100)
    form: str = Field(default="", max_length=100)
    frequency: str = Field(default="", max_length=100)
    meal: str = Field(default="", max_length=160)
    duration: str = Field(default="", max_length=100)
    route: str = Field(default="", max_length=100)
    instruction: str = Field(default="", max_length=1000)
    evidence: str = Field(default="", max_length=2000)
    confidence: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    box: list[FiniteFloat] | None = Field(default=None, min_length=4, max_length=4)


class Extraction(Strict):
    status: Literal["ready", "no_readable_medicines", "not_configured"]
    model_version: str = Field(min_length=1, max_length=120)
    raw_text: str = Field(default="", max_length=50000)
    candidates: list[Candidate] = Field(default_factory=list, max_length=100)


def adapter_from_env():
    setting = os.environ.get("MEDAI_OCR_ADAPTER", "").strip()
    if not setting:
        return None
    if not re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*:[A-Za-z_]\w*", setting):
        raise RuntimeError("MEDAI_OCR_ADAPTER must name a local Python module:function")
    module, function = setting.split(":")
    adapter = getattr(importlib.import_module(module), function)
    if not callable(adapter):
        raise RuntimeError("Configured OCR adapter is not callable")
    return adapter


def printed_candidates(text):
    # A conservative fallback, limited to explicit form + name + strength.
    # It never fills instructions or schedules from unstructured OCR.
    pattern = re.compile(
        r"^\s*(?:\d{1,2}[.)]\s*)?(tab(?:let)?|cap(?:sule)?|syp|syrup)\.?\s+"
        r"([A-Za-z][A-Za-z0-9 -]{0,70}?)\s+(\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu)\b)", re.I
    )
    forms = dict(tab="Tablet", tablet="Tablet", cap="Capsule", capsule="Capsule", syp="Syrup", syrup="Syrup")
    found = {}
    for line in text.splitlines()[:1000]:
        m = pattern.match(line)
        if m:
            form, name, strength = m.groups()
            key = (name.casefold(), strength.replace(" ", "").casefold(), form.lower()[:3])
            found.setdefault(key, dict(name=name, strength=strength, form=forms[form.lower()],
                                       evidence=line[:2000]))
    return list(found.values())[:100]


def local_text(image, language):
    if os.environ.get("MEDAI_OCR_ENABLED", "").lower() not in ("1", "true", "yes"):
        return ""
    try:
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / "prescription.jpg"
            f.write_bytes(image)
            for lang in dict.fromkeys((language, "eng")):
                try:
                    proc = subprocess.run(
                        [os.environ.get("MEDAI_TESSERACT_PATH") or "tesseract", str(f), "stdout", "-l", lang],
                        capture_output=True, encoding="utf-8", errors="replace", timeout=25, check=True,
                    )
                    if proc.stdout.strip():
                        return proc.stdout[:50000]
                except subprocess.CalledProcessError:
                    continue
            return ""
    except (OSError, subprocess.SubprocessError):
        return ""


def routed_candidates(result):
    candidates = []
    for field in result.get("fields", [])[:100]:
        if field.get("field") != "medicine" or field.get("status") != "draft":
            continue
        name = field.get("text")
        if isinstance(name, str) and name.strip():
            # Independent boxes are not linked to medicine rows by the pilot.
            # Never attach a dose or frequency from a nearby crop.
            candidates.append(dict(name=name.strip()[:160], evidence="Routed medicine-name crop"))
    return candidates


def register_extraction(app, store, auth):
    app.state.ocr_error = False
    try:
        app.state.ocr_adapter = adapter_from_env()
    except (ImportError, AttributeError, RuntimeError):
        app.state.ocr_adapter = None
        app.state.ocr_error = True
        logging.getLogger(__name__).warning("Configured prescription OCR adapter could not be loaded. Check the backend OCR environment.")

    @app.get("/api/extraction/capabilities")
    def capabilities(user=Depends(auth)):
        return {
            "structured_ocr": app.state.ocr_adapter is not None or callable(getattr(app.state, "scan_prescription_page", None)),
            "models": app.state.prescription_model_status() if callable(getattr(app.state, "prescription_model_status", None)) else {},
            "review_required": True,
            "contract_version": 1,
            "adapter_load_failed": app.state.ocr_error,
            "message": "Photo capture and manual medicine entry work now. Structured extraction requires your local OCR model.",
        }

    @app.post("/api/documents/{identifier}/extract")
    def extract(identifier: str, user=Depends(auth)):
        with store.db() as db:
            row = db.execute(
                "SELECT * FROM documents WHERE id=? AND user_id=?",
                (identifier, user["id"]),
            ).fetchone()
            if not row:
                raise HTTPException(404, "Document not found")
            metadata = store.decrypt(row["payload"])
        if metadata["kind"] != "Prescription":
            raise HTTPException(
                422, "Choose a prescription image for medicine extraction."
            )
        try:
            image = store.cipher.decrypt((store.files / identifier).read_bytes())
        except (OSError, ValueError):
            raise HTTPException(503, "The saved image is unavailable. Try taking another photo.")
        language = metadata.get("language", "eng")
        result = None
        adapter_failed = app.state.ocr_error
        routed_failed = False
        if app.state.ocr_adapter is not None:
            try:
                result = Extraction.model_validate(app.state.ocr_adapter(image, language))
                result.candidates = [c for c in result.candidates if c.name.strip()]
            except Exception:
                # Preserve the image and use the local, conservative fallback if available.
                adapter_failed = True
                result = None
        if result is None or not result.candidates:
            routed = getattr(app.state, "scan_prescription_page", None)
            if callable(routed):
                try:
                    routed_result = routed(image)
                    names = routed_candidates(routed_result)
                    if names:
                        result = Extraction(status="ready",model_version="03P + 03C local",candidates=names)
                    elif any(x.get("field") == "medicine" and x.get("status") == "manual"
                             for x in routed_result.get("fields", [])):
                        routed_failed = True
                except Exception:
                    routed_failed = True
        if result is None or not result.candidates:
            adapter_text = result.raw_text if result is not None else ""
            text = metadata.get("ocr_text") or adapter_text or local_text(image, language)
            fallback = printed_candidates(text)
            if (adapter_failed or routed_failed) and not fallback:
                raise HTTPException(503, "The prescription model could not run. Your photo is saved. Ask the server owner to run CHECK_OCR.ps1; you can enter medicines manually.")
            result = Extraction(
                status="ready" if fallback else ("no_readable_medicines" if text else "not_configured"),
                model_version="local-printed-ocr" if text else "none", raw_text=text, candidates=fallback,
            )
        payload = result.model_dump()
        payload.update(document_id=identifier, extracted_at=now(), review_required=True)
        if result.status == "not_configured":
            payload["message"] = (
                "Prescription scanning is temporarily unavailable. Your photo is saved; enter medicines manually."
                if routed_failed else
                "No readable medicine text was found. Your photo is saved; try a clearer picture or enter medicines manually."
            )
        with store.db() as db:
            metadata["extraction"] = payload
            db.execute(
                "UPDATE documents SET payload=? WHERE id=?",
                (store.encrypt(metadata), identifier),
            )
            store.audit(db, user["id"], "document.extracted", identifier)
        return payload
