#!/usr/bin/env python3
"""A minimal FTP server, used only by the test suite.

Python has no FTP server in its standard library, and testing only the listing
parser would leave the transfers themselves unverified. This implements just
enough of RFC 959 for the client to log in, list, download, upload and delete:
USER, PASS, PWD, CWD, CDUP, TYPE, PASV, LIST, RETR, STOR, DELE, QUIT.

    python3 test-ftp-server.py <root-directory>

It binds to 127.0.0.1 on a port the operating system chooses, then prints

    PORT <number>

on stdout so the caller knows where to connect. It serves one client at a time
and exits when that client disconnects or after a two-minute idle timeout.
"""

import os
import socket
import sys
import threading

USER = "tester"
PASSWORD = "secret"


class Session:
    def __init__(self, conn, root):
        self.conn = conn
        self.root = os.path.realpath(root)
        self.cwd = "/"
        self.data_listener = None
        self.authenticated = False

    # -- plumbing ---------------------------------------------------------

    def reply(self, code, text):
        self.conn.sendall(f"{code} {text}\r\n".encode())

    def local_path(self, remote):
        """Maps a path the client sent onto a real one, refusing escapes."""
        if not remote.startswith("/"):
            remote = os.path.join(self.cwd, remote)
        candidate = os.path.realpath(os.path.join(self.root, remote.lstrip("/")))
        if candidate != self.root and not candidate.startswith(self.root + os.sep):
            return None
        return candidate

    def open_data_connection(self):
        if self.data_listener is None:
            return None
        conn, _ = self.data_listener.accept()
        self.data_listener.close()
        self.data_listener = None
        return conn

    # -- commands ---------------------------------------------------------

    def cmd_pasv(self, _arg):
        self.data_listener = socket.socket()
        self.data_listener.bind(("127.0.0.1", 0))
        self.data_listener.listen(1)
        port = self.data_listener.getsockname()[1]
        self.reply(227, f"Entering Passive Mode (127,0,0,1,{port >> 8},{port & 0xFF}).")

    def cmd_list(self, arg):
        target = self.local_path(arg) if arg and not arg.startswith("-") else self.local_path(self.cwd)
        data = self.open_data_connection()
        if data is None:
            self.reply(425, "Use PASV first.")
            return
        self.reply(150, "Here comes the directory listing.")
        lines = []
        if target and os.path.isdir(target):
            for name in sorted(os.listdir(target)):
                full = os.path.join(target, name)
                if os.path.isdir(full):
                    lines.append(f"drwxr-xr-x 2 owner group {4096:>8} Jan  1 00:00 {name}")
                else:
                    size = os.path.getsize(full)
                    lines.append(f"-rw-r--r-- 1 owner group {size:>8} Jan  1 00:00 {name}")
        data.sendall(("\r\n".join(lines) + ("\r\n" if lines else "")).encode())
        data.close()
        self.reply(226, "Directory send OK.")

    def cmd_retr(self, arg):
        path = self.local_path(arg)
        if not path or not os.path.isfile(path):
            self.reply(550, "No such file.")
            return
        data = self.open_data_connection()
        if data is None:
            self.reply(425, "Use PASV first.")
            return
        self.reply(150, "Opening data connection.")
        with open(path, "rb") as handle:
            data.sendall(handle.read())
        data.close()
        self.reply(226, "Transfer complete.")

    def cmd_stor(self, arg):
        path = self.local_path(arg)
        if not path:
            self.reply(553, "Path not allowed.")
            return
        data = self.open_data_connection()
        if data is None:
            self.reply(425, "Use PASV first.")
            return
        self.reply(150, "Ok to send data.")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            while True:
                chunk = data.recv(65536)
                if not chunk:
                    break
                handle.write(chunk)
        data.close()
        self.reply(226, "Transfer complete.")

    def cmd_cwd(self, arg):
        path = self.local_path(arg)
        if not path or not os.path.isdir(path):
            self.reply(550, "No such directory.")
            return
        self.cwd = "/" + os.path.relpath(path, self.root).replace(".", "").lstrip("/")
        self.reply(250, "Directory changed.")

    def cmd_dele(self, arg):
        path = self.local_path(arg)
        if not path or not os.path.isfile(path):
            self.reply(550, "No such file.")
            return
        os.remove(path)
        self.reply(250, "File deleted.")

    # -- loop -------------------------------------------------------------

    def run(self):
        self.reply(220, "NotepadMac test server")
        buffer = b""
        while True:
            try:
                chunk = self.conn.recv(4096)
            except OSError:
                break
            if not chunk:
                break
            buffer += chunk
            while b"\r\n" in buffer:
                line, buffer = buffer.split(b"\r\n", 1)
                verb, _, arg = line.decode(errors="replace").partition(" ")
                verb = verb.upper()

                if verb == "USER":
                    self.reply(331, "Password required.") if arg == USER else self.reply(530, "Unknown user.")
                elif verb == "PASS":
                    self.authenticated = arg == PASSWORD
                    self.reply(230, "Logged in.") if self.authenticated else self.reply(530, "Wrong password.")
                elif not self.authenticated:
                    self.reply(530, "Log in first.")
                elif verb == "SYST":
                    self.reply(215, "UNIX Type: L8")
                elif verb == "TYPE":
                    self.reply(200, "Type set.")
                elif verb == "PWD":
                    self.reply(257, f'"{self.cwd}" is the current directory.')
                elif verb == "CWD":
                    self.cmd_cwd(arg)
                elif verb == "CDUP":
                    self.cmd_cwd("..")
                elif verb == "PASV":
                    self.cmd_pasv(arg)
                elif verb == "LIST" or verb == "NLST":
                    self.cmd_list(arg)
                elif verb == "RETR":
                    self.cmd_retr(arg)
                elif verb == "STOR":
                    self.cmd_stor(arg)
                elif verb == "DELE":
                    self.cmd_dele(arg)
                elif verb == "MKD":
                    path = self.local_path(arg)
                    if path:
                        os.makedirs(path, exist_ok=True)
                        self.reply(257, "Directory created.")
                    else:
                        self.reply(550, "Cannot create.")
                elif verb == "QUIT":
                    self.reply(221, "Goodbye.")
                    self.conn.close()
                    return
                else:
                    self.reply(502, "Not implemented.")
        self.conn.close()


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(root, exist_ok=True)

    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(4)
    print(f"PORT {listener.getsockname()[1]}", flush=True)

    listener.settimeout(120)
    while True:
        try:
            conn, _ = listener.accept()
        except socket.timeout:
            return
        threading.Thread(target=Session(conn, root).run, daemon=True).start()


if __name__ == "__main__":
    main()
