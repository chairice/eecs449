"""Production launch boundaries without model calls or existing trip data."""
import importlib.util
import io
import os
from pathlib import Path
import stat
import subprocess
import sys
import tarfile

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("serve_studio", ROOT / "scripts/serve-studio.py")
production = importlib.util.module_from_spec(spec)
spec.loader.exec_module(production)


def configured(tmp_path, **extra):
    return production.configuration({"ANTHROPIC_API_KEY": "test-only-not-a-provider-key", "DETOUR_STATE_DIR": str(tmp_path / "state"), **extra})


def test_persistent_secret_and_isolated_storage_survive_restart(tmp_path):
    first, worker, web = configured(tmp_path, KUBERNETES_SERVICE_HOST="injected", PORT="8123")
    second, _, _ = configured(tmp_path)
    assert first["JAC_SERVE_AUTH_SECRET"] == second["JAC_SERVE_AUTH_SECRET"]
    assert len(first["JAC_SERVE_AUTH_SECRET"]) >= 32
    state = tmp_path / "state"
    assert stat.S_IMODE((state / "jwt-secret").stat().st_mode) == 0o600
    for key in ["PLANNER_DATA_DIR", "JAC_CACHE_HOME", "JAC_DATA_PATH"]:
        assert Path(first[key]).parent == state
        assert stat.S_IMODE(Path(first[key]).stat().st_mode) == 0o700
    assert "KUBERNETES_SERVICE_HOST" not in first
    assert first["JAC_SERVE_DOCS"] == first["JAC_SERVE_GRAPH"] == "false"
    assert first["JAC_SERVE_WORKERS"] == "1"
    assert worker[1:] == ["-m", "atlas_runtime"]
    assert "--no-dev" in web and web[-1] == str(state / "app/main.jac")
    assert first["DETOUR_BUNDLE"].endswith(".jab")
    assert web[web.index("--port") + 1] == "8123"


@pytest.mark.parametrize("changes", [
    {"ANTHROPIC_API_KEY": ""}, {"DETOUR_STATE_DIR": "relative"},
    {"DETOUR_STATE_DIR": str(ROOT / "web/private-state")},
    {"JAC_SERVE_AUTH_SECRET": "short"}, {"PORT": "0"}, {"PORT": "not-a-port"},
    {"JAC_CACHE_HOME": "relative-cache"}, {"PLANNER_DATA_DIR": str(ROOT / "web/private-uploads")},
])
def test_invalid_production_configuration_fails_before_process_start(tmp_path, changes):
    with pytest.raises(ValueError):
        configured(tmp_path, **changes)


def test_child_failure_stops_the_other_process_without_exposing_secrets(tmp_path):
    if os.name != "posix":
        pytest.skip("Production supervisor uses POSIX process groups")
    worker = tmp_path / "failing-worker"
    worker.write_text('#!/bin/sh\nwhile [ ! -s "$PRODUCTION_TEST_PID" ]; do sleep 0.01; done\nexit 23\n')
    jac = tmp_path / "fake-jac"
    pid_file = tmp_path / "jac.pid"
    jac.write_text('#!/bin/sh\nprintf "%s" "$$" > "$PRODUCTION_TEST_PID"\nexec sleep 30\n')
    worker.chmod(0o700)
    jac.chmod(0o700)
    bundle = fake_bundle(tmp_path, "original")
    env = {**os.environ, "ANTHROPIC_API_KEY": "test-private-placeholder", "DETOUR_STATE_DIR": str(tmp_path / "state"), "DETOUR_BUNDLE": str(bundle),
           "WORKER_PYTHON": str(worker), "JAC_BIN": str(jac), "PRODUCTION_TEST_PID": str(pid_file)}
    result = subprocess.run([sys.executable, str(ROOT / "scripts/serve-studio.py")], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 23
    assert "test-private-placeholder" not in result.stdout + result.stderr
    assert pid_file.is_file()
    pid = int(pid_file.read_text())
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


def fake_bundle(folder, version):
    path = folder / (version + ".jab")
    with tarfile.open(path, "w:gz") as archive:
        for name in ["main.jac", "jac.toml", ".jac/serve_manifest.json", ".jac/client/dist/index.html"]:
            data = version.encode()
            member = tarfile.TarInfo(name)
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
    return path


def test_release_upgrade_keeps_project_path_and_private_state(tmp_path):
    state = production.private_directory(tmp_path / "state")
    first = production.materialize_release(fake_bundle(tmp_path, "original"), state)
    private = production.private_directory(state / "graph") / "retained"
    private.write_text("account state")
    second = production.materialize_release(fake_bundle(tmp_path, "upgrade"), state)
    assert first == second == state / "app"
    assert (second / "main.jac").read_text() == "upgrade"
    assert private.read_text() == "account state"
    assert not (state / ".previous-app").exists()


def test_materialization_will_not_overwrite_unmanaged_directory(tmp_path):
    state = production.private_directory(tmp_path / "state")
    existing = production.private_directory(state / "app") / "notes"
    existing.write_text("keep this")
    with pytest.raises(ValueError, match="not a managed"):
        production.materialize_release(fake_bundle(tmp_path, "upgrade"), state)
    assert existing.read_text() == "keep this"


def test_unsafe_archive_cannot_escape_private_release_directory(tmp_path):
    state = production.private_directory(tmp_path / "state")
    archive_path = tmp_path / "unsafe.jab"
    with tarfile.open(archive_path, "w") as archive:
        entry = tarfile.TarInfo("../../escape")
        entry.size = 4
        archive.addfile(entry, io.BytesIO(b"nope"))
    with pytest.raises(tarfile.FilterError):
        production.materialize_release(archive_path, state)
    assert not (tmp_path / "escape").exists()
