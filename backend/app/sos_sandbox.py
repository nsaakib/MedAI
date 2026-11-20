"""Bind an isolated, test-only Med.ai server to loopback. No SMS or live dispatch."""
from pathlib import Path
from cryptography.fernet import Fernet
import uvicorn
from .main import create_app


def create_sandbox():
    root = (Path.cwd() / 'sos-local-sandbox').resolve()
    root.mkdir(mode=0o700, exist_ok=True)
    marker = root / 'sandbox.key'
    if not marker.exists():
        if (root / 'medai.db').exists():
            raise SystemExit('Sandbox directory has an existing database without a sandbox key.')
        with marker.open('xb') as key:
            key.write(Fernet.generate_key())
    app = create_app(directory=root, key=marker.read_bytes(), ocr_enabled=False, sos_sandbox=True)
    return app


def main():
    uvicorn.run(create_sandbox(), host='127.0.0.1', port=8001,
                proxy_headers=True, forwarded_allow_ips='127.0.0.1', access_log=False)


if __name__ == '__main__':
    main()
