"""Copies the list of common passwords Django's `CommonPasswordValidator`
refuses (20,000 of them, gzipped, one per line) to where the server reads it.

    cd <linkding checkout> && uv run python <this file> \
        <clone>/packages/linkding_server/web/data/common-passwords.txt.gz

The list is Django's (BSD-3-Clause, Copyright (c) Django Software Foundation
and individual contributors), created by Royce Williams.
"""

import pathlib
import shutil
import sys

import django.contrib.auth

source = pathlib.Path(django.contrib.auth.__file__).parent / "common-passwords.txt.gz"
shutil.copyfile(source, sys.argv[1])
