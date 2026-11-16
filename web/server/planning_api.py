"""Validated DTO transformations used by native Jac account transactions."""
import copy
from datetime import date
from server.planning_core import (PlanningError, apply_operations, blank_trip, change_summary, dumps, fingerprint,
    identifier, loads, now, public_url, record, sequence, text, uid, validate_trip, budget_summary)
from server import planning_jobs as jobs
from server.planning_lifecycle import needs_decision, remember_undo, bound_undo


def fresh(raw=""):
    value = record(loads(raw), "trip import") if raw else {}
    if value.get("activeJob"):
        raise PlanningError("Stop the current research task before saving this guest trip to an account.")
    snapshot = validate_trip(value["snapshot"]) if value.get("snapshot") else blank_trip()
    conversation = sequence(value.get("conversation", []), "conversation", 1500)
    for turn in conversation:
        record(turn, "conversation turn")
        if turn.get("role") not in {"user", "assistant"}:
            raise PlanningError("Invalid conversation role.")
        text(turn.get("content"), "conversation message", 160000)
    state = {"id": snapshot["id"], "snapshot": snapshot, "revision": 0, "conversation": conversation,
            "workingContext": record(value.get("workingContext", {}), "working context"), "summary": text(value.get("summary", ""), "conversation summary", 20000),
            "pending": None, "offers": [], "comparisonOffers": [], "researchLinks": [], "nextDecision": value.get("nextDecision", {}), "jobs": {}, "updatedAt": now(),
            "preferences": value.get("preferences", {"values": {}, "forgotten": [], "applied": []}),
            "undo": None, "undoHistory": [], "retainedDraft": bool(value.get("retainedDraft")), "hasImportedMaterial": bool(value.get("hasImportedMaterial"))}
    if value.get("pending"):
        pending = value["pending"]
        proposed = validate_trip(pending["snapshot"])
        if proposed["id"] != snapshot["id"]:
            raise PlanningError("The preview belongs to a different trip.")
        state["pending"] = {"id": identifier(pending["id"]), "snapshot": proposed, "baseRevision": 0,
                            "changes": change_summary(snapshot, proposed), "warnings": pending.get("warnings", []), "createdAt": now()}
    state["budgetSummary"] = budget_summary(snapshot, [])
    return state


def fresh_json(raw: str = "") -> str:
    return dumps(fresh(raw))


def owner(root_id: str) -> str:
    return jobs.account_owner(root_id)


def prepare_request(state_json: str, request_json: str, preferences_json: str = "{}") -> str:
    state, request = loads(state_json), record(loads(request_json), "request")
    if request.get("baseRevision") != state["revision"]:
        raise PlanningError("This trip changed in another window. Reload before sending this message.")
    request["workingContext"] = state["workingContext"]
    request["proposal"] = state.get("pending")
    request["researchContext"] = {"offers": state.get("offers", []), "comparisonOfferIds": [offer["id"] for offer in state.get("comparisonOffers", [])],
                                  "routes": [{k: v for k, v in source.items() if k != "points"} for source in state.get("routes", [])], "daylight": state.get("daylight", [])}
    from server.planning_weather import cached_weather
    request["researchContext"]["weather"] = cached_weather(state["snapshot"], state.get("routes", []))
    request.update(snapshot=state["snapshot"], tripId=state["id"], conversation=state["conversation"], summary=state["summary"],
                   preferences=loads(preferences_json), today=request.get("today") or date.today().isoformat())
    return dumps(jobs.validated_request(dumps(request)))


def record_job(state_json: str, request_json: str, job_id: str) -> str:
    state, request = loads(state_json), loads(request_json)
    turn = request["clientTurnId"]
    if turn not in state["jobs"]:
        state["conversation"].append({"role": "user", "content": request["message"], "turnId": turn})
        state["jobs"][turn] = job_id
    state["updatedAt"] = now()
    state["activeJob"] = job_id
    if request.get("attachments"): state["hasImportedMaterial"] = True
    return dumps(state)


def stage(state_json, owner_id, job_id):
    state = loads(state_json)
    job = jobs.read(owner_id, job_id, include_request=True)
    if job["status"] != "SUCCEEDED":
        raise PlanningError("This planning task is not complete.")
    if job_id not in state["jobs"].values():
        raise PlanningError("This task belongs to a different trip.")
    result, request = job["result"], job["request"]
    if request.get("attachments"): state["hasImportedMaterial"] = True
    if any(t.get("jobId") == job_id for t in state["conversation"]):
        return state
    if state.get("activeJob") != job_id:
        raise PlanningError("This planning result is no longer active. Start a new request.")
    if state["revision"] != request["baseRevision"]:
        raise PlanningError("This suggestion was based on an older revision. Ask Detour to update it.")
    # Re-evaluate the worker operations against authoritative state, including fixed items.
    expected = apply_operations(state["snapshot"], result.get("operations", []))
    proposed = validate_trip(result.get("proposed", expected))
    # Only sourced geographic enrichment may differ from the checked operations.
    check = copy.deepcopy(proposed)
    expected_places = {p["id"]: p for p in expected["places"]}
    for place in check["places"]:
        old = expected_places.get(place["id"], {})
        for key in ["lat", "lon", "timezone", "sourceUrl", "photoUrl"]:
            if key in old:
                place[key] = old[key]
    if check != expected:
        raise PlanningError("The proposed plan did not match its checked operations.")
    quotes = {offer["id"]: offer for offer in state.get("offers", [])}
    quotes.update({offer["id"]: offer for offer in result.get("offers", [])})
    validate_selections(proposed, quotes, state["snapshot"])
    changes = change_summary(state["snapshot"], proposed)
    if changes:
        if needs_decision(state, proposed, result):
            decision = result.get("decision") or {}
            question = text(decision.get("question") or result["assistantMessage"], "trip question", 2000, empty=False)
            state["pending"] = {"id": uid("decision"), "jobId": job_id, "baseRevision": state["revision"],
                                "snapshot": proposed, "question": question, "changes": changes,
                                "warnings": result.get("warnings", []), "createdAt": now(), "budget": budget_summary(proposed, list(quotes.values()))}
            result["assistantMessage"] = question
        else:
            remember_undo(state)
            state["snapshot"] = proposed
            state["revision"] += 1
            state["pending"] = None
            state["budgetSummary"] = budget_summary(proposed, list(quotes.values()))
    if result.get("retainDraft") is True: state["retainedDraft"] = True
    state["workingContext"] = result.get("workingContext", {})
    state["summary"] = result.get("summary", "")
    selected = {item.get("offerId") for field in ["stays", "legs", "rentals"] for item in proposed.get(field, [])}
    recent = list(quotes)[-60:]
    state["offers"] = [offer for key, offer in quotes.items() if key in selected or key in recent]
    if result.get("sourceCount") or result.get("researchQuery") or result.get("offers") or result.get("researchLinks"):
        state["comparisonOffers"] = result.get("offers", [])
        state["researchLinks"] = [{"label": text(link.get("label"), "link label", 200), "url": public_url(link.get("url"), empty=False)} for link in result.get("researchLinks", [])[:12]]
    state["nextDecision"] = result.get("nextDecision", {})
    for field in ["routes", "daylight", "researchSources", "mapLocations"]:
        previous = {item.get("id", item.get("captureId")): item for item in state.get(field, [])}
        previous.update({item.get("id", item.get("captureId")): item for item in result.get(field, [])})
        state[field] = list(previous.values())[-200:]
    state["preferences"] = learn(state.get("preferences", {}), result.get("memoryUpdates", []), job_id)
    state["conversation"].append({"role": "assistant", "content": result["assistantMessage"], "jobId": job_id,
                                   "offerIds": [offer["id"] for offer in result.get("offers", [])],
                                   "decisionId": state["pending"]["id"] if state.get("pending") else ""})
    state["updatedAt"] = now()
    state["activeJob"] = ""
    return bound_undo(state)


def stage_json(state_json: str, owner_id: str, job_id: str) -> str:
    return dumps(stage(state_json, owner_id, job_id))


def approve(state_json, proposal_id, revision, command_id):
    state = loads(state_json)
    command_id = identifier(command_id, "approval ID")
    commands = state.setdefault("commands", {})
    signature = fingerprint({"proposalId": proposal_id, "revision": revision})
    if command_id in commands:
        if commands[command_id] != signature:
            raise PlanningError("This approval ID was already used for a different change.")
        return state
    pending = state.get("pending")
    if not pending or pending["id"] != proposal_id or pending["baseRevision"] != revision or state["revision"] != revision:
        raise PlanningError("This preview is no longer current. Reload the trip before approving.")
    remember_undo(state)
    state["snapshot"] = validate_trip(pending["snapshot"])
    state["budgetSummary"] = budget_summary(state["snapshot"], state.get("offers", []))
    state["revision"] += 1
    state["pending"] = None
    commands[command_id] = signature
    state["updatedAt"] = now()
    return bound_undo(state)


def approve_json(state_json: str, proposal_id: str, revision: int, command_id: str) -> str:
    return dumps(approve(state_json, proposal_id, revision, command_id))


def reject_json(state_json: str, proposal_id: str) -> str:
    state = loads(state_json)
    if state.get("pending") and state["pending"]["id"] == proposal_id:
        state["pending"] = None
        state["conversation"].append({"role": "assistant", "content": "We can leave that idea aside. Your trip is unchanged."})
    return dumps(state)


def guest_start(token: str, request_json: str) -> str:
    return dumps({"jobId": jobs.enqueue(jobs.guest_owner(token), request_json)})


def guest_stage(token: str, state_json: str, job_id: str) -> str:
    state = loads(state_json)
    job = jobs.read(jobs.guest_owner(token), job_id, include_request=True)
    state["jobs"][job["request"]["clientTurnId"]] = job_id
    return dumps(stage(dumps(state), jobs.guest_owner(token), job_id))


def upload(owner_id: str, name: str, media: str, content: str) -> str:
    return dumps(jobs.attachment(owner_id, name, media, content))


def status_json() -> str:
    return dumps(jobs.status())


def learn(profile, updates, job_id):
    profile = copy.deepcopy(profile)
    profile.setdefault("values", {}); profile.setdefault("forgotten", []); profile.setdefault("applied", [])
    if job_id in profile["applied"]:
        return profile
    for update in sequence(updates, "learned preferences", 30):
        key = text(update.get("key"), "preference", 100, empty=False)
        value = text(update.get("value"), "preference value", 3000, empty=False)
        if key not in profile["forgotten"]:
            profile["values"][key] = {"value": value, "learnedAt": now()}
    profile["applied"] = (profile["applied"] + [job_id])[-1000:]
    return profile


def learn_json(profile_json: str, owner_id: str, job_id: str) -> str:
    job = jobs.read(owner_id, job_id)
    if job["status"] != "SUCCEEDED":
        raise PlanningError("Preference learning is not ready.")
    return dumps(learn(loads(profile_json), job["result"].get("memoryUpdates", []), job_id))


def forget_json(profile_json: str, key: str) -> str:
    profile = learn(loads(profile_json), [], "manual")
    profile["values"].pop(key, None)
    if key not in profile["forgotten"]:
        profile["forgotten"].append(text(key, "preference", 100, empty=False))
    return dumps(profile)


def failure(exc: Exception) -> str:
    return dumps({"error": str(exc) if isinstance(exc, (PlanningError, ValueError)) else "This request could not complete. Your trip is unchanged."})


def import_hash(raw: str) -> str:
    value = record(loads(raw), "trip import")
    return fingerprint({key: value.get(key) for key in ["snapshot", "conversation", "workingContext", "summary"]})


def merge_preferences(profile_json: str, state_json: str) -> str:
    profile = learn(loads(profile_json), [], "import")
    source = loads(state_json).get("preferences", {})
    if not isinstance(source, dict):
        return dumps(profile)
    for key, item in list(source.get("values", {}).items())[:100]:
        if key in profile["values"] or key in profile["forgotten"]:
            continue
        if isinstance(item, dict) and isinstance(item.get("value"), str):
            profile = learn(profile, [{"key": key, "value": item["value"]}], "import_" + key)
    return dumps(profile)


def validate_selections(snapshot, quotes, before=None):
    for field in ["stays", "legs", "rentals"]:
        earlier = {item["id"]: item for item in (before or {}).get(field, [])}
        for item in snapshot.get(field, []):
            ref = item.get("offerId")
            if not ref:
                continue
            offer = quotes.get(ref)
            if not offer:
                raise PlanningError("This option needs a researched source before adding it to the trip.")
            old = earlier.get(item["id"], {})
            if not old.get("bookingId") and not old.get("locked") and not old.get("status") == "BOOKED":
                supplied = next((b for b in snapshot["bookings"] if b["id"] == item.get("bookingId") and b.get("source") in {"USER", "DOCUMENT"} and b.get("status") != "CANCELLED"), None)
                if (item.get("bookingId") or item.get("status") == "BOOKED") and not supplied:
                    raise PlanningError("Choosing an option does not book it. Add an actual booking separately after booking with the provider.")
            query = offer["query"]
            pairs = {"stays": [("checkIn", "checkIn"), ("checkOut", "checkOut")], "legs": [],
                     "rentals": [("pickupDate", "pickupDate"), ("dropoffDate", "dropoffDate"), ("pickupTime", "pickupTime"), ("dropoffTime", "dropoffTime")]}[field]
            if any(item.get(left) != query.get(right) for left, right in pairs):
                raise PlanningError("A selected offer no longer matches the proposed dates or times. Research it again.")
            categories = {"stays": {"HOTEL", "STAY"}, "legs": {"FLIGHT"}, "rentals": {"CAR"}}[field]
            if offer.get("category") not in categories:
                raise PlanningError("The selected offer is for a different kind of travel.")
            if field == "legs":
                places = {place["id"]: place for place in snapshot["places"]}
                first, last = _airport_code(places[item["fromId"]]), _airport_code(places[item["toId"]])
                outbound = (query.get("origin"), query.get("destination"), query.get("departDate"))
                returning = (query.get("destination"), query.get("origin"), query.get("returnDate"))
                if not first or not last or (first, last, item.get("departDate")) not in {outbound, returning}:
                    raise PlanningError("The selected flight does not match this leg's airports and date.")
            if not item.get("bookingId") and item.get("status") != "BOOKED":
                for key in ["adults", "driverAge"]:
                    expected = snapshot["party"].get(key)
                    if expected is not None and key in query and expected != query[key]:
                        raise PlanningError("The selected offer does not match the current travelers or driver age.")
                if "childrenAges" in query and sorted(snapshot["party"]["childrenAges"]) != sorted(query["childrenAges"]):
                    raise PlanningError("The selected offer does not match the current child ages.")
                if field == "stays" and snapshot["party"].get("rooms") is not None and query.get("rooms") is not None and snapshot["party"]["rooms"] != query["rooms"]:
                    raise PlanningError("The selected hotel offer does not match the room count.")


def _airport_code(place):
    import re
    from server.atlas_service import _catalog
    if place.get("kind") != "AIRPORT":
        return ""
    fields = (place.get("query", "") + " " + place.get("label", "")).upper()
    candidates = {item["code"] for item in _catalog() if item["kind"] == "AIRPORT" and item["code"] and re.search(r"(?<![A-Z])" + re.escape(item["code"]) + r"(?![A-Z])", fields)}
    return next(iter(candidates)) if len(candidates) == 1 else ""


def import_resources_json(raw: str, token: str, account: str) -> str:
    source = record(loads(raw), "guest import")
    state = fresh(raw)
    quotes = {}
    for job_id in record(source.get("jobs", {}), "guest tasks").values():
        try:
            job = jobs.read(jobs.guest_owner(token), job_id, include_request=True)
        except PlanningError:
            job = jobs.read(account, job_id, include_request=True)
        if job["request"]["tripId"] != state["id"] or job["status"] != "SUCCEEDED":
            continue
        for offer in job["result"].get("offers", []): quotes[offer["id"]] = offer
        for field in ["routes", "daylight", "researchSources", "mapLocations"]:
            state[field] = state.get(field, []) + job["result"].get(field, [])
    state["offers"] = list(quotes.values())
    active_ids = {offer.get("id") for offer in source.get("comparisonOffers", source.get("offers", []))}
    state["comparisonOffers"] = [offer for offer in quotes.values() if offer["id"] in active_ids]
    state["researchLinks"] = [{"label": text(link.get("label"), "search label", 200), "url": public_url(link.get("url"), empty=False)} for link in source.get("researchLinks", [])[:12]]
    validate_selections(state["snapshot"], quotes)
    state["budgetSummary"] = budget_summary(state["snapshot"], state["offers"])
    if state["pending"]:
        state["pending"]["budget"] = budget_summary(state["pending"]["snapshot"], state["offers"])
    return dumps(state)
