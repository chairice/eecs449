#!/usr/bin/env python3
"""Check the actual JAB archive, without printing credential contents."""
import re
import sys
import tarfile
from pathlib import Path, PurePosixPath

artifact = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "web/dist/everyday-agent-web.jab"
problems = []
with tarfile.open(artifact, "r:*") as archive:
    for member in archive.getmembers():
        basename = PurePosixPath(member.name).name
        if basename == ".env" or (basename.startswith(".env.") and basename != ".env.example") or basename.endswith(("runtime.sqlite3", ".pem")):
            problems.append(member.name)
        if member.isfile() and member.size < 30_000_000:
            data = archive.extractfile(member).read()
            if re.search(rb"sk-ant-[A-Za-z0-9_-]{20,}", data):
                problems.append(member.name)
if problems:
    raise SystemExit("Build contains private configuration or credential material. Do not distribute it. Keep worker configuration in workers/.env, outside the Jac web root, then rebuild.")
print("PASS: built JAB contains no local environment file, private worker database, or Anthropic credential.")
