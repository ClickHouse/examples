#!/usr/bin/env python3
"""Install an exact official Linux release, verifying the published SHA256."""

import hashlib
from pathlib import Path
import platform
import tarfile
import tempfile
import urllib.request

VERSION = "16.4"
ARTIFACTS = {
    "aarch64": (
        "aarch64",
        "bf544f94f305a1ff37d82f5ef1298d584f1f98b51dfd8182d1437a02073d8731",
    ),
    "x86_64": (
        "x86-64",
        "b47ecc82fce1dcebbbc4183d839e52f07f7630c9d7ad0f54db753d1939299354",
    ),
}


def main() -> None:
    if platform.system() != "Linux" or platform.machine() not in ARTIFACTS:
        raise SystemExit("This helper supports Linux ARM64 and x86-64 only.")
    architecture, expected = ARTIFACTS[platform.machine()]
    artifact = f"postgrest-v{VERSION}-linux-static-{architecture}.tar.xz"
    url = f"https://github.com/PostgREST/postgrest/releases/download/v{VERSION}/{artifact}"
    destination = Path(__file__).resolve().parents[1] / ".local/bin"
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        archive = Path(directory) / artifact
        urllib.request.urlretrieve(url, archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != expected:
            raise SystemExit(
                "PostgREST release checksum does not match; refusing installation."
            )
        with tarfile.open(archive) as release:
            entries = release.getmembers()
            binary = next(
                item for item in entries if Path(item.name).name == "postgrest"
            )
            if not binary.isfile() or binary.size > 200_000_000:
                raise SystemExit("Unexpected release archive contents.")
            contents = release.extractfile(binary)
            if contents is None:
                raise SystemExit("The release does not contain its binary.")
            target = destination / "postgrest"
            target.write_bytes(contents.read())
            target.chmod(0o755)
        print(f"Installed PostgREST {VERSION} ({architecture}); SHA256 {digest}")


if __name__ == "__main__":
    main()
