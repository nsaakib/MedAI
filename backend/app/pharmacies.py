import math
import re
import time
import threading
import httpx
from fastapi import Depends, HTTPException
from pydantic import Field
from .schemas import Strict


class Nearby(Strict):
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    radius_m: int = Field(default=3000, ge=500, le=10000)


def distance(a, b, c, d):
    p, q = math.radians(c - a), math.radians(d - b)
    h = (
        math.sin(p / 2) ** 2
        + math.cos(math.radians(a)) * math.cos(math.radians(c)) * math.sin(q / 2) ** 2
    )
    return round(6371000 * 2 * math.atan2(math.sqrt(h), math.sqrt(max(0, 1 - h))))


def normalize(data, lat, lon):
    items = []
    for e in data.get("elements", [])[:2000]:
        tags = e.get("tags", {})
        point = e.get("center", e)
        if (
            tags.get("amenity") != "pharmacy"
            or "lat" not in point
            or "lon" not in point
        ):
            continue
        if not (-90 <= point["lat"] <= 90 and -180 <= point["lon"] <= 180):
            continue
        phone = tags.get("contact:phone") or tags.get("phone")
        if phone and not re.fullmatch(r"[+0-9 ()-]{5,40}", phone):
            phone = None
        items.append(
            {
                "id": f"{e['type']}/{e['id']}",
                "name": tags.get("name")
                or tags.get("name:en")
                or "Pharmacy (name not mapped)",
                "latitude": point["lat"],
                "longitude": point["lon"],
                "distance_m": distance(lat, lon, point["lat"], point["lon"]),
                "address": ", ".join(
                    tags[k]
                    for k in [
                        "addr:housenumber",
                        "addr:street",
                        "addr:suburb",
                        "addr:city",
                    ]
                    if tags.get(k)
                ),
                "opening_hours": tags.get("opening_hours"),
                "phone": phone,
                "osm_url": f"https://www.openstreetmap.org/{e['type']}/{e['id']}",
            }
        )
    return sorted(items, key=lambda i: i["distance_m"])[:50]


def register_pharmacies(app, auth):
    cache, lock = {}, threading.Lock()

    @app.post("/api/pharmacies/nearby")
    def nearby(body: Nearby, user=Depends(auth)):
        # Coordinates are intentionally not stored in patient records or audit events.
        key = (round(body.latitude, 3), round(body.longitude, 3), body.radius_m)
        with lock:
            entry = cache.get(key)
        data = entry[1] if entry and time.time() - entry[0] < 900 else None
        if data is None:
            query = f'[out:json][timeout:15];nwr["amenity"="pharmacy"](around:{body.radius_m + 150},{key[0]},{key[1]});out center tags;'
            try:
                with httpx.Client(
                    timeout=20,
                    headers={"User-Agent": "MedAI/0.3 nearby-pharmacy lookup"},
                ) as c:
                    r = c.post(
                        "https://overpass-api.de/api/interpreter", data={"data": query}
                    )
                    r.raise_for_status()
                    if len(r.content) > 2000000:
                        raise ValueError()
                    data = r.json()
            except (httpx.HTTPError, ValueError):
                raise HTTPException(
                    503, "Map search is unavailable. Try again or open Google Maps."
                )
            with lock:
                if len(cache) >= 100:
                    cache.clear()
                cache[key] = (time.time(), data)
        return {
            "items": [i for i in normalize(data, body.latitude, body.longitude) if i["distance_m"] <= body.radius_m],
            "source": "OpenStreetMap contributors",
            "radius_m": body.radius_m,
            "message": "Mapped locations, not medicine stock or pharmacist verification. Call before travelling.",
        }
