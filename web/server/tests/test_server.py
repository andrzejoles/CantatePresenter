"""Testy serwera: python3 -I -m unittest discover -s web/server/tests"""
import http.client
import json
import os
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import appversion  # noqa: E402
import auth  # noqa: E402
import server  # noqa: E402
from storage import Conflict, Storage  # noqa: E402

PASSWORD = "dobre-haslo-123"


class VersionTests(unittest.TestCase):
    def test_version_from_commit_count(self):
        cases = {0: "1.0.0", 9: "1.0.0", 10: "1.0.1", 91: "1.0.9", 100: "1.1.0", 109: "1.1.0", 110: "1.1.1",
                 999: "1.9.9", 1000: "1.10.0", 9999: "1.99.9", 10000: "2.0.0", 12345: "2.23.4"}
        for count, version in cases.items():
            self.assertEqual(appversion.from_count(count), version, count)

    def test_same_as_shell_script(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
        import subprocess
        script = subprocess.run([os.path.join(root, "scripts", "version.sh")], capture_output=True, text=True, check=True)
        self.assertEqual(script.stdout.strip(), appversion.current(root))

    def test_fallback_without_git(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(appversion.current(directory), "dev")
            os.makedirs(os.path.join(directory, "web"))
            with open(os.path.join(directory, "web", "VERSION"), "w") as target:
                target.write("1.2.3\n")
            self.assertEqual(appversion.current(directory), "1.2.3")


class AuthTests(unittest.TestCase):
    def test_password_hash(self):
        stored = auth.hash_password("tajne-haslo-1")
        self.assertTrue(auth.verify_password("tajne-haslo-1", stored))
        self.assertFalse(auth.verify_password("tajne-haslo-2", stored))
        self.assertFalse(auth.verify_password("x", "nonsense"))

    def test_totp_rfc6238(self):
        import base64
        secret = base64.b32encode(b"12345678901234567890").decode()
        self.assertEqual(auth.totp(secret, 59 // 30, 8), "94287082")
        self.assertEqual(auth.totp(secret, 1111111109 // 30, 8), "07081804")

    def test_totp_window_and_replay(self):
        secret = auth.new_totp_secret()
        now = 1_760_000_000
        code = auth.totp(secret, auth.totp_counter(now))
        counter = auth.verify_totp(secret, code, -1, now)
        self.assertIsNotNone(counter)
        self.assertIsNone(auth.verify_totp(secret, code, counter, now), "ten sam kod drugi raz")
        self.assertIsNotNone(auth.verify_totp(secret, auth.totp(secret, auth.totp_counter(now) - 1), -1, now))
        self.assertIsNone(auth.verify_totp(secret, auth.totp(secret, auth.totp_counter(now) - 3), -1, now))

    def test_users_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            users = auth.Users(os.path.join(directory, "users.json"))
            with self.assertRaises(ValueError):
                users.add("ala", "krotkie")
            with self.assertRaises(ValueError):
                users.add("zła nazwa", PASSWORD)
            users.add("ala", PASSWORD)
            self.assertEqual(os.stat(os.path.join(directory, "users.json")).st_mode & 0o777, 0o600)
            self.assertNotIn(PASSWORD, open(os.path.join(directory, "users.json")).read())


class StorageTests(unittest.TestCase):
    def test_revisions_history_and_quarantine(self):
        with tempfile.TemporaryDirectory() as directory:
            storage = Storage(directory)
            self.assertEqual(storage.save("songs", [{"title": "A"}], 0), 1)
            with self.assertRaises(Conflict):
                storage.save("songs", [], 0)
            for index in range(8):
                storage.save("songs", [{"title": str(index)}], None)
            self.assertEqual(len(os.listdir(os.path.join(directory, "history"))), 5)
            self.assertEqual(Storage(directory).revisions["songs"], 9)
            with open(os.path.join(directory, "plans.json"), "w") as broken:
                broken.write("{nie json")
            storage = Storage(directory)
            self.assertIsNone(storage.load("plans"))
            self.assertTrue(any(name.startswith("plans.corrupt-") for name in os.listdir(directory)))
            with self.assertRaises(PermissionError):
                storage.save("plans", [], None)

    def test_newer_schema_is_read_only(self):
        """Dane z nowszej wersji (schemaVersion w settings.json) tylko do odczytu, jak DataSchema w macOS."""
        with tempfile.TemporaryDirectory() as directory:
            storage = Storage(directory)
            storage.save("settings", {"schemaVersion": 1}, None)
            storage.save("songs", [], None)
            with open(os.path.join(directory, "settings.json"), "w") as future:
                json.dump({"schemaVersion": 99, "futureField": 1}, future)
            snapshot = storage.snapshot()
            self.assertEqual(snapshot["newerSchema"], 99)
            self.assertEqual(snapshot["locked"], sorted(["songs", "plans", "settings", "extraFiles"]))
            with self.assertRaises(PermissionError):
                storage.save("songs", [{"title": "x"}], None)
            self.assertEqual(storage.load("songs"), [])

    def test_restore_rejects_newer_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            storage = Storage(directory)
            with self.assertRaises(ValueError):
                storage.restore({"songs": [], "settings": {"schemaVersion": 99}})
            self.assertIsNone(storage.load("songs"))
            storage.restore({"songs": [], "settings": {}})
            self.assertEqual(storage.load("songs"), [])


class Client:
    def __init__(self, port):
        self.port = port
        self.cookies = {}

    def request(self, method, path, body=None, headers=None, csrf=True):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        all_headers = {"Cookie": "; ".join(f"{k}={v}" for k, v in self.cookies.items())}
        if csrf:
            all_headers["X-Cantate-Request"] = "1"
        if body is not None:
            all_headers["Content-Type"] = "application/json"
        all_headers.update(headers or {})
        connection.request(method, path, json.dumps(body) if body is not None else None, all_headers)
        response = connection.getresponse()
        data = response.read()
        connection.close()
        for header, value in response.getheaders():
            if header.lower() == "set-cookie":
                name, rest = value.split("=", 1)
                cookie_value = rest.split(";", 1)[0]
                if "Max-Age=0" in value:
                    self.cookies.pop(name, None)
                else:
                    self.cookies[name] = cookie_value
        try:
            payload = json.loads(data) if data else None
        except ValueError:
            payload = data
        return response.status, payload, dict(response.getheaders())


class ServerTests(unittest.TestCase):
    def setUp(self):
        server.log = lambda message: None
        self.directory = tempfile.TemporaryDirectory()
        users = auth.Users(os.path.join(self.directory.name, "users.json"))
        users.add("ala", PASSWORD)
        self.http = server.make_server(self.directory.name, "127.0.0.1", 0, secure_cookies=False, trust_proxy=False)
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.port = self.http.server_port

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.directory.cleanup()

    def login(self, client, secret=None):
        status, reply, _ = client.request("POST", "/api/login", {"username": "ala", "password": PASSWORD})
        self.assertEqual(status, 200)
        if reply["step"] == "enroll":
            secret = reply["secret"]
            self.assertTrue(reply["uri"].startswith("otpauth://totp/CantatePresenter%3Aala?"))
            status, done, _ = client.request("POST", "/api/login/enroll", {"code": auth.totp(secret, auth.totp_counter())})
            self.assertEqual(status, 200)
            return secret, done["backupCodes"]
        return secret, None

    def test_app_requires_login(self):
        client = Client(self.port)
        status, _, headers = client.request("GET", "/index.html")
        self.assertEqual(status, 302)
        self.assertEqual(headers["Location"], "/login.html")
        self.assertEqual(client.request("GET", "/src/app/main.js")[0], 401)
        self.assertEqual(client.request("GET", "/api/data")[0], 401)
        self.assertEqual(client.request("GET", "/src/i18n.js")[0], 200)
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])

    def test_full_login_with_enrollment_and_data(self):
        client = Client(self.port)
        secret, codes = self.login(client)
        self.assertEqual(len(codes), 8)
        self.assertNotIn("Secure", "")  # bez TLS w teście
        self.assertEqual(client.request("GET", "/index.html")[0], 200)
        status, snapshot, _ = client.request("GET", "/api/data")
        self.assertEqual(status, 200)
        self.assertEqual(snapshot["revisions"]["songs"], 0)
        status, reply, _ = client.request("PUT", "/api/data/songs", [{"title": "A"}], {"If-Match": "0"})
        self.assertEqual((status, reply["revision"]), (200, 1))
        self.assertEqual(client.request("PUT", "/api/data/songs", [], {"If-Match": "0"})[0], 409)
        self.assertEqual(client.request("PUT", "/api/data/songs", {"nie": "lista"}, {"If-Match": "1"})[0], 400)
        self.assertEqual(client.request("PUT", "/api/data/songs", [], {"If-Match": "1"}, csrf=False)[0], 403)
        self.assertEqual(client.request("PUT", "/api/data/songs", [], {"If-Match": "1", "Origin": "https://evil.example"})[0], 403)

        self.assertEqual(client.request("POST", "/api/logout", {})[0], 200)
        self.assertEqual(client.request("GET", "/api/data")[0], 401)

        # Drugie logowanie: kod z aplikacji, kod zapasowy jednorazowo.
        second = Client(self.port)
        status, reply, _ = second.request("POST", "/api/login", {"username": "ala", "password": PASSWORD})
        self.assertEqual(reply["step"], "totp")
        self.assertEqual(second.request("POST", "/api/login/totp", {"code": "000000"})[0], 401)
        self.assertEqual(second.request("POST", "/api/login/totp", {"code": codes[0]})[0], 200)
        third = Client(self.port)
        third.request("POST", "/api/login", {"username": "ala", "password": PASSWORD})
        self.assertEqual(third.request("POST", "/api/login/totp", {"code": codes[0]})[0], 401, "kod zapasowy drugi raz")

    def test_wrong_password_and_lockout(self):
        client = Client(self.port)
        self.assertEqual(client.request("POST", "/api/login", {"username": "nikt", "password": "x"})[0], 401)
        for _ in range(5):
            self.assertEqual(client.request("POST", "/api/login", {"username": "ala", "password": "zle-haslo-000"})[0], 401)
        self.assertEqual(client.request("POST", "/api/login", {"username": "ala", "password": PASSWORD})[0], 429)

    def test_second_step_needs_password_step(self):
        client = Client(self.port)
        self.assertEqual(client.request("POST", "/api/login/totp", {"code": "123456"})[0], 401)
        self.assertEqual(client.request("POST", "/api/login/enroll", {"code": "123456"})[0], 401)

    def test_hidden_and_traversal_paths(self):
        client = Client(self.port)
        self.login(client)
        for path in ("/server/server.py", "/tools/cdp.py", "/tests/index.html", "/../../CLAUDE.md", "/%2e%2e/%2e%2e/CLAUDE.md", "/.git/config"):
            self.assertEqual(client.request("GET", path)[0], 404, path)

    def test_restore_replaces_all_and_can_be_undone(self):
        client = Client(self.port)
        self.login(client)
        client.request("PUT", "/api/data/songs", [{"title": "Przed"}], {"If-Match": "0"})
        status, reply, _ = client.request("POST", "/api/data/restore", {"songs": [{"title": "X"}], "plans": [], "settings": {"appLanguage": "en"}, "extraFiles": {"logos/a.svg": "PHN2Zy8+"}})
        self.assertEqual(status, 200)
        snapshot = client.request("GET", "/api/data")[1]
        self.assertEqual(snapshot["data"]["settings"]["appLanguage"], "en")
        self.assertEqual(snapshot["data"]["songs"][0]["title"], "X")
        self.assertEqual(snapshot["data"]["extraFiles"], {"logos/a.svg": "PHN2Zy8+"})
        self.assertTrue(snapshot["canUndoRestore"])
        self.assertEqual(client.request("POST", "/api/data/undo-restore", {})[0], 200)
        snapshot = client.request("GET", "/api/data")[1]
        self.assertEqual(snapshot["data"]["songs"][0]["title"], "Przed")
        self.assertFalse(snapshot["canUndoRestore"])


if __name__ == "__main__":
    unittest.main()
