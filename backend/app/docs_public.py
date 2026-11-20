"""Read-only docs relay. Expose this port, never the private application port."""

import re
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import Response

PUBLIC_PATHS = {
    "/docs",
    "/docs/assets/docs.css",
    "/docs/assets/docs.js",
    "/api/docs/public",
    "/api/docs/export",
}


def allowed(path):
    return path in PUBLIC_PATHS or bool(re.fullmatch(r"/docs/team/[a-f0-9]{32}", path))


def create_relay():
    relay = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @relay.api_route(
        "/{path:path}",
        methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        include_in_schema=False,
    )
    async def forward(path: str, request: Request):
        target = "/" + path
        if target == "/" and request.method in ("GET", "HEAD"):
            return Response(
                status_code=307,
                headers={"Location": "/docs", "Cache-Control": "no-store"},
            )
        if request.method not in ("GET", "HEAD") or not allowed(target):
            return Response(
                "Not available", status_code=404, headers={"Cache-Control": "no-store"}
            )
        try:
            async with httpx.AsyncClient(
                trust_env=False, follow_redirects=False, timeout=20
            ) as client:
                # No credentials, cookies, query values or caller-controlled host are forwarded.
                result = await client.get("http://127.0.0.1:8000" + target)
            headers = {
                k: v
                for k, v in result.headers.items()
                if k.lower()
                in (
                    "content-type",
                    "content-disposition",
                    "content-security-policy",
                    "x-content-type-options",
                    "x-frame-options",
                    "referrer-policy",
                )
            }
            headers["Cache-Control"] = "no-store"
            return Response(
                result.content if request.method == "GET" else b"",
                status_code=result.status_code,
                headers=headers,
            )
        except httpx.HTTPError:
            return Response(
                "Documentation backend unavailable. Retry later.",
                status_code=503,
                headers={"Cache-Control": "no-store"},
            )

    return relay


if __name__ == "__main__":
    import uvicorn

    print(
        "Read-only docs relay at http://127.0.0.1:8010. Keep the backend on port 8000 running."
    )
    uvicorn.run(
        create_relay(),
        host="127.0.0.1",
        port=8010,
        access_log=False,
        proxy_headers=False,
    )
