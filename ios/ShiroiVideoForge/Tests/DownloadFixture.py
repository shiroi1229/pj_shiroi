from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time

SIZE = 8 * 1024 * 1024
class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path != '/model.bin':
            self.send_error(404); return
        start = 0
        if value := self.headers.get('Range'):
            try: start = int(value.removeprefix('bytes=').split('-')[0])
            except ValueError: self.send_error(416); return
        if not 0 <= start < SIZE: self.send_error(416); return
        self.send_response(206 if start else 200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(SIZE - start))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('ETag', '"shiroi-fixture-v1"')
        self.send_header('Last-Modified', 'Sat, 05 Sep 2026 00:00:00 GMT')
        if start: self.send_header('Content-Range', f'bytes {start}-{SIZE-1}/{SIZE}')
        self.end_headers()
        try:
            for offset in range(start, SIZE, 65536):
                self.wfile.write(b'F' * min(65536, SIZE-offset)); self.wfile.flush(); time.sleep(0.01)
        except (BrokenPipeError, ConnectionResetError): pass

ThreadingHTTPServer(('127.0.0.1', 18764), Handler).serve_forever()
