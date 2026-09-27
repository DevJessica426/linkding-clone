#!/usr/bin/env bash
# Builds the page script the server serves as /static/bundle.js, as
# linkding's esbuild step does: Turbo and Floating UI as published, then
# the small custom-element shim, then the Dart components compiled to
# JavaScript.
#
#   tool/build_web.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/packages/linkding_web"
OUT="$ROOT/packages/linkding_server/web/static/bundle.js"
BUILD="$ROOT/build/web"

mkdir -p "$BUILD"
(cd "$WEB" && dart compile js -O2 --no-source-maps \
  -o "$BUILD/main.js" web/main.dart)

{
  for part in \
    "$WEB/vendor/turbo.es2017-umd.js" \
    "$WEB/vendor/floating-ui.core.umd.min.js" \
    "$WEB/vendor/floating-ui.dom.umd.min.js" \
    "$WEB/web/elements.js" \
    "$BUILD/main.js"; do
    cat "$part"
    # Each part is a complete script; keep the next from continuing it.
    printf '\n;\n'
  done
} > "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
