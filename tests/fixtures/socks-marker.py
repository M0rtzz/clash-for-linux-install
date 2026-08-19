#!/usr/bin/env python3

import argparse
import socketserver
from pathlib import Path


def recv_exact(stream, size):
    data = b""
    while len(data) < size:
        chunk = stream.recv(size - len(data))
        if not chunk:
            raise ConnectionError("unexpected end of stream")
        data += chunk
    return data


class SocksMarkerHandler(socketserver.BaseRequestHandler):
    def handle(self):
        version, method_count = recv_exact(self.request, 2)
        if version != 5:
            return
        recv_exact(self.request, method_count)
        self.request.sendall(b"\x05\x00")

        version, command, _reserved, address_type = recv_exact(self.request, 4)
        if version != 5 or command != 1:
            return
        if address_type == 1:
            recv_exact(self.request, 4)
        elif address_type == 3:
            recv_exact(self.request, recv_exact(self.request, 1)[0])
        elif address_type == 4:
            recv_exact(self.request, 16)
        else:
            return
        recv_exact(self.request, 2)
        self.request.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")

        request = b""
        while b"\r\n\r\n" not in request and len(request) < 65536:
            chunk = self.request.recv(4096)
            if not chunk:
                return
            request += chunk
        body = self.server.marker.encode("utf-8")
        response = (
            b"HTTP/1.1 200 OK\r\n"
            + f"Content-Length: {len(body)}\r\n".encode("ascii")
            + b"Connection: close\r\n\r\n"
            + body
        )
        self.request.sendall(response)


class MarkerServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("marker")
    parser.add_argument("port_file", type=Path)
    args = parser.parse_args()

    with MarkerServer(("127.0.0.1", 0), SocksMarkerHandler) as server:
        server.marker = args.marker
        args.port_file.write_text(str(server.server_address[1]), encoding="ascii")
        server.serve_forever()


if __name__ == "__main__":
    main()
