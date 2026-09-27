"""Writes the fixture the server's ports of linkding/Django helpers are tested
against: URL validation, URL normalization, tag strings, auto-tagging, DRF's
pagination links, and date parsing for `modified_since` and `date_added`.

Each function is linkding's (or Django's / DRF's) own, run over hand-picked
edge cases plus deterministic random inputs.

    cd <linkding checkout> && PYTHONPATH=. uv run python <this file> > logic.json
"""

import json
import os
import random
import sys

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "bookmarks.settings")
django.setup()

from django.core.exceptions import ValidationError  # noqa: E402
from django.core.validators import URLValidator  # noqa: E402
from django.utils.dateparse import parse_datetime, parse_date  # noqa: E402
from rest_framework import fields as drf_fields  # noqa: E402
from rest_framework.utils.urls import remove_query_param, replace_query_param  # noqa: E402

from bookmarks.models import parse_tag_string  # noqa: E402
from bookmarks.services import auto_tagging  # noqa: E402
from bookmarks.utils import normalize_url  # noqa: E402
from bookmarks.services.wayback import generate_fallback_webarchive_url  # noqa: E402

rng = random.Random(1234)

URLS = [
    "https://example.com", "http://example.com/", "HTTPS://Example.COM/Path/",
    "https://example.com/a/b/", "https://example.com/a//", "https://example.com?b=2&a=1",
    "https://example.com/?a=1&a=0&b=", "https://example.com/?q=a+b&x=%20y",
    "https://example.com/?flag", "https://example.com/#Frag", "https://example.com/p;params?x=1#f",
    "https://user:pass@Example.com:8080/x/", "https://user@example.com/", "http://localhost:8000/",
    "http://127.0.0.1/", "http://[::1]:80/a", "http://[2001:db8::1]/", "ftp://files.example.com/a.txt",
    "ftps://x.example.org", "mailto:someone@example.com", "javascript:alert(1)", "example.com",
    "//example.com/path", "http://", "http://.com", "http://-a.com", "http://a-.com", "http://a.b-c.de",
    "http://xn--bcher-kva.example", "http://bücher.example/ä?ö=ü", "https://例子.测试", "http://a.b",
    "http://localhost", "http://localhost.", "http://example.com.", "http://exa mple.com",
    "http://example.com/a b", "http://example.com/\t", "https://example.com:0/", "https://example.com:65536/",
    "https://example.com:abc/", "https://example.com:99999/", "http://256.1.1.1", "http://1.2.3", "http://0.0.0.0",
    "http://01.2.3.4", "http://[::g]/", "http://[::1", "https://a..com", "https://" + "a" * 64 + ".com",
    "https://" + "a" * 63 + ".com", "https://example.com/" + "x" * 2100, "  https://example.com/pad  ",
    "https://example.com/%7Euser", "https://example.com/?b=%2F&a=%2f", "https://EXAMPLE.com/Case?Q=V",
    "https://example.com/?a=1;b=2", "https://example.com/?=x", "https://example.com/?&&a=1&&",
    "https://example.com/?%zz=1", "https://example.com/path/?", "https://example.com#", "http:example.com",
    "https:/example.com", "https:///example.com", "HTTP://EXAMPLE.COM:80", "https://example.com/p?a=b#c?d",
    "", " ", "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s", "https://github.com/sissbruecker/linkding/",
]


def fuzz_urls(n):
    schemes = ["http", "https", "HTTP", "ftp", "file", ""]
    hosts = ["example.com", "Example.COM", "a.b.c", "localhost", "127.0.0.1", "[::1]", "xn--p1ai", "ü.de", "bad_host.com", "a"]
    paths = ["", "/", "/a", "/a/", "/A//", "/x;y", "/%20", "/ä", "/a b"]
    queries = ["", "?", "?a=1", "?b=2&a=1", "?a", "?a=&b", "?x=%41&y=+", "?z=1&z=0"]
    frags = ["", "#", "#top", "#A?b"]
    out = set()
    while len(out) < n:
        s = rng.choice(schemes)
        u = (s + "://" if s else rng.choice(["", "//"])) + rng.choice(hosts)
        if rng.random() < 0.2:
            u += ":" + rng.choice(["80", "8080", "0", "70000", "x"])
        u += rng.choice(paths) + rng.choice(queries) + rng.choice(frags)
        out.add(u)
    return sorted(out)


def url_valid(u):
    try:
        URLValidator()(u)
        return True
    except ValidationError:
        return False


TAG_STRINGS = [
    "", " ", ",", "a", "a,b", "b,a", "A,a", "a,A", "b,A,a", "  spaced tag  , other", "x,,y",
    "Äpfel,äpfel,Zebra,apple", "one two three", "c,B,a", " , , ", "tag1,Tag1,TAG1", "é,e,E",
    "java,Java,JAVA,web dev", "a b,a-b", "日本,中文",
]

RULES = """
# comment line
example.com tag1
youtube.com video media   # trailing comment
github.com/sissbruecker linkding
reddit.com/r/programming dev
example.org/?lang=en english
example.org/?q= query
example.net/#section anchor
bücher.example books
.co.uk british
localhost:8000 local
"""
AUTO_URLS = [
    "https://example.com", "https://sub.example.com/path", "https://notexample.com",
    "https://www.youtube.com/watch?v=1", "https://github.com/sissbruecker/linkding",
    "https://github.com/other/repo", "https://reddit.com/r/programming/comments/1",
    "https://reddit.com/r/Programming", "https://example.org/?lang=en&x=1", "https://example.org/?lang=de",
    "https://example.org/?q=anything", "https://example.org/", "https://example.net/#section-2",
    "https://example.net/#other", "https://bücher.example/x", "https://xn--bcher-kva.example/",
    "https://bbc.co.uk/news", "http://localhost:8000/admin", "http://localhost:9000/", "not a url", "",
    "HTTPS://EXAMPLE.COM/UPPER",
]

PAGE_URLS = [
    "http://testserver/api/bookmarks/",
    "http://testserver/api/bookmarks/?q=a+b&limit=5",
    "http://testserver/api/bookmarks/?offset=10&limit=5&q=%23tag",
    "http://testserver/api/bookmarks/?disable_scraping&z=1&a=2",
    "http://testserver/api/bookmarks/?q=%C3%A4+x&limit=2&offset=4",
    "http://testserver/api/bookmarks/?q=a%2Fb&q=c",
    "http://testserver/api/bookmarks/?sort=title_asc#frag",
]

DATES = [
    "2025-01-01T00:00:00Z", "2025-01-01T00:00:00", "2025-01-01 00:00", "2025-01-01T10:20:30.123456+02:00",
    "2025-01-01T10:20:30.1234567Z", "2025-01-01T10:20:30,5Z", "2025-01-01", "2025-1-1", "2025-01-01T25:00:00",
    "2025-13-01T00:00:00Z", "yesterday", "", "2025-01-01T10:20Z", "2025-01-01T10:20:30-0530",
    "2025-01-01T10:20:30+05", "2025-01-01T10:20:30 +02:00", "  2025-01-01T00:00:00Z", "2025-02-30T00:00:00Z",
]


def dt_or_none(fn, s):
    try:
        v = fn(s)
    except (ValueError, TypeError):
        return "error"
    if v is None:
        return None
    return v.isoformat()


def auto_tags(rules, url):
    """linkding's callers catch any exception and apply no auto tags."""
    try:
        return sorted(auto_tagging.get_tags(rules, url))
    except Exception as e:
        return {"error": type(e).__name__}


def drf_datetime(s):
    field = drf_fields.DateTimeField()
    try:
        v = field.to_internal_value(s)
    except Exception as e:
        return {"error": str(e.detail[0]) if hasattr(e, "detail") else str(e)}
    return v.isoformat()


urls = sorted(set(URLS) | set(fuzz_urls(300)))
data = {
    "url_valid": [[u, url_valid(u)] for u in urls],
    "normalize_url": [[u, normalize_url(u)] for u in urls],
    "tag_strings": [[s, parse_tag_string(s), parse_tag_string(s, " ")] for s in TAG_STRINGS],
    "auto_tagging": {"rules": RULES, "cases": [[u, auto_tags(RULES, u)] for u in AUTO_URLS]},
    "auto_tagging_single": [[rule, u, auto_tags(rule, u)] for rule in RULES.strip().split("\n") for u in AUTO_URLS],
    "page_links": [
        [u, replace_query_param(u, "limit", 5), replace_query_param(replace_query_param(u, "limit", 5), "offset", 15),
         remove_query_param(u, "offset")]
        for u in PAGE_URLS
    ],
    "parse_datetime": [[s, dt_or_none(parse_datetime, s), dt_or_none(parse_date, s)] for s in DATES],
    "drf_datetime": [[s, drf_datetime(s)] for s in DATES],
    "web_archive": [
        ["https://example.com/a", "2026-09-27T04:07:44.503580+00:00",
         generate_fallback_webarchive_url("https://example.com/a", parse_datetime("2026-09-27T04:07:44.503580+00:00"))],
    ],
}
json.dump(data, sys.stdout, ensure_ascii=False, indent=1)
