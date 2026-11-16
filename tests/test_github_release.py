# ci/github-release.py: the GitHub token must not follow a redirect to another host; failed requests end in die().
import http.server
import importlib.util
import json
import os
import subprocess
import sys
import threading
import unittest

TREE = os.environ['ALT_TREE']


def load():
    sys.dont_write_bytecode = True  # no ci/__pycache__ in the tree under test
    spec = importlib.util.spec_from_file_location('github_release', os.path.join(TREE, 'ci', 'github-release.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def server(host, handler):
    s = http.server.HTTPServer((host, 0), handler)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s


class TokenOnRedirect(unittest.TestCase):
    def test_token_not_sent_to_redirect_target(self):
        seen = {}

        class Target(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen['target'] = self.headers.get('Authorization')
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{}')

            def log_message(self, *a):
                pass

        target = server('127.0.0.2', Target)

        class Origin(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen['origin'] = self.headers.get('Authorization')
                self.send_response(302)
                self.send_header('Location', 'http://127.0.0.2:%d/elsewhere' % target.server_address[1])
                self.end_headers()

            def log_message(self, *a):
                pass

        origin = server('127.0.0.1', Origin)
        try:
            st, body = load().gh('GET', 'http://127.0.0.1:%d/repos/x/y' % origin.server_address[1], 'example-token')
        finally:
            for s in (origin, target):
                s.shutdown()
                s.server_close()
        self.assertEqual(st, 200)
        self.assertEqual(seen.get('origin'), 'Bearer example-token')
        self.assertIn('target', seen)
        self.assertIsNone(seen['target'], 'token was sent to the redirect target')


class EmptyChecksumAsset(unittest.TestCase):
    def test_empty_sha256_asset_is_reported_by_die(self):
        files = {'m.zip': b'zip bytes', 'm.zip.sha256': b''}

        class Forgejo(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                port = self.server.server_address[1]
                if self.path == '/api/v1/repos/o/r/releases/tags/v1.0-r1':
                    assets = [{'name': n, 'size': len(d), 'browser_download_url': 'http://127.0.0.1:%d/dl/%s' % (port, n)}
                              for n, d in files.items()]
                    body = json.dumps({'tag_name': 'v1.0-r1', 'draft': False, 'assets': assets}).encode()
                elif self.path.startswith('/dl/'):
                    body = files[self.path[4:]]
                else:
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        srv = server('127.0.0.1', Forgejo)
        try:
            r = subprocess.run([sys.executable, '-I', '-B', os.path.join(TREE, 'ci', 'github-release.py'),
                                '--forgejo-api', 'http://127.0.0.1:%d/api/v1' % srv.server_address[1],
                                '--repo', 'o/r', '--github-repo', 'o/r', '--tag', 'v1.0-r1', '--dry-run'],
                               capture_output=True, text=True, timeout=60, env={'PATH': os.environ.get('PATH', '')})
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertNotIn('Traceback', r.stderr)
        self.assertIn('github-release: m.zip.sha256', r.stderr)


class TruncatedResponse(unittest.TestCase):
    """A response cut off mid-body must end in die(), not a traceback."""

    class Short(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header('Content-Length', '100')
            self.end_headers()
            self.wfile.write(b'{"ta')
            self.wfile.flush()
            self.close_connection = True

        def log_message(self, *a):
            pass

    def test_forgejo_release_lookup(self):
        srv = server('127.0.0.1', self.Short)
        try:
            r = subprocess.run([sys.executable, '-I', '-B', os.path.join(TREE, 'ci', 'github-release.py'),
                                '--forgejo-api', 'http://127.0.0.1:%d/api/v1' % srv.server_address[1],
                                '--repo', 'o/r', '--github-repo', 'o/r', '--tag', 'v1.0-r1', '--dry-run'],
                               capture_output=True, text=True, timeout=60, env={'PATH': os.environ.get('PATH', '')})
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertNotIn('Traceback', r.stderr)
        self.assertIn('github-release: GET http://127.0.0.1', r.stderr)

    def test_github_request(self):
        srv = server('127.0.0.1', self.Short)
        try:
            with self.assertRaises(SystemExit) as cm:
                load().gh('GET', 'http://127.0.0.1:%d/repos/x/y' % srv.server_address[1], 'example-token')
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual(cm.exception.code, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
