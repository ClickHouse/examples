#!/bin/sh
# Host-side OrbStack management only. Application commands execute in the VM.
set -eu
cd "$(dirname "$0")/.."
machine=link-shortener-dev
case "${1:-}" in
  push|pull-generated|run) ;;
  *) echo 'Usage: sh scripts/vm.sh push | pull-generated | run <command> [args...]' >&2; exit 2 ;;
esac
# Fail closed if this VM is absent, isolation is disabled, or the CLI schema
# changes. Creating/configuring a VM is an explicit prerequisite in AGENTS.md.
command -v jq >/dev/null 2>&1 || { echo 'Install jq to verify OrbStack isolation.' >&2; exit 1; }
info=$(orb info "$machine" --format json)
if ! printf '%s\n' "$info" | jq -e '
  .record.config.isolated == true and
  .record.config.isolate_network == true and
  .record.config.forward_ssh_agent == false
' >/dev/null; then
  echo 'Refusing to use a VM without verified host/network isolation and disabled SSH-agent forwarding.' >&2
  exit 1
fi
vm_home=$(orb -m "$machine" -w /home sh -lc 'printf "%s" "$HOME"')
case "$vm_home" in
  /home/*|/root) ;;
  *) echo 'Unexpected VM home directory; refusing to transfer source.' >&2; exit 1 ;;
esac
project="$vm_home/link-shortener"
orb -m "$machine" -w /home mkdir -p "$project"
case "$1" in
  push)
    # Stage the archive first so tar failure cannot be hidden by a successful
    # receiver. Public templates are included; private state never crosses.
    archive=$(mktemp "${TMPDIR:-/tmp}/shortwave-source.XXXXXXXX")
    trap 'rm -f "$archive"' EXIT HUP INT TERM
    COPYFILE_DISABLE=1 tar --no-xattrs --exclude=.git --exclude='.env*' \
      --exclude=.secrets --exclude=.private --exclude='.deployment*' --exclude=.clickhouse --exclude='*.pem' --exclude=.wrangler \
      --exclude='.dev.vars*' --exclude=node_modules --exclude=.output \
      --exclude=dist --exclude=.tanstack --exclude=.vite --exclude=coverage \
      --exclude=test-results --exclude=playwright-report --exclude=playwright \
      --exclude='*.log' --exclude='._*' -cf "$archive" .
    COPYFILE_DISABLE=1 tar --no-xattrs -rf "$archive" .env.example
    orb -m "$machine" -w "$project" tar -xf - < "$archive"
    ;;
  pull-generated)
    # Lockfile and router source are reviewable; no build products or credentials.
    # Stage both before replacing local files so a failed read cannot truncate.
    generated=$(mktemp -d "${TMPDIR:-/tmp}/shortwave-generated.XXXXXXXX")
    trap 'rm -rf "$generated"' EXIT HUP INT TERM
    orb -m "$machine" -w "$project" cat package-lock.json > "$generated/package-lock.json"
    orb -m "$machine" -w "$project" cat src/routeTree.gen.ts > "$generated/routeTree.gen.ts"
    mv "$generated/package-lock.json" package-lock.json
    mv "$generated/routeTree.gen.ts" src/routeTree.gen.ts
    ;;
  run)
    shift
    [ "$#" -gt 0 ] || { echo 'run requires a command.' >&2; exit 2; }
    exec orb -m "$machine" -w "$project" env \
      PATH="$vm_home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
    ;;
esac
