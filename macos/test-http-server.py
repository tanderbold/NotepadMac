#!/usr/bin/env python3
"""A small HTTP server, used only by the test suite: it says back what it was
asked, so that a test can see the request as the server saw it.

    python3 test-http-server.py

It binds to 127.0.0.1 on a port the operating system chooses, prints

    PORT <number>

on stdout, and exits after two minutes or when /quit is asked for.

    /echo             JSON: method, path, query, headers, body (as text)
    /status/<code>    that status, with a short body
    /redirect         302 to /echo?redirected=1
    /latin1           a body in ISO-8859-1, declared as such
    /binary           four bytes that are no text in any encoding
    /gzip             a gzip-encoded body
    /slow             answers after three seconds
"""
import gzip, json, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qsl


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def send(self, status, body, content_type="text/plain; charset=utf-8", extra=()):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Test-Server", "notepad")
        for name, value in extra:
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def answer(self):
        parts = urlsplit(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        if parts.path == "/echo":
            said = {"method": self.command, "path": parts.path, "query": parse_qsl(parts.query, keep_blank_values=True),
                    "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body.decode("utf-8", "replace")}
            self.send(200, json.dumps(said, ensure_ascii=False).encode("utf-8"), "application/json")
        elif parts.path.startswith("/status/"):
            code = int(parts.path.rsplit("/", 1)[1])
            self.send(code, f"status {code}".encode())
        elif parts.path == "/redirect":
            self.send(302, b"moved", extra=[("Location", "/echo?redirected=1")])
        elif parts.path == "/latin1":
            self.send(200, "café crème".encode("latin-1"), "text/plain; charset=ISO-8859-1")
        elif parts.path == "/binary":
            self.send(200, b"\xff\xfe\x00\xc3", "application/octet-stream")
        elif parts.path == "/gzip":
            self.send(200, gzip.compress(b"unpacked text"), extra=[("Content-Encoding", "gzip")])
        elif parts.path == "/slow":
            time.sleep(3)
            self.send(200, b"late")
        elif parts.path == "/quit":
            self.send(200, b"bye")
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        else:
            self.send(404, b"not here")

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = answer


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print("PORT", server.server_address[1], flush=True)
    threading.Timer(120, server.shutdown).start()
    server.serve_forever()
    sys.exit(0)


if __name__ == "__main__":
    main()
