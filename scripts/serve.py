"""Loopback-only static server for the built game; no third-party dependencies."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class GameServer(ThreadingHTTPServer):
    # A fresh Flutter page requests many assets at once. Queue a bounded burst
    # while the accept loop is busy starting request threads.
    request_queue_size = 128

    def handle_error(self, request, client_address):
        # Closing a browser profile or leaving a page can cancel an asset
        # response. Keep those ordinary disconnects out of failure evidence,
        # while preserving tracebacks for unexpected handler/file errors.
        if isinstance(sys.exc_info()[1], (BrokenPipeError, ConnectionResetError, ConnectionAbortedError)):
            return
        super().handle_error(request, client_address)


class GameHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    disable_nagle_algorithm = True
    timeout = 10

    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".json": "application/json",
        ".bin": "application/octet-stream",
        ".webp": "image/webp",
    }

    def handle_one_request(self):
        # A buffered peek preserves pipelined bytes while bounding normal idle
        # connections without reporting them as failed transfers. Once any
        # request bytes arrive, stdlib parsing and transfer errors stay intact.
        try:
            if not self.rfile.peek(1):
                self.close_connection = True
                return
        except socket.timeout:
            self.close_connection = True
            return
        return super().handle_one_request()

    def send_head(self):
        path = Path(self.translate_path(self.path))
        if path.is_dir():
            if not urlsplit(self.path).path.endswith("/"):
                return super().send_head()  # Preserve the directory redirect.
            for name in ("index.html", "index.htm"):
                if (path / name).is_file():
                    path /= name
                    break
            else:
                return super().send_head()
        if not path.resolve().is_relative_to(Path(self.directory).resolve()):
            self.send_error(404, "File not found")
            return None
        try:
            source = path.open("rb")
        except OSError:
            return super().send_head()
        try:
            info = os.fstat(source.fileno())
            checksum = hashlib.sha256()
            for block in iter(lambda: source.read(1024 * 1024), b""):
                checksum.update(block)
            etag = '"' + checksum.hexdigest() + '"'
            source.seek(0)
            matches = [value.strip().removeprefix("W/") for value in
                       self.headers.get("If-None-Match", "").split(",")]
            if etag in matches or "*" in matches:
                source.close()
                self.send_response(304)
                self.send_header("ETag", etag)
                self.end_headers()
                return None
            # Reproducible archives can have older or identical mtimes for new
            # bytes. Legacy date-only validators must receive a fresh response.
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(str(path)))
            self.send_header("Content-Length", str(info.st_size))
            self.send_header("Last-Modified", self.date_time_string(info.st_mtime))
            self.send_header("ETag", etag)
            self.end_headers()
            return source
        except OSError:
            source.close()
            raise

    def do_GET(self):
        if urlsplit(self.path).path == "/__lcs_launcher_health":
            payload = json.dumps({
                "application": "lcs-modern-local",
                "directory": str(Path(self.directory).resolve()),
            }).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        return super().do_GET()

    def end_headers(self):
        if self.close_connection and not any(
            header.lower().startswith(b"connection:")
            for header in getattr(self, "_headers_buffer", ())
        ):
            # HTTP/1.0 and explicit-close clients must not attempt reuse just
            # because the response advertises our HTTP/1.1 capabilities.
            self.send_header("Connection", "close")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(403, "Directory listing is disabled")
        return None

    def translate_path(self, path):
        translated = Path(super().translate_path(path)).resolve()
        root = Path(self.directory).resolve()
        # A build must never expose a symlink target outside its directory.
        if not translated.is_relative_to(root):
            return str(root / "__path_not_available__")
        return str(translated)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    directory = args.directory.resolve(strict=True)
    if not (directory / "index.html").is_file():
        parser.error(f"No built game at {directory}; index.html is missing")
    if not 1 <= args.port <= 65535:
        parser.error("Port must be between 1 and 65535")
    handler = partial(GameHandler, directory=str(directory))
    server = GameServer(("127.0.0.1", args.port), handler)
    print(f"LCS local game: http://127.0.0.1:{args.port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
