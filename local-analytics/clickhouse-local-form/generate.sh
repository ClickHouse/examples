#!/usr/bin/env bash
# Generate sample url-encoded form payloads locally, so nothing is committed to git.
# Writes into ./data/ (gitignored):
#   data/payload.txt        - one webhook-style form body (the worked example)
#   data/encoded.txt        - a body with percent-encoding and '+' (the gotcha)
#   data/hooks/*.txt        - 3 readable webhook bodies (the glob example)
#   data/perf/*.txt         - many one-line form bodies (the perf number)
# Each file holds ONE application/x-www-form-urlencoded body: a=1&b=hello&...
# Form parses that into ONE row with columns a, b, ...
# Idempotent: re-running overwrites.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data data/hooks data/perf

PERF_FILES=${PERF_FILES:-2000}

echo "Generating data/payload.txt (one form body)..."
printf 'event=signup&user_id=1001&plan=pro&amount=49.00&country=GB' > data/payload.txt

echo "Generating data/encoded.txt (percent-encoding + plus)..."
# %C3%A3 -> a-tilde, %26 -> &, %3D -> =, and a literal '+'
printf 'name=Jane+Doe&city=S%%C3%%A3o+Paulo&note=a%%26b%%3Dc&amount=19.99' > data/encoded.txt

echo "Generating data/hooks/*.txt (3 webhook bodies)..."
printf 'event=signup&user_id=1001&plan=pro&amount=49.00&ts=2026-06-01'  > data/hooks/hook1.txt
printf 'event=upgrade&user_id=1002&plan=team&amount=99.00&ts=2026-06-02' > data/hooks/hook2.txt
printf 'event=signup&user_id=1003&plan=free&amount=0.00&ts=2026-06-03'   > data/hooks/hook3.txt

echo "Generating data/perf/*.txt ($PERF_FILES form bodies)..."
rm -f data/perf/*.txt
plans=(free pro team enterprise)
countries=(GB US DE FR IN BR)
for i in $(seq 1 "$PERF_FILES"); do
  p=${plans[$((i % 4))]}
  c=${countries[$((i % 6))]}
  amt=$(( (i % 4) * 25 ))
  printf 'event=signup&user_id=%d&plan=%s&amount=%d.00&country=%s' "$i" "$p" "$amt" "$c" > "data/perf/p$i.txt"
done

echo
echo "Generated files:"
ls -la data
echo "perf file count: $(ls data/perf | wc -l | tr -d ' ')"
