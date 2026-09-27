"""Writes the search-language fixture the Dart parser is tested against.

Runs linkding's own parser (bookmarks/services/search_query_parser.py) over
every string literal in linkding's parser tests plus a deterministic batch of
random queries, and records what it makes of each: tokens, the tree or the
error, the tree written back, the tags it mentions, and the query with a tag
stripped. The Dart port must produce the same for every entry.

    cd <linkding checkout> && uv run python <this file> > search_queries.json
"""

import ast
import json
import random
import sys

import django
import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "bookmarks.settings")
django.setup()

from bookmarks.models import UserProfile  # noqa: E402
from bookmarks.services.search_query_parser import (  # noqa: E402
    AndExpression,
    NotExpression,
    OrExpression,
    SearchQueryParseError,
    SearchQueryTokenizer,
    SpecialKeywordExpression,
    TagExpression,
    TermExpression,
    expression_to_string,
    extract_tag_names_from_query,
    parse_search_query,
    strip_tag_from_query,
)


def tree(e):
    if isinstance(e, TermExpression):
        return ["term", e.term]
    if isinstance(e, TagExpression):
        return ["tag", e.tag]
    if isinstance(e, SpecialKeywordExpression):
        return ["keyword", e.keyword]
    if isinstance(e, AndExpression):
        return ["and", tree(e.left), tree(e.right)]
    if isinstance(e, OrExpression):
        return ["or", tree(e.left), tree(e.right)]
    if isinstance(e, NotExpression):
        return ["not", tree(e.operand)]
    return None


def literals(path):
    with open(path) as f:
        source = ast.parse(f.read())
    return {n.value for n in ast.walk(source) if isinstance(n, ast.Constant) and isinstance(n.value, str)}


def random_queries(count):
    rng = random.Random(4711)
    pieces = [
        "rome", "History", "and", "OR", "not", "(", ")", "#book", "#Book", "#",
        "!unread", "!untagged", "!", '"', "'", '"a b"', "'x y'", "\\", "#tag(", "a-b",
        "nOt", "#a#b", "!foo", "  ", "\t", "ümlaut", "\\\"", "a\"b", "c'd", "!unread)",
    ]
    out = set()
    while len(out) < count:
        n = rng.randint(1, 7)
        glue = [rng.choice([" ", "", " "]) for _ in range(n)]
        out.add("".join(rng.choice(pieces) + g for g in glue))
    return out


class Profile:
    def __init__(self, mode):
        self.tag_search = mode


def entry(q):
    tokens = [[t.type.value, t.value, t.position] for t in SearchQueryTokenizer(q).tokenize()]
    try:
        parsed = parse_search_query(q)
        result = {"tree": tree(parsed), "text": expression_to_string(parsed)}
    except SearchQueryParseError as e:
        result = {"error": [e.message, e.position]}
    strict, lax = Profile(UserProfile.TAG_SEARCH_STRICT), Profile(UserProfile.TAG_SEARCH_LAX)
    return {
        "query": q,
        "tokens": tokens,
        **result,
        "tags_strict": extract_tag_names_from_query(q, strict),
        "tags_lax": extract_tag_names_from_query(q, lax),
        "strip_book_strict": strip_tag_from_query(q, "book", strict),
        "strip_book_lax": strip_tag_from_query(q, "book", lax),
    }


queries = sorted(literals(sys.argv[1]) | random_queries(400))
json.dump([entry(q) for q in queries], sys.stdout, ensure_ascii=False, indent=1)
