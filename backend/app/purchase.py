"""Whole-prescription shopping estimates. Never changes a prescribed quantity."""

import math
import re
from pydantic import Field
from fastapi import Depends, HTTPException
from .schemas import Strict
from .core import now, uid
from .market import MarketClient, MarketUnavailable


def form_key(value):
    v = re.sub(r"[^a-z]", "", value.lower())
    return {
        "tab": "tablet",
        "tablets": "tablet",
        "cap": "capsule",
        "capsules": "capsule",
        "syp": "syrup",
        "inj": "injection",
    }.get(v, v)


def compatible(med, quote):
    return (
        bool(med.get("product_match_confirmed"))
        and re.sub(r"\s+", "", med.get("strength", "")).lower()
        == re.sub(r"\s+", "", quote["strength"]).lower()
        and form_key(med.get("form", "")) == form_key(quote["form"])
        and form_key(med.get("quantity_unit", "unit")) == form_key(quote["base_unit"])
    )


def build_plan(medicines, quotes, budget, delivery, selected=None, stamp=None):
    stamp = now() if stamp is None else stamp
    rows, known_total, unknown = [], 0, 0
    remaining = None if budget is None else max(0, budget - delivery)
    for m in medicines:
        stock = m.get("stock_units")
        required = (0 if m.get("purchased") else m["quantity"]) if stock is None else max(
            0, m["quantity"] - m.get("units_taken", 0) - stock
        )
        row = {
            "medicine_id": m["id"],
            "name": m["name"],
            "strength": m.get("strength", ""),
            "form": m.get("form", ""),
            "prescribed_units": m["quantity"],
            "purchase_units": required,
            "included": False,
            "cart_eligible": False,
            "line_total_minor": None,
            "affordable_units": None,
            "review_required": not bool(m.get("verified")),
            "reason": "",
            "quote": None,
        }
        if required == 0:
            row["reason"] = "Already purchased" if stock is None else "No additional purchase needed"
            rows.append(row)
            continue
        q = quotes.get(m.get("quote_id"))
        if q and q["expires_at"] > stamp and compatible(m, q):
            row["quote"] = q
            packs = (required + q["units_per_pack"] - 1) // q["units_per_pack"]
            row.update(
                packs=packs,
                supplied_units=packs * q["units_per_pack"],
                line_total_minor=packs * q["pack_price_minor"],
                cart_eligible=bool(q["available"] and m.get("verified")),
            )
            row["affordable_units"] = required
            if budget is not None:
                row["affordable_units"] = min(
                    required,
                    max(0, budget - delivery)
                    // q["pack_price_minor"]
                    * q["units_per_pack"],
                )
        elif m.get("price_confirmed") and m.get("unit_price_minor", 0) > 0:
            row.update(
                line_total_minor=required * m["unit_price_minor"],
                packs=None,
                supplied_units=required,
            )
            row["affordable_units"] = required
            if budget is not None:
                row["affordable_units"] = min(
                    required, max(0, budget - delivery) // m["unit_price_minor"]
                )
        else:
            row["reason"] = (
                "Refresh or confirm the product match"
                if m.get("quote_id")
                else "Price not available"
            )
            unknown += 1
            rows.append(row)
            continue
        cost = row["line_total_minor"]
        known_total += cost
        chosen = selected is None or m["id"] in selected
        if not m.get("verified"):
            row["reason"] = "Review prescription details first"
        elif q and row["quote"] and not q["available"]:
            row["reason"] = "Supplier reports unavailable"
        elif not chosen:
            row["reason"] = "Not selected"
        elif remaining is not None and cost > remaining:
            row["reason"] = "Full prescribed quantity exceeds remaining budget"
        else:
            row["included"] = True
            row["reason"] = "Included"
            if remaining is not None:
                remaining -= cost
        rows.append(row)
    included = [r for r in rows if r["included"]]
    subtotal = sum(r["line_total_minor"] for r in included)
    reserve = delivery if included else 0
    need = [r for r in rows if r["purchase_units"] > 0]
    full = known_total + (delivery if need else 0)
    product_keys = [
        (r["quote"]["product_id"], r["quote"]["variant_id"])
        for r in included
        if r.get("quote")
    ]
    duplicate_products = len(set(product_keys)) != len(product_keys)
    return {
        "rows": rows,
        "budget_minor": budget,
        "medicine_allowance_minor": None if budget is None else max(0, budget - delivery),
        "delivery_shortfall_minor": 0 if budget is None else max(0, delivery - budget),
        "delivery_minor": reserve,
        "delivery_reserve_minor": delivery,
        "known_full_total_minor": full,
        "full_total_minor": None if unknown else full,
        "unpriced_count": unknown,
        "selected_subtotal_minor": subtotal,
        "selected_total_minor": subtotal + reserve,
        "remaining_minor": None if budget is None else budget - subtotal - reserve,
        "shortfall_minor": None if budget is None or unknown else max(0, full - budget),
        "incomplete": any(not r["included"] for r in need),
        "cart_ready": bool(included)
        and not duplicate_products
        and all(r["cart_eligible"] for r in included),
        "duplicate_products": duplicate_products,
        "selection_rule": "Whole remaining purchase quantities in medicine-list order; prescription directions stay unchanged.",
        "generated_at": stamp,
    }


class Lookup(Strict):
    query: str = Field(min_length=2, max_length=160)


class QuoteRequest(Strict):
    product_url: str = Field(min_length=20, max_length=1000)


class ResolveRequest(Strict):
    name: str = Field(min_length=1, max_length=180)
    strength: str = Field(min_length=1, max_length=80)
    form: str = Field(min_length=1, max_length=80)


class PlanRequest(Strict):
    base_version: int = Field(ge=0)
    budget_minor: int | None = Field(default=None, ge=0, le=100000000)
    delivery_minor: int = Field(default=0, ge=0, le=10000000)
    selected_ids: list[str] | None = Field(default=None, max_length=200)


def register_purchase(app, store, auth, get_state):
    app.state.market = MarketClient()
    with store.db() as db:
        db.execute(
            "CREATE TABLE IF NOT EXISTS market_quotes(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),payload BLOB NOT NULL,created INTEGER NOT NULL)"
        )

    @app.post("/api/market/search")
    def search(body: Lookup, user=Depends(auth)):
        from urllib.parse import urlencode

        try:
            items = app.state.market.search(body.query)
        except MarketUnavailable as e:
            raise HTTPException(503, str(e))
        return {
            "items": items,
            "search_url": "https://www.arogga.com/search?"
            + urlencode({"_search": body.query, "_product_type": "medicine"}),
            "status": "candidates" if items else "open_supplier_search",
            "message": "Choose and confirm the exact brand, strength, form and pack; no substitute is selected automatically.",
        }

    @app.post("/api/market/quote")
    def quote(body: QuoteRequest, user=Depends(auth)):
        try:
            result = app.state.market.quote(body.product_url)
        except MarketUnavailable as e:
            raise HTTPException(503, str(e))
        checked = result.get("fetched_at", now())
        result.update(quote_id=uid(), fetched_at=checked, expires_at=checked + 86400)
        with store.db() as db:
            db.execute(
                "DELETE FROM market_quotes WHERE user_id=? AND created<?",
                (user["id"], now() - 7 * 86400),
            )
            if (
                db.execute(
                    "SELECT COUNT(*) FROM market_quotes WHERE user_id=?", (user["id"],)
                ).fetchone()[0]
                >= 1000
            ):
                raise HTTPException(
                    429, "Quote history limit reached; retry when older quotes expire."
                )
            db.execute(
                "INSERT INTO market_quotes VALUES(?,?,?,?)",
                (result["quote_id"], user["id"], store.encrypt(result), now()),
            )
            store.audit(db, user["id"], "price.fetched", result["product_id"])
        return result

    @app.post("/api/market/resolve")
    def resolve(body: ResolveRequest, user=Depends(auth)):
        from .discovery import resolve_listing
        try:
            url = resolve_listing(app.state.market, body.name, body.strength, body.form)
            if url is None:
                raise HTTPException(409, 'No unique exact product match. Check the prescribed brand, strength including its unit, and dosage form. No substitute was chosen.')
            return quote(QuoteRequest(product_url=url), user)
        except MarketUnavailable as e:
            raise HTTPException(503, str(e))

    @app.post("/api/shopping/plan")
    def plan(body: PlanRequest, user=Depends(auth)):
        with store.db() as db:
            state = get_state(db, user["id"])
            if state["version"] != body.base_version:
                raise HTTPException(
                    409, "Sync your latest medicine list before creating a basket."
                )
            medicines = state["state"]["medicines"]
            ids = {m["id"] for m in medicines}
            if body.selected_ids is not None and any(
                i not in ids for i in body.selected_ids
            ):
                raise HTTPException(422, "Selected medicine is not in your list.")
            quotes = {
                r["id"]: store.decrypt(r["payload"])
                for r in db.execute(
                    "SELECT id,payload FROM market_quotes WHERE user_id=?",
                    (user["id"],),
                )
            }
            store.audit(db, user["id"], "shopping.estimated", "medicine-list")
        return build_plan(
            medicines, quotes, body.budget_minor, body.delivery_minor, body.selected_ids
        )
