#!/usr/bin/env bash
# Formats the hand-written Dart files. Dust's generated `.g.dart` files are
# left alone: `dart format` over them makes `dust check` report them stale.
#
#   tool/format.sh [--output=none --set-exit-if-changed]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
find "$ROOT/packages" \( -name .dart_tool -o -name build \) -prune -o \
  -type f -name '*.dart' ! -name '*.g.dart' ! -path '*/test/generated/*' \
  -print0 | xargs -0 dart format "$@"
