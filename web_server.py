import os
import sys
import http.server
import urllib.request
import urllib.error

WEB_DIR = r"d:\EB GLOBAL APP\gebtalk_flutter\build\web"
API_BACKEND = "http://127.0.0.1:5000"
PORT = 8080

class DevProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH')
        self.send_header('Access-Control-Allow-Headers', '*')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        if self.path.startswith('/api/') or self.path == '/api':
            self._proxy()
        else:
            path_no_query = self.path.split('?')[0]
            local_path = os.path.join(WEB_DIR, path_no_query.lstrip('/'))
            if not os.path.exists(local_path) and '.' not in os.path.basename(path_no_query):
                self.path = '/index.html'
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/') or self.path == '/api':
            self._proxy()
        else:
            super().do_POST()

    def do_PUT(self):
        if self.path.startswith('/api/') or self.path == '/api':
            self._proxy()
        else:
            self.send_error(405)

    def do_DELETE(self):
        if self.path.startswith('/api/') or self.path == '/api':
            self._proxy()
        else:
            self.send_error(405)

    def _proxy(self):
        target_url = API_BACKEND + self.path
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        headers = {}
        for k, v in self.headers.items():
            if k.lower() not in ('host', 'content-length'):
                headers[k] = v

        req = urllib.request.Request(target_url, data=body, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ('transfer-encoding', 'content-length', 'access-control-allow-origin'):
                        self.send_header(k, v)
                content = resp.read()
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in ('transfer-encoding', 'content-length', 'access-control-allow-origin'):
                    self.send_header(k, v)
            content = e.read()
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_error(502, f"Proxy error: {e}")

if __name__ == '__main__':
    server = http.server.ThreadingHTTPServer(('0.0.0.0', PORT), DevProxyHandler)
    print(f"Serving GEBTALK web on http://localhost:{PORT}")
    server.serve_forever()
