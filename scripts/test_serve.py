"""Real loopback requests cover concurrent cold loads and static-file safety."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr
from functools import partial
from http.client import HTTPConnection, HTTPResponse, IncompleteRead
import hashlib
import io
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from serve import GameHandler, GameServer


class QuietGameHandler(GameHandler):
    def log_message(self, format, *args):
        pass


class CountingGameServer(GameServer):
    def __init__(self, *args, **kwargs):
        self.accepted_connections = 0
        self.socket_options = []
        self.stats_lock = threading.Lock()
        super().__init__(*args, **kwargs)

    def get_request(self):
        request, address = super().get_request()
        with self.stats_lock:
            self.accepted_connections += 1
        return request, address


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

    def server(self, handler=QuietGameHandler, server_class=GameServer):
        server = server_class(
            ("127.0.0.1", 0),
            partial(handler, directory=str(self.root)),
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

    def test_237_asset_requests_reuse_six_connections_with_tcp_nodelay(self):
        expected = {}
        for index in range(237):
            path = f"/assets/burst-{index}.bin"
            payload = f"Independent asset {index}\n".encode()
            (self.root / path.lstrip('/')).write_bytes(payload)
            expected[path] = payload

        class ObservedSocketHandler(QuietGameHandler):
            def setup(self):
                super().setup()
                with self.server.stats_lock:
                    self.server.socket_options.append(
                        self.connection.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY))

        server = self.server(ObservedSocketHandler, CountingGameServer)
        self.start(server)
        barrier = threading.Barrier(6)
        paths = list(expected)

        def load(batch):
            client = HTTPConnection(*server.server_address, timeout=5)
            try:
                barrier.wait(timeout=5)
                for path in batch:
                    client.request('GET', path)
                    response = client.getresponse()
                    self.assertEqual(response.version, 11)
                    self.assertEqual(response.status, 200)
                    self.assertFalse(response.will_close)
                    self.assertEqual(response.read(), expected[path])
            finally:
                client.close()

        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(load, [paths[index::6] for index in range(6)]))
        self.assertEqual(server.accepted_connections, 6)
        self.assertEqual(server.socket_options, [1] * 6)

    def test_persistent_health_head_conditional_and_redirect_responses_are_framed(self):
        server = self.server(server_class=CountingGameServer)
        self.start(server)
        client = HTTPConnection(*server.server_address, timeout=2)
        try:
            def exchange(method, path, status, headers=None):
                client.request(method, path, headers=headers or {})
                response = client.getresponse()
                self.assertEqual(response.status, status, (method, path))
                self.assertFalse(response.will_close, (method, path))
                return response, response.read()

            response, body = exchange('GET', '/__lcs_launcher_health', 200)
            self.assertEqual(json.loads(body)['directory'], str(self.root.resolve()))
            self.assertEqual(int(response.getheader('Content-Length')), len(body))
            response, body = exchange('GET', '/main.dart.js', 200)
            etag = response.getheader('ETag')
            self.assertEqual(body, b"console.log('QA');")
            response, body = exchange('HEAD', '/main.dart.js', 200)
            self.assertEqual(body, b'')
            self.assertEqual(int(response.getheader('Content-Length')), len(b"console.log('QA');"))
            response, body = exchange('GET', '/main.dart.js', 304, {'If-None-Match': etag})
            self.assertEqual(body, b'')
            response, body = exchange('GET', '/assets', 301)
            self.assertEqual((response.getheader('Location'), body), ('/assets/', b''))
            self.assertEqual(response.getheader('Content-Length'), '0')
            exchange('GET', '/__lcs_launcher_health', 200)
            self.assertEqual(server.accepted_connections, 1)
        finally:
            client.close()

    def test_explicit_close_http10_and_errors_close_without_duplicate_connection_headers(self):
        server = self.server(server_class=CountingGameServer)
        self.start(server)
        for method, path, headers, status in [
            ('GET', '/main.dart.js', {'Connection': 'close'}, 200),
            ('GET', '/missing.bin', {}, 404),
            ('HEAD', '/missing.bin', {}, 404),
            ('GET', '/assets/', {}, 403),
            ('POST', '/main.dart.js', {}, 501),
        ]:
            with self.subTest(method=method, path=path):
                client = HTTPConnection(*server.server_address, timeout=2)
                try:
                    client.request(method, path, headers=headers)
                    response = client.getresponse()
                    self.assertEqual(response.status, status)
                    self.assertTrue(response.will_close)
                    self.assertEqual(response.getheaders().count(('Connection', 'close')), 1)
                    body = response.read()
                    if method == 'HEAD':
                        self.assertEqual(body, b'')
                    else:
                        self.assertEqual(int(response.getheader('Content-Length')), len(body))
                finally:
                    client.close()
        with socket.create_connection(server.server_address, timeout=2) as client:
            client.sendall(b'GET /main.dart.js HTTP/1.0\r\nHost: localhost\r\n\r\n')
            with HTTPResponse(client) as response:
                response.begin()
                self.assertEqual(response.status, 200)
                self.assertTrue(response.will_close)
                self.assertEqual(response.read(), b"console.log('QA');")
            self.assertEqual(client.recv(1), b'')

    def test_buffered_pipelined_requests_keep_their_next_request_bytes(self):
        server = self.server(server_class=CountingGameServer)
        self.start(server)
        with socket.create_connection(server.server_address, timeout=2) as client:
            client.sendall(
                b'GET /main.dart.js HTTP/1.1\r\nHost: localhost\r\n\r\n'
                b'GET /assets/FontManifest.json HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
            with client.makefile('rb') as stream:
                for expected in [b"console.log('QA');", self.manifest]:
                    self.assertEqual(stream.readline(), b'HTTP/1.1 200 OK\r\n')
                    fields = {}
                    while (line := stream.readline()) != b'\r\n':
                        self.assertTrue(line, 'A pipelined response ended before its headers')
                        key, value = line.decode('iso-8859-1').split(':', 1)
                        fields[key.lower()] = value.strip()
                    self.assertEqual(stream.read(int(fields['content-length'])), expected)
                self.assertEqual(stream.read(1), b'')
        self.assertEqual(server.accepted_connections, 1)

    def test_normal_idle_expiry_is_silent_but_partial_reads_keep_timeout_logs(self):
        class ObservedTimeoutHandler(QuietGameHandler):
            timeout = .15

            def log_error(self, format, *args):
                self.server.timeout_errors.append((format, args))
                super().log_error(format, *args)

        server = self.server(ObservedTimeoutHandler)
        server.timeout_errors = []
        self.start(server)
        client = HTTPConnection(*server.server_address, timeout=2)
        try:
            client.request('GET', '/__lcs_launcher_health')
            response = client.getresponse()
            self.assertFalse(response.will_close)
            response.read()
            self.assertEqual(client.sock.recv(1), b'')
            self.assertEqual(server.timeout_errors, [])
        finally:
            client.close()
        for partial in [b'G', b'GET / HTTP/1.1\r\nHost: localhost\r\n']:
            with socket.create_connection(server.server_address, timeout=2) as client:
                client.sendall(partial)
                self.assertEqual(client.recv(1), b'')
        self.assertEqual(len(server.timeout_errors), 2)
        self.assertTrue(all(any(isinstance(error, socket.timeout) for error in args)
                            for _, args in server.timeout_errors))
        self.assertEqual(self.request(server, '/__lcs_launcher_health')[0], 200)

    def test_transfer_timeout_is_logged_and_not_treated_as_normal_idle(self):
        class TransferTimeoutHandler(QuietGameHandler):
            def copyfile(self, source, outputfile):
                raise socket.timeout('Controlled body-write failure')

            def log_error(self, format, *args):
                self.server.transfer_errors.append((format, args))
                super().log_error(format, *args)

        server = self.server(TransferTimeoutHandler)
        server.transfer_errors = []
        self.start(server)
        client = HTTPConnection(*server.server_address, timeout=2)
        try:
            client.request('GET', '/main.dart.js')
            response = client.getresponse()
            self.assertEqual(response.status, 200)
            with self.assertRaises(IncompleteRead):
                response.read()
        finally:
            client.close()
        self.assertEqual(len(server.transfer_errors), 1)
        self.assertTrue(any(isinstance(error, socket.timeout)
                            for error in server.transfer_errors[0][1]))

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

    def test_client_disconnects_do_not_emit_tracebacks_and_server_keeps_serving(self):
        failures = {
            '/broken-pipe': BrokenPipeError('Client closed the response'),
            '/reset': ConnectionResetError('Client reset the response'),
            '/aborted': ConnectionAbortedError(10053, 'Browser cancelled the response'),
        }

        class DisconnectedHandler(QuietGameHandler):
            def do_GET(self):
                if self.path in failures:
                    raise failures[self.path]
                super().do_GET()

        server = self.server(DisconnectedHandler)
        self.start(server)
        errors = io.StringIO()
        with redirect_stderr(errors):
            for path in failures:
                with self.subTest(path=path), self.assertRaises(ConnectionError):
                    self.request(server, path)
            status, _, body = self.request(server, '/__lcs_launcher_health')
        self.assertEqual(errors.getvalue(), '')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)['directory'], str(self.root.resolve()))

    def test_unexpected_handler_errors_keep_their_traceback(self):
        class FailingHandler(QuietGameHandler):
            def do_GET(self):
                if self.path == '/unexpected':
                    raise RuntimeError('Unexpected fixture failure')
                super().do_GET()

        server = self.server(FailingHandler)
        self.start(server)
        errors = io.StringIO()
        with redirect_stderr(errors):
            with self.assertRaises(ConnectionError):
                self.request(server, '/unexpected')
            status, _, _ = self.request(server, '/__lcs_launcher_health')
        self.assertIn('RuntimeError: Unexpected fixture failure', errors.getvalue())
        self.assertEqual(status, 200)

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

    def test_etags_stream_bounded_reads_without_the_python_311_file_digest_api(self):
        payload = bytes(range(256)) * 4097  # Larger than the hashing read budget.
        assets = {self.root / "large.bin": payload, self.root / "empty.bin": b""}
        for path, contents in assets.items():
            path.write_bytes(contents)
        asset_paths = {path.resolve() for path in assets}
        server = self.server()
        self.start(server)
        original_open = Path.open
        reads = []

        class ObservedFile:
            def __init__(self, source):
                self.source = source
                self.hashing = True

            def read(self, size=-1):
                if self.hashing:
                    if not 0 < size <= 1024 * 1024:
                        raise AssertionError(f"Hashing must use bounded reads, got {size}.")
                    reads.append(size)
                return self.source.read(size)

            def seek(self, *args):
                self.hashing = False
                return self.source.seek(*args)

            def __getattr__(self, name):
                return getattr(self.source, name)

        def observed_open(path, mode="r", *args, **kwargs):
            source = original_open(path, mode, *args, **kwargs)
            return ObservedFile(source) if path.resolve() in asset_paths and mode == "rb" else source

        # Standalone player servers cannot depend on release_common or on an
        # API absent from otherwise supported Python 3.9/3.10 installations.
        legacy_hashlib = SimpleNamespace(sha256=hashlib.sha256)
        with patch("serve.hashlib", legacy_hashlib), patch.object(Path, "open", observed_open):
            for path, contents in assets.items():
                with self.subTest(asset=path.name):
                    expected = '"' + hashlib.sha256(contents).hexdigest() + '"'
                    status, headers, body = self.request(server, '/' + path.name)
                    self.assertEqual((status, body), (200, contents))
                    self.assertEqual(headers["ETag"], expected)
                    status, headers, body = self.request(server, '/' + path.name, {"If-None-Match": expected})
                    self.assertEqual((status, body), (304, b""))
                    self.assertEqual(headers["ETag"], expected)
                    status, headers, body = self.request(server, '/' + path.name, method="HEAD")
                    self.assertEqual((status, body), (200, b""))
                    self.assertEqual(headers["ETag"], expected)
                    self.assertEqual(int(headers["Content-Length"]), len(contents))
        self.assertGreater(len(reads), 1, "The real HTTP requests must exercise bounded streaming.")

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
