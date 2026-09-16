#!/bin/sh
# Run inside an isolated Linux environment. Installs only user-local tools.
set -eu
[ "$(uname -s)" = Linux ] || { echo 'Run this in an isolated Linux environment.' >&2; exit 1; }
for tool in curl tar xz sha256sum awk; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
case "$(uname -m)" in
  aarch64) node_arch=arm64; cli_arch=aarch64 ;;
  x86_64) node_arch=x64; cli_arch=x86_64 ;;
  *) echo 'Supported architectures: aarch64 and x86_64.' >&2; exit 1 ;;
esac
node_version=22.23.2
cli_version=0.4.2
tools_dir="$HOME/.local/share/shortwave-tools"
bin_dir="$HOME/.local/bin"
mkdir -p "$tools_dir" "$bin_dir"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
cd "$stage"
node_archive="node-v${node_version}-linux-${node_arch}.tar.xz"
curl --fail --silent --show-error --location --retry 3 --max-time 180 \
  "https://nodejs.org/dist/v${node_version}/${node_archive}" -o "$node_archive"
curl --fail --silent --show-error --location --retry 3 --max-time 60 \
  "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt" -o SHASUMS256.txt
awk -v file="$node_archive" '$2 == file {print}' SHASUMS256.txt > node.sha256
[ -s node.sha256 ] || { echo 'Node checksum not found.' >&2; exit 1; }
sha256sum --check node.sha256
tar -xJf "$node_archive" -C "$tools_dir"
cli_base="clickhousectl-${cli_arch}-unknown-linux-musl-v${cli_version}"
curl --fail --silent --show-error --location --retry 3 --max-time 180 \
  "https://builds.clickhouse.com/clickhousectl/${cli_base}.tar.gz" -o cli.tar.gz
tar -xzf cli.tar.gz -C "$tools_dir"
# Reject unexpected contents before linking any executable into PATH.
[ -x "$tools_dir/$cli_base/clickhousectl" ] || { echo 'Unexpected CLI archive layout.' >&2; exit 1; }
for tool in node npm npx; do
  ln -sf "$tools_dir/node-v${node_version}-linux-${node_arch}/bin/$tool" "$bin_dir/$tool"
done
ln -sf "$tools_dir/$cli_base/clickhousectl" "$bin_dir/clickhousectl"
PATH="$bin_dir:$PATH"
export PATH
[ "$(node --version)" = "v${node_version}" ] || exit 1
[ "$(clickhousectl --version)" = "clickhousectl ${cli_version}" ] || exit 1
node --version
clickhousectl --version
echo 'Tools installed. Add $HOME/.local/bin to PATH in this terminal.'
