"""Pure Atlas edits and a single atomic, versioned browser-storage boundary.

Drafts can contain unresolved stops. Saved journeys must satisfy the editor's
validation rules. Malformed existing storage is never silently replaced.
"""
import from .composer_model { valid_date, valid_time }

glob ATLAS_KEY: str = "detour.atlas.v1";
glob STATE_CODES: str = "AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY";
glob cached_catalog: any = None;
glob cached_names: any = [];
glob STATE_NAMES: str = "alabama|al;alaska|ak;arizona|az;arkansas|ar;california|ca;colorado|co;connecticut|ct;delaware|de;district of columbia|dc;florida|fl;georgia|ga;hawaii|hi;idaho|id;illinois|il;indiana|in;iowa|ia;kansas|ks;kentucky|ky;louisiana|la;maine|me;maryland|md;massachusetts|ma;michigan|mi;minnesota|mn;mississippi|ms;missouri|mo;montana|mt;nebraska|ne;nevada|nv;new hampshire|nh;new jersey|nj;new mexico|nm;new york|ny;north carolina|nc;north dakota|nd;ohio|oh;oklahoma|ok;oregon|or;pennsylvania|pa;rhode island|ri;south carolina|sc;south dakota|sd;tennessee|tn;texas|tx;utah|ut;vermont|vt;virginia|va;washington|wa;west virginia|wv;wisconsin|wi;wyoming|wy";

def:pub clone_value(value: any) -> any { return JSON.parse(JSON.stringify(value)); }

def:pub new_route -> any {
    return {"status": "UNROUTED", "points": [], "message": "", "source": ""};
}

def new_leg -> any {
    return {"mode": "UNKNOWN", "departDate": "", "arriveDate": "", "departTime": "", "arriveTime": "", "timingNote": "", "route": new_route()};
}

def:pub new_journey -> any {
    return {"schemaVersion": 1, "id": "journey-" + str(Date.now()) + "-" + str(Math.random())[2:10], "title": "", "status": "PLANNED", "note": "", "color": "#36b9ac", "stops": [], "legs": [], "conversation": [], "unresolved": [], "originalText": "", "sourceText": "", "pendingPrompt": "", "deletedAt": ""};
}

def text_ok(value: any, maximum: int) -> bool {
    return isinstance(value, str) and len(value) <= maximum;
}

def object_ok(value: any) -> bool { return bool(value) and Object.prototype.toString.call(value) == "[object Object]"; }

def place_ok(place: any) -> bool {
    return object_ok(place) and text_ok(place["id"], 100) and place["id"] != "" and text_ok(place["name"], 240) and place["name"] != "" and place["state"] in STATE_CODES.split(" ") and place["kind"] in ["CITY", "AIRPORT"] and Number.isFinite(place["lat"]) and Number.isFinite(place["lon"]) and place["lat"] >= -90 and place["lat"] <= 90 and place["lon"] >= -180 and place["lon"] <= 180;
}

"""Shape checks apply even to drafts; semantic checks are added when saving."""
def shape_errors(journey: any) -> list[str] {
    errors: list[str] = [];
    if not object_ok(journey) { return ["Journey must be an object."]; }
    if journey["schemaVersion"] != 1 { errors.append("Unsupported journey version."); }
    for key in ["id", "title", "status", "color", "deletedAt"] {
        if not text_ok(journey[key], 240) { errors.append("Invalid journey " + key + "."); }
    }
    if not text_ok(journey["note"], 8000) { errors.append("Keep the journey note under 8,000 characters."); }
    if "pendingPrompt" in Object.keys(journey) and not text_ok(journey["pendingPrompt"], 4000) { errors.append("Keep the pending request under 4,000 characters."); }
    for key in ["originalText", "sourceText"] {
        if journey[key] is not None and not text_ok(journey[key], 12000) { errors.append("Keep the source description under 12,000 characters."); }
    }
    if journey["status"] not in ["PLANNED", "PAST"] { errors.append("Choose planned or past for the journey status."); }
    if not Array.isArray(journey["stops"]) or journey["stops"].length > 50 { return errors + ["A journey supports at most 50 stops."]; }
    if not Array.isArray(journey["legs"]) or journey["legs"].length != Math.max(0, journey["stops"].length - 1) { return errors + ["Every neighboring pair of stops needs one leg."]; }
    for stop in journey["stops"] {
        if not object_ok(stop) or not text_ok(stop["query"], 240) or (stop["place"] is not None and not place_ok(stop["place"])) { errors.append("Invalid stop record."); }
    }
    for leg in journey["legs"] {
        if not object_ok(leg) { errors.append("Invalid leg record."); continue; }
        if leg["mode"] not in ["UNKNOWN", "FLIGHT", "DRIVE"] { errors.append("Invalid travel mode."); }
        for key in ["departDate", "arriveDate", "departTime", "arriveTime"] {
            if not text_ok(leg[key], 30) { errors.append("Invalid leg timing."); }
        }
        if not text_ok(leg["timingNote"], 2000) { errors.append("Keep each timing note under 2,000 characters."); }
        route = leg["route"];
        if not object_ok(route) or not Array.isArray(route["points"]) or route["points"].length > 16000 { errors.append("Invalid route geometry."); }
        else {
            if not text_ok(route["status"], 40) or not text_ok(route["source"], 240) or not text_ok(route["message"], 2000) { errors.append("Invalid route metadata."); }
            for point in route["points"] {
                if not Array.isArray(point) or point.length != 2 or not Number.isFinite(point[0]) or not Number.isFinite(point[1]) or point[0] < -90 or point[0] > 90 or point[1] < -180 or point[1] > 180 { errors.append("Invalid route coordinate."); break; }
            }
        }
    }
    if not Array.isArray(journey["conversation"]) or journey["conversation"].length > 80 { errors.append("A draft supports at most 80 conversation messages."); }
    else {
        for item in journey["conversation"] {
            if not object_ok(item) or item["role"] not in ["user", "assistant"] or not text_ok(item["content"], 12000) { errors.append("Invalid conversation message."); }
        }
    }
    if not Array.isArray(journey["unresolved"]) or journey["unresolved"].length > 100 { errors.append("Invalid unresolved details."); }
    else { for item in journey["unresolved"] { if not text_ok(item, 5000) { errors.append("Invalid unresolved detail."); } } }
    return errors;
}

def:pub validate_journey(journey: any) -> list[str] {
    errors = shape_errors(journey);
    if len(errors) > 0 { return errors; }
    if journey["unresolved"].length > 0 { errors.append("Review the unresolved details before saving."); }
    if not journey["id"] or not journey["title"].trim() { errors.append("Give this journey a title."); }
    if journey["stops"].length < 2 { errors.append("Add at least two stops."); }
    for stop in journey["stops"] { if not place_ok(stop["place"]) { errors.append("Choose a US city or airport for every stop."); } }
    last_date = "";
    for leg in journey["legs"] {
        if leg["mode"] not in ["FLIGHT", "DRIVE"] { errors.append("Choose flight or drive for every leg."); }
        for key in ["departDate", "arriveDate"] {
            if leg[key] and not valid_date(leg[key]) { errors.append("Use a valid calendar date."); }
        }
        for key in ["departTime", "arriveTime"] {
            if leg[key] and not valid_time(leg[key]) { errors.append("Use a valid 24-hour time."); }
        }
        depart = leg["departDate"]; arrive = leg["arriveDate"];
        if depart and arrive and valid_date(depart) and valid_date(arrive) and arrive < depart { errors.append("Arrival date cannot precede departure date."); }
        # Times are local wall-clock values; comparing them across time zones
        # would reject legitimate flights. Only calendar dates are ordered.
        if last_date and depart and valid_date(depart) and depart < last_date { errors.append("A leg cannot depart before the preceding leg arrives."); }
        if arrive and valid_date(arrive) { last_date = arrive; }
        elif depart and valid_date(depart) { last_date = depart; }
    }
    return errors;
}

def storage -> any { browser: any = window; return browser.localStorage; }

def stored_error(value: any) -> str {
    if not object_ok(value) or value["schemaVersion"] != 1 or not Array.isArray(value["journeys"]) or value["journeys"].length > 250 { return "Saved Atlas data is malformed or uses an unsupported version. It has been preserved."; }
    ids: list[str] = [];
    for journey in value["journeys"] {
        if len(validate_journey(journey)) > 0 or journey["id"] in ids { return "A saved journey is malformed. Existing Atlas data has been preserved."; }
        ids.append(journey["id"]);
    }
    if value["draft"] is not None and len(shape_errors(value["draft"])) > 0 { return "The saved draft is malformed. Existing Atlas data has been preserved."; }
    return "";
}

def:pub load_atlas -> any {
    try {
        raw = storage().getItem(ATLAS_KEY);
        if raw is None { return {"journeys": [], "draft": None, "error": ""}; }
        parsed = JSON.parse(raw);
        error = stored_error(parsed);
        if error { return {"journeys": [], "draft": None, "error": error}; }
        return {"journeys": parsed["journeys"], "draft": parsed["draft"], "error": ""};
    } except Exception { return {"journeys": [], "draft": None, "error": "Atlas could not read this browser's saved data. Existing data has been preserved."}; }
}

def:pub write_atlas(journeys: any, draft: any) -> str {
    try {
        existing = load_atlas();
        if existing["error"] { return existing["error"]; }
        value = {"schemaVersion": 1, "journeys": journeys, "draft": draft};
        error = stored_error(value);
        if error { return error; }
        storage().setItem(ATLAS_KEY, JSON.stringify(value));
        return "";
    } except Exception { return "Atlas could not save. Browser storage may be full or unavailable; your changes remain in this session."; }
}

def normalize(value: any) -> str {
    if not isinstance(value, str) { return ""; }
    return " ".join([word for word in value.strip().lower().replace(",", " ").replace(".", "").split(" ") if word != ""]);
}

def names_for(place: any) -> list[str] {
    names: list[str] = [normalize(place["name"])];
    if place["code"] { names.append(normalize(place["code"])); }
    if Array.isArray(place["aliases"]) { for alias in place["aliases"] { names.append(normalize(alias)); } }
    return names;
}

def normalize_query(query: str) -> str {
    normalized = normalize(query);
    for pair in STATE_NAMES.split(";") {
        parts = pair.split("|"); suffix = " " + parts[0];
        if normalized.endswith(suffix) { return normalized[:-len(suffix)] + " " + parts[1]; }
    }
    return normalized;
}

def prepare_search(catalog: any) {
    if cached_catalog is catalog { return; }
    cached_catalog = catalog; cached_names = [];
    for place in catalog {
        names = names_for(place);
        state = normalize(place["state"]); county = normalize(place["county"]);
        exact: list[str] = []; labels: list[str] = [];
        for name in names {
            exact.append(name); exact.append(name + " " + state);
            exact.append(name + " " + county + " " + state);
            labels.append(name + " " + county + " " + state);
        }
        cached_names.push({"place": place, "exact": exact, "labels": labels});
    }
}

def:pub search_places(catalog: any, query: str) -> list[any] {
    needle = normalize_query(query);
    if not needle or not Array.isArray(catalog) { return []; }
    prepare_search(catalog);
    parts = needle.split(" ");
    codes: list[any] = []; exact: list[any] = []; prefix: list[any] = []; contains: list[any] = [];
    for indexed in cached_names {
        place = indexed["place"];
        if place["kind"] == "AIRPORT" and (needle == normalize(place["code"]) or needle == normalize(place["code"]) + " " + normalize(place["state"])) { if len(codes) < 8 { codes.append(place); } continue; }
        if needle in indexed["exact"] { if len(exact) < 8 { exact.append(place); } continue; }
        starts = False; includes = False;
        for name in indexed["exact"] { if name.startsWith(needle) { starts = True; } }
        for label in indexed["labels"] {
            matches = True;
            for part in parts { if part not in label { matches = False; } }
            if matches { includes = True; }
        }
        if starts and len(prefix) < 8 { prefix.append(place); }
        elif includes and len(contains) < 8 { contains.append(place); }
    }
    return (codes + exact + prefix + contains)[:8];
}

"""Keep a leg only between the same ordered stop occurrences after an edit.

Object identity within the cloned journey distinguishes repeated visits to the
same city, which can have different dates and modes. Newly adjacent stops get a
fresh leg instead of inheriting another segment's timing or route.
"""
def reconnect_legs(previous_stops: any, previous_legs: any, stops: any) -> any {
    legs: any = [];
    for index in range(Math.max(0, stops.length - 1)) {
        retained = new_leg();
        for old_index in range(previous_legs.length) {
            if stops[index] is previous_stops[old_index] and stops[index + 1] is previous_stops[old_index + 1] {
                retained = previous_legs[old_index];
                break;
            }
        }
        legs.push(retained);
    }
    return legs;
}

def:pub add_stop(journey: any) -> any {
    updated = clone_value(journey);
    if updated["stops"].length >= 50 { return updated; }
    if updated["stops"].length > 0 { updated["legs"].push(new_leg()); }
    updated["stops"].push({"query": "", "place": None});
    return updated;
}

def:pub update_stop(journey: any, index: int, place: any, query: str) -> any {
    updated = clone_value(journey);
    if index < 0 or index >= updated["stops"].length { return updated; }
    updated["stops"][index] = {"query": query, "place": clone_value(place)};
    if index > 0 { updated["legs"][index - 1]["route"] = new_route(); }
    if index < updated["legs"].length { updated["legs"][index]["route"] = new_route(); }
    return updated;
}

def:pub remove_stop(journey: any, index: int) -> any {
    updated = clone_value(journey);
    if index < 0 or index >= updated["stops"].length { return updated; }
    previous_stops = updated["stops"].slice();
    updated["stops"].splice(index, 1);
    updated["legs"] = reconnect_legs(previous_stops, updated["legs"], updated["stops"]);
    return updated;
}

def:pub move_stop(journey: any, index: int, offset: int) -> any {
    updated = clone_value(journey);
    target = index + offset;
    if index < 0 or index >= updated["stops"].length or target < 0 or target >= updated["stops"].length { return updated; }
    previous_stops = updated["stops"].slice();
    item = updated["stops"].splice(index, 1)[0];
    updated["stops"].splice(target, 0, item);
    updated["legs"] = reconnect_legs(previous_stops, updated["legs"], updated["stops"]);
    return updated;
}

def:pub set_leg_field(journey: any, index: int, field: str, value: any) -> any {
    updated = clone_value(journey);
    if index < 0 or index >= updated["legs"].length or field not in ["mode", "departDate", "arriveDate", "departTime", "arriveTime", "timingNote", "route"] { return updated; }
    if field == "mode" and updated["legs"][index]["mode"] != value { updated["legs"][index]["route"] = new_route(); }
    updated["legs"][index][field] = clone_value(value);
    return updated;
}

"""Resolve only an unambiguous complete name/code, never a search suggestion."""
def resolve_exact(catalog: any, query: str) -> any {
    prepare_search(catalog);
    needle = normalize_query(query);
    code_matches: list[any] = [];
    for place in catalog {
        if place["kind"] == "AIRPORT" and (needle == normalize(place["code"]) or needle == normalize(place["code"]) + " " + normalize(place["state"])) { code_matches.append(place); }
    }
    if len(code_matches) == 1 { return code_matches[0]; }
    if len(code_matches) > 1 { return None; }
    found: any = None;
    for indexed in cached_names {
        if needle in indexed["exact"] {
            if found is not None { return None; }
            found = indexed["place"];
        }
    }
    return found;
}

def:pub apply_proposal(journey: any, proposal: any, catalog: any) -> any {
    updated = clone_value(journey);
    if not object_ok(proposal) { return updated; }
    # The interpretation contract is a complete replacement. Reject partial
    # arrays atomically; neither metadata nor existing stops should be lost.
    if not Array.isArray(proposal["stops"]) or not Array.isArray(proposal["legs"]) or proposal["stops"].length > 50 or proposal["legs"].length != Math.max(0, proposal["stops"].length - 1) { return updated; }
    if proposal["stops"].length == 0 and updated["stops"].length > 0 { return updated; }
    for field in ["title", "status", "note", "color", "originalText", "sourceText"] {
        if field in Object.keys(proposal) and not isinstance(proposal[field], str) { return updated; }
    }
    if "unresolved" in Object.keys(proposal) and not Array.isArray(proposal["unresolved"]) { return updated; }
    for supplied in proposal["legs"] {
        if not object_ok(supplied) or supplied["mode"] not in ["UNKNOWN", "FLIGHT", "DRIVE"] { return updated; }
        for field in ["departDate", "arriveDate", "departTime", "arriveTime", "timingNote"] {
            if field in Object.keys(supplied) and not isinstance(supplied[field], str) { return updated; }
        }
    }
    for field in ["title", "status", "color", "originalText", "sourceText"] {
        if isinstance(proposal[field], str) { updated[field] = proposal[field]; }
    }
    # Personal notes are not part of the model's context and cannot be revised
    # by it. The original request remains available in conversation/sourceText.
    if not updated["note"].trim() and isinstance(proposal["note"], str) { updated["note"] = proposal["note"]; }
    if Array.isArray(proposal["unresolved"]) { updated["unresolved"] = clone_value(proposal["unresolved"]); }
    updated["stops"] = []; updated["legs"] = [];
    for stop in proposal["stops"] {
        query = "";
        if isinstance(stop, str) { query = stop; }
        elif object_ok(stop) {
            query = stop["query"] or stop["name"] or stop["code"] or "";
            if stop["state"] {
                if not text_ok(stop["state"], 60) or not text_ok(query, 240) { return clone_value(journey); }
                if not normalize(query).endswith(" " + normalize(stop["state"])) { query += ", " + stop["state"]; }
            }
        }
        if not text_ok(query, 240) or not query.strip() { return clone_value(journey); }
        resolved = resolve_exact(catalog, query);
        updated["stops"].push({"query": query, "place": clone_value(resolved)});
        if updated["stops"].length > 1 { updated["legs"].push(new_leg()); }
    }
    if Array.isArray(proposal["legs"]) {
        for index in range(Math.min(updated["legs"].length, proposal["legs"].length)) {
            supplied = proposal["legs"][index];
            if object_ok(supplied) {
                for field in ["mode", "departDate", "arriveDate", "departTime", "arriveTime", "timingNote"] {
                    if isinstance(supplied[field], str) { updated["legs"][index][field] = supplied[field]; }
                }
            }
        }
    }
    if len(shape_errors(updated)) > 0 { return clone_value(journey); }
    return updated;
}
