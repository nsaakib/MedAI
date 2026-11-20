"""Local setup and clinician provisioning. Never ship passwords or keys in source."""

import argparse
import getpass
import os
from pathlib import Path
from cryptography.fernet import Fernet
from .core import Store, password_hash, token_hash


def load_env():
    file = Path(".env")
    if file.exists():
        for line in file.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k, v.strip().strip('"'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["init", "clinician", "password"])
    args = parser.parse_args()
    if args.command == "init":
        file = Path(".env")
        if file.exists():
            print(".env already exists; kept existing encryption key.")
            return
        file.write_text(
            "MEDAI_ENCRYPTION_KEY="
            + Fernet.generate_key().decode()
            + "\nMEDAI_DATA_DIR=./data\nMEDAI_OCR_ENABLED=false\n"
        )
        file.chmod(0o600)
        print(
            "Created .env. Back it up securely with the database; losing the key makes records unreadable."
        )
    else:
        load_env()
        store = Store(
            os.environ.get("MEDAI_DATA_DIR", "./data"),
            os.environ["MEDAI_ENCRYPTION_KEY"],
        )
        email = input("Account email: ").strip().lower()
        name = (
            input("Clinician name: ").strip()
            if args.command == "clinician"
            else "Account recovery"
        )
        password = getpass.getpass("Password (at least 10 characters): ")
        if len(password) < 10 or "@" not in email or not name:
            raise SystemExit("Invalid account details")
        if args.command == "password":
            with store.db() as db:
                user = db.execute(
                    "SELECT id FROM users WHERE email_hash=?", (token_hash(email),)
                ).fetchone()
                if not user:
                    raise SystemExit("Account not found")
                db.execute(
                    "UPDATE users SET password=? WHERE id=?",
                    (password_hash(password), user["id"]),
                )
                db.execute("DELETE FROM sessions WHERE user_id=?", (user["id"],))
                store.audit(db, "local-admin", "password.reset", user["id"])
            print("Password reset and all sessions revoked.")
            return
        store.create_user(email, password, name, "clinician")
        print("Clinician account created. Sign in at /care-team.")


if __name__ == "__main__":
    main()
