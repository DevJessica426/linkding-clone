#!/usr/bin/env python3
"""Compares the HTML pages of a real linkding and this clone.

    tool/html_parity.py REF_BASE REF_DB CLONE_BASE CLONE_DB STEPS_FILE

Signs in to both as admin/admin12345 and runs each step of STEPS_FILE
against both, printing a diff of the two pages after normalizing what is
expected to differ: whitespace between and inside text, attribute order,
CSRF tokens, and the few things listed in EXPECTED. Exit status 1 when any
page differs. Steps, one per line:

    GET /bookmarks?q=x          signed in as admin
    ANON /bookmarks/shared      signed out
    POST /bookmarks/action archive=3&x=y
                                a form, with the CSRF token added; the page
                                the redirect leads to is compared
    UPLOAD /bookmarks/action a=1 field=name.txt|text/plain|content
                                the same as multipart/form-data, with a file
    SQL UPDATE ...              run on both databases, nothing compared
    # a comment

A step may start with `FRAME=<id>` (a Turbo frame request) and `STREAM`
(accepting a Turbo Stream answer), as linkding's page scripts send them.
"""

import difflib
import html.parser
import http.cookiejar
import re
import subprocess
import sys
import urllib.parse
import urllib.request

CREDENTIALS = {"username": "admin", "password": "admin12345"}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "source", "track", "wbr"}


class Tokens(html.parser.HTMLParser):
    """The document as one line per tag and text run."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lines = []
        self.depth = 0
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if self.skip or tag == "ld-dev-tool" or attrs.get("id") == "json_profile":
            if tag not in VOID:
                self.skip += 1
            return
        if attrs.get("name") == "csrfmiddlewaretoken":
            attrs["value"] = "<csrf>"
        if "data-csrf-token" in attrs:
            attrs["data-csrf-token"] = "<csrf>"
        shown = " ".join(
            f'{k}="{v}"' if v is not None else k for k, v in sorted(attrs.items())
        )
        self.lines.append("  " * self.depth + f"<{tag}{' ' + shown if shown else ''}>")
        if tag not in VOID:
            self.depth += 1

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID and not self.skip:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if self.skip:
            if tag not in VOID:
                self.skip -= 1
            return
        if tag in VOID:
            return
        self.depth -= 1
        self.lines.append("  " * self.depth + f"</{tag}>")

    def handle_data(self, data):
        if self.skip:
            return
        text = re.sub(r"\s+", " ", data).strip()
        if text:
            self.lines.append("  " * self.depth + text)


# What differs on purpose, and data that differs between the two databases
# rather than in how a page is made: linkding's development-only reload
# script, the Django admin site the clone does not have, the second a
# bookmark was saved, which appears in fallback Wayback Machine links, and
# the size of a gzipped asset, which depends on the zlib build (the API
# parity run checks sizes to within two bytes).
EXPECTED = [
    (re.compile(r'<span class="filesize">[^<]*</span>'), '<span class="filesize"><size></span>'),
    (re.compile(r'<script src="/static/live-reload.js"></script>'), ""),
    (re.compile(r'<li class="menu-item">\s*<a href="/admin/"[^>]*>Admin</a>\s*</li>'), ""),
    (re.compile(r"web\.archive\.org/web/\d{14}/"), "web.archive.org/web/<time>/"),
]


def normalize(document):
    for pattern, replacement in EXPECTED:
        document = pattern.sub(replacement, document)
    parser = Tokens()
    parser.feed(document)
    return parser.lines


class Client:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar)
        )

    def csrf(self):
        for cookie in self.jar:
            if cookie.name.endswith("csrftoken"):
                return cookie.value
        return ""

    def request(self, path, form=None, files=None, headers=None):
        data = None
        headers = dict(headers or {})
        if form is not None:
            form = {**form, "csrfmiddlewaretoken": [self.csrf()]}
            if files is None:
                data = urllib.parse.urlencode(form, doseq=True).encode()
            else:
                data, headers["Content-Type"] = multipart(form, files)
        req = urllib.request.Request(self.base + path, data=data, headers=headers)
        if data is not None:
            req.add_header("Referer", self.base + path)
        try:
            with self.opener.open(req) as response:
                return response.status, response.geturl(), response.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, error.geturl(), error.read().decode()

    def login(self):
        self.request("/login/")
        self.request("/login/", CREDENTIALS)


def multipart(fields, files):
    boundary = "parityboundary7MA4YWxkTrZu0gW"
    out = []
    for name, values in fields.items():
        for value in values:
            out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"'
                       f"\r\n\r\n{value}\r\n")
    for name, (filename, content_type, content) in files.items():
        out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; '
                   f'filename="{filename}"\r\nContent-Type: {content_type}'
                   f"\r\n\r\n{content}\r\n")
    out.append(f"--{boundary}--\r\n")
    return "".join(out).encode(), f"multipart/form-data; boundary={boundary}"


def compare(label, ref, clone, results):
    (rs, ru, rb), (cs, cu, cb) = results
    ru = ru.replace(ref.base, "")
    cu = cu.replace(clone.base, "")
    # The reference runs Django's development server, whose error pages are
    # debug pages; only the status of an error is compared.
    if rs >= 400 and "NONE,NOARCHIVE" in rb:
        rb = cb = ""
    diff = list(difflib.unified_diff(
        [f"status {rs} at {ru}"] + normalize(rb),
        [f"status {cs} at {cu}"] + normalize(cb),
        "linkding", "clone", lineterm="", n=2,
    ))
    if diff:
        print(f"--- {label}: differs")
        print("\n".join(diff[:200]))
        return False
    print(f"ok  {label}")
    return True


def main():
    ref_base, ref_db, clone_base, clone_db, steps_file = sys.argv[1:]
    ref, clone = Client(ref_base), Client(clone_base)
    anon_ref, anon_clone = Client(ref_base), Client(clone_base)
    ref.login()
    clone.login()
    pages = failed = 0
    with open(steps_file, encoding="utf-8") as steps:
        for line in steps:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            headers = {}
            while True:
                kind, _, rest = line.partition(" ")
                if kind.startswith("FRAME="):
                    headers["Turbo-Frame"] = kind.removeprefix("FRAME=")
                elif kind == "STREAM":
                    headers["Accept"] = "text/vnd.turbo-stream.html, text/html"
                else:
                    break
                line = rest
            label = line if not headers else f"{' '.join(f'{k}={v}' for k, v in headers.items())} {line}"
            if kind == "SQL":
                for db in (ref_db, clone_db):
                    subprocess.run(["psql", db, "-qAtc", rest], check=True,
                                   stdout=subprocess.DEVNULL)
                continue
            path, _, body = rest.partition(" ")
            form = files = None
            if kind == "UPLOAD":
                body, _, file_spec = body.partition(" ")
                field, _, spec = file_spec.partition("=")
                files = {field: tuple(spec.split("|", 2))}
            if kind in ("POST", "UPLOAD"):
                form = urllib.parse.parse_qs(body, keep_blank_values=True)
            clients = (anon_ref, anon_clone) if kind == "ANON" else (ref, clone)
            results = [c.request(path, form, files, headers) for c in clients]
            pages += 1
            if not compare(label, *clients, results):
                failed += 1
    print(f"{pages - failed} of {pages} pages match")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
