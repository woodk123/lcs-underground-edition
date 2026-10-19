"""Real loopback requests cover concurrent cold loads and static-file safety."""
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from http.client import HTTPConnection, HTTPResponse
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import unittest

from serve import GameHandler, GameServer


class QuietGameHandler(GameHandler):
    def log_message(self, format, *args):
        pass


class GameServerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "web"
        (self.root / "assets").mkdir(parents=True)
        (self.root / "index.html").write_text("<html>QA game</html>", encoding="utf-8")
        self.manifest = b'[{"family":"QA","fonts":[{"asset":"fonts/QA.woff2"}]}]'
        (self.root / "assets" / "FontManifest.json").write_bytes(self.manifest)
        (self.root / "main.dart.js").write_bytes(b"console.log('QA');")
        (self.root / "canvaskit.wasm").write_bytes(b"\x00asmQA")

    def server(self):
        server = GameServer(
            ("127.0.0.1", 0),
            partial(QuietGameHandler, directory=str(self.root)),
        )
        self.addCleanup(server.server_close)
        return server

    def start(self, server):
        thread = threading.Thread(
            target=server.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )
        thread.start()

        def stop():
            server.shutdown()
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive(), "Loopback test server did not stop")

        self.addCleanup(stop)

    def request(self, server, path, headers=None, method="GET"):
        connection = HTTPConnection(*server.server_address, timeout=1)
        try:
            connection.request(method, path, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.headers, response.read()
        finally:
            connection.close()

    def test_cold_asset_connections_queue_before_the_accept_loop_starts(self):
        server = self.server()  # Already bound/listening; accepting is paused.
        request = (
            b"GET /assets/FontManifest.json HTTP/1.0\r\n"
            b"Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )

        def connect(_):
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.settimeout(1)
            try:
                client.connect(server.server_address)
                client.sendall(request)
                return client, None
            except OSError as error:
                client.close()
                return None, str(error)

        with ThreadPoolExecutor(max_workers=48) as pool:
            connected = list(pool.map(connect, range(48)))
        clients = [client for client, error in connected if client is not None]
        failures = [error for client, error in connected if error is not None]
        try:
            # No request was accepted until the entire parallel burst finished.
            self.start(server)
            for client in clients:
                with HTTPResponse(client) as response:
                    response.begin()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.getheader("Content-Type"), "application/json")
                    self.assertEqual(response.read(), self.manifest)
            self.assertEqual(failures, [], f"Only {len(clients)}/48 cold asset connections queued")
            self.assertEqual(len(clients), 48)
        finally:
            for client in clients:
                client.close()

    def test_health_identifies_the_served_build_and_keeps_security_headers(self):
        server = self.server()
        self.start(server)
        status, headers, body = self.request(server, "/__lcs_launcher_health?fresh=1")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {
            "application": "lcs-modern-local",
            "directory": str(self.root.resolve()),
        })
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(int(headers["Content-Length"]), len(body))
        self.assertEqual(headers["Cache-Control"], "no-cache")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")

    def test_flutter_assets_have_browser_usable_mime_types_and_security_headers(self):
        server = self.server()
        self.start(server)
        for path, expected_type, expected_body in [
            ("/assets/FontManifest.json", "application/json", self.manifest),
            ("/main.dart.js?fresh=1", "text/javascript", b"console.log('QA');"),
            ("/canvaskit.wasm", "application/wasm", b"\x00asmQA"),
        ]:
            with self.subTest(path=path):
                status, headers, body = self.request(server, path)
                self.assertEqual(status, 200)
                self.assertEqual(headers["Content-Type"], expected_type)
                self.assertEqual(body, expected_body)
                self.assertEqual(headers["Cache-Control"], "no-cache")
                self.assertEqual(headers["X-Content-Type-Options"], "nosniff")

    def test_directory_listing_and_parent_paths_do_not_expose_files(self):
        private = self.root / "private"
        private.mkdir()
        (private / "unlisted.txt").write_bytes(b"directory-only content")
        secret = Path(self.temporary.name) / "secret.txt"
        secret.write_bytes(b"outside-root secret")
        server = self.server()
        self.start(server)
        status, headers, body = self.request(server, "/private/")
        self.assertEqual(status, 403)
        self.assertNotIn(b"unlisted.txt", body)
        for path in ["/../secret.txt", "/%2e%2e/secret.txt"]:
            with self.subTest(path=path):
                status, headers, body = self.request(server, path)
                self.assertEqual(status, 404)
                self.assertNotIn(b"outside-root secret", body)

    def test_date_only_cache_from_another_build_cannot_hide_new_bytes(self):
        server = self.server()
        self.start(server)
        for name, url in [("index.html", "/"), ("sw.js", "/sw.js"),
                          ("main.dart.js", "/main.dart.js?version=next")]:
            with self.subTest(name=name):
                path = self.root / name
                path.write_bytes(b"old-build")
                os.utime(path, (2_000_000_000, 2_000_000_000))
                _, original, _ = self.request(server, url)
                path.write_bytes(b"new-build")  # Same size; older archive mtime.
                os.utime(path, (315_532_800, 315_532_800))
                status, headers, body = self.request(server, url, {
                    "If-Modified-Since": original["Last-Modified"],
                })
                self.assertEqual(status, 200)
                self.assertEqual(body, b"new-build")
                self.assertTrue(headers["ETag"].startswith('"'))

    def test_content_etags_revalidate_even_with_identical_size_and_mtime(self):
        path = self.root / "main.dart.js"
        path.write_bytes(b"first-build")
        os.utime(path, (315_532_800, 315_532_800))
        server = self.server()
        self.start(server)
        _, original, _ = self.request(server, "/main.dart.js")
        self.assertIsNotNone(original["ETag"])
        status, headers, body = self.request(server, "/main.dart.js", {
            "If-None-Match": original["ETag"],
        })
        self.assertEqual((status, body), (304, b""))
        self.assertEqual(headers["ETag"], original["ETag"])
        self.assertEqual(headers["Cache-Control"], "no-cache")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        path.write_bytes(b"other-build")
        os.utime(path, (315_532_800, 315_532_800))
        status, changed, body = self.request(server, "/main.dart.js", {
            "If-None-Match": original["ETag"],
            "If-Modified-Since": "Wed, 18 May 2033 03:33:20 GMT",
        })
        self.assertEqual((status, body), (200, b"other-build"))
        self.assertNotEqual(changed["ETag"], original["ETag"])
        status, _, body = self.request(server, "/main.dart.js", {
            "If-None-Match": f'"unrelated", W/{changed["ETag"]}',
        })
        self.assertEqual((status, body), (304, b""))
        status, head, body = self.request(server, "/main.dart.js", method="HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertEqual(head["ETag"], changed["ETag"])
        self.assertEqual(int(head["Content-Length"]), len(b"other-build"))
        status, _, body = self.request(server, "/main.dart.js", {
            "If-None-Match": changed["ETag"],
        }, method="HEAD")
        self.assertEqual((status, body), (304, b""))

    def test_symlink_cannot_escape_the_served_build(self):
        secret = Path(self.temporary.name) / "secret.txt"
        secret.write_bytes(b"outside-root secret")
        try:
            (self.root / "external.txt").symlink_to(secret)
            indexed = self.root / "indexed"
            indexed.mkdir()
            (indexed / "index.html").symlink_to(secret)
        except OSError as error:
            self.skipTest(f"Host does not permit test symlinks: {error}")
        server = self.server()
        self.start(server)
        for path in ("/external.txt", "/indexed/"):
            with self.subTest(path=path):
                status, headers, body = self.request(server, path)
                self.assertEqual(status, 404)
                self.assertNotIn(b"outside-root secret", body)


if __name__ == "__main__":
    unittest.main()
