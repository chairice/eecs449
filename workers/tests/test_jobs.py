import json
from concurrent.futures import ThreadPoolExecutor

import pytest

from server import planning_jobs as jobs
from server.planning_core import PlanningError, blank_trip, dumps


@pytest.fixture(autouse=True)
def isolated_store(tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))


def request(turn="turn-1"):
    return dumps({"tripId": "trip-test", "snapshot": blank_trip("trip-test"), "message": "Plan Arizona", "clientTurnId": turn})


def test_retried_submit_returns_one_job_and_rejects_payload_key_reuse():
    first = jobs.enqueue("a", request())
    assert jobs.enqueue("a", request()) == first
    altered = json.loads(request()); altered["message"] = "Different request"
    with pytest.raises(PlanningError, match="different request"):
        jobs.enqueue("a", dumps(altered))


def test_private_owner_boundary_does_not_trust_a_job_id():
    job_id = jobs.enqueue("a", request())
    for operation in [lambda: jobs.read("b", job_id), lambda: jobs.cancel("b", job_id)]:
        with pytest.raises(PlanningError, match="unavailable"):
            operation()


def test_prepared_account_job_is_not_claimed_before_commit_activation():
    job_id = jobs.enqueue("a", request(), deferred=True)
    assert jobs.claim("worker") is None
    jobs.activate("b", job_id)
    assert jobs.claim("worker") is None
    jobs.activate("a", job_id)
    assert jobs.claim("worker")["id"] == job_id


def test_only_one_worker_claims_a_job():
    job_id = jobs.enqueue("a", request())
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(jobs.claim, ["one", "two"]))
    claimed = [result for result in results if result]
    assert len(claimed) == 1 and claimed[0]["id"] == job_id


def test_expired_lease_can_resume_and_old_worker_cannot_publish():
    job_id = jobs.enqueue("a", request())
    first = jobs.claim("one", lease_seconds=-1)
    second = jobs.claim("two")
    assert first["lease_token"] != second["lease_token"]
    assert not jobs.finish(job_id, first["lease_token"], {"obsolete": True})
    assert jobs.finish(job_id, second["lease_token"], {"current": True})
    assert jobs.read("a", job_id)["result"] == {"current": True}


def test_cancelled_work_never_publishes_a_late_result():
    job_id = jobs.enqueue("a", request())
    active = jobs.claim("worker")
    assert jobs.cancel("a", job_id)["status"] == "CANCELLED"
    assert not jobs.still_running(job_id, active["lease_token"])
    assert not jobs.finish(job_id, active["lease_token"], {"late": True})


def test_guest_work_can_only_be_claimed_once_by_one_account():
    token = "a" * 64; owner = jobs.guest_owner(token)
    job_id = jobs.enqueue(owner, request())
    jobs.claim_guest(token, "account:first")
    jobs.claim_guest(token, "account:first")
    assert jobs.read("account:first", job_id)["id"] == job_id
    with pytest.raises(PlanningError):
        jobs.read(owner, job_id)
    with pytest.raises(PlanningError, match="different account"):
        jobs.claim_guest(token, "account:second")


def test_worker_heartbeat_elects_one_runtime():
    assert jobs.heartbeat("one")
    assert not jobs.heartbeat("two")
    assert jobs.status()["workerReady"]


def test_lease_renewal_preserves_actual_current_activity():
    job_id = jobs.enqueue("a", request())
    job = jobs.claim("worker")
    assert jobs.progress(job_id, job["lease_token"], "Searching DTW → SFO")
    assert jobs.renew(job_id, job["lease_token"])
    assert jobs.read("a", job_id)["progress"] == "Searching DTW → SFO"
    jobs.cancel("a", job_id)
    assert not jobs.renew(job_id, job["lease_token"])
