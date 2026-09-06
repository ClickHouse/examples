#!/usr/bin/env bash
# Run every implementation (or the ones named as arguments) against the service in
# ../.env and diff its stdout with expected-output.txt. Exit non-zero if any differ.
#
#   scripts/verify.sh              # all implementations
#   scripts/verify.sh rust go      # a subset
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ ! -f .env ]]; then
  echo "No .env found. Run scripts/cloud.sh setup first (or copy .env.example)." >&2
  exit 1
fi
set -a; source .env; set +a

if (( $# )); then langs=("$@"); else
  langs=(); for d in */; do [[ -x "$d/run.sh" ]] && langs+=("${d%/}"); done
fi

normalize() { sed -E 's/^1 connect: ok, server version .*/1 connect: ok, server version <version>/'; }

failed=0
for lang in "${langs[@]}"; do
  printf '%-12s ' "$lang"
  start=$(date +%s)
  actual="$(./"$lang"/run.sh 2>"/tmp/client-tour-$lang.stderr" | normalize)"
  status=$?
  secs=$(( $(date +%s) - start ))
  if [[ $status -eq 0 ]] && diff -q <(printf '%s\n' "$actual") expected-output.txt >/dev/null; then
    echo "PASS (${secs}s)"
  else
    echo "FAIL (exit $status, ${secs}s); stderr in /tmp/client-tour-$lang.stderr"
    diff <(printf '%s\n' "$actual") expected-output.txt | sed 's/^/    /'
    failed=1
  fi
done
exit $failed
