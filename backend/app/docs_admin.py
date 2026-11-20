"""Trusted local provisioning; does not change patient or partner roles."""

import argparse
import getpass
import os
from pathlib import Path
from .core import Store, token_hash
from .manage import load_env
from .live_docs import initialize


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["live", "sandbox"], default="sandbox")
    parser.add_argument("--revoke", action="store_true")
    parser.add_argument(
        "--role", choices=["admin", "super_admin"], default="super_admin"
    )
    args = parser.parse_args()
    load_env()
    if args.mode == "sandbox":
        root = Path.cwd() / "sos-local-sandbox"
        marker = root / "sandbox.key"
        if not marker.is_file():
            raise SystemExit(
                "Start the sandbox server once before provisioning its documentation admin."
            )
        store = Store(root, marker.read_bytes())
    else:
        key = os.environ.get("MEDAI_ENCRYPTION_KEY")
        if not key:
            raise SystemExit(
                "Restore the existing backend .env. Do not generate another key for existing data."
            )
        store = Store(os.environ.get("MEDAI_DATA_DIR", "./data"), key)
    initialize(store)
    email = input("Documentation admin email: ").strip().lower()
    if "@" not in email or "." not in email.split("@")[-1] or len(email) > 254:
        raise SystemExit("Enter a valid account email.")
    with store.db() as db:
        row = db.execute(
            "SELECT id FROM users WHERE email_hash=?", (token_hash(email),)
        ).fetchone()
    if args.revoke:
        if not row:
            raise SystemExit("Account not found.")
        with store.db() as db:
            db.execute("DELETE FROM docs_admins WHERE user_id=?", (row["id"],))
            store.audit(db, "local-admin", "docs.admin_revoked", row["id"])
        print("Documentation permission revoked; the patient/partner account was kept.")
        return
    if row:
        identifier = row["id"]
    else:
        name = input("Admin display name: ").strip()
        password = getpass.getpass("New account password (at least 10 characters): ")
        repeat = getpass.getpass("Repeat password: ")
        if (
            not name
            or len(name) > 120
            or not 10 <= len(password) <= 256
            or password != repeat
        ):
            raise SystemExit("Name or matching password requirements were not met.")
        identifier = store.create_user(email, password, name)
    with store.db() as db:
        db.execute(
            "INSERT INTO docs_admins VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET role=excluded.role",
            (identifier, args.role),
        )
        store.audit(db, "local-admin", "docs.admin_granted", identifier)
    print(
        "Documentation " + args.role + " permission granted in " + args.mode + " mode."
    )
    print(
        "Sign in at /docs/admin using that account. Publish a draft and apply visibility settings."
    )
    print(
        "No existing account password, medical records or partner roles were changed."
    )


if __name__ == "__main__":
    main()
