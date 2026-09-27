"""Writes the fixture the server's Netscape bookmark file parser and
timestamp reading are tested against: linkding's `parser.parse` and
`utils.parse_timestamp` over hand-picked files and values.

    cd <linkding checkout> && PYTHONPATH=. uv run python <this file> > netscape.json
"""

import json
import os

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "bookmarks.settings")
django.setup()

from bookmarks.services.parser import parse  # noqa: E402
from bookmarks.utils import parse_timestamp  # noqa: E402

DOCUMENTS = [
    "",
    "<DL><p></DL><p>",
    '<DL><p>\n<DT><A HREF="https://a.example/" ADD_DATE="1" TAGS="x,y">A</A>\n</DL><p>',
    '<DL><p>\n<DT><A HREF="https://a.example/">  Spaced title  </A>\n<DD>  Desc  \n<DT><A HREF="https://b.example/">B</A>\n</DL>',
    '<DL><dt><a href="https://lower.example/" tags="One, two ,,Three" toread="1" private="0">lower</a><dd>d</dl>',
    '<DL><DT><A HREF="https://e.example/?a=1&amp;b=2" TAGS="&lt;t&gt;">T &amp; &copy; &#169; &notit;</A></DL>',
    '<DL><DT><A HREF="https://n.example/">N</A><DD>before[linkding-notes]the notes[/linkding-notes]after</DL>',
    '<DL><DT><A HREF="https://n2.example/">N</A><DD>[linkding-notes]only notes</DL>',
    '<DL><DT><A HREF="https://p.example/" PRIVATE>P</A><DT><A HREF="https://q.example/" PRIVATE="0">Q</A></DL>',
    '<DL><DT><A HREF="https://arch.example/" TAGS="linkding:bookmarks.archived,z">Arch</A></DL>',
    '<DL><DT><A HREF="https://arch2.example/" TAGS="x-linkding:bookmarks.archived-y">Arch2</A></DL>',
    '<DL><DT><H3>Folder</H3><DL><p><DT><A HREF="https://in.example/">In</A></DL><p><DT><A HREF="https://out.example/">Out</A></DL>',
    '<DL><DT><A HREF="https://nested.example/">Nested <b>bold</b> rest</A><DD>desc <br> more</DL>',
    '<DL><DT><A HREF="https://nodt.example/" TAGS="kept">First</A><A HREF="https://second.example/">Second</A></DL>',
    '<DL><DT><A HREF="https://empty.example/"></A></DL>',
    '<DL><DT><A>no href</A></DL>',
    '<!-- comment --><DL><DT><A HREF="https://c.example/" ADD_DATE=1600000000 LAST_MODIFIED=\'1600000001\'>C</A></DL>',
    '<DL><DT><A HREF="https://u.example/" TITLE="attr title">Text title</A></DL>',
    '<DL><DT><A HREF="https://u2.example/" TITLE="attr title"></A></DL>',
    '<DL><DT><A HREF="https://x.example/">X</A>\n<DD>line one\nline two\n</DL>',
    '<DL><DT><A HREF="https://a.example/" TAGS="">A</A><DT><A HREF="https://b.example/">B</A></DL>',
    '<DL><DT><A HREF="https://1.example/">1 < 2</A></DL>',
]

TIMESTAMPS = [
    "0", "1", "-1", "1600000000", "1600000000000", "1600000000000000",
    "1600000000000000000", "253402300799", "253402300800", "-62135596800",
    "-62135596801", "1_000", " 42 ", "+7", "abc", "", "1.5", "99999999999999999999999",
]


def bookmark(b):
    return {
        "href": b.href, "href_normalized": b.href_normalized, "title": b.title,
        "description": b.description, "notes": b.notes, "date_added": b.date_added,
        "date_modified": b.date_modified, "tag_names": b.tag_names,
        "to_read": b.to_read, "private": b.private, "archived": b.archived,
    }


def timestamp(value):
    try:
        return parse_timestamp(value).isoformat()
    except Exception:
        return None


print(json.dumps({
    "documents": [[d, [bookmark(b) for b in parse(d)]] for d in DOCUMENTS],
    "timestamps": [[t, timestamp(t)] for t in TIMESTAMPS],
}, ensure_ascii=False, indent=1))
