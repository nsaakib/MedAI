import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
from contextlib import contextmanager
from cryptography.fernet import Fernet


def now():
    return int(time.time())


def uid():
    return secrets.token_hex(16)


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def password_hash(password):
    salt = secrets.token_bytes(16)
    key = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1)
    return base64.b64encode(salt + key).decode()


def verify_password(password, encoded):
    try:
        raw = base64.b64decode(encoded)
        return hmac.compare_digest(
            hashlib.scrypt(password.encode(), salt=raw[:16], n=16384, r=8, p=1),
            raw[16:],
        )
    except (ValueError, TypeError):
        return False


class Store:
    def __init__(self, directory, key):
        self.root = Path(directory)
        self.root.mkdir(parents=True, exist_ok=True)
        self.files = self.root / "documents"
        self.files.mkdir(exist_ok=True)
        self.path = self.root / "medai.db"
        self.key = key
        self.cipher = Fernet(key)
        with self.db() as db:
            db.executescript(
                """
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email_hash TEXT UNIQUE NOT NULL,password TEXT NOT NULL,role TEXT NOT NULL,created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS states(user_id TEXT PRIMARY KEY REFERENCES users(id),version INTEGER NOT NULL,payload BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS sync_receipts(user_id TEXT NOT NULL,event_id TEXT NOT NULL,digest TEXT NOT NULL,version INTEGER NOT NULL,PRIMARY KEY(user_id,event_id));
CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),payload BLOB NOT NULL,created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS cases(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),status TEXT NOT NULL,version INTEGER NOT NULL,payload BLOB NOT NULL,created INTEGER NOT NULL,updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS audits(id INTEGER PRIMARY KEY AUTOINCREMENT,actor TEXT NOT NULL,action TEXT NOT NULL,target TEXT NOT NULL,created INTEGER NOT NULL);
"""
            )

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA journal_mode=WAL")
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def encrypt(self, data):
        return self.cipher.encrypt(
            json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode()
        )

    def decrypt(self, data):
        return json.loads(self.cipher.decrypt(data))

    def audit(self, db, actor, action, target):
        db.execute(
            "INSERT INTO audits(actor,action,target,created) VALUES(?,?,?,?)",
            (actor, action, target, now()),
        )

    def create_user(self, email, password, name, role="patient"):
        identifier = uid()
        state = {
            "name": name,
            "email": email.strip().lower(),
            "phone": "",
            "allergies": "",
            "medicines": [],
            "vitals": [],
            "doses": [],
            "reminders": [],
            "budget": 0,
            "delivery": 0,
            "selected_ids": [],
            "journal": "",
            "mood": "",
            "language": "English",
            "timezone": "Asia/Dhaka",
        }
        with self.db() as db:
            db.execute(
                "INSERT INTO users VALUES(?,?,?,?,?)",
                (
                    identifier,
                    token_hash(email.strip().lower()),
                    password_hash(password),
                    role,
                    now(),
                ),
            )
            db.execute(
                "INSERT INTO states VALUES(?,?,?)", (identifier, 0, self.encrypt(state))
            )
            self.audit(db, identifier, "account.created", identifier)
        return identifier

    def session(self, identifier):
        token = secrets.token_urlsafe(40)
        with self.db() as db:
            db.execute(
                "INSERT INTO sessions VALUES(?,?,?)",
                (token_hash(token), identifier, now() + 7 * 86400),
            )
        return token
