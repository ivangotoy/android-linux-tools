#!/usr/bin/env python3
"""Copy a published Forgejo release (all assets, same bytes) to the GitHub mirror.

The GitHub repository receives git refs from the Forgejo push mirror. This script
never creates or moves a tag, never edits an existing release body and never
deletes anything. It waits until the mirrored tag exists on GitHub at the same
commit, creates the GitHub release on that tag (or completes a partial one),
uploads every Forgejo asset and byte-verifies each upload by downloading it.

Usage: github-release.py --forgejo-api URL --repo OWNER/NAME --github-repo OWNER/NAME
                         --tag TAG [--wait-tag SECONDS] [--wait-release SECONDS] [--dry-run]
Token: GH_RELEASE_TOKEN in the environment (GitHub token with public_repo).
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

GH_API = 'https://api.github.com'
UA = 'android-linux-tools-ci'


def die(msg):
    print('github-release: ' + msg, file=sys.stderr, flush=True)
    sys.exit(1)


def fetch(url):
    """Anonymous GET (redirects followed); no credential is sent."""
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        die('GET %s failed: %s' % (url.split('?', 1)[0], e.reason))


def gh(method, url, token, payload=None, raw=None, ctype='application/json'):
    data = raw if raw is not None else (None if payload is None else json.dumps(payload).encode())
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('User-Agent', UA)
    req.add_header('Accept', 'application/vnd.github+json')
    req.add_header('X-GitHub-Api-Version', '2022-11-28')
    if token:
        req.add_header('Authorization', 'Bearer ' + token)
    if data is not None:
        req.add_header('Content-Type', ctype)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        die('%s %s failed: %s' % (method, url.split('?', 1)[0], e.reason))


def gh_json(method, url, token, want=(200,), what='GitHub request', **kw):
    st, body = gh(method, url, token, **kw)
    if st not in want:
        die('%s returned HTTP %d' % (what, st))
    return json.loads(body)


def gh_peeled(base, tag, token):
    """Peeled commit of refs/tags/<tag> on GitHub, or None if absent."""
    st, body = gh('GET', '%s/git/ref/tags/%s' % (base, urllib.parse.quote(tag)), token)
    if st == 404:
        return None
    if st != 200:
        die('GitHub tag lookup returned HTTP %d' % st)
    ref = json.loads(body)
    if not isinstance(ref, dict) or ref.get('ref') != 'refs/tags/' + tag:
        die('GitHub tag lookup did not return exactly refs/tags/%s' % tag)
    obj = ref['object']
    for _ in range(8):
        if obj['type'] == 'commit':
            return obj['sha']
        if obj['type'] != 'tag':
            die('GitHub tag %s points to a %s' % (tag, obj['type']))
        obj = gh_json('GET', '%s/git/tags/%s' % (base, obj['sha']), token,
                      what='GitHub tag object lookup')['object']
    die('GitHub tag %s: tag chain too deep' % tag)


def gh_releases_for(base, tag, token):
    found, page = [], 1
    while True:
        rows = gh_json('GET', '%s/releases?per_page=100&page=%d' % (base, page), token,
                       what='GitHub release list')
        found += [r for r in rows if r.get('tag_name') == tag]
        if len(rows) < 100:
            return found
        page += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--forgejo-api', required=True)
    ap.add_argument('--repo', required=True)
    ap.add_argument('--github-repo', required=True)
    ap.add_argument('--tag', required=True)
    ap.add_argument('--wait-tag', type=int, default=1800)
    ap.add_argument('--wait-release', type=int, default=0,
                    help='seconds to wait for the Forgejo release to be published')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    token = os.environ.get('GH_RELEASE_TOKEN', '')
    if not token and not a.dry_run:
        die('no GitHub release token in the environment')
    tag = a.tag
    if not re.fullmatch(r'v[0-9][A-Za-z0-9._-]*', tag):
        die('unexpected tag name %r' % tag)
    fbase = '%s/repos/%s' % (a.forgejo_api.rstrip('/'), a.repo)
    gbase = '%s/repos/%s' % (GH_API, a.github_repo)

    # Published Forgejo release, read anonymously. The tag is pushed before the release
    # is published (drafts are not visible anonymously), so wait for it.
    rdeadline = time.monotonic() + a.wait_release
    while True:
        st, body = fetch('%s/releases/tags/%s' % (fbase, urllib.parse.quote(tag)))
        if st == 200 and not json.loads(body).get('draft'):
            break
        if st not in (200, 404):
            die('Forgejo release lookup returned HTTP %d' % st)
        if time.monotonic() >= rdeadline:
            die('no published Forgejo release for %s within %d s' % (tag, a.wait_release))
        time.sleep(30)
    frel = json.loads(body)
    if frel.get('draft') or frel.get('tag_name') != tag:
        die('Forgejo release for %s is not a published release of that tag' % tag)
    assets = {x['name']: x for x in frel.get('assets', [])}
    if not assets:
        die('Forgejo release %s has no assets' % tag)
    files = {}
    for name in sorted(assets):
        st, data = fetch(assets[name]['browser_download_url'])
        if st != 200 or len(data) != assets[name]['size']:
            die('Forgejo asset %s download failed (HTTP %d)' % (name, st))
        files[name] = data
    sums = {n: hashlib.sha256(d).hexdigest() for n, d in files.items()}
    # Every <file>.sha256 must match its file, and every non-checksum file must have one.
    for name, data in files.items():
        if name.endswith('.sha256'):
            base = name[:-len('.sha256')]
            if base not in files:
                die('%s has no matching file' % name)
            if data.split()[0].decode() != sums[base]:
                die('%s does not match %s' % (name, base))
        elif name + '.sha256' not in files:
            die('%s has no .sha256 asset' % name)
    st, body = fetch('%s/releases/latest' % fbase)
    latest = st == 200 and json.loads(body).get('tag_name') == tag

    st, body = fetch('%s/tags/%s' % (fbase, urllib.parse.quote(tag)))
    if st != 200:
        die('Forgejo tag lookup returned HTTP %d' % st)
    commit = json.loads(body)['commit']['sha']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        die('Forgejo tag %s has no commit' % tag)
    deadline = time.monotonic() + a.wait_tag
    while True:
        peeled = gh_peeled(gbase, tag, token)
        if peeled is not None and peeled != commit:
            die('GitHub tag %s is at %s, Forgejo tag is at %s' % (tag, peeled[:12], commit[:12]))
        if peeled == commit:
            break
        if time.monotonic() >= deadline:
            die('GitHub tag %s did not appear within %d s' % (tag, a.wait_tag))
        time.sleep(15)
    print('%s: %d Forgejo assets verified, GitHub tag peels to %s' % (tag, len(files), commit[:12]),
          flush=True)

    def check_published(rel, names):
        for x in rel['assets']:
            st, data = fetch(x['browser_download_url'])
            if st != 200 or hashlib.sha256(data).hexdigest() != sums[x['name']]:
                die('GitHub asset %s does not match the Forgejo file (HTTP %d)' % (x['name'], st))
        if sorted(x['name'] for x in rel['assets']) != sorted(names):
            die('GitHub release asset list differs from Forgejo')

    def upload(rel, name):
        url = rel['upload_url'].split('{', 1)[0] + '?name=' + urllib.parse.quote(name)
        if not url.startswith('https://uploads.github.com/'):
            die('unexpected GitHub upload host')
        x = gh_json('POST', url, token, want=(201,), what='asset upload ' + name,
                    raw=files[name], ctype='application/octet-stream')
        if x.get('name') != name or x.get('size') != len(files[name]) or x.get('state') != 'uploaded':
            die('GitHub asset %s: stored name/size/state differs' % name)

    existing = gh_releases_for(gbase, tag, token)
    if len(existing) > 1:
        die('GitHub has %d releases for %s' % (len(existing), tag))
    if existing:
        rel = existing[0]
        if rel.get('draft'):
            die('GitHub has an unpublished draft for %s; inspect it by hand' % tag)
        have = {x['name']: x for x in rel['assets']}
        extra = sorted(set(have) - set(files))
        if extra:
            die('GitHub release %s has extra assets: %s' % (tag, ', '.join(extra)))
        for x in have.values():
            if x.get('state') != 'uploaded' or x.get('size') != len(files[x['name']]):
                die('GitHub asset %s is incomplete or differs in size' % x['name'])
        missing = sorted(set(files) - set(have))
        check_published(rel, have)
        if a.dry_run:
            print('dry run: release %s exists on GitHub (id %d); would upload %s'
                  % (tag, rel['id'], ', '.join(missing) or 'nothing'))
            return
        for name in missing:
            upload(rel, name)
        rel = gh_json('GET', '%s/releases/%d' % (gbase, rel['id']), token, what='GitHub release read')
        check_published(rel, files)
        print('GitHub release %s (id %d) verified, %d assets byte-equal to Forgejo, uploaded: %s'
              % (tag, rel['id'], len(files), ', '.join(missing) or 'none'))
        return

    body = (frel.get('body') or '').rstrip() + '\n\n---\nCopied from the original release: %s\n' % (
        frel['html_url'])
    if a.dry_run:
        print('dry run: would create release %s (name %r, prerelease %s, latest %s) with %s'
              % (tag, frel['name'], bool(frel.get('prerelease')), latest, ', '.join(sorted(files))))
        return
    # Draft first, upload, verify sizes, then publish and byte-verify the public downloads.
    rel = gh_json('POST', '%s/releases' % gbase, token, want=(201,), what='GitHub release create',
                  payload={'tag_name': tag, 'name': frel['name'], 'body': body, 'draft': True,
                           'prerelease': bool(frel.get('prerelease')), 'make_latest': 'false'})
    for name in sorted(files):
        upload(rel, name)
    rel = gh_json('PATCH', '%s/releases/%d' % (gbase, rel['id']), token, what='GitHub release publish',
                  payload={'draft': False, 'make_latest': 'true' if latest else 'false'})
    if rel.get('tag_name') != tag or rel.get('draft'):
        die('GitHub release %s did not publish on its tag' % tag)
    if gh_peeled(gbase, tag, token) != commit:
        die('GitHub tag %s moved during publication' % tag)
    check_published(rel, files)
    print('published GitHub release %s (id %d), %d assets byte-verified: %s'
          % (tag, rel['id'], len(files), ', '.join(sorted(files))))


if __name__ == '__main__':
    main()
