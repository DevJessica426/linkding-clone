#!/usr/bin/env bash
# Runs the same API requests against a real linkding and this clone, each on
# an empty database, and reports every response that differs.
#
#   LINKDING_DIR=~/src/linkding tool/parity.sh
#
# Needs PostgreSQL (as PGUSER/PGPASSWORD on localhost), and a linkding
# checkout at the version this clone targets with `uv sync` done in it.
# The databases linkding_ref and linkding_clone are dropped and recreated.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINKDING_DIR="${LINKDING_DIR:?set LINKDING_DIR to a linkding checkout}"
PGUSER="${PGUSER:-conduit}"
PGPASSWORD="${PGPASSWORD:-conduit}"
export PGPASSWORD
PG="postgres://$PGUSER:$PGPASSWORD@localhost:5432"
REF_PORT=9090
CLONE_PORT=9091
LOGS="$ROOT/build/parity"
mkdir -p "$LOGS"

stop() { fuser -k "$1/tcp" >/dev/null 2>&1 || true; }
wait_for() {
  for _ in $(seq 1 120); do
    curl -sf -o /dev/null "http://localhost:$1/health" && return 0
    sleep 1
  done
  echo "server on port $1 did not start; see $LOGS" >&2
  exit 1
}

stop $REF_PORT
stop $CLONE_PORT
stop 9099
# The pages metadata scraping reads. Both servers may reach localhost, and
# only localhost: requests to 127.0.0.1 must be refused as internal.
export LD_ALLOWED_INTERNAL_HOSTS=localhost
(cd "$ROOT/packages/linkding_server/tool/parity_pages" &&
  nohup python3 -m http.server 9099 --bind 127.0.0.1 > "$LOGS/pages.log" 2>&1 &)
for db in linkding_ref linkding_clone; do
  psql "$PG/postgres" -qc "DROP DATABASE IF EXISTS $db" -qc "CREATE DATABASE $db" 2>/dev/null
done

echo "starting linkding on :$REF_PORT"
(
  cd "$LINKDING_DIR"
  export LD_DB_ENGINE=postgres LD_DB_DATABASE=linkding_ref LD_DB_USER="$PGUSER"
  export LD_DB_PASSWORD="$PGPASSWORD" LD_DB_HOST=localhost LD_DB_PORT=5432
  export LD_DISABLE_BACKGROUND_TASKS=True LD_SUPERUSER_NAME=admin
  export LD_SUPERUSER_PASSWORD=admin12345
  uv run manage.py migrate -v 0
  uv run manage.py create_initial_superuser
  uv run manage.py shell -c "
from django.contrib.auth.models import User
from bookmarks.models import ApiToken
print(ApiToken.objects.create(user=User.objects.get(username='admin'), name='parity').key)
" | grep -oE '[0-9a-f]{40}' > "$LOGS/ref_token"
  nohup uv run manage.py runserver "127.0.0.1:$REF_PORT" --noreload \
    > "$LOGS/linkding.log" 2>&1 &
)

echo "starting the clone on :$CLONE_PORT"
(
  cd "$ROOT"
  export DATABASE_URL="$PG/linkding_clone?sslmode=disable"
  export LD_SERVER_PORT=$CLONE_PORT LD_SUPERUSER_NAME=admin
  export LD_SUPERUSER_PASSWORD=admin12345
  nohup dart run packages/linkding_server/bin/server.dart \
    > "$LOGS/clone.log" 2>&1 &
  wait_for $CLONE_PORT
  dart run packages/linkding_server/bin/manage.dart create_token admin parity \
    | grep -oE '[0-9a-f]{40}' > "$LOGS/clone_token"
)
wait_for $REF_PORT

cd "$ROOT/packages/linkding_server"
dart run tool/parity.dart \
  "http://localhost:$REF_PORT=$(cat "$LOGS/ref_token")=$PG/linkding_ref" \
  "http://localhost:$CLONE_PORT=$(cat "$LOGS/clone_token")=$PG/linkding_clone"
