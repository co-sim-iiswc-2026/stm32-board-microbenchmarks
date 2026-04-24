#!/bin/bash
# Diff board and gem5 sweep outputs, showing which tests don't match.
# Board is the reference; this tool reports every divergence.
#
# Usage:
#   ./verification/diff_gem5_vs_board.sh
#     Diffs verification/logs/gem5/ento_results.txt (latest sweep)
#     against verification/board_reference.txt (committed board baseline).
#     Works on any host that has the repo checked out; no scp needed.
#
#   ./verification/diff_gem5_vs_board.sh BOARD_LOG GEM5_LOG
#     Compares specific files (useful for diffing two fresh sweeps on one host).
#
# Exit code is the count of divergent+missing tests, capped at 255 — useful
# as a health check, but this tool is primarily informational. Nothing is
# classified or suppressed; the output is the raw picture.

set -euo pipefail
cd "$(dirname "$0")/.."

BOARD_LOG="${1:-verification/board_reference.txt}"
GEM5_LOG="${2:-verification/logs/gem5/ento_results.txt}"

[[ -f "$BOARD_LOG" ]] || { echo "missing board log: $BOARD_LOG" >&2; exit 2; }
[[ -f "$GEM5_LOG"  ]] || { echo "missing gem5 log:  $GEM5_LOG"  >&2; exit 2; }

# Normalize each log to sorted "name<TAB>signature" TSV. Signature is either
# the bytes= value or a STATUS token (GEM5_FAILED / FLASH_FAILED / etc).
# Failure lines use dashed names ("bench-foo:"); ENTO_RESULT lines use
# underscored names. Normalize to underscored.
parse() {
  awk '
    /^ENTO_RESULT name=/ {
      split($2, a, "="); split($3, b, "=");
      print a[2] "\t" b[2];
      next;
    }
    /^[a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]/ {
      name=$1; sub(/:$/, "", name); gsub("-", "_", name);
      print name "\t" $2;
    }
  ' "$1" | sort -t $'\t' -k1,1
}

TMPDIR=$(mktemp -d); trap 'rm -rf "$TMPDIR"' EXIT
parse "$BOARD_LOG" > "$TMPDIR/board.tsv"
parse "$GEM5_LOG"  > "$TMPDIR/gem5.tsv"

# Outer-join on name; missing sides become "MISSING".
join -t $'\t' -a1 -a2 -e MISSING -o '0,1.2,2.2' \
  "$TMPDIR/board.tsv" "$TMPDIR/gem5.tsv" > "$TMPDIR/joined.tsv"

DIVERGE=0; BOARD_ONLY=0; GEM5_ONLY=0; IDENTICAL=0

: > "$TMPDIR/diverge.txt"
: > "$TMPDIR/board_only.txt"
: > "$TMPDIR/gem5_only.txt"

while IFS=$'\t' read -r name bsig gsig; do
  if   [[ "$bsig" == MISSING ]]; then echo "$name"            >> "$TMPDIR/gem5_only.txt";  GEM5_ONLY=$((GEM5_ONLY+1))
  elif [[ "$gsig" == MISSING ]]; then echo "$name"            >> "$TMPDIR/board_only.txt"; BOARD_ONLY=$((BOARD_ONLY+1))
  elif [[ "$bsig" == "$gsig" ]]; then IDENTICAL=$((IDENTICAL+1))
  else
    {
      printf '%s\n' "$name"
      printf '  board: %s\n' "$bsig"
      printf '  gem5:  %s\n' "$gsig"
    } >> "$TMPDIR/diverge.txt"
    DIVERGE=$((DIVERGE+1))
  fi
done < "$TMPDIR/joined.tsv"

if [[ $DIVERGE -gt 0 ]]; then
  echo "=== Diverges (${DIVERGE}) ==="
  cat "$TMPDIR/diverge.txt"
  echo
fi
if [[ $BOARD_ONLY -gt 0 ]]; then
  echo "=== Board-only (${BOARD_ONLY}) — tests in board log but missing from gem5 ==="
  sed 's/^/  /' "$TMPDIR/board_only.txt"
  echo
fi
if [[ $GEM5_ONLY -gt 0 ]]; then
  echo "=== Gem5-only (${GEM5_ONLY}) — tests in gem5 log but missing from board ==="
  sed 's/^/  /' "$TMPDIR/gem5_only.txt"
  echo
fi

TOTAL=$((DIVERGE + BOARD_ONLY + GEM5_ONLY + IDENTICAL))
echo "Summary: ${TOTAL} tests total | ${IDENTICAL} match | ${DIVERGE} diverge | ${BOARD_ONLY} board-only | ${GEM5_ONLY} gem5-only"
echo "         board log: $BOARD_LOG"
echo "         gem5 log:  $GEM5_LOG"

FAIL=$((DIVERGE + BOARD_ONLY + GEM5_ONLY))
if [[ $FAIL -gt 255 ]]; then FAIL=255; fi
exit $FAIL
