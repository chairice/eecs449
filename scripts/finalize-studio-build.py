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


def finalize(artifact: Path, dist: Path, worker_template: Path, public_assets: Path | None = None):
    # Jac serves its nested public asset directory through /static/assets/.
    # Include local carrier marks/fonts without caching provenance JSON or any
    # account/research resources. Relative paths also prevent basename clashes.
    extensions = {".js", ".css", ".html", ".png", ".svg", ".jpg", ".jpeg", ".webp", ".woff", ".woff2"}
    assets = {path.relative_to(dist).as_posix(): path.read_bytes() for path in dist.rglob("*")
              if path.is_file() and path.name != "sw.js"
              and (path.suffix in extensions or (path.parent == dist and path.suffix == ".json"))}
    # String-addressed public assets are served by Jac from the source assets/
    # directory, but are not emitted by Vite unless explicitly imported. Stage
    # those same files in the offline client and sealed dist, where both the
    # native server and production-client preview can serve /static/assets/.
    added_assets = {}
    if public_assets and public_assets.is_dir():
        for path in sorted(public_assets.rglob("*")):
            if path.is_file() and path.suffix in extensions:
                relative = "assets/" + path.relative_to(public_assets).as_posix()
                assets[relative] = path.read_bytes()
                added_assets[".jac/client/dist/" + relative] = assets[relative]
    urls = []
    template = worker_template.read_text()
    digest = hashlib.sha256(template.encode())
    for relative, asset in sorted(assets.items()):
        digest.update(relative.encode()); digest.update(asset)
        urls.append("./static/" + relative if relative.startswith("assets/") else "./" + relative)
    source = template.replace("__BUILD_ID__", digest.hexdigest()[:16]).replace("__PRECACHE_ASSETS__", json.dumps(urls))
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
            for name, asset in added_assets.items():
                manifest["payloads"][name] = hashlib.sha256(asset).hexdigest()
            manifest_data = json.dumps(manifest, sort_keys=True, indent=2).encode()
            present = set()
            for member in original:
                present.add(member.name)
                if member.name == member_name:
                    member = copy.copy(member); member.size = len(data)
                    patched.addfile(member, io.BytesIO(data)); found += 1
                elif member.name == manifest_name:
                    member = copy.copy(member); member.size = len(manifest_data)
                    patched.addfile(member, io.BytesIO(manifest_data))
                elif member.name in added_assets:
                    member = copy.copy(member); member.size = len(added_assets[member.name])
                    patched.addfile(member, io.BytesIO(added_assets[member.name]))
                else:
                    patched.addfile(member, original.extractfile(member) if member.isfile() else None)
            for name, asset in added_assets.items():
                if name not in present:
                    member = tarfile.TarInfo(name); member.size = len(asset); member.mode = 0o644
                    patched.addfile(member, io.BytesIO(asset))
        if found != 1:
            raise RuntimeError("Expected exactly one production service worker in the Jac artifact")
        with tarfile.open(output) as checked:
            for name, expected in manifest["payloads"].items():
                if hashlib.sha256(checked.extractfile(name).read()).hexdigest() != expected:
                    raise RuntimeError("A sealed client payload does not match its manifest; rebuild before distributing")
        output.replace(artifact)
        for name, asset in added_assets.items():
            path = dist / name.removeprefix(".jac/client/dist/")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(asset)
        (dist / "sw.js").write_bytes(data)
    finally:
        output.unlink(missing_ok=True)
    print("Finalized offline studio shell and verified sealed payload hashes; account APIs and external map tiles excluded")


def main():
    finalize(ARTIFACT, DIST, ROOT / "web/offline-worker.js", ROOT / "web/assets")


if __name__ == "__main__": main()
