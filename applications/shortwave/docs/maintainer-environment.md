# Maintainer development environment

The repository maintainer and coding agents use the dedicated OrbStack VM from
[AGENTS.md](../AGENTS.md). Before reusing it, verify isolation and disabled SSH
forwarding. The helper checks these settings before each operation and derives
the VM's home directory.

```sh
orb list
# Create only if absent:
orb create --isolated --isolate-network ubuntu:noble link-shortener-dev
orb info link-shortener-dev --format json
sh scripts/vm.sh push
```

The host helper requires jq. Keep host mounts, command execution, SSH forwarding,
and host Docker sockets disabled. Transfer public source with the helper; keep
credentials, dependencies, build output, and database connections inside the VM.

In the Linux environment, install prerequisites and the pinned tools:

```sh
sudo apt-get update
sudo apt-get install -y curl ca-certificates xz-utils git jq postgresql-client openssl
sh scripts/install-tools.sh
export PATH="$HOME/.local/bin:$PATH"
npm ci
```

The installer uses official Node and ClickHouse download hosts and pins Node
22.23.2 and clickhousectl 0.4.2. It verifies Node's published SHA256 checksum.
It installs user-local node/npm/npx/clickhousectl symlinks. Linux arm64 was tested;
Linux x86_64 uses the corresponding official archives and needs independent verification.
Wrangler and the Cloudflare Vite plugin come from package-lock.json.

From the macOS maintainer checkout, run application commands through
`sh scripts/vm.sh run <command>`. This is the maintainer's development workflow;
people deploying the example follow [README](../README.md) from their laptops.

## Generated files and browser checks

After changing dependencies or route generation in the VM, copy back only reviewed
package-lock.json, src/routeTree.gen.ts, and generic worker-configuration.d.ts.
The VM helper's pull-generated command handles the first two; inspect Worker types
before copying them.

An interactive browser on the host can reach the development app at the VM's
address. Keep the automated Playwright runner, dependencies, binaries, and caches
inside Linux. Preserve VM isolation and report manual and automated checks separately.
The optional `scripts/install-local-services.sh` creates web/event user services
inside this VM for development convenience.
