#!/usr/bin/env bash
# Dust's layout rule: no hand-written Dart file passes 180 lines. Checks every
# package's lib, bin, web, test and tool; generated code (`.g.dart`, and files
# headed "GENERATED CODE - DO NOT MODIFY BY HAND") is left out.
#
#   tool/check_loc.sh [limit]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIMIT="${1:-180}"
failed=0
checked=0

while IFS= read -r -d '' file; do
  if head -3 "$file" | grep -q 'GENERATED CODE - DO NOT MODIFY BY HAND'; then
    continue
  fi
  checked=$((checked + 1))
  lines=$(wc -l < "$file")
  if [ "$lines" -gt "$LIMIT" ]; then
    echo "${file#"$ROOT"/}: $lines lines"
    failed=$((failed + 1))
  fi
done < <(find "$ROOT/packages" \
  \( -name .dart_tool -o -name build \) -prune -o \
  -type f -name '*.dart' ! -name '*.g.dart' \
  \( -path '*/lib/*' -o -path '*/bin/*' -o -path '*/web/*' \
     -o -path '*/test/*' -o -path '*/tool/*' \) -print0)

if [ "$failed" -gt 0 ]; then
  echo "$failed of $checked files pass $LIMIT lines"
  exit 1
fi
echo "all $checked files are within $LIMIT lines"
