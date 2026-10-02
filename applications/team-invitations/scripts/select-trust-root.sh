#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 2 ]; then
  printf 'Usage: PGHOST=... PGPORT=5432 select-trust-root.sh authenticated-ca-bundle.pem selected-root.pem\n' >&2
  exit 1
fi
: "${PGHOST:?Set the managed endpoint hostname}"
: "${PGPORT:?Set the managed endpoint port}"
bundle=$1
selected=$2
[ "$bundle" != "$selected" ] || { printf 'Keep the original bundle separately\n' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The peer is fully verified against the authenticated CLI bundle and the endpoint name.
timeout 20 openssl s_client -starttls postgres -connect "$PGHOST:$PGPORT" -servername "$PGHOST" \
  -CAfile "$bundle" -verify_hostname "$PGHOST" -verify_return_error -showcerts \
  </dev/null > "$work/handshake.txt" 2> "$work/handshake.err"
awk '/-----BEGIN CERTIFICATE-----/{copy=1} copy{print} /-----END CERTIFICATE-----/{exit}' \
  "$work/handshake.txt" > "$work/leaf.pem"
# Candidates are ONLY certificates from the authenticated bundle, never peer certificates.
awk -v dir="$work" '/-----BEGIN CERTIFICATE-----/{n++; file=dir "/candidate-" n ".pem"} file{print > file} /-----END CERTIFICATE-----/{close(file); file=""}' "$bundle"
matching=0
anchor=
for candidate in "$work"/candidate-*.pem; do
  [ -f "$candidate" ] || continue
  if openssl verify -CAfile "$candidate" -verify_hostname "$PGHOST" "$work/leaf.pem" >/dev/null 2>&1; then
    matching=$((matching + 1))
    anchor=$candidate
  fi
done
[ "$matching" -eq 1 ] || { printf 'Expected exactly one matching downloaded trust anchor; found %s\n' "$matching" >&2; exit 1; }
umask 077
cp "$anchor" "$selected"
chmod 600 "$selected"
printf 'Selected one verified downloaded trust anchor: '
openssl x509 -in "$selected" -noout -fingerprint -sha256
