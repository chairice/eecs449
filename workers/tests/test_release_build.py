"""Regression: replacing the PWA worker must remain a runnable sealed image."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("finalize_studio_build", ROOT / "scripts/finalize-studio-build.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def fixture(tmp_path, corrupt=False):
    dist = tmp_path / "dist"; dist.mkdir()
    (dist / "index.html").write_text("<main>Detour</main>")
    template = tmp_path / "worker.js"
    template.write_text("const build='__BUILD_ID__'; const assets=__PRECACHE_ASSETS__;")
    files = {".jac/client/dist/sw.js": b"old generic worker", ".jac/client/dist/index.html": (dist / "index.html").read_bytes()}
    manifest = {"payloads": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}}
    if corrupt:
        files[".jac/client/dist/index.html"] = b"unsealed edit"
    files["_precompiled/MANIFEST.json"] = json.dumps(manifest).encode()
    artifact = tmp_path / "app.jab"
    with tarfile.open(artifact, "w:gz") as archive:
        for name, data in files.items():
            member = tarfile.TarInfo(name); member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
    return artifact, dist, template


def test_custom_worker_and_sealed_payload_manifest_are_consistent(tmp_path):
    artifact, dist, template = fixture(tmp_path)
    release.finalize(artifact, dist, template)
    with tarfile.open(artifact) as archive:
        manifest = json.load(archive.extractfile("_precompiled/MANIFEST.json"))
        worker = archive.extractfile(".jac/client/dist/sw.js").read()
        assert worker == (dist / "sw.js").read_bytes()
        assert b"__BUILD_ID__" not in worker and b"index.html" in worker
        for name, expected in manifest["payloads"].items():
            assert hashlib.sha256(archive.extractfile(name).read()).hexdigest() == expected


def test_other_corrupt_payload_is_rejected_without_replacing_release(tmp_path):
    artifact, dist, template = fixture(tmp_path, corrupt=True)
    original = artifact.read_bytes()
    with pytest.raises(RuntimeError, match="payload"):
        release.finalize(artifact, dist, template)
    assert artifact.read_bytes() == original
