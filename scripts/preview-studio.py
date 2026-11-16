#!/usr/bin/env python3
"""Local production-client QA, proxying Jac's existing local API on port 8001.

This localhost-only preview is not a deployment server. Build/validate first.
"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

DIST = Path(__file__).resolve().parents[1] / "web/.jac/client/dist"


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(DIST), **kwargs)

    def proxy(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length > 20 * 1024 * 1024:
            self.send_error(413); return
        headers = {key: value for key, value in self.headers.items() if key.lower() in {"content-type", "authorization", "accept"}}
        request = Request("http://localhost:8001" + self.path, data=self.rfile.read(length) if length else None, headers=headers, method=self.command)
        try:
            response = urlopen(request, timeout=60)
        except HTTPError as exc:
            response = exc
        except OSError:
            self.send_error(503, "Start scripts/dev-studio.sh for the local API"); return
        with response:
            content = response.read()
            self.send_response(response.status)
            self.send_header("Content-Type", response.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers(); self.wfile.write(content)

    def do_GET(self):
        if self.path.startswith(("/function/", "/user/", "/walker/", "/api/")):
            self.proxy(); return
        if self.path.split("?")[0] in {"/", "/studio"}:
            self.path = "/index.html"
        super().do_GET()

    def do_POST(self):
        if self.path.startswith(("/function/", "/user/", "/walker/", "/api/")):
            self.proxy(); return
        self.send_error(404)


if __name__ == "__main__":
    print("Production client preview: http://localhost:8002/studio", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8002), Handler).serve_forever()
