"""Writes the fixture the server's rendering of bookmark notes is tested
against: linkding's `{% markdown %}` tag (Python-Markdown with fenced code
and nl2br, cleaned by bleach, then linkified) over typical and hostile notes.

    cd <linkding checkout> && PYTHONPATH=. uv run python <this file> > markdown.json
"""

import json
import os
import random

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "bookmarks.settings")
django.setup()

from bookmarks.templatetags.shared import render_markdown  # noqa: E402

CASES = [
    "",
    "plain",
    "two\nlines",
    "three\nshort\nlines",
    "para one\n\npara two",
    "trailing spaces  \nhard break",
    "*em* and **strong** and _under_ and __double__",
    "snake_case_word and 2*3*4",
    "`code` and ``co`de``",
    "# Heading\ntext",
    "## Heading 2\n\n### Heading 3",
    "Heading\n=======",
    "Sub\n---",
    "- one\n- two\n- three",
    "* star\n* list",
    "1. first\n2. second",
    "text\n- not a list without blank line",
    "text\n\n- list after blank",
    "- item\n\n    continued paragraph",
    "- outer\n    - inner",
    "> quote\n> more",
    "> quote\n\nafter",
    "```\nfenced\ncode\n```",
    "```python\ndef f():\n    return 1\n```",
    "~~~\ntilde fence\n~~~",
    "    indented code\n    block",
    "---",
    "a\n\n***\n\nb",
    "[link](https://example.com)",
    "[link](https://example.com \"title\")",
    "[js](javascript:alert(1))",
    "![img](https://example.com/a.png)",
    "<https://example.com/auto>",
    "https://example.com/bare",
    "see http://example.com/http and www.example.com/www",
    "example.com without scheme",
    "mail me@example.com",
    "<script>alert(1)</script>",
    "<b>bold html</b> <i>i</i>",
    "<div onclick=\"x\">div</div>",
    "<iframe src=\"https://evil\"></iframe>",
    "a < b & c > d",
    "&amp; &copy; &#169;",
    "line with \\*escaped\\* stars",
    "Some *notes* for 5\nsecond line https://example.com/x\n\n- item\n- `code`",
    "tab\tseparated",
    "unicode: 日本語 émile ✓",
    "https://example.com/path_(with)_parens",
    "https://example.com/end.",
    "(https://example.com/in-parens)",
    "**bold with [link](https://x.example)**",
    "table | not\n--- | ---\na | b",
    "1) paren list\n2) second",
    "+ plus\n+ list",
    "text  \n",
    "\n\nleading blank lines",
    "ends with newline\n",
    "html comment <!-- hidden --> after",
    "<p>raw paragraph</p>",
    "<a href=\"https://ok\" onclick=\"x\">a</a>",
    "<img src=\"https://example.com/i.png\" onerror=\"x\">",
    "Setext\n===\nfollowed",
    "* a\n\n* b",
    "10. ten\n11. eleven",
]


def main():
    rng = random.Random(7)
    words = ["word", "*em*", "`c`", "https://x.example/p", "- li", "\n", "\n\n",
             "# h", "> q", "**b**", "<b>", "&", "_u_", "1. n", "    ind"]
    cases = list(CASES)
    for _ in range(80):
        cases.append(" ".join(rng.choice(words) for _ in range(rng.randint(1, 8))))
    out = [{"input": text, "html": str(render_markdown({}, text))} for text in cases]
    print(json.dumps(out, ensure_ascii=False, indent=1))


main()
