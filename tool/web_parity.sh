#!/usr/bin/env bash
# Compares the web pages of a real linkding and this clone: runs the API
# parity suite (which starts both servers on fresh databases), loads the
# same extra data into both, then fetches and submits the same pages on
# both and reports every page that differs, and finally drives both in a
# browser, reporting every interaction that behaves differently and every
# page whose screenshot differs (pairs and diffs in build/screenshots).
#
#   LINKDING_DIR=~/src/linkding tool/web_parity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGUSER="${PGUSER:-conduit}"
PGPASSWORD="${PGPASSWORD:-conduit}"
export PGUSER PGPASSWORD
PG="postgres://$PGUSER:$PGPASSWORD@localhost:5432"

"$ROOT/tool/parity.sh"

TOOL="$ROOT/packages/linkding_server/tool"
for db in linkding_ref linkding_clone; do
  psql "$PG/$db" -q -v ON_ERROR_STOP=1 -f "$TOOL/web_parity_seed.sql"
done
python3 "$TOOL/html_parity.py" \
  http://localhost:9090 "$PG/linkding_ref" \
  http://localhost:9091 "$PG/linkding_clone" \
  "$TOOL/web_parity_steps.txt"

# The pages in a browser, when Playwright for Node is installed.
export NODE_PATH="${NODE_PATH:-$(npm root -g 2>/dev/null || true)}"
if node -e 'require("playwright")' 2>/dev/null; then
  node "$TOOL/browser_parity.js" http://localhost:9090 http://localhost:9091
  node "$TOOL/screenshot_parity.js" http://localhost:9090 http://localhost:9091 \
    "$ROOT/build/screenshots"
else
  echo "browser parity skipped: Playwright for Node is not installed" \
    "(npm i -g playwright)"
fi
