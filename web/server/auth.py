"""Uwierzytelnianie: hasła (scrypt), kody TOTP (RFC 6238), kody zapasowe, blokada po nieudanych próbach.

Tylko biblioteka standardowa. Konta w pliku users.json w katalogu danych (prawa 0600).
"""
import base64
import hashlib
import hmac
import json
import os
import secrets
import struct
import threading
import time
import urllib.parse

# MARK: - Hasła

SCRYPT_N, SCRYPT_R, SCRYPT_P = 2 ** 15, 8, 1
MIN_PASSWORD_LENGTH = 10


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, maxmem=64 * 1024 * 1024, dklen=32)
    return f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, n, r, p, salt, digest = stored.split("$")
        if scheme != "scrypt":
            return False
        actual = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p),
                                maxmem=64 * 1024 * 1024, dklen=len(base64.b64decode(digest)))
        return hmac.compare_digest(actual, base64.b64decode(digest))
    except (ValueError, TypeError):
        return False


# Stały koszt sprawdzenia nieistniejącego użytkownika (czas odpowiedzi nie zdradza loginów).
_DUMMY_HASH = hash_password(secrets.token_hex(8))

# MARK: - TOTP


def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp(secret: str, counter: int, digits: int = 6) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(code).zfill(digits)


def totp_counter(now: float | None = None) -> int:
    return int((time.time() if now is None else now) // 30)


def verify_totp(secret: str, code: str, last_counter: int, now: float | None = None) -> int | None:
    """Zwraca licznik użytego kodu (do ochrony przed ponownym użyciem) albo None. Okno ±1 krok (30 s)."""
    code = "".join(ch for ch in str(code) if ch.isdigit())
    if len(code) != 6:
        return None
    current = totp_counter(now)
    for counter in (current - 1, current, current + 1):
        if counter > last_counter and hmac.compare_digest(totp(secret, counter), code):
            return counter
    return None


def otpauth_uri(secret: str, username: str, issuer: str = "CantatePresenter") -> str:
    label = urllib.parse.quote(f"{issuer}:{username}")
    query = urllib.parse.urlencode({"secret": secret, "issuer": issuer, "algorithm": "SHA1", "digits": 6, "period": 30})
    return f"otpauth://totp/{label}?{query}"


# MARK: - Kody zapasowe


def new_backup_codes(count: int = 8) -> list[str]:
    alphabet = "abcdefghjkmnpqrstuvwxyz23456789"
    return ["-".join("".join(secrets.choice(alphabet) for _ in range(4)) for _ in range(2)) for _ in range(count)]


def hash_backup_code(code: str) -> str:
    return hashlib.sha256(code.replace("-", "").strip().lower().encode()).hexdigest()


# MARK: - Konta


class Users:
    """Plik users.json: {"users": {nazwa: {...}}}. Zapis atomowy, blokada wątków."""

    MAX_FAILURES = 5
    LOCK_SECONDS = 15 * 60

    def __init__(self, path: str):
        self.path = path
        self.lock = threading.RLock()
        self.users = {}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as source:
                self.users = json.load(source).get("users", {})

    def save(self):
        with self.lock:
            temporary = f"{self.path}.tmp"
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as target:
                json.dump({"users": self.users}, target, indent=2, ensure_ascii=False)
            os.replace(temporary, self.path)

    @staticmethod
    def valid_username(name: str) -> bool:
        return 1 <= len(name) <= 64 and all(ch.isalnum() or ch in "._-@" for ch in name)

    def add(self, name: str, password: str):
        if not self.valid_username(name):
            raise ValueError("Nazwa użytkownika: litery, cyfry i . _ - @ (do 64 znaków).")
        if len(password) < MIN_PASSWORD_LENGTH:
            raise ValueError(f"Hasło musi mieć co najmniej {MIN_PASSWORD_LENGTH} znaków.")
        with self.lock:
            if name in self.users:
                raise ValueError("Taki użytkownik już istnieje.")
            self.users[name] = {"password": hash_password(password), "totpSecret": None, "totpLastCounter": -1,
                                "backupCodes": [], "failures": 0, "lockedUntil": 0, "createdAt": int(time.time())}
            self.save()

    def set_password(self, name: str, password: str):
        if len(password) < MIN_PASSWORD_LENGTH:
            raise ValueError(f"Hasło musi mieć co najmniej {MIN_PASSWORD_LENGTH} znaków.")
        with self.lock:
            self.users[name]["password"] = hash_password(password)
            self.save()

    def reset_totp(self, name: str):
        with self.lock:
            self.users[name].update(totpSecret=None, totpLastCounter=-1, backupCodes=[])
            self.save()

    def remove(self, name: str):
        with self.lock:
            self.users.pop(name, None)
            self.save()

    def is_locked(self, name: str, now: float | None = None) -> bool:
        user = self.users.get(name)
        return bool(user and user.get("lockedUntil", 0) > (time.time() if now is None else now))

    def record_failure(self, name: str):
        with self.lock:
            user = self.users.get(name)
            if not user:
                return
            user["failures"] = user.get("failures", 0) + 1
            if user["failures"] >= self.MAX_FAILURES:
                user["lockedUntil"] = int(time.time()) + self.LOCK_SECONDS
                user["failures"] = 0
            self.save()

    def record_success(self, name: str):
        with self.lock:
            user = self.users[name]
            if user.get("failures"):
                user["failures"] = 0
                self.save()

    def check_password(self, name: str, password: str) -> bool:
        user = self.users.get(name)
        if not user:
            verify_password(password, _DUMMY_HASH)
            return False
        return verify_password(password, user["password"])

    def check_second_factor(self, name: str, code: str) -> bool:
        """Kod TOTP (jednorazowo w swoim oknie czasu) albo niewykorzystany kod zapasowy."""
        with self.lock:
            user = self.users.get(name)
            if not user or not user.get("totpSecret"):
                return False
            counter = verify_totp(user["totpSecret"], code, user.get("totpLastCounter", -1))
            if counter is not None:
                user["totpLastCounter"] = counter
                self.save()
                return True
            hashed = hash_backup_code(code)
            for stored in user.get("backupCodes", []):
                if hmac.compare_digest(stored, hashed):
                    user["backupCodes"].remove(stored)
                    self.save()
                    return True
            return False

    def regenerate_backup_codes(self, name: str) -> list[str]:
        """Nowe kody zapasowe; poprzednie przestają działać."""
        with self.lock:
            codes = new_backup_codes()
            self.users[name]["backupCodes"] = [hash_backup_code(c) for c in codes]
            self.save()
            return codes

    def enroll_totp(self, name: str, secret: str, code: str) -> list[str] | None:
        """Potwierdza konfigurację aplikacji kodem; zwraca kody zapasowe (pokazywane raz)."""
        with self.lock:
            counter = verify_totp(secret, code, -1)
            if counter is None:
                return None
            codes = new_backup_codes()
            self.users[name].update(totpSecret=secret, totpLastCounter=counter, backupCodes=[hash_backup_code(c) for c in codes])
            self.save()
            return codes
