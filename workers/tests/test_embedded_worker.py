"""Canonical web-only worker startup without providers, credentials or installs."""
from pathlib import Path
import sys
import types

import pytest

from server import embedded_worker as embedded, planning_jobs as jobs
from server.planning_core import blank_trip, dumps


def test_canonical_runtime_and_catalog_follow_the_web_package():
    from atlas_runtime import browser, flight_journey, geography, planner
    web = Path(__file__).resolve().parents[2] / "web"
    for module in [browser, flight_journey, geography, planner]:
        assert Path(module.__file__).resolve().is_relative_to(web / "atlas_runtime")
    assert any(place.get("code") == "SFO" for place in geography.catalog())
    assert geography.states()


def test_project_env_fills_missing_names_without_replacing_host_settings(tmp_path, monkeypatch):
    first, parent = tmp_path / "project.env", tmp_path / "parent.env"
    first.write_text('export DETOUR_TEST_MODE="project"\nDETOUR_TEST_EXISTING=from-file\n')
    parent.write_text("DETOUR_TEST_MODE=parent\nDETOUR_TEST_PARENT=parent\n")
    monkeypatch.setattr(embedded, "env_files", lambda: [first, parent])
    monkeypatch.delenv("DETOUR_TEST_MODE", raising=False)
    monkeypatch.delenv("DETOUR_TEST_PARENT", raising=False)
    monkeypatch.setenv("DETOUR_TEST_EXISTING", "from-host")
    embedded.load_project_env()
    import os
    assert os.environ["DETOUR_TEST_MODE"] == "project"
    assert os.environ["DETOUR_TEST_PARENT"] == "parent"
    assert os.environ["DETOUR_TEST_EXISTING"] == "from-host"


def test_runner_uses_canonical_package_without_electing_a_second_worker(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "  'test-only-placeholder'  ")
    monkeypatch.setattr(embedded, "load_project_env", lambda: None)
    checks = []
    monkeypatch.setattr(embedded, "_ensure_libraries", lambda root: checks.append(root))
    module = types.ModuleType("atlas_runtime.__main__")
    module.run = lambda worker, stopped: None
    monkeypatch.setitem(sys.modules, "atlas_runtime.__main__", module)
    assert embedded._load_runner() is module.run
    assert checks == [Path(embedded.__file__).resolve().parents[1]]


def test_missing_key_diagnostic_contains_names_but_never_values(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("DETOUR_TEST_API_KEY", "test-only-private-value")
    monkeypatch.setattr(embedded, "env_files", lambda: [])
    monkeypatch.setattr(embedded, "load_project_env", lambda: None)
    with pytest.raises(RuntimeError) as error:
        embedded._load_runner()
    assert "ANTHROPIC_API_KEY is not set" in str(error.value)
    assert "DETOUR_TEST_API_KEY" in str(error.value)
    assert "test-only-private-value" not in str(error.value)


def test_enqueued_job_is_committed_before_embedded_worker_wakes(tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))
    seen = []
    def wake():
        with jobs.connection() as db:
            seen.extend(row["id"] for row in db.execute("SELECT id FROM jobs"))
    monkeypatch.setattr(embedded, "ensure_started", wake)
    trip = blank_trip()
    job_id = jobs.enqueue("account:embedded-qa", dumps({
        "tripId": trip["id"], "snapshot": trip, "baseRevision": 0,
        "clientTurnId": "embedded-qa", "message": "Test queue ordering only"}))
    assert seen == [job_id]
    assert "playwright" in embedded.WORKER_LIBRARIES
