# ci/github-release.py: the GitHub token must not follow a redirect to another host.
import http.server
import importlib.util
import os
import threading
import unittest

TREE = os.environ['ALT_TREE']


def load():
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


if __name__ == '__main__':
    unittest.main(verbosity=2)
