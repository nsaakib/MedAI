import io
import json
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from PIL import Image
from app.main import create_app
from app.market import parse_product, product_url, MarketUnavailable, parse_search
from app.purchase import build_plan
from app.pharmacies import normalize

URL = "https://www.arogga.com/product/42/test-brand-tablet-500mg"


def page(price="11.40", visible="11.40", sales="Strip × 10", base="Tablet × 1"):
    data = {
        "@type": "Product",
        "sku": "42",
        "brand": {"name": "Test Manufacturer"},
        "offers": {
            "priceCurrency": "BDT",
            "price": price,
            "availability": "https://schema.org/InStock",
        },
        "additionalProperty": [
            {"name": "Strength", "value": "500mg"},
            {"name": "Form", "value": "Tablet"},
            {"name": "Sales Unit", "value": sales},
            {"name": "Base Unit", "value": base},
        ],
    }
    return f"""<script type="application/ld+json">{json.dumps(data)}</script>
<div id="product-42-variant-43" data-user-type="b2c"><h1>Test Brand</h1><div><div data-pv-id="43"><div class="product_single_label_generate">10 Tablets (1 Strip)</div><div class="product_single_price_generate">৳{visible}</div></div><button>Add To Cart</button></div></div>"""


def quote(**changes):
    return {
        **parse_product(page(), URL),
        "quote_id": "q1",
        "fetched_at": 100,
        "expires_at": 10000,
        **changes,
    }


def med(id="m1", **changes):
    return {
        "id": id,
        "name": "Test Brand",
        "strength": "500 mg",
        "form": "Tab",
        "quantity": 15,
        "quantity_unit": "Tablet",
        "quote_id": "q1",
        "product_match_confirmed": True,
        "verified": True,
        "unit_price_minor": 114,
        "price_confirmed": False,
        **changes,
    }


def test_price_is_sales_pack_not_unit_and_uses_exact_minor_units():
    q = quote()
    assert q["pack_price_minor"] == 1140 and q["units_per_pack"] == 10
    assert q["unit_price_minor"] == 114 and q["unit_price_bdt"] == "1.14"
    p = build_plan([med()], {"q1": q}, None, 0, stamp=200)
    assert p["selected_total_minor"] == 2280
    assert (
        p["rows"][0]["supplied_units"] == 20 and p["rows"][0]["prescribed_units"] == 15
    )


@pytest.mark.parametrize(
    "bad",
    [
        "http://www.arogga.com/product/42/test",
        "https://evil.example/product/42/test",
        "https://www.arogga.com@127.0.0.1/product/42/test",
        "https://www.arogga.com:444/product/42/test",
        "https://www.arogga.com/search?q=x",
        "https://www.arogga.com/product/42/../../admin",
    ],
)
def test_only_supplier_product_urls_are_fetchable(bad):
    with pytest.raises(MarketUnavailable):
        product_url(bad)


@pytest.mark.parametrize(
    "changes",
    [
        {"visible": "12.00"},
        {"sales": "unknown"},
        {"base": "ml × 5"},
        {"price": "NaN"},
        {"price": "0"},
        {"sales": "Strip × 20"},
    ],
)
def test_ambiguous_or_disagreeing_source_data_is_not_used(changes):
    with pytest.raises(MarketUnavailable):
        parse_product(page(**changes), URL)


def test_search_deduplicates_and_does_not_invent_prices():
    result = parse_search(
        f'<a href="{URL}">Test Brand 500mg</a><a href="{URL}">same</a><a href="https://evil.example/product/5/test">wrong</a>'
    )
    assert result == [{"source_url": URL, "title": "Test Brand 500mg"}]


def test_budget_selects_whole_quantities_in_order_without_rationing():
    rows = [med("a", quantity=30), med("b", quantity=20), med("c", quantity=10)]
    p = build_plan(rows, {"q1": quote(pack_price_minor=10000)}, 55000, 5000, stamp=200)
    assert [r["included"] for r in p["rows"]] == [True, True, False]
    assert p["selected_total_minor"] == 55000 and p["full_total_minor"] == 65000
    assert p["shortfall_minor"] == 10000 and p["incomplete"] is True
    assert [r["prescribed_units"] for r in p["rows"]] == [30, 20, 10]


def test_owned_missing_stale_unreviewed_and_wrong_quantity_units():
    rows = [
        med("owned", purchased=True),
        med("missing", quote_id=None),
        med("unreviewed", verified=False),
        med("wrongunit", quantity_unit="Strip"),
    ]
    p = build_plan(rows, {"q1": quote()}, 100000, 0, stamp=200)
    assert all(not r["included"] for r in p["rows"])
    assert (
        p["unpriced_count"] == 2
        and p["full_total_minor"] is None
        and p["cart_ready"] is False
    )
    p = build_plan([med()], {"q1": quote(expires_at=199)}, 10000, 0, stamp=200)
    assert p["unpriced_count"] == 1


def test_manual_price_can_estimate_but_never_claim_automatic_cart_ready():
    p = build_plan(
        [med(quote_id=None, price_confirmed=True, unit_price_minor=200)],
        {},
        4000,
        0,
        stamp=200,
    )
    assert p["selected_total_minor"] == 3000 and p["cart_ready"] is False
    p = build_plan([med(purchased=True)], {}, 0, 5000, stamp=200)
    assert p["selected_total_minor"] == 0 and p["full_total_minor"] == 0


@pytest.fixture
def system(tmp_path):
    app = create_app(tmp_path, Fernet.generate_key(), ocr_enabled=False)
    store = app.state.store
    user = store.create_user("one@example.com", "Long-password-123", "One")
    other = store.create_user("two@example.com", "Long-password-123", "Two")
    h = {"Authorization": "Bearer " + store.session(user)}
    oh = {"Authorization": "Bearer " + store.session(other)}

    class Source:
        def quote(self, url):
            return parse_product(page(), url)

        def search(self, query):
            return []

    app.state.market = Source()
    with TestClient(app) as c:
        yield app, store, c, h, oh


def test_api_keeps_quotes_account_scoped_and_rejects_stale_state(system):
    app, store, c, h, oh = system
    q = c.post("/api/market/quote", headers=h, json={"product_url": URL}).json()
    for headers, expected in [(h, True), (oh, False)]:
        state = c.get("/api/state", headers=headers).json()
        state["state"]["medicines"] = [med(quote_id=q["quote_id"])]
        assert (
            c.post(
                "/api/sync",
                headers=headers,
                json={
                    "event_id": "event-id-12345",
                    "base_version": 0,
                    "state": state["state"],
                },
            ).status_code
            == 200
        )
        plan = c.post(
            "/api/shopping/plan", headers=headers, json={"base_version": 1}
        ).json()
        assert plan["cart_ready"] == expected
        if expected:
            assert plan["selected_total_minor"] == 2280
        else:
            assert plan["unpriced_count"] == 1
    assert (
        c.post("/api/shopping/plan", headers=h, json={"base_version": 0}).status_code
        == 409
    )
    assert c.post("/api/market/quote", json={"product_url": URL}).status_code == 401
    assert (
        c.post(
            "/api/shopping/plan",
            headers=h,
            json={"base_version": 1, "selected_ids": ["not-mine"]},
        ).status_code
        == 422
    )


def upload(c, h):
    image = io.BytesIO()
    Image.new("RGB", (50, 50), "white").save(image, format="PNG")
    r = c.post(
        "/api/documents",
        headers=h,
        files={"file": ("image.png", image.getvalue(), "image/png")},
        data={"client_id": "test-source", "kind": "Prescription", "language": "eng"},
    )
    assert r.status_code == 201
    return r.json()["id"]


def test_ocr_not_configured_is_honest_and_adapter_contract_requires_review(system):
    app, store, c, h, oh = system
    id = upload(c, h)
    r = c.post(f"/api/documents/{id}/extract", headers=h).json()
    assert r["status"] == "not_configured" and r["candidates"] == []
    assert c.post(f"/api/documents/{id}/extract", headers=oh).status_code == 404

    def model(image, language):
        assert language == "eng" and image.startswith(b"\xff\xd8")
        return {
            "status": "ready",
            "model_version": "synthetic-test-only",
            "raw_text": "Synthetic source, not a clinical record",
            "candidates": [
                {
                    "name": "Synthetic candidate",
                    "strength": "500 mg",
                    "form": "Tablet",
                    "confidence": 0.8,
                }
            ],
        }

    app.state.ocr_adapter = model
    r = c.post(f"/api/documents/{id}/extract", headers=h).json()
    assert (
        r["review_required"] is True
        and r["candidates"][0]["name"] == "Synthetic candidate"
    )
    assert c.get("/api/state", headers=h).json()["state"]["medicines"] == []

    def broken(image, language):
        return {
            "status": "ready",
            "model_version": "bad",
            "candidates": [{"name": "x", "confidence": 2}],
        }

    app.state.ocr_adapter = broken
    assert c.post(f"/api/documents/{id}/extract", headers=h).status_code == 503


def test_pharmacy_data_is_tagged_locations_and_distance_sorted():
    data = {
        "elements": [
            {
                "type": "node",
                "id": 1,
                "lat": 23.8,
                "lon": 90.4,
                "tags": {"amenity": "pharmacy", "name": "Mapped test pharmacy"},
            },
            {
                "type": "way",
                "id": 2,
                "center": {"lat": 23.81, "lon": 90.4},
                "tags": {"amenity": "pharmacy"},
            },
            {
                "type": "node",
                "id": 3,
                "lat": 23.8,
                "lon": 90.4,
                "tags": {"amenity": "cafe"},
            },
        ]
    }
    items = normalize(data, 23.8, 90.4)
    assert (
        len(items) == 2 and items[0]["distance_m"] == 0 and items[1]["distance_m"] > 0
    )
    assert items[0]["opening_hours"] is None and "stock" not in items[0]


def test_purchase_metadata_not_leaked_to_clinician_snapshot(system):
    app, store, c, h, oh = system
    state = c.get("/api/state", headers=h).json()["state"]
    state["medicines"] = [med(price_quote={"private_price": 100})]
    assert (
        c.post(
            "/api/sync",
            headers=h,
            json={"event_id": "event-metadata-1", "base_version": 0, "state": state},
        ).status_code
        == 200
    )
    r = c.post(
        "/api/cases",
        headers=h,
        json={"reason": "Review this test entry", "consent": True, "document_ids": []},
    )
    assert r.status_code == 201
    text = json.dumps(c.get("/api/cases", headers=h).json()[0])
    assert "private_price" not in text and "quote_id" not in text


def test_duplicate_supplier_products_never_claim_an_automatic_cart_is_ready():
    result = build_plan(
        [med("first"), med("second")], {"q1": quote()}, None, 0, stamp=200
    )
    assert result["duplicate_products"] is True and result["cart_ready"] is False


def test_zero_budget_and_unpriced_items_never_become_free_medicines():
    result = build_plan([med()], {"q1": quote()}, 0, 0, stamp=200)
    assert result["selected_total_minor"] == 0
    assert result["rows"][0]["included"] is False
    assert result["shortfall_minor"] == 2280
    result = build_plan(
        [med(quote_id=None, unit_price_minor=0, price_confirmed=True)],
        {},
        None,
        0,
        stamp=200,
    )
    assert result["full_total_minor"] is None and result["cart_ready"] is False


def test_location_endpoint_requires_authentication_and_finite_coordinates(system):
    app, store, c, h, oh = system
    assert (
        c.post(
            "/api/pharmacies/nearby", json={"latitude": 23.8, "longitude": 90.4}
        ).status_code
        == 401
    )
    assert (
        c.post(
            "/api/pharmacies/nearby",
            headers=h,
            json={"latitude": 100, "longitude": 90.4},
        ).status_code
        == 422
    )
    assert (
        c.post(
            "/api/pharmacies/nearby",
            headers=h,
            json={"latitude": 23.8, "longitude": 90.4, "radius_m": 50000},
        ).status_code
        == 422
    )


def test_expired_session_relogin_preserves_budget_and_cart_plan(system):
    app, store, c, h, _ = system
    original = c.get('/api/state', headers=h).json()
    original['state'].update(budget=60000, budget_set=True, delivery=25000,
                             medicines=[med(quote_id=None)])
    assert c.post('/api/sync', headers=h, json={
        'event_id': 'before-expiry', 'base_version': original['version'],
        'state': original['state'],
    }).status_code == 200
    with store.db() as db:
        db.execute('UPDATE sessions SET expires=0')
    assert c.get('/api/state', headers=h).status_code == 401
    login = c.post('/api/auth/login', json={
        'email': 'one@example.com', 'password': 'Long-password-123',
    })
    assert login.status_code == 200
    fresh = {'Authorization': 'Bearer ' + login.json()['token']}
    restored = c.get('/api/state', headers=fresh).json()
    assert restored['state']['budget'] == 60000
    assert len(restored['state']['medicines']) == 1
    q = c.post('/api/market/quote', headers=fresh, json={'product_url': URL})
    assert q.status_code == 200
    restored['state']['medicines'] = [med(quote_id=q.json()['quote_id'])]
    saved = c.post('/api/sync', headers=fresh, json={
        'event_id': 'after-relogin', 'base_version': restored['version'],
        'state': restored['state'],
    })
    assert saved.status_code == 200
    plan = c.post('/api/shopping/plan', headers=fresh, json={
        'base_version': saved.json()['version'], 'budget_minor': 60000,
        'delivery_minor': 25000,
    })
    assert plan.status_code == 200
    assert plan.json()['cart_ready'] is True
    assert plan.json()['selected_total_minor'] == 27280


def test_automatic_discovery_rejects_similar_brands_and_missing_units():
    from app.discovery import exact_match
    q = quote(product_name='Napa 500')
    assert exact_match('Napa', '500 mg', 'Tab', q)
    assert exact_match('Napa 500', '500mg', 'Tablet', q)
    assert not exact_match('Napa Rapid', '500mg', 'Tablet', q)
    assert not exact_match('Napa', '500', 'Tablet', q)
    assert not exact_match('Napa', '500mg', 'Syrup', q)


def test_resolver_finds_owned_quote_without_link_input(system):
    app, store, c, h, _ = system
    app.state.market.search = lambda query: [{'source_url': URL}]
    result = c.post('/api/market/resolve', headers=h, json={
        'name': 'Test Brand', 'strength': '500 mg', 'form': 'Tab',
    })
    assert result.status_code == 200
    assert result.json()['pack_price_minor'] == 1140
    assert result.json()['quote_id']
    assert c.post('/api/market/resolve', headers=h, json={
        'name': 'Different Brand', 'strength': '500mg', 'form': 'Tablet',
    }).status_code == 409
    app.state.market.search = lambda query: [{'source_url': URL}, {'source_url': URL}]
    assert c.post('/api/market/resolve', headers=h, json={
        'name': 'Test Brand', 'strength': '500mg', 'form': 'Tablet',
    }).status_code == 409


def test_budget_below_delivery_reports_zero_affordability_and_review_reason():
    p = build_plan([med(verified=False)], {'q1': quote()}, 15000, 25000, stamp=200)
    assert p['medicine_allowance_minor'] == 0
    assert p['delivery_shortfall_minor'] == 10000
    assert p['rows'][0]['affordable_units'] == 0
    assert p['rows'][0]['review_required'] is True
    assert p['delivery_minor'] == 0 and p['delivery_reserve_minor'] == 25000
    assert not p['cart_ready']


def test_partial_affordability_is_visible_without_changing_prescription():
    p = build_plan([med(quantity=20)], {'q1': quote()}, 2000, 0, stamp=200)
    assert p['rows'][0]['affordable_units'] == 10
    assert p['rows'][0]['prescribed_units'] == 20
    assert not p['rows'][0]['included']
    p = build_plan([med(quantity=20)], {'q1': quote()}, 2280, 0, stamp=200)
    assert p['rows'][0]['included'] and p['cart_ready']
    assert p['selected_total_minor'] == 2280


def test_full_estimate_always_exposes_quantity_comparison():
    p = build_plan([med(quantity=20)], {'q1': quote()}, None, 0, stamp=200)
    assert p['rows'][0]['affordable_units'] == 20
