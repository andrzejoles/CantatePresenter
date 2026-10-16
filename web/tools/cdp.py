#!/usr/bin/env python3
"""Sterowanie Chrome bez okna przez protokół DevTools (tylko biblioteka standardowa).

Do testów interfejsu wersji webowej: otwarcie strony, czekanie na element, wykonanie JS,
kliknięcie, klawisze, zrzut ekranu. Przykład w web/tools/ui_check.py.
"""
import base64
import json
import os
import socket
import struct
import subprocess
import tempfile
import time
import urllib.request

CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")


class WebSocket:
    """Minimalny klient WebSocket (RFC 6455) do lokalnego DevTools: tekst, bez rozszerzeń."""

    def __init__(self, url):
        assert url.startswith("ws://")
        host_port, path = url[5:].split("/", 1)
        host, port = host_port.split(":")
        self.sock = socket.create_connection((host, int(port)))
        key = base64.b64encode(os.urandom(16)).decode()
        request = (f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                   f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.sock.sendall(request.encode())
        response = b""
        while b"\r\n\r\n" not in response:
            response += self.sock.recv(1)
        if b" 101 " not in response.split(b"\r\n")[0]:
            raise RuntimeError(response.decode(errors="replace"))
        self.buffer = b""

    def send(self, text):
        data = text.encode()
        header = bytearray([0x81])
        mask = os.urandom(4)
        if len(data) < 126:
            header.append(0x80 | len(data))
        elif len(data) < 65536:
            header.append(0x80 | 126)
            header += struct.pack(">H", len(data))
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", len(data))
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(bytes(header) + mask + masked)

    def _read(self, n):
        while len(self.buffer) < n:
            chunk = self.sock.recv(1 << 20)
            if not chunk:
                raise ConnectionError("closed")
            self.buffer += chunk
        data, self.buffer = self.buffer[:n], self.buffer[n:]
        return data

    def receive(self):
        message = b""
        while True:
            first, second = self._read(2)
            length = second & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read(8))[0]
            payload = self._read(length)
            message += payload
            if first & 0x80:
                return message.decode()


class Browser:
    def __init__(self, width=1440, height=900, extra_args=()):
        self.profile = tempfile.mkdtemp(prefix="cantate-cdp-")
        self.process = subprocess.Popen(
            [CHROME, "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
             "--remote-debugging-port=0", f"--user-data-dir={self.profile}", f"--window-size={width},{height}",
             "--hide-scrollbars", *extra_args, "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        port_file = os.path.join(self.profile, "DevToolsActivePort")
        for _ in range(200):
            if os.path.exists(port_file) and open(port_file).read().strip():
                break
            time.sleep(0.05)
        port = open(port_file).read().split()[0]
        targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
        page = next(t for t in targets if t["type"] == "page")
        self.ws = WebSocket(page["webSocketDebuggerUrl"])
        self.next_id = 0
        self.events = []
        self.call("Page.enable")
        self.call("Runtime.enable")
        self.call("Emulation.setDeviceMetricsOverride", width=width, height=height, deviceScaleFactor=1, mobile=False)

    def call(self, method, **params):
        self.next_id += 1
        message_id = self.next_id
        self.ws.send(json.dumps({"id": message_id, "method": method, "params": params}))
        while True:
            message = json.loads(self.ws.receive())
            if message.get("id") == message_id:
                if "error" in message:
                    raise RuntimeError(f"{method}: {message['error']}")
                return message.get("result", {})
            self.events.append(message)

    def console_errors(self):
        errors = []
        for event in self.events:
            if event.get("method") == "Runtime.exceptionThrown":
                details = event["params"]["exceptionDetails"]
                errors.append(details.get("exception", {}).get("description") or details.get("text"))
            elif event.get("method") == "Runtime.consoleAPICalled" and event["params"]["type"] in ("error", "warning"):
                errors.append(" ".join(str(a.get("value", a.get("description", ""))) for a in event["params"]["args"]))
        return errors

    def goto(self, url):
        self.call("Page.navigate", url=url)

    def evaluate(self, expression):
        result = self.call("Runtime.evaluate", expression=expression, awaitPromise=True, returnByValue=True)
        if "exceptionDetails" in result:
            raise RuntimeError(result["exceptionDetails"].get("exception", {}).get("description", "JS error"))
        return result.get("result", {}).get("value")

    def wait_for(self, expression, timeout=10):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if self.evaluate(expression):
                    return True
            except RuntimeError:
                pass
            time.sleep(0.1)
        raise TimeoutError(expression)

    def click(self, selector):
        box = self.evaluate(f"(() => {{ const e = document.querySelector({json.dumps(selector)}); if (!e) return null; e.scrollIntoView({{block: 'center'}}); const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }})()")
        if not box:
            raise LookupError(selector)
        for kind in ("mousePressed", "mouseReleased"):
            self.call("Input.dispatchMouseEvent", type=kind, x=box[0], y=box[1], button="left", clickCount=1)

    def key(self, code, key=None, text=None, modifiers=0):
        params = {"code": code, "key": key or code, "modifiers": modifiers}
        if text:
            params["text"] = text
        self.call("Input.dispatchKeyEvent", type="keyDown", **params)
        self.call("Input.dispatchKeyEvent", type="keyUp", code=code, key=key or code, modifiers=modifiers)

    def type(self, text):
        self.call("Input.insertText", text=text)

    def screenshot(self, path):
        data = self.call("Page.captureScreenshot", format="png")["data"]
        with open(path, "wb") as output:
            output.write(base64.b64decode(data))

    def close(self):
        try:
            self.process.terminate()
            self.process.wait(timeout=5)
        except Exception:
            self.process.kill()
