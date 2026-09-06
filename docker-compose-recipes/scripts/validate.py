#!/usr/bin/env python3
"""Cheap Compose, recipe-index and XML checks; Python standard library only."""
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
errors = []
compose_files = sorted(
    path for path in (ROOT / "recipes").rglob("*")
    if path.name in {"compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"}
)
for target in re.findall(r"\]\(([^)]+)\)", (ROOT / "README.md").read_text()):
    if "://" not in target and not target.startswith("#"):
        if not (ROOT / target.split("#", 1)[0]).exists():
            errors.append(f"Broken index link: {target}")
for path in compose_files:
    if not (path.parent / "README.md").is_file():
        errors.append(f"Missing README: {path.parent.relative_to(ROOT)}")
    try:
        result = subprocess.run(
            ["docker", "compose", "-f", str(path), "config", "--quiet"],
            cwd=path.parent,
            env={**os.environ, "PWD": str(path.parent)},
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode:
            errors.append(f"{path.relative_to(ROOT)}: {result.stderr.strip()}")
    except (OSError, subprocess.TimeoutExpired) as error:
        errors.append(f"{path.relative_to(ROOT)}: {error}")
xml_files = sorted((ROOT / "recipes").rglob("*.xml"))
for path in xml_files:
    try:
        ET.parse(path)
    except (ET.ParseError, OSError) as error:
        errors.append(f"{path.relative_to(ROOT)}: {error}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"OK: index links, {len(compose_files)} recipe READMEs/Compose files, {len(xml_files)} XML files")
