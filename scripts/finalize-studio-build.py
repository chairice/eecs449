#!/usr/bin/env python3
"""Replace Jac 0.37.14's generic PWA worker with the studio's offline policy.

Updates both the emitted client and the same file in the sealed tar artifact.
Jac's serve manifest contains endpoint metadata, not asset integrity hashes.
No other bundle member is changed. Run after `jac build main.jac`.
"""
import copy
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "web/.jac/client/dist"
ARTIFACT = ROOT / "web/dist/everyday-agent-web.jab"


def main():
    assets = sorted(path for path in DIST.iterdir() if path.is_file() and path.suffix in {".js", ".css", ".html", ".json", ".png"} and path.name != "sw.js")
    template = (ROOT / "web/offline-worker.js").read_text()
    digest = hashlib.sha256(template.encode())
    for path in assets:
        digest.update(path.name.encode()); digest.update(path.read_bytes())
    source = template.replace("__BUILD_ID__", digest.hexdigest()[:16]).replace("__PRECACHE_ASSETS__", json.dumps(["./" + path.name for path in assets]))
    data = source.encode()
    member_name = ".jac/client/dist/sw.js"
    with tempfile.NamedTemporaryFile(dir=ARTIFACT.parent, suffix=".tmp", delete=False) as temporary:
        output = Path(temporary.name)
    try:
        found = 0
        with tarfile.open(ARTIFACT) as original, tarfile.open(output, "w:gz") as patched:
            for member in original:
                if member.name == member_name:
                    member = copy.copy(member); member.size = len(data)
                    patched.addfile(member, io.BytesIO(data)); found += 1
                else:
                    patched.addfile(member, original.extractfile(member) if member.isfile() else None)
        if found != 1:
            raise RuntimeError("Expected exactly one production service worker in the Jac artifact")
        output.replace(ARTIFACT)
        (DIST / "sw.js").write_bytes(data)
    finally:
        output.unlink(missing_ok=True)
    print("Finalized offline studio shell; account APIs and external map tiles excluded")


if __name__ == "__main__": main()
