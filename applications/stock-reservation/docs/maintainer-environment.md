# Isolated development environment

Maintainers run Bun, dependency installation, development servers, type checking,
and tests inside an isolated OrbStack Linux machine. Source editing and Cloud
management can happen on the host. The database remains in ClickHouse Cloud.

[OrbStack isolated machines](https://docs.orbstack.dev/machines/isolated) disable
macOS integration and shared files. We also enable network isolation and leave
SSH-agent forwarding disabled. This reduces dependency access to the host; it
does not make OrbStack a separate-kernel malware-analysis environment.

## 1. Create and inspect the machine

Run these commands on the macOS host. Inspect the list first; reuse the named
machine only if its settings match:

```sh
orb list
orb create --isolated --isolate-network --cpus 4 --memory 4G --disk 16G \
  ubuntu:noble stock-reservation-dev
orb info stock-reservation-dev
```

The configuration must show `isolated: true`, `isolate_network: true`, and
`forward_ssh_agent: false`, with no host mounts. Do not add `--mount` or
`--forward-ssh-agent`. Inspect the Linux environment as well:

```sh
orb -m stock-reservation-dev -w /home bash -lc '
  test ! -e /mnt/mac &&
  test -z "$SSH_AUTH_SOCK" &&
  test ! -S /var/run/docker.sock &&
  echo "Host integrations are absent"
'
```

## 2. Copy source explicitly

From `applications/stock-reservation` on the host, send a source archive into
the machine's own filesystem. The archive excludes credentials and generated
files; it does not create a host mount:

```sh
tar --exclude=.git --exclude=.deployment --exclude=.clickhouse \
  --exclude=.env --exclude='.env.*' --exclude=node_modules \
  --exclude=coverage --exclude=dist -cf - . \
  | orb -m stock-reservation-dev -w /home bash -lc \
      'mkdir -p "$HOME/stock-reservation"; tar -xf - -C "$HOME/stock-reservation"'
```

The exclusions also omit `.env.example`; copy this reviewed, generic file
explicitly when it is needed:

```sh
cat .env.example | orb -m stock-reservation-dev -w /home bash -lc \
  'cat > "$HOME/stock-reservation/.env.example"'
```

Repeat source transfer after edits. If a file was removed or renamed, remove
that specific stale file in the VM before testing; an archive extraction does
not delete old files. Never send the host's parent `.env`, CLI credential store,
SSH keys, or unrelated project files.

## 3. Install and run inside Linux

Open a Linux shell:

```sh
orb -m stock-reservation-dev -w /home bash
cd "$HOME/stock-reservation"
```

Install the tools and pinned Bun release there:

```sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl unzip postgresql-client jq openssl
curl -fsSL https://bun.sh/install -o /tmp/bun-install.sh
less /tmp/bun-install.sh
bash /tmp/bun-install.sh bun-v1.4.2
export PATH="$HOME/.bun/bin:$PATH"
bun --version
bun install --frozen-lockfile --ignore-scripts
bun run typecheck
bun run test
```

Keep dependencies, Bun's cache, and generated output in Linux. Do not run `bun`,
`npm`, `npx`, or application code on macOS for this project. The example needs no
Node.js installation.

## 4. Transfer only task-specific database access

Run the README's explicit `clickhousectl` commands on the authenticated host.
Keep Cloud API credentials there. Transfer the downloaded CA and the runtime
environment file into `.deployment/` in the VM using standard input:

```sh
orb -m stock-reservation-dev -w /home bash -lc \
  'umask 077; mkdir -p "$HOME/stock-reservation/.deployment"'
cat .deployment/postgres-ca.pem \
  | orb -m stock-reservation-dev -w /home bash -lc \
      'umask 077; cat > "$HOME/stock-reservation/.deployment/postgres-ca.pem"'
cat .deployment/app.env \
  | orb -m stock-reservation-dev -w /home bash -lc \
      'umask 077; cat > "$HOME/stock-reservation/.deployment/app.env"'
```

Set `PG_CA_CERT_PATH=.deployment/postgres-ca.pem` in the runtime file so it resolves
from the application directory in either environment. Database bootstrap and
migration verification also require their scoped credentials; transfer those
separately only for that work, then remove them from the VM when finished. Never
put administrator or migration credentials in `app.env`.

Start the application in Linux using the README. Run its `curl` examples from
a second Linux shell. The default listener is `127.0.0.1:3000` inside the
machine; host port forwarding is unnecessary.

Before a release, record the source revision and actual commands/results in
[verification.md](verification.md). Copy only reviewed source files or sanitized
test evidence back to the host. Never copy the entire working directory back.

## 5. Finish the session

Stop the app with Ctrl-C. Stop the machine when pausing work:

```sh
orb stop stock-reservation-dev
```

After saving reviewed changes and completing the README's Cloud cleanup, remove
the dedicated machine if it is no longer needed:

```sh
orb delete stock-reservation-dev
```

Deleting or stopping the VM does not stop billing for the Cloud database.
