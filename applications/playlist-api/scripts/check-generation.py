"""Fail if pinned regeneration changes any Go/config/module source file."""
from pathlib import Path
import hashlib
import subprocess


def snapshot():
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in Path(".").rglob("*") if path.is_file()
            and (path.suffix == ".go" or path.name in ("go.mod", "go.sum"))
            and ".local" not in path.parts}


before = snapshot()
subprocess.run(["go", "generate", "./..."], check=True)
after = snapshot()
assert before == after, "Generation drift: review generated changes before commit"
print(f"Deterministic regeneration matched {len(before)} Go/module source files")
