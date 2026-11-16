#!/usr/bin/env python3
"""Replace Jac 0.37.14's generic PWA worker with the studio's offline policy.

Updates both the emitted client and sealed tar artifact, including the payload
hash in `_precompiled/MANIFEST.json`. The runtime verifies that hash before
serving a sealed image. Run after `jac build main.jac`.
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


def finalize(artifact: Path, dist: Path, worker_template: Path):
    assets = sorted(path for path in dist.iterdir() if path.is_file() and path.suffix in {".js", ".css", ".html", ".json", ".png"} and path.name != "sw.js")
    template = worker_template.read_text()
    digest = hashlib.sha256(template.encode())
    for path in assets:
        digest.update(path.name.encode()); digest.update(path.read_bytes())
    source = template.replace("__BUILD_ID__", digest.hexdigest()[:16]).replace("__PRECACHE_ASSETS__", json.dumps(["./" + path.name for path in assets]))
    data = source.encode()
    member_name = ".jac/client/dist/sw.js"
    manifest_name = "_precompiled/MANIFEST.json"
    with tempfile.NamedTemporaryFile(dir=artifact.parent, suffix=".tmp", delete=False) as temporary:
        output = Path(temporary.name)
    try:
        found = 0
        with tarfile.open(artifact) as original, tarfile.open(output, "w:gz") as patched:
            manifest = json.load(original.extractfile(manifest_name))
            if member_name not in manifest.get("payloads", {}):
                raise RuntimeError("The sealed image does not index its production service worker")
            manifest["payloads"][member_name] = hashlib.sha256(data).hexdigest()
            manifest_data = json.dumps(manifest, sort_keys=True, indent=2).encode()
            for member in original:
                if member.name == member_name:
                    member = copy.copy(member); member.size = len(data)
                    patched.addfile(member, io.BytesIO(data)); found += 1
                elif member.name == manifest_name:
                    member = copy.copy(member); member.size = len(manifest_data)
                    patched.addfile(member, io.BytesIO(manifest_data))
                else:
                    patched.addfile(member, original.extractfile(member) if member.isfile() else None)
        if found != 1:
            raise RuntimeError("Expected exactly one production service worker in the Jac artifact")
        with tarfile.open(output) as checked:
            for name, expected in manifest["payloads"].items():
                if hashlib.sha256(checked.extractfile(name).read()).hexdigest() != expected:
                    raise RuntimeError("A sealed client payload does not match its manifest; rebuild before distributing")
        output.replace(artifact)
        (dist / "sw.js").write_bytes(data)
    finally:
        output.unlink(missing_ok=True)
    print("Finalized offline studio shell and verified sealed payload hashes; account APIs and external map tiles excluded")


def main():
    finalize(ARTIFACT, DIST, ROOT / "web/offline-worker.js")


if __name__ == "__main__": main()
