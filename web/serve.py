#!/usr/bin/env python3
"""Local dev server for the Deadeye Obfuscator web app.

Serves web/ as the document root, and maps /modules/<Name>.lua (and
/modules/vm/<Name>.lua) to the real .lua sources at the repo root, so the
local URL layout matches the deployed GitHub Pages layout exactly.

    python3 web/serve.py            # http://localhost:8000
    python3 web/serve.py 8080       # custom port
"""
import http.server, os, sys, posixpath
from urllib.parse import unquote

WEB_DIR  = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(WEB_DIR)

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB_DIR, **k)

    def translate_path(self, path):
        # /modules/<rel> -> <repo>/<rel>, restricted to .lua files under the repo.
        clean = unquote(path.split("?", 1)[0].split("#", 1)[0])
        if clean.startswith("/modules/"):
            rel = posixpath.normpath(clean[len("/modules/"):]).lstrip("/")
            target = os.path.normpath(os.path.join(REPO_DIR, rel))
            if target.startswith(REPO_DIR + os.sep) and target.endswith(".lua"):
                return target
            return os.path.join(WEB_DIR, "__forbidden__")
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")  # always serve fresh .lua during dev
        super().end_headers()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"Deadeye web UI: http://localhost:{port}/  (modules -> {REPO_DIR})")
    http.server.ThreadingHTTPServer(("", port), Handler).serve_forever()
