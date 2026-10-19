"""Loopback-only static server for the built game; no third-party dependencies."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class GameServer(ThreadingHTTPServer):
    # A fresh Flutter page requests many assets at once. Queue a bounded burst
    # while the accept loop is busy starting request threads.
    request_queue_size = 128


class GameHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".json": "application/json",
        ".bin": "application/octet-stream",
        ".webp": "image/webp",
    }

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
            etag = '"' + hashlib.file_digest(source, "sha256").hexdigest() + '"'
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
