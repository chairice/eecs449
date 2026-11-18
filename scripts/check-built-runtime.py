#!/usr/bin/env python3
"""Require a self-contained planning runtime in the actual sealed Jac release."""
from pathlib import Path
import sys
import tarfile


REQUIRED = {
    "atlas_runtime/__init__.py", "atlas_runtime/__main__.py", "atlas_runtime/planner.py",
    "atlas_runtime/browser.py", "atlas_runtime/geography.py", "atlas_runtime/flight_journey.py",
    "atlas_runtime/place_photos.py", "atlas_runtime/travel_tools.py", "atlas_runtime/errors.py",
    "server/embedded_worker.py", "server/planning_api.py", "server/planning_jobs.py",
    "server/place_photos.py", "server/planning_media.py",
    "fixtures/atlas/places.json.gz", "fixtures/atlas/states.geojson",
}


def check(artifact: Path) -> None:
    with tarfile.open(artifact, "r:*") as archive:
        members = {member.name.removeprefix("./"): member for member in archive.getmembers() if member.isfile()}
        missing = sorted(name for name in REQUIRED if name not in members or members[name].size == 0)
        if missing:
            raise RuntimeError("The sealed app is missing planning runtime files: " + ", ".join(missing))


if __name__ == "__main__":
    artifact = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "web/dist/everyday-agent-web.jab"
    try:
        check(artifact)
    except (OSError, tarfile.TarError, RuntimeError) as error:
        raise SystemExit(str(error)) from None
    print("PASS: sealed app includes its canonical planning runtime, sourced journey/media helpers and geographic catalog.")
