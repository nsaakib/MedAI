"""Bounded, on-demand reads of public Arogga product pages; never private APIs."""

import json
import re
import time
import threading
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from urllib.parse import urlsplit, urlunsplit, urlencode
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError, URLError
from bs4 import BeautifulSoup


class MarketUnavailable(ValueError):
    pass


BASE = "https://www.arogga.com"


def product_url(value):
    try:
        u = urlsplit(value.strip())
        if (
            u.scheme != "https"
            or u.hostname not in ("www.arogga.com", "arogga.com")
            or u.username
            or u.password
            or u.port not in (None, 443)
            or not re.fullmatch(r"/product/[0-9]+/[a-zA-Z0-9%_-]+/?", u.path)
        ):
            raise ValueError()
        return urlunsplit(("https", "www.arogga.com", u.path.rstrip("/"), "", ""))
    except (ValueError, AttributeError):
        raise MarketUnavailable(
            "Choose an Arogga product URL, not a search or payment URL."
        )


def minor(value):
    try:
        amount = Decimal(str(value))
        if not amount.is_finite() or not 0 < amount <= 1000000:
            raise ValueError()
        return int((amount * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    except (ValueError, InvalidOperation):
        raise MarketUnavailable("The source did not provide a valid product price.")


def canonical_matches(value, expected):
    try:
        return product_url(value) == expected
    except MarketUnavailable:
        return False


def parse_product(html, url):
    url = product_url(url)
    soup = BeautifulSoup(html, "html.parser")
    pid = urlsplit(url).path.split("/")[2]
    products = []
    for script in soup.select('script[type="application/ld+json"]'):
        try:
            node = json.loads(script.string or script.get_text())
        except (ValueError, TypeError):
            continue
        nodes = node if isinstance(node, list) else [node]
        for n in nodes:
            if isinstance(n, dict):
                products += n.get("@graph", [])
                products.append(n)
    root = soup.select_one(f'[id^="product-{pid}-variant-"][data-user-type="b2c"]')
    variant = root.select_one("[data-pv-id]") if root else None
    variant_id = str(variant["data-pv-id"]) if variant else ""
    product = next(
        (
            p
            for p in products
            if isinstance(p, dict)
            and p.get("@type") == "Product"
            and str(p.get("sku")) in {pid, variant_id}
            and (str(p.get("sku")) == pid or
                 (isinstance(p.get("offers"), dict) and
                  canonical_matches(p["offers"].get("url"), url)))
        ),
        None,
    )
    if not product or not root:
        raise MarketUnavailable(
            "Product data is unavailable or the supplier page changed. Open the source and enter a price manually."
        )
    props = {
        x.get("name"): str(x.get("value", ""))
        for x in product.get("additionalProperty", [])
        if isinstance(x, dict)
    }
    offer = product.get("offers")
    if not isinstance(offer, dict) or offer.get("priceCurrency") != "BDT":
        raise MarketUnavailable(
            "No single BDT offer was found; select a specific product."
        )
    pack = props.get("Sales Unit", "")
    size = re.fullmatch(r"(.+?)\s*[×x]\s*(\d+)", pack.strip())
    if not size or not 1 <= int(size[2]) <= 10000:
        raise MarketUnavailable(
            "The sales-pack size is unclear. Automatic price calculation is unavailable for this listing."
        )
    # Only accept a visible sales unit and price for the selected primary variant.
    visible = root.select_one(".product_single_price_generate")
    label = root.select_one(".product_single_label_generate")
    title = root.select_one("h1")
    if not all((variant, visible, label, title)):
        raise MarketUnavailable("The displayed product/pack could not be verified.")
    digits = re.sub(r"[^0-9.]", "", visible.get_text("", strip=True))
    price = minor(offer["price"])
    if minor(digits) != price:
        raise MarketUnavailable(
            "Displayed and structured prices disagree. Check the source manually."
        )
    base = re.fullmatch(r"(.+?)\s*[×x]\s*1", props.get("Base Unit", "").strip())
    if not base:
        raise MarketUnavailable(
            "The individual quantity unit is unclear. Use a manually verified price."
        )
    units = int(size[2])
    label_text = label.get_text(" ", strip=True)
    if not re.search(r"(?<!\d)" + str(units) + r"(?!\d)", label_text):
        raise MarketUnavailable(
            "Pack count does not agree with the displayed sales unit."
        )
    if not props.get("Strength") or not props.get("Form"):
        raise MarketUnavailable(
            "Strength or dosage form is missing from this product listing."
        )
    brand = product.get("brand", {})
    unit_exact = Decimal(price) / Decimal(units) / Decimal(100)
    return {
        "source": "Arogga",
        "source_url": url,
        "product_id": pid,
        "variant_id": str(variant["data-pv-id"]),
        "product_name": title.get_text(" ", strip=True),
        "manufacturer": (
            brand.get("name", "") if isinstance(brand, dict) else str(brand)
        ),
        "strength": props["Strength"],
        "form": props["Form"],
        "pack_label": label_text,
        "base_unit": base[1].strip(),
        "units_per_pack": units,
        "pack_price_minor": price,
        "unit_price_minor": int(
            (Decimal(price) / units).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
        ),
        "unit_price_bdt": format(unit_exact.normalize(), "f"),
        "currency": "BDT",
        "available": str(offer.get("availability", "")).endswith("/InStock"),
    }


def parse_search(html):
    soup = BeautifulSoup(html, "html.parser")
    seen, items = set(), []
    for a in soup.select('a[href*="/product/"]'):
        try:
            url = product_url(
                BASE + a["href"] if a["href"].startswith("/") else a["href"]
            )
        except MarketUnavailable:
            continue
        if url in seen:
            continue
        title = a.get_text(" ", strip=True)[:180]
        if not title:
            image = a.find("img")
            title = image.get("alt", "")[:180] if image else ""
        if not title:
            continue
        seen.add(url)
        items.append({"source_url": url, "title": title})
        if len(items) >= 12:
            break
    return items


class MarketClient:
    def __init__(self):
        self.cache = {}
        self.lock = threading.Lock()

    def get(self, url):
        # Callers build this URL from a fixed origin or the strict product validator.
        with self.lock:
            cached = self.cache.get(url)
            if cached and time.time() - cached[0] < 120:
                return cached[1]

        class NoRedirect(HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None

        try:
            request = Request(
                url,
                headers={
                    "User-Agent": "MedAI/0.3 (user-requested medicine price lookup)",
                    "Accept-Language": "en",
                },
            )
            with build_opener(NoRedirect()).open(request, timeout=12) as response:
                data = response.read(2500001)
                if len(data) > 2500000:
                    raise MarketUnavailable("Supplier response is too large.")
            text = data.decode("utf-8", errors="replace")
        except (HTTPError, URLError, TimeoutError, OSError):
            raise MarketUnavailable(
                "Could not connect to the price source. Try again or enter a price manually."
            )
        with self.lock:
            if len(self.cache) > 200:
                self.cache.clear()
            self.cache[url] = (time.time(), text)
        return text

    def search(self, query):
        url = BASE + "/search?" + urlencode({"_search": query, "_product_type": "medicine"})
        items = parse_search(self.get(url))
        if not items:
            from .discovery import rendered_search
            items = rendered_search(url)
        return items

    def quote(self, url):
        url = product_url(url)
        result = parse_product(self.get(url), url)
        with self.lock:
            result["fetched_at"] = int(self.cache.get(url, (time.time(), ""))[0])
        return result
