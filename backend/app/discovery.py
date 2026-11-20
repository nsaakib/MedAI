"""Bounded public product discovery. No login, orders, or private API calls."""
import os
import re
from .market import MarketUnavailable, parse_search


def rendered_search(url):
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            options = {'headless': True}
            if os.environ.get('MEDAI_CHROMIUM_PATH'):
                options['executable_path'] = os.environ['MEDAI_CHROMIUM_PATH']
            browser = p.chromium.launch(**options)
            try:
                page = browser.new_page()
                page.goto(url, wait_until='domcontentloaded', timeout=12000)
                page.locator('a[href*="/product/"]').first.wait_for(timeout=6500)
                return parse_search(page.content())
            finally:
                browser.close()
    except Exception as e:
        raise MarketUnavailable('Automatic supplier search is unavailable. Check the server browser installation or retry later.') from e


def brand_key(text, strength, pack=None):
    text = text.casefold().strip()
    if pack and pack > 1:
        text = re.sub(r"\s*\(\s*" + str(pack) + r"\s*\)\s*$", "", text)
    explicit = re.escape(re.sub(r"\s+", "", strength.casefold()))
    explicit = explicit.replace("mg", r"\s*mg").replace("mcg", r"\s*mcg")
    text = re.sub(r"(?<!\w)" + explicit + r"\s*$", "", text).strip()
    n = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(?:mg|mcg|g|iu)\s*", strength, re.I)
    if n:
        text = re.sub(r"(?<!\w)" + re.escape(n[1]) + r"\s*$", "", text).strip()
    return re.sub(r"\s+", " ", text)


def exact_match(name, strength, form, q):
    from .purchase import form_key
    key = lambda s: re.sub(r"\s+", "", s).casefold()
    if not re.search(r"[A-Za-zµ%]", strength) or key(strength) != key(q["strength"]):
        return False
    if not form_key(form) or form_key(form) != form_key(q["form"]):
        return False
    name = brand_key(name, strength)
    return bool(name) and name == brand_key(q["product_name"], strength, q.get("units_per_pack"))


# Known public listing URLs, verified from Arogga; only discovery hints.
# Each result is always rechecked against the current product page.
KNOWN_LISTINGS = {
    "napa": ["/product/12474/napa-500-tablet-500mg"],
    "zopride": ["/product/86910/zopride-50-tablet-50mg"],
    "exium": ["/product/54418/exium-40-10-capsule-40mg"],
}


def resolve_listing(market, name, strength, form):
    from .market import BASE
    base = brand_key(name, strength)
    urls = {}
    failure = None
    for query in dict.fromkeys([f"{base} {strength}", base]):
        try:
            for item in market.search(query):
                url = item["source_url"]
                title = item.get("title", "").casefold()
                if not title or (base and re.search(r"(?<!\w)" + re.escape(base) + r"(?!\w)", title)):
                    urls[url] = title
            if urls:
                break
        except MarketUnavailable as exc:
            failure = exc
            break
    for path in KNOWN_LISTINGS.get(base, []):
        urls.setdefault(BASE + path, base)
    matches = {}
    successful_quotes = 0
    from concurrent.futures import ThreadPoolExecutor
    def read_candidate(url):
        try:
            return url, market.quote(url), None
        except MarketUnavailable as exc:
            return url, None, exc
    with ThreadPoolExecutor(max_workers=5) as workers:
        for url, result, exc in workers.map(read_candidate, list(urls)[:10]):
            if exc:
                failure = exc
                continue
            successful_quotes += 1
            if exact_match(name, strength, form, result):
                key = (result["product_id"], result["variant_id"])
                matches[key] = result.get("source_url", url)
    if len(matches) == 1:
        return next(iter(matches.values()))
    if successful_quotes == 0 and failure:
        raise failure
    return None
