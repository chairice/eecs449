"""Structural edit authorization, revision Undo, and recoverable trip lifecycle.

Language interpretation belongs to the model; these checks bind its decision to
concrete trip fields, current revisions, and the pending question it answered.
"""
import copy
from datetime import datetime, timedelta, timezone

from server.planning_core import PlanningError, dumps, fingerprint, identifier, loads, now, validate_trip, budget_summary


def consequential_view(snapshot):
    return {
        "dates": [snapshot.get("startDate"), snapshot.get("endDate")],
        "places": sorted(({k: p.get(k) for k in ["id", "query", "kind"]} for p in snapshot.get("places", [])), key=lambda p: p["id"]),
        "legs": [{k: item.get(k) for k in ["id", "fromId", "toId", "mode", "departDate", "arriveDate", "departTime", "arriveTime"]} for item in snapshot.get("legs", [])],
        "stays": [{k: item.get(k) for k in ["id", "placeId", "checkIn", "checkOut"]} for item in snapshot.get("stays", [])],
        "days": [{k: item.get(k) for k in ["id", "date", "overnightPlaceId"]} for item in snapshot.get("days", [])],
    }


def consequential(before, after):
    """New plans can be created naturally; protect established route commitments."""
    if not any(before.get(k) for k in ["legs", "stays", "days", "bookings"]):
        return False
    for field in ["startDate", "endDate"]:
        if before.get(field) and before.get(field) != after.get(field): return True
    for field, keys in [("legs", ["fromId", "toId", "mode", "departDate", "arriveDate", "departTime", "arriveTime"]),
                        ("stays", ["placeId", "checkIn", "checkOut"]), ("days", ["date", "overnightPlaceId"])]:
        right = {x["id"]: x for x in after.get(field, [])}
        if set(right) != {x["id"] for x in before.get(field, [])}: return True
        for old in before.get(field, []):
            new = right.get(old["id"])
            if new is None or any(old.get(k) and old.get(k) != new.get(k) for k in keys): return True
    old_places = {p["id"]: p for p in before.get("places", [])}
    new_places = {p["id"]: p for p in after.get("places", [])}
    if set(old_places) - set(new_places): return True
    route_places = {item.get(key) for field in ["legs", "stays", "days", "rentals"] for item in before.get(field, [])
                    for key in ["fromId", "toId", "placeId", "overnightPlaceId", "pickupPlaceId", "dropoffPlaceId"] if item.get(key)}
    return any(any(old_places[place_id].get(k) != new_places[place_id].get(k) for k in ["query", "kind"]) for place_id in route_places)


def needs_decision(state, proposed, result):
    auth = result.get("editAuthorization") or {}
    source = auth.get("source")
    if source not in {None, "USER_REQUEST", "AGENT_SUGGESTION"}:
        raise PlanningError("The planner needs to identify which change you requested.")
    confirmation = auth.get("confirmedDecisionId")
    pending = state.get("pending")
    if confirmation:
        if not pending or pending["id"] != confirmation or pending["baseRevision"] != state["revision"]:
            raise PlanningError("That question belongs to an earlier version of this trip. Please answer the current question.")
        if consequential_view(proposed) != consequential_view(pending["snapshot"]):
            raise PlanningError("The answer changed a different route or date than the question. Ask about that change first.")
        return False
    return consequential(state["snapshot"], proposed) and source != "USER_REQUEST"


MAX_STATE_BYTES = 1_900_000
MAX_UNDO_BYTES = 650_000


def bound_undo(state):
    """Only redundant Undo copies may be pruned; the plan and chat stay intact."""
    history = state.get("undoHistory", [])
    while len(history) > 1 and (len(dumps(history).encode()) > MAX_UNDO_BYTES or len(dumps(state).encode()) > MAX_STATE_BYTES):
        history.pop(0)
    if len(dumps(state).encode()) > MAX_STATE_BYTES:
        raise PlanningError("This update is too large to save together with Undo. Your current trip is kept; try making a smaller change or importing fewer days at once.")
    return state


def remember_undo(state, label="Trip updated"):
    history = state.setdefault("undoHistory", [])
    history.append({"snapshot": copy.deepcopy(state["snapshot"]), "revision": state["revision"], "label": label})
    state["undoHistory"] = history[-20:]
    state["undo"] = {"revision": state["revision"] + 1, "label": label}


def rename_json(state_json: str, title: str, revision: int, command_id: str) -> str:
    """Rename the trip as an ordinary revision, undoable like any other update."""
    state = loads(state_json)
    command = identifier(command_id, "rename ID")
    clean = " ".join(str(title or "").split())
    signature = fingerprint({"renameRevision": revision, "title": clean})
    commands = state.setdefault("commands", {})
    if command in commands:
        if commands[command] != signature: raise PlanningError("This rename request was already used for a different title.")
        return dumps(state)
    if not clean: raise PlanningError("Give the trip a name.")
    if len(clean) > 160: raise PlanningError("Trip names can be up to 160 characters.")
    if state.get("activeJob"): raise PlanningError("Stop the current planning task before renaming the trip.")
    if state["revision"] != revision: raise PlanningError("This trip changed in another window. Reload before renaming it.")
    if clean == state["snapshot"].get("title"): return dumps(state)
    remember_undo(state, "Trip renamed")
    snapshot = copy.deepcopy(state["snapshot"]); snapshot["title"] = clean
    state["snapshot"] = validate_trip(snapshot)
    state["revision"] += 1
    state["updatedAt"] = now()
    commands[command] = signature
    return dumps(bound_undo(state))


def undo_json(state_json: str, revision: int, command_id: str) -> str:
    state = loads(state_json)
    command = identifier(command_id, "undo ID")
    signature = fingerprint({"undoRevision": revision})
    commands = state.setdefault("commands", {})
    if command in commands:
        if commands[command] != signature: raise PlanningError("This Undo request was already used for a different update.")
        return dumps(state)
    if state.get("activeJob"): raise PlanningError("Stop the current planning task before undoing an update.")
    if state["revision"] != revision or not state.get("undoHistory"):
        raise PlanningError("That update is no longer the latest change. Open the current trip to undo it.")
    previous = state["undoHistory"].pop()
    state["snapshot"] = validate_trip(previous["snapshot"])
    state["revision"] += 1
    state["pending"] = None
    state["undo"] = {"revision": state["revision"], "label": "Previous trip update"} if state["undoHistory"] else None
    state["budgetSummary"] = budget_summary(state["snapshot"], state.get("offers", []))
    state["updatedAt"] = now()
    state["conversation"].append({"role": "assistant", "content": "Undone. Your previous plan is back."})
    commands[command] = signature
    return dumps(bound_undo(state))


def meaningful(state):
    """Chats, title changes and an isolated candidate place do not constitute a plan."""
    snapshot = state.get("snapshot", {})
    if state.get("retainedDraft") or state.get("hasImportedMaterial") or state.get("activeJob") or state.get("pending"):
        return True
    if any(snapshot.get(k) for k in ["legs", "stays", "rentals", "bookings"]): return True
    if any(day.get("items") or day.get("overnightPlaceId") for day in snapshot.get("days", [])): return True
    # Preserve genuine multi-stop route outlines even before legs are connected.
    return len(snapshot.get("places", [])) >= 2


def abandoned(state: dict, active_trip_id: str = "", stamp=None) -> bool:
    if state.get("id") == active_trip_id or state.get("deletedAt") or meaningful(state): return False
    try:
        changed = datetime.fromisoformat(state["updatedAt"])
        if changed.tzinfo is None: changed = changed.replace(tzinfo=timezone.utc)
        return (stamp or datetime.now(timezone.utc)) - changed > timedelta(hours=24)
    except (TypeError, ValueError, KeyError):
        return False


def delete_json(state_json: str, reason: str = "USER") -> str:
    state = loads(state_json)
    if state.get("activeJob"): raise PlanningError("Stop the current planning task before removing this trip.")
    if not state.get("deletedAt"):
        state.update(deletedAt=now(), deleteReason=reason)
    return dumps(state)


def restore_json(state_json: str) -> str:
    state = loads(state_json)
    state.pop("deletedAt", None); state.pop("deleteReason", None)
    state["retainedDraft"] = True
    state["updatedAt"] = now()
    return dumps(state)


def recent_deleted(state: dict, stamp=None) -> bool:
    try:
        deleted = datetime.fromisoformat(state["deletedAt"])
        if deleted.tzinfo is None: deleted = deleted.replace(tzinfo=timezone.utc)
        return (stamp or datetime.now(timezone.utc)) - deleted < timedelta(days=30)
    except (KeyError, TypeError, ValueError): return False
