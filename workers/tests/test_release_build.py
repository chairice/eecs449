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


def test_nested_carrier_assets_are_cached_at_their_served_urls_without_metadata(tmp_path):
    artifact, dist, template = fixture(tmp_path)
    airline = dist / "assets/airlines/f9.png"
    airline.parent.mkdir(parents=True)
    airline.write_bytes(b"carrier-mark")
    (airline.parent / "sources.json").write_text('{"source":"provenance only"}')
    release.finalize(artifact, dist, template)
    worker = (dist / "sw.js").read_text()
    assert "./static/assets/airlines/f9.png" in worker
    assert '"./assets/airlines/f9.png"' not in worker
    assert "sources.json" not in worker
    first = worker
    airline.write_bytes(b"updated-carrier-mark")
    release.finalize(artifact, dist, template)
    assert (dist / "sw.js").read_text() != first
    with tarfile.open(artifact) as archive:
        manifest = json.load(archive.extractfile("_precompiled/MANIFEST.json"))
        assert hashlib.sha256(archive.extractfile(".jac/client/dist/sw.js").read()).hexdigest() == manifest["payloads"][".jac/client/dist/sw.js"]


def test_source_assets_are_added_to_sealed_dist_and_manifest_before_offline_install(tmp_path):
    artifact, dist, template = fixture(tmp_path)
    public_assets = tmp_path / "source-assets"
    logo = public_assets / "airlines/f9.png"
    logo.parent.mkdir(parents=True)
    logo.write_bytes(b"real-local-logo")
    (logo.parent / "sources.json").write_text('{"not":"a rendered asset"}')
    release.finalize(artifact, dist, template, public_assets)
    name = ".jac/client/dist/assets/airlines/f9.png"
    with tarfile.open(artifact) as archive:
        manifest = json.load(archive.extractfile("_precompiled/MANIFEST.json"))
        assert archive.extractfile(name).read() == logo.read_bytes()
        assert manifest["payloads"][name] == hashlib.sha256(logo.read_bytes()).hexdigest()
        for path, expected in manifest["payloads"].items():
            assert hashlib.sha256(archive.extractfile(path).read()).hexdigest() == expected
    assert (dist / "assets/airlines/f9.png").read_bytes() == logo.read_bytes()
    assert not (dist / "assets/airlines/sources.json").exists()
    # Re-running finalization updates a changed logo without duplicate archive
    # entries, and invalidates the cache using its actual new bytes.
    first_worker = (dist / "sw.js").read_bytes()
    logo.write_bytes(b"updated-local-logo")
    release.finalize(artifact, dist, template, public_assets)
    with tarfile.open(artifact) as archive:
        assert archive.getnames().count(name) == 1
        assert archive.extractfile(name).read() == logo.read_bytes()
    assert (dist / "sw.js").read_bytes() != first_worker
