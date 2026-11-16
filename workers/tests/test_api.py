import copy
import pytest
from server import planning_api as api, planning_jobs as jobs
from server.planning_core import blank_trip, dumps, PlanningError


@pytest.fixture
def directory(tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))


def completed(directory):
    state = api.fresh()
    request = {"tripId": state["id"], "snapshot": state["snapshot"], "baseRevision": 0,
               "message": "A work trip", "clientTurnId": "turn_1"}
    job_id = jobs.enqueue("account:a", dumps(request))
    state = __import__('json').loads(api.record_job(dumps(state), dumps(request), job_id))
    job = jobs.claim("worker")
    operations = [{"action": "set_trip", "value": {"title": "A work trip", "detail": "LOGISTICS", "intent": "BUSINESS"}}]
    proposed = copy.deepcopy(state["snapshot"]); proposed.update(operations[0]["value"])
    jobs.finish(job_id, job["lease_token"], {"operations": operations, "proposed": proposed,
         "assistantMessage": "Here is a proposal.", "workingContext": {"adults": 1}, "summary": "Work trip", "nextDecision": {}})
    return state, job_id


def test_requested_changes_apply_immediately_with_undo(directory):
    state, job = completed(directory)
    before = copy.deepcopy(state["snapshot"])
    staged = api.stage(dumps(state), "account:a", job)
    assert staged["snapshot"]["title"] == "A work trip"
    assert staged["pending"] is None and staged["revision"] == 1
    assert staged["undoHistory"][-1]["snapshot"] == before
    assert staged["undo"]["revision"] == 1
    assert staged["workingContext"] == {"adults": 1}
    assert api.stage(dumps(staged), "account:a", job) == staged


def test_approval_is_idempotent_and_payload_bound(directory):
    state, job = completed(directory)
    # Retain the old endpoint for previously saved preview states.
    proposed = copy.deepcopy(state["snapshot"]); proposed["title"] = "A work trip"
    state["pending"] = {"id": "legacy-preview", "baseRevision": 0, "snapshot": proposed}
    proposal = state["pending"]["id"]
    accepted = api.approve(dumps(state), proposal, 0, "command_1")
    assert accepted["revision"] == 1 and accepted["pending"] is None
    assert accepted["snapshot"]["title"] == "A work trip"
    assert api.approve(dumps(accepted), proposal, 0, "command_1") == accepted
    with pytest.raises(PlanningError): api.approve(dumps(accepted), "different", 0, "command_1")
    with pytest.raises(PlanningError): api.approve(dumps(accepted), proposal, 0, "command_2")


def test_stale_or_foreign_result_cannot_be_staged(directory):
    state, job = completed(directory)
    with pytest.raises(PlanningError): api.stage(dumps(state), "account:b", job)
    state["revision"] = 1
    with pytest.raises(PlanningError, match="older revision"): api.stage(dumps(state), "account:a", job)


def test_reject_keeps_snapshot_and_revision(directory):
    state, job = completed(directory)
    proposed = copy.deepcopy(state["snapshot"]); proposed["title"] = "Another idea"
    state["pending"] = {"id": "decision_1", "baseRevision": 0, "snapshot": proposed}
    rejected = __import__('json').loads(api.reject_json(dumps(state), state["pending"]["id"]))
    assert rejected["snapshot"] == state["snapshot"] and rejected["revision"] == 0
    assert rejected["pending"] is None


def test_worker_cannot_sneak_non_geographic_changes(directory):
    state, job_id = completed(directory)
    with jobs.connection() as db:
        row = db.execute("SELECT result FROM jobs WHERE id=?", (job_id,)).fetchone()
        result = __import__('json').loads(row[0]); result["proposed"]["notes"] = "unreviewed change"
        db.execute("UPDATE jobs SET result=? WHERE id=?", (dumps(result), job_id))
    with pytest.raises(PlanningError, match="checked operations"): api.stage(dumps(state), "account:a", job_id)


def test_new_offer_selection_requires_a_verified_matching_quote():
    snapshot = blank_trip("trip_quote")
    snapshot["places"] = [{"id": "tucson", "query": "Tucson, AZ"}]
    snapshot["stays"] = [{"id": "stay", "placeId": "tucson", "checkIn": "2026-12-26", "checkOut": "2026-12-28", "offerId": "quote"}]
    from server.planning_core import validate_trip
    snapshot = validate_trip(snapshot)
    with pytest.raises(PlanningError, match="researched source"):
        api.validate_selections(snapshot, {})
    offer = {"id": "quote", "category": "HOTEL", "query": {"checkIn": "2026-12-26", "checkOut": "2026-12-28"}}
    api.validate_selections(snapshot, {"quote": offer})
    offer["query"]["checkOut"] = "2026-12-29"
    with pytest.raises(PlanningError, match="dates"):
        api.validate_selections(snapshot, {"quote": offer})


def test_car_rental_is_separate_from_driving_and_a_booked_car_stays_fixed():
    from server.planning_core import validate_trip, apply_operations
    snapshot = blank_trip("trip_car")
    snapshot["places"] = [{"id": "phx", "query": "PHX"}]
    snapshot = apply_operations(snapshot, [{"action": "upsert_rental", "value": {"id": "car", "pickupPlaceId": "phx", "dropoffPlaceId": "phx",
        "pickupDate": "2026-12-26", "dropoffDate": "2027-01-04", "pickupTime": "17:00", "dropoffTime": "14:00", "status": "BOOKED"}}])
    assert snapshot["rentals"][0]["locked"] and not snapshot["legs"]
    with pytest.raises(PlanningError, match="fixed"):
        apply_operations(snapshot, [{"action": "upsert_rental", "value": {"id": "car", "dropoffDate": "2027-01-05"}}])


def test_selecting_an_option_does_not_book_it_but_actual_user_booking_can_be_kept():
    from server.planning_core import validate_trip
    snapshot = blank_trip("trip_booking_quote")
    snapshot["places"] = [{"id": "sf", "query": "San Francisco, CA"}]
    snapshot["stays"] = [{"id": "stay", "placeId": "sf", "checkIn": "2026-11-22", "checkOut": "2026-11-25", "offerId": "quote", "status": "BOOKED"}]
    snapshot = validate_trip(snapshot)
    offer = {"id": "quote", "category": "HOTEL", "query": {"checkIn": "2026-11-22", "checkOut": "2026-11-25"}}
    with pytest.raises(PlanningError, match="does not book"):
        api.validate_selections(snapshot, {"quote": offer})
    snapshot["bookings"] = [{"id": "user_booking", "title": "Hotel confirmation supplied by traveler", "source": "USER", "status": "BOOKED"}]
    snapshot["stays"][0]["bookingId"] = "user_booking"
    snapshot = validate_trip(snapshot)
    api.validate_selections(snapshot, {"quote": offer})  # Also supports guest→account resource import.
