#!/bin/bash
# Sanity-check that the generators reproduce the currently-committed
# generated files + manifest byte-for-byte. Run this before committing
# changes to fpu_repeat.py or fpu_seq.py — if output drifts unintentionally,
# you'll see the diff and can either revert or review + accept the change.
#
# Exit 0 if everything matches. Non-zero with a diff if anything drifted.
#
# Usage:
#   ./verification/gen/check.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Snapshot what's currently on disk (i.e. committed state, assuming clean tree).
cp -r benchmark/microbench/generated "$TMPDIR/before"
cp verification/gen/fpu_seq_manifest.txt "$TMPDIR/before_manifest.txt"

# Regenerate.
python3 verification/gen/fpu_repeat.py > /dev/null
python3 verification/gen/fpu_seq.py    > /dev/null

# Diff. `diff -r` exits non-zero on any mismatch.
if ! diff -r "$TMPDIR/before" benchmark/microbench/generated > "$TMPDIR/gen.diff"; then
  echo "FAIL: regenerated .cc files differ from committed state:" >&2
  cat "$TMPDIR/gen.diff" >&2
  exit 1
fi

if ! diff "$TMPDIR/before_manifest.txt" verification/gen/fpu_seq_manifest.txt > "$TMPDIR/manifest.diff"; then
  echo "FAIL: regenerated manifest differs from committed state:" >&2
  cat "$TMPDIR/manifest.diff" >&2
  exit 1
fi

echo "OK: generators reproduce committed output byte-for-byte."
