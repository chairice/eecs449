import copy
from datetime import datetime, timedelta, timezone

import pytest

from server import planning_api as api, planning_jobs as jobs
from server.planning_core import PlanningError, blank_trip, dumps, loads, validate_trip, budget_summary
from server.planning_lifecycle import abandoned, meaningful, needs_decision, undo_json, delete_json, restore_json, recent_deleted


@pytest.fixture(autouse=True)
def private_store(tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))


def planned():
    state = api.fresh()
    trip = state["snapshot"]
    trip.update(startDate="2026-11-22", endDate="2026-11-25", places=[{"id": "sf", "query": "San Francisco"}],
                days=[{"id": "day1", "date": "2026-11-22", "title": "San Francisco", "overnightPlaceId": "sf", "items": []}])
    state["snapshot"] = validate_trip(trip)
    return state


def run_result(state, operations, extra=None):
    request = {"tripId": state["id"], "snapshot": state["snapshot"], "baseRevision": state["revision"],
               "message": "A user instruction", "clientTurnId": jobs.uid("turn")}
    job_id = jobs.enqueue("account:a", dumps(request))
    state = loads(api.record_job(dumps(state), dumps(request), job_id))
    job = jobs.claim("worker")
    result = {"operations": operations, "assistantMessage": "Done.", **(extra or {})}
    jobs.finish(job_id, job["lease_token"], result)
    return api.stage(dumps(state), "account:a", job_id)


def test_routine_rest_break_commits_and_undo_is_revision_bound_idempotent():
    state = planned()
    state["snapshot"]["days"].append({"id": "day2", "date": "2026-11-23", "title": "A fixed work day", "overnightPlaceId": "sf", "items": [{"id": "meeting", "kind": "ACTIVITY", "title": "Work meeting", "startTime": "09:00", "endTime": "10:00", "locked": True}]})
    state["snapshot"]["bookings"].append({"id": "booking", "title": "Confirmed train", "status": "BOOKED", "source": "USER"})
    state["snapshot"] = validate_trip(state["snapshot"])
    before = copy.deepcopy(state["snapshot"])
    state = run_result(state, [{"action": "upsert_item", "dayId": "day1", "value": {"id": "rest", "title": "A quiet break", "kind": "REST"}}])
    assert state["revision"] == 1 and state["pending"] is None
    assert state["snapshot"]["days"][0]["items"][0]["kind"] == "REST"
    assert state["snapshot"]["days"][1] == before["days"][1]
    assert state["snapshot"]["bookings"] == before["bookings"]
    with pytest.raises(PlanningError, match="latest change"): undo_json(dumps(state), 0, "stale")
    state = loads(undo_json(dumps(state), 1, "undo-1"))
    assert state["snapshot"] == before and state["revision"] == 2
    assert loads(undo_json(dumps(state), 1, "undo-1")) == state
    with pytest.raises(PlanningError, match="different update"): undo_json(dumps(state), 2, "undo-1")


def test_agent_date_change_asks_and_confirmation_binds_to_current_decision():
    state = planned()
    ops = [{"action": "set_trip", "value": {"endDate": "2026-11-26"}}]
    staged = run_result(state, ops, {"editAuthorization": {"source": "AGENT_SUGGESTION"}, "decision": {"question": "Stay one more night, through November 26?"}})
    assert staged["snapshot"] == state["snapshot"] and staged["revision"] == 0
    assert staged["pending"]["question"] == staged["conversation"][-1]["content"]
    confirmed = {"editAuthorization": {"source": "USER_REQUEST", "confirmedDecisionId": staged["pending"]["id"]}}
    after = run_result(staged, ops, confirmed)
    assert after["snapshot"]["endDate"] == "2026-11-26" and after["pending"] is None
    # A yes to a current question cannot authorize another date.
    wrong = copy.deepcopy(staged["pending"]["snapshot"]); wrong["endDate"] = "2026-11-27"
    with pytest.raises(PlanningError, match="different route or date"): needs_decision(staged, wrong, confirmed)
    staged["pending"]["baseRevision"] = -1
    with pytest.raises(PlanningError, match="earlier version"): needs_decision(staged, wrong, confirmed)


def test_explicit_date_instruction_applies_without_a_redundant_question():
    state = run_result(planned(), [{"action": "set_trip", "value": {"endDate": "2026-11-26"}}], {"editAuthorization": {"source": "USER_REQUEST"}})
    assert state["pending"] is None and state["revision"] == 1


def test_chat_filled_renamed_empty_shell_is_recoverable_but_active_draft_is_safe():
    state = api.fresh(); state["updatedAt"] = (datetime.now(timezone.utc)-timedelta(days=2)).isoformat()
    state["snapshot"]["title"] = "A wonderful adventure"
    state["conversation"] = [{"role": "user", "content": "Plan something"}]*20
    assert abandoned(state)
    assert not abandoned(state, state["id"])
    deleted = loads(delete_json(dumps(state), "ABANDONED_DRAFT"))
    assert recent_deleted(deleted)
    restored = loads(restore_json(dumps(deleted)))
    assert restored["snapshot"] == state["snapshot"] and restored["conversation"] == state["conversation"]
    assert not abandoned(restored) and restored["retainedDraft"]
    deleted["deletedAt"] = (datetime.now(timezone.utc)-timedelta(days=31)).isoformat()
    assert not recent_deleted(deleted)  # Hidden after retention; underlying state is preserved.


@pytest.mark.parametrize("field,value", [("legs", [{"id": "route"}]), ("stays", [{"id": "base"}]), ("bookings", [{"id": "booking"}]), ("rentals", [{"id": "car"}]), ("days", [{"id": "day", "items": [{"id": "rest"}]}])])
def test_meaningful_plans_survive_cleanup_independent_of_title(field, value):
    state = api.fresh(); state["snapshot"][field] = value
    assert meaningful(state)


def test_selected_starting_and_unit_rates_are_estimates_not_verified_totals():
    trip = blank_trip(); trip["stays"] = [{"offerId": "nightly"}]; trip["legs"] = [{"offerId": "fare", "mode": "FLIGHT"}]
    summary = budget_summary(trip, [{"id": "nightly", "price": {"basis": "PER_NIGHT", "amountMinor": 10000, "currency": "USD", "estimatedTotalMinor": 30000, "from": True}},
                                   {"id": "fare", "price": {"basis": "TOTAL", "amountMinor": 25000, "currency": "USD", "feesIncluded": True, "from": False}}])
    assert summary["selectedQuoteSubtotals"] == {"USD": 25000}
    assert summary["selectedEstimateSubtotals"] == {"USD": 30000}


def test_explicit_model_interpreted_keep_draft_flag_protects_a_near_empty_trip():
    state = run_result(api.fresh(), [], {"retainDraft": True})
    assert state["retainedDraft"] and meaningful(state)
    state["updatedAt"] = (datetime.now(timezone.utc)-timedelta(days=3)).isoformat()
    assert not abandoned(state)


def test_reusing_a_base_id_for_another_city_still_requires_a_conversational_decision():
    state = planned()
    next_state = run_result(state, [{"action": "upsert_place", "value": {"id": "sf", "query": "New York, NY"}}],
                            {"editAuthorization": {"source": "AGENT_SUGGESTION"}, "decision": {"question": "Move the overnight base to New York?"}})
    assert next_state["pending"] and next_state["snapshot"] == state["snapshot"]


def test_repeated_detailed_trip_edits_keep_latest_undo_within_decoder_budget():
    from server.planning_lifecycle import bound_undo, remember_undo, MAX_STATE_BYTES
    state = planned()
    first = datetime(2026, 11, 22)
    state["snapshot"]["endDate"] = (first + timedelta(days=59)).date().isoformat()
    state["snapshot"]["days"] = [{"id": "day-"+str(n), "date": (first+timedelta(days=n)).date().isoformat(), "title": "A detailed day", "overnightPlaceId": "sf",
        "items": [{"id": f"item-{n}-{j}", "title": "A useful activity", "kind": "ACTIVITY", "placeId": "sf", "notes": "Keep the useful booking and address details. "*5} for j in range(12)]} for n in range(60)]
    state["snapshot"] = validate_trip(state["snapshot"])
    state["conversation"] = [{"role": "user", "content": "Preserve this conversation and every planned day."}]
    for index in range(12):
        before = copy.deepcopy(state["snapshot"])
        remember_undo(state)
        state["snapshot"]["title"] = f"Detailed trip update {index}"
        state["revision"] += 1
        bound_undo(state)
        assert state["undoHistory"][-1]["snapshot"] == before
        assert len(dumps(state).encode()) <= MAX_STATE_BYTES
        assert len(state["snapshot"]["days"]) == 60 and len(state["conversation"]) == 1
    assert len(state["undoHistory"]) < 12
    restored = loads(undo_json(dumps(state), state["revision"], "large-trip-undo"))
    assert restored["snapshot"] == before


def test_unbounded_last_snapshot_is_rejected_before_it_can_be_persisted():
    from server.planning_lifecycle import bound_undo, remember_undo
    state = planned(); remember_undo(state)
    state["conversation"] = [{"role": "user", "content": "x"*1_900_000}]
    with pytest.raises(PlanningError, match="too large to save together with Undo"):
        bound_undo(state)
    assert state["undoHistory"]  # Never trim the last Undo or the person's chat.
