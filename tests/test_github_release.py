# ci/github-release.py: the GitHub token must not follow a redirect to another host; failed requests end in die().
import contextlib
import hashlib
import http.server
import io
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


class NonJsonBody(unittest.TestCase):
    """A 200 response that is not JSON must end in die() naming the request, without echoing the body."""
    BODY = b'<html>example-secret-page</html>'

    class Html(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header('Content-Length', str(len(NonJsonBody.BODY)))
            self.end_headers()
            self.wfile.write(NonJsonBody.BODY)

        def log_message(self, *a):
            pass

    def test_forgejo_release_lookup(self):
        srv = server('127.0.0.1', self.Html)
        try:
            r = subprocess.run([sys.executable, '-I', '-B', os.path.join(TREE, 'ci', 'github-release.py'),
                                '--forgejo-api', 'http://127.0.0.1:%d/api/v1' % srv.server_address[1],
                                '--repo', 'o/r', '--github-repo', 'o/r', '--tag', 'v1.0-r1'],
                               capture_output=True, text=True, timeout=60,
                               env={'PATH': os.environ.get('PATH', ''), 'GH_RELEASE_TOKEN': 'example-token'})
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertNotIn('Traceback', r.stderr)
        self.assertIn('github-release: Forgejo release lookup did not return valid JSON', r.stderr)
        self.assertNotIn('example-secret-page', r.stderr + r.stdout)
        self.assertNotIn('example-token', r.stderr + r.stdout)

    def test_github_request(self):
        srv = server('127.0.0.1', self.Html)
        try:
            with self.assertRaises(SystemExit) as cm:
                load().gh_json('GET', 'http://127.0.0.1:%d/repos/x/y' % srv.server_address[1], 'example-token',
                               what='GitHub release list')
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual(cm.exception.code, 1)


class WrongShape(unittest.TestCase):
    """Valid JSON of the wrong shape (list for object, wrong field type, missing field) must end in die() naming
    the request that returned it, never a traceback."""

    def run_script(self, routes):
        class Srv(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path not in routes:
                    self.send_response(404)
                    self.end_headers()
                    return
                body = routes[self.path](self.server.server_address[1])
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        srv = server('127.0.0.1', Srv)
        try:
            return subprocess.run([sys.executable, '-I', '-B', os.path.join(TREE, 'ci', 'github-release.py'),
                                   '--forgejo-api', 'http://127.0.0.1:%d/api/v1' % srv.server_address[1],
                                   '--repo', 'o/r', '--github-repo', 'o/r', '--tag', 'v1.0-r1', '--dry-run'],
                                  capture_output=True, text=True, timeout=60, env={'PATH': os.environ.get('PATH', '')})
        finally:
            srv.shutdown()
            srv.server_close()

    def check(self, r, what):
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertNotIn('Traceback', r.stderr)
        self.assertIn('github-release: %s returned JSON of an unexpected shape' % what, r.stderr)

    REL = '/api/v1/repos/o/r/releases/tags/v1.0-r1'

    def test_release_lookup_list(self):
        self.check(self.run_script({self.REL: lambda port: b'[]'}), 'Forgejo release lookup')

    def test_release_lookup_assets_wrong_type(self):
        rel = json.dumps({'tag_name': 'v1.0-r1', 'name': 'v1.0-r1', 'html_url': 'http://example.org/r',
                          'draft': False, 'assets': 'm.zip'}).encode()
        self.check(self.run_script({self.REL: lambda port: rel}), 'Forgejo release lookup')

    def test_tag_lookup_commit_wrong_type(self):
        data = b'zip bytes'
        sha = hashlib.sha256(data).hexdigest().encode()

        def rel(port):
            assets = [{'name': n, 'size': len(d), 'browser_download_url': 'http://127.0.0.1:%d/dl/%s' % (port, n)}
                      for n, d in (('m.zip', data), ('m.zip.sha256', sha + b'  m.zip\n'))]
            return json.dumps({'tag_name': 'v1.0-r1', 'name': 'v1.0-r1', 'html_url': 'http://example.org/r',
                               'draft': False, 'assets': assets}).encode()
        r = self.run_script({self.REL: rel, '/dl/m.zip': lambda port: data,
                             '/dl/m.zip.sha256': lambda port: sha + b'  m.zip\n',
                             '/api/v1/repos/o/r/tags/v1.0-r1': lambda port: b'{"commit": []}'})
        self.check(r, 'Forgejo tag lookup')

    def test_github_tag_lookup_object_wrong_type(self):
        body = b'{"ref": "refs/tags/v1.0-r1", "object": "abc"}'

        class Gh(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        srv = server('127.0.0.1', Gh)
        err = io.StringIO()
        try:
            with self.assertRaises(SystemExit) as cm, contextlib.redirect_stderr(err):
                load().gh_peeled('http://127.0.0.1:%d/repos/o/r' % srv.server_address[1], 'v1.0-r1', 'example-token')
        finally:
            srv.shutdown()
            srv.server_close()
        self.assertEqual(cm.exception.code, 1)
        self.assertIn('GitHub tag lookup returned JSON of an unexpected shape', err.getvalue())


class PublishedAssetList(unittest.TestCase):
    """An existing GitHub release whose re-read lists an asset the Forgejo release does not have must end in die()
    naming the release, not a KeyError."""

    def test_extra_asset_after_reread(self):
        data = b'zip bytes'
        sha = hashlib.sha256(data).hexdigest().encode() + b'  m.zip\n'
        files = {'m.zip': data, 'm.zip.sha256': sha, 'x.bin': b'other'}
        commit = '0' * 40
        reads = []

        class Srv(http.server.BaseHTTPRequestHandler):
            def reply(self, body):
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def asset(self, n):
                port = self.server.server_address[1]
                return {'name': n, 'size': len(files[n]), 'state': 'uploaded',
                        'browser_download_url': 'http://127.0.0.1:%d/dl/%s' % (port, n)}

            def do_GET(self):
                port = self.server.server_address[1]
                if self.path == '/api/v1/repos/o/r/releases/tags/v1.0-r1':
                    self.reply(json.dumps({'tag_name': 'v1.0-r1', 'name': 'v1.0-r1', 'html_url': 'http://example.org/r',
                                           'draft': False, 'assets': [self.asset('m.zip'), self.asset('m.zip.sha256')]}).encode())
                elif self.path == '/api/v1/repos/o/r/tags/v1.0-r1':
                    self.reply(json.dumps({'commit': {'sha': commit}}).encode())
                elif self.path.startswith('/dl/'):
                    self.reply(files[self.path[4:]])
                elif self.path == '/repos/o/r/git/ref/tags/v1.0-r1':
                    self.reply(json.dumps({'ref': 'refs/tags/v1.0-r1', 'object': {'type': 'commit', 'sha': commit}}).encode())
                elif self.path.startswith('/repos/o/r/releases?'):
                    self.reply(json.dumps([{'id': 7, 'tag_name': 'v1.0-r1', 'draft': False,
                                            'upload_url': 'https://uploads.github.com/x{?name}',
                                            'assets': [self.asset('m.zip'), self.asset('m.zip.sha256')]}]).encode())
                elif self.path == '/repos/o/r/releases/7':
                    reads.append(1)
                    self.reply(json.dumps({'id': 7, 'tag_name': 'v1.0-r1', 'upload_url': 'https://uploads.github.com/x{?name}',
                                           'assets': [self.asset('m.zip'), self.asset('m.zip.sha256'),
                                                      self.asset('x.bin')]}).encode())
                else:
                    self.send_response(404)
                    self.end_headers()

            def log_message(self, *a):
                pass

        srv = server('127.0.0.1', Srv)
        mod = load()
        mod.GH_API = 'http://127.0.0.1:%d' % srv.server_address[1]
        err = io.StringIO()
        argv = sys.argv
        env = os.environ.get('GH_RELEASE_TOKEN')
        sys.argv = ['github-release.py', '--forgejo-api', 'http://127.0.0.1:%d/api/v1' % srv.server_address[1],
                    '--repo', 'o/r', '--github-repo', 'o/r', '--tag', 'v1.0-r1']
        os.environ['GH_RELEASE_TOKEN'] = 'example-token'
        try:
            with self.assertRaises(SystemExit) as cm, contextlib.redirect_stderr(err), \
                    contextlib.redirect_stdout(io.StringIO()):
                mod.main()
        finally:
            sys.argv = argv
            if env is None:
                os.environ.pop('GH_RELEASE_TOKEN', None)
            else:
                os.environ['GH_RELEASE_TOKEN'] = env
            srv.shutdown()
            srv.server_close()
        self.assertEqual(reads, [1])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn('github-release: GitHub release v1.0-r1 asset list differs from Forgejo', err.getvalue())


if __name__ == '__main__':
    unittest.main(verbosity=2)
