"""Native Jac ownership and atomic accepted-trip revisions; research runs out of band."""
import json;
import from server.planning_api {
    fresh_json as _fresh_json, owner as _owner, prepare_request as _prepare_request, record_job as _record_job,
    stage_json as _stage_json, approve_json as _approve_json, reject_json as _reject_json, guest_start as _guest_start,
    guest_stage as _guest_stage, upload as _upload, status_json as _status_json, failure as _failure,
    learn_json as _learn_json, forget_json as _forget_json, import_hash as _import_hash, merge_preferences as _merge_preferences,
    import_resources_json as _import_resources_json
}
import from server.planning_jobs {
    guest_owner as _guest_owner, enqueue_json as _enqueue_json, activate as _activate, read_json as _read_json,
    cancel as _cancel, claim_guest as _claim_guest, assert_claimable as _assert_claimable
}

import from server.planning_lifecycle {
    undo_json as _undo_json, rename_json as _rename_json, confirmations_json as _confirmations_json, delete_json as _delete_json, restore_json as _restore_json,
    abandoned as _abandoned, recent_deleted as _recent_deleted
}
import from server.planning_weather { weather_json as _weather_json }
import from server.planning_media { media_json as _media_json }

node PlannerTrip {
    has uid: str, state_json: str;
    has imported_hash: str = "";
}

node PlannerRevision {
    has version: int, snapshot_json: str, command_id: str;
}

node PlannerProfile {
    has preferences_json: str = "{}", version: int = 0;
}

def _find_trip(trip_id: str) -> PlannerTrip {
    for trip in [root -->][?:PlannerTrip] {
        if trip.uid == trip_id { return trip; }
    }
    raise ValueError("This trip is unavailable in your account.");
}

def:pub planner_status -> str { return _status_json(); }
def:pub planner_blank -> str { return _fresh_json(); }

def:pub planner_guest_start(token: str, request_json: str) -> str {
    try { return _guest_start(token, request_json); } except Exception as exc { return _failure(exc); }
}
def:pub planner_guest_poll(token: str, job_id: str) -> str {
    try { return _read_json(_guest_owner(token), job_id); } except Exception as exc { return _failure(exc); }
}
def:pub planner_guest_stage(token: str, state_json: str, job_id: str) -> str {
    try { return _guest_stage(token, state_json, job_id); } except Exception as exc { return _failure(exc); }
}
def:pub planner_guest_cancel(token: str, job_id: str) -> str {
    try { return json.dumps(_cancel(_guest_owner(token), job_id)); } except Exception as exc { return _failure(exc); }
}
def:pub planner_guest_upload(token: str, name: str, media: str, content: str) -> str {
    try { return _upload(_guest_owner(token), name, media, content); } except Exception as exc { return _failure(exc); }
}
def:pub planner_guest_approve(state_json: str, proposal_id: str, revision: int, command_id: str) -> str {
    # Guest snapshots remain device-local. This pure helper creates no shared graph data.
    try { return _approve_json(state_json, proposal_id, revision, command_id); } except Exception as exc { return _failure(exc); }
}
def:pub planner_guest_reject(state_json: str, proposal_id: str) -> str {
    try { return _reject_json(state_json, proposal_id); } except Exception as exc { return _failure(exc); }
}

def:protect planner_list(active_trip_id: str = "") -> str {
    values: list[dict] = [];
    for trip in [root -->][?:PlannerTrip] {
        state = json.loads(trip.state_json);
        if _abandoned(state, active_trip_id) {
            trip.state_json = _delete_json(trip.state_json, "ABANDONED_DRAFT");
            state = json.loads(trip.state_json);
        }
        if not state.get("deletedAt") {
            values.append({"id": trip.uid, "title": state["snapshot"]["title"], "updatedAt": state["updatedAt"]});
        }
    }
    return json.dumps(values);
}

def:protect planner_deleted -> str {
    values: list[dict] = [];
    for trip in [root -->][?:PlannerTrip] {
        state = json.loads(trip.state_json);
        if _recent_deleted(state) {
            values.append({"id": trip.uid, "title": state["snapshot"]["title"], "updatedAt": state["updatedAt"], "deletedAt": state["deletedAt"], "deleteReason": state.get("deleteReason", "USER")});
        }
    }
    return json.dumps(values);
}

def:protect planner_delete(trip_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        trip.state_json = _delete_json(trip.state_json);
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_restore(trip_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        trip.state_json = _restore_json(trip.state_json);
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:pub planner_guest_undo(state_json: str, revision: int, command_id: str) -> str {
    try { return _undo_json(state_json, revision, command_id); } except Exception as exc { return _failure(exc); }
}

def:protect planner_undo(trip_id: str, revision: int, command_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        before = json.loads(trip.state_json)["revision"];
        trip.state_json = _undo_json(trip.state_json, revision, command_id);
        state = json.loads(trip.state_json);
        if state["revision"] != before {
            trip ++> PlannerRevision(version=state["revision"], snapshot_json=json.dumps(state["snapshot"]), command_id=command_id);
        }
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:pub planner_guest_rename(state_json: str, title: str, revision: int, command_id: str) -> str {
    try { return _rename_json(state_json, title, revision, command_id); } except Exception as exc { return _failure(exc); }
}

def:protect planner_rename(trip_id: str, title: str, revision: int, command_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        before = json.loads(trip.state_json)["revision"];
        trip.state_json = _rename_json(trip.state_json, title, revision, command_id);
        state = json.loads(trip.state_json);
        if state["revision"] != before {
            trip ++> PlannerRevision(version=state["revision"], snapshot_json=json.dumps(state["snapshot"]), command_id=command_id);
        }
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:pub planner_guest_confirmations(state_json: str, confirmations_json: str) -> str {
    try { return _confirmations_json(state_json, confirmations_json); } except Exception as exc { return _failure(exc); }
}

def:protect planner_confirmations(trip_id: str, confirmations_json: str) -> str {
    try {
        trip = _find_trip(trip_id);
        trip.state_json = _confirmations_json(trip.state_json, confirmations_json);
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:pub planner_guest_weather(state_json: str) -> str {
    try { return _weather_json(state_json); } except Exception as exc { return _failure(exc); }
}

def:protect planner_weather(trip_id: str) -> str {
    try { return _weather_json(_find_trip(trip_id).state_json); } except Exception as exc { return _failure(exc); }
}

def:protect planner_import(state_json: str, token: str) -> str {
    try {
        digest = _import_hash(state_json);
        account = _owner(jid(root));
        normalized = _import_resources_json(state_json, token, account) if token else _fresh_json(state_json);
        state = json.loads(normalized);
        if token { _assert_claimable(token, account); }
        for trip in [root -->][?:PlannerTrip] {
            if trip.uid == state["id"] {
                if trip.imported_hash and trip.imported_hash != digest {
                    raise ValueError("This trip already has a different saved version. Your device draft is kept. Open the saved trip or start a separate trip before importing these changes.");
                }
                return trip.state_json;
            }
        }
        profiles = [root -->][?:PlannerProfile];
        profile_json = profiles[0].preferences_json if len(profiles) > 0 else "{}";
        next_profile = _merge_preferences(profile_json, normalized);
        trip = PlannerTrip(uid=state["id"], state_json=normalized, imported_hash=digest);
        root ++> trip;
        if len(profiles) == 0 { root ++> PlannerProfile(preferences_json=next_profile); }
        else { profiles[0].preferences_json = next_profile; }
        trip ++> PlannerRevision(version=0, snapshot_json=json.dumps(state["snapshot"]), command_id="import");
        if token { on_commit(lambda { _claim_guest(token, account); }); }
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_get(trip_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        if json.loads(trip.state_json).get("deletedAt") { raise ValueError("This trip is in Recently Deleted. Restore it to keep planning."); }
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_start(trip_id: str, request_json: str) -> str {
    try {
        trip = _find_trip(trip_id);
        state = json.loads(trip.state_json);
        if state.get("deletedAt") { raise ValueError("Restore this trip from Recently Deleted before planning."); }
        turn_id = json.loads(request_json)["clientTurnId"];
        if turn_id in state["jobs"] { return json.dumps({"jobId": state["jobs"][turn_id]}); }
        if state.get("activeJob") {
            active = json.loads(_read_json(_owner(jid(root)), str(state["activeJob"])));
            if active["status"] in ["PREPARED", "QUEUED", "RUNNING", "SUCCEEDED"] { raise ValueError("Finish or stop this trip's current planning task before starting another."); }
        }
        preferences: str = "{}";
        for profile in [root -->][?:PlannerProfile] { preferences = profile.preferences_json; }
        request = _prepare_request(trip.state_json, request_json, preferences);
        account = _owner(jid(root));
        job_id = _enqueue_json(account, request, True);
        trip.state_json = _record_job(trip.state_json, request, job_id);
        on_commit(lambda { _activate(account, job_id); });
        return json.dumps({"jobId": job_id});
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_poll(trip_id: str, job_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        state = json.loads(trip.state_json);
        if job_id not in state["jobs"].values() { raise ValueError("This task is unavailable."); }
        account = _owner(jid(root));
        # Reconcile a prepared task if a server restart interrupted the post-commit callback.
        _activate(account, job_id);
        result = _read_json(account, job_id);
        if json.loads(result)["status"] in ["FAILED", "CANCELLED"] {
            state["activeJob"] = ""; trip.state_json = json.dumps(state);
        }
        return result;
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_stage(trip_id: str, job_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        before = json.loads(trip.state_json)["revision"];
        next_state = _stage_json(trip.state_json, _owner(jid(root)), job_id);
        next_value = json.loads(next_state);
        if next_value["revision"] != before {
            trip ++> PlannerRevision(version=next_value["revision"], snapshot_json=json.dumps(next_value["snapshot"]), command_id=job_id);
        }
        profiles = [root -->][?:PlannerProfile];
        profile_json = profiles[0].preferences_json if len(profiles) > 0 else "{}";
        next_profile = _learn_json(profile_json, _owner(jid(root)), job_id);
        trip.state_json = next_state;
        if len(profiles) == 0 { root ++> PlannerProfile(preferences_json=next_profile); }
        else { profiles[0].preferences_json = next_profile; }
        return trip.state_json;
    } except Exception as exc {
        # A structurally rejected result must not leave this trip stuck busy.
        try {
            failed_trip = _find_trip(trip_id);
            failed_state = json.loads(failed_trip.state_json);
            if failed_state.get("activeJob") == job_id {
                failed_state["activeJob"] = "";
                failed_trip.state_json = json.dumps(failed_state);
            }
        } except Exception {}
        return _failure(exc);
    }
}

def:protect planner_approve(trip_id: str, proposal_id: str, revision: int, command_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        before = json.loads(trip.state_json)["revision"];
        trip.state_json = _approve_json(trip.state_json, proposal_id, revision, command_id);
        state = json.loads(trip.state_json);
        if state["revision"] != before {
            trip ++> PlannerRevision(version=state["revision"], snapshot_json=json.dumps(state["snapshot"]), command_id=command_id);
        }
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_reject(trip_id: str, proposal_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        trip.state_json = _reject_json(trip.state_json, proposal_id);
        return trip.state_json;
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_cancel(trip_id: str, job_id: str) -> str {
    try {
        trip = _find_trip(trip_id);
        if job_id not in json.loads(trip.state_json)["jobs"].values() { raise ValueError("This task is unavailable."); }
        result = _cancel(_owner(jid(root)), job_id);
        state = json.loads(trip.state_json); state["activeJob"] = ""; trip.state_json = json.dumps(state);
        return json.dumps(result);
    } except Exception as exc { return _failure(exc); }
}

def:protect planner_upload(name: str, media: str, content: str) -> str {
    try { return _upload(_owner(jid(root)), name, media, content); } except Exception as exc { return _failure(exc); }
}

def:protect planner_preferences -> str {
    for profile in [root -->][?:PlannerProfile] { return profile.preferences_json; }
    return "{\"values\":{},\"forgotten\":[],\"applied\":[]}";
}

def:protect planner_forget_preference(key: str) -> str {
    for profile in [root -->][?:PlannerProfile] {
        profile.preferences_json = _forget_json(profile.preferences_json, key);
        profile.version += 1;
        return profile.preferences_json;
    }
    return "{}";
}

# Auxiliary reads return cached media immediately and schedule bounded public lookups.
def:pub planner_guest_media(state_json: str) -> str {
    try { return _media_json(state_json); } except Exception as exc { return _failure(exc); }
}
def:protect planner_media(trip_id: str) -> str {
    try { return _media_json(_find_trip(trip_id).state_json); } except Exception as exc { return _failure(exc); }
}
