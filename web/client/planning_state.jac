"""Device cache and transport DTOs. Trip updates are reversible; device caches support offline reading."""

def:pub parse_response(raw: str) -> any {
    value: any = JSON.parse(raw);
    if value and value["error"] { raise ValueError(str(value["error"])); }
    return value;
}

"""A failed task is a valid status response, distinct from an RPC failure."""
def:pub parse_job_response(raw: str) -> any {
    value: any = JSON.parse(raw);
    if value and value["id"] and value["status"] in ["PREPARED", "QUEUED", "RUNNING", "SUCCEEDED", "FAILED", "CANCELLED"] {
        return value;
    }
    _ = parse_response(raw);
    raise ValueError("Detour couldn't read the planning status. Please reconnect and try again.");
}

def:pub planner_id(prefix: str) -> str {
    browser: any = window;
    return prefix + "_" + str(browser.crypto.randomUUID()).replace("-", "");
}

def:pub guest_token -> str {
    browser: any = window;
    token = browser.localStorage.getItem("atlas.guest.capability.v1");
    if not token {
        token = planner_id("guest") + planner_id("cap");
        browser.localStorage.setItem("atlas.guest.capability.v1", token);
    }
    return str(token);
}

def:pub load_session(key: str) -> any {
    browser: any = window;
    raw: any = browser.localStorage.getItem("atlas.studio.v1." + key);
    if not raw { return None; }
    value: any = JSON.parse(str(raw));
    if value["snapshot"] and value["snapshot"]["schemaVersion"] == 1 { return value; }
    raise ValueError("This saved trip uses an unsupported format. Your stored data has been kept.");
}

def:pub save_session(key: str, value: any) -> str {
    try {
        browser: any = window;
        browser.localStorage.setItem("atlas.studio.v1." + key, JSON.stringify(value));
        return "";
    } except Exception { return "This device couldn't save the latest changes. Keep this tab open and free some browser storage."; }
}

def:pub planner_today -> str {
    value: any = new(Date);
    return str(value.getFullYear()) + "-" + str(value.getMonth() + 1).zfill(2) + "-" + str(value.getDate()).zfill(2);
}

def:pub planner_zone -> str {
    browser: any = window;
    return str(browser.Intl.DateTimeFormat().resolvedOptions().timeZone);
}

def:pub date_label(raw: str) -> str {
    if not raw { return "Dates open"; }
    value: any = new(Date, raw + "T12:00:00");
    return str(value.toLocaleDateString("en-US", {"month": "short", "day": "numeric"}));
}

def:pub time_label(raw: str) -> str {
    if not raw { return ""; }
    hour = int(raw[:2]);
    return str(hour % 12 or 12) + ":" + raw[3:] + (" am" if hour < 12 else " pm");
}

def:pub place_label(snapshot: any, place_id: str) -> str {
    for place in snapshot["places"] {
        if place["id"] == place_id { return str(place["label"]); }
    }
    return "Location to decide";
}

def:pub nights(stay: any) -> str {
    if not stay["checkIn"] or not stay["checkOut"] { return "Nights open"; }
    first: any = new(Date, stay["checkIn"] + "T12:00:00Z");
    last: any = new(Date, stay["checkOut"] + "T12:00:00Z");
    count = Math.round((last.getTime() - first.getTime()) / 86400000);
    return str(count) + (" night" if count == 1 else " nights");
}

def:pub money_label(minor: int, currency: str) -> str {
    browser: any = window;
    return str(browser.Intl.NumberFormat("en-US", {"style": "currency", "currency": currency}).format(minor / 100));
}

def:pub offer_context(offer: any) -> str {
    query = offer["query"];
    if offer["category"] in ["HOTEL", "STAY"] {
        return date_label(str(query["checkIn"])) + " — " + date_label(str(query["checkOut"])) + " · " + str(query["adults"]) + (" adult" if query["adults"] == 1 else " adults") + (" · " + str(len(query["childrenAges"])) + " children" if len(query["childrenAges"]) > 0 else " · no children") + (" · " + str(query["rooms"]) + (" room" if query["rooms"] == 1 else " rooms") if query["rooms"] else "");
    }
    if offer["category"] == "FLIGHT" {
        return str(query["origin"]) + " → " + str(query["destination"]) + " · " + date_label(str(query["departDate"])) + (" — " + date_label(str(query["returnDate"])) if query["returnDate"] else " · one way") + " · " + str(query["adults"]) + (" adult" if query["adults"] == 1 else " adults");
    }
    return str(query["pickupLocation"]) + " · " + date_label(str(query["pickupDate"])) + " " + time_label(str(query["pickupTime"])) + " — " + date_label(str(query["dropoffDate"])) + " " + time_label(str(query["dropoffTime"])) + " · driver " + str(query["driverAge"]);
}

async def:pub file_content(file: any) -> str {
    buffer: any = await file.arrayBuffer();
    fileBytes: any = new(Uint8Array, buffer);
    binary: str = "";
    for index in range(fileBytes.length) { binary += String.fromCharCode(fileBytes[index]); }
    browser: any = window;
    return str(browser.btoa(binary));
}

def:pub observed_label(stamp: any) -> str {
    value: any = new(Date, stamp * 1000 if Number.isFinite(stamp) else stamp);
    return str(value.toLocaleString()) if Number.isFinite(value.getTime()) else "";
}

def:pub load_preferences(key: str) -> any {
    browser: any = window;
    raw: any = browser.localStorage.getItem("atlas.preferences.v1." + key);
    return JSON.parse(str(raw)) if raw else {"values": {}, "forgotten": [], "applied": []};
}

def:pub save_preferences(key: str, value: any) {
    browser: any = window;
    browser.localStorage.setItem("atlas.preferences.v1." + key, JSON.stringify(value));
}

def:pub finish_guest_import {
    browser: any = window;
    browser.localStorage.removeItem("atlas.studio.v1.guest");
    browser.localStorage.removeItem("atlas.guest.capability.v1");
    browser.localStorage.removeItem("atlas.preferences.v1.guest");
}

def:pub clear_account_cache(key: str) {
    browser: any = window;
    browser.localStorage.removeItem("atlas.studio.v1." + key);
    browser.localStorage.removeItem("atlas.preferences.v1." + key);
}

def:pub forget_local(profile: any, key: str) -> any {
    value = JSON.parse(JSON.stringify(profile));
    values: any = {};
    for name in Object.keys(value["values"] or {}) { if name != key { values[name] = value["values"][name]; } }
    value["values"] = values;
    value["forgotten"] = (value["forgotten"] or []) + [key];
    return value;
}

def:pub trap_dialog(close: Callable[[], None]) -> Callable[[], None] {
    doc: any = document;
    dialog: any = doc.querySelector(".studio-modal");
    previous: any = doc.activeElement;
    if not dialog { return lambda {}; }
    first: any = dialog.querySelector("input") or dialog.querySelector("button");
    if first { first.focus(); }
    def keydown(event: any) {
        if event.key == "Escape" { event.preventDefault(); close(); return; }
        if event.key != "Tab" { return; }
        elements: any = dialog.querySelectorAll("button:not(:disabled),input:not(:disabled),a[href],[tabindex='0']");
        if len(elements) == 0 { return; }
        first: any = elements[0]; last: any = elements[len(elements) - 1];
        if event.shiftKey and doc.activeElement == first { event.preventDefault(); last.focus(); }
        elif not event.shiftKey and doc.activeElement == last { event.preventDefault(); first.focus(); }
    }
    doc.addEventListener("keydown", keydown);
    return lambda { doc.removeEventListener("keydown", keydown); if previous and previous.isConnected { previous.focus(); } };
}

def:pub mapped_snapshot(snapshot: any, locations: any) -> any {
    value = JSON.parse(JSON.stringify(snapshot));
    for place in value["places"] {
        for location in locations or [] {
            if place["id"] == location["id"] and place["query"] == location["query"] and Number.isFinite(location["lat"]) and Number.isFinite(location["lon"]) and Math.abs(location["lat"]) <= 90 and Math.abs(location["lon"]) <= 180 {
                for field in ["lat", "lon", "timezone", "sourceUrl", "photoUrl", "photoSourceUrl", "photoAttribution", "photoLicense", "photoTitle", "address"] { if location[field] is not None { place[field] = location[field]; } }
            }
        }
    }
    return value;
}

"""Presentation joins never change the accepted trip snapshot."""
def:pub selected_offer(resources: any, item: any) -> any {
    for offer in resources["offers"] or [] { if item["offerId"] and offer["id"] == item["offerId"] { return offer; } }
    return None;
}

def:pub trip_place(snapshot: any, placeId: str) -> any {
    for place in snapshot["places"] or [] { if place["id"] == placeId { return place; } }
    return {};
}

def:pub trip_photo(snapshot: any, item: any, offer: any = None) -> any {
    if item["photoUrl"] { return item; }
    if offer and offer["photoUrl"] { return offer; }
    place = trip_place(snapshot, str(item["placeId"] or item["overnightPlaceId"] or ""));
    if item["checkIn"] and place["kind"] != "PROPERTY" { return {}; }
    if item["kind"] == "MEAL" and place["kind"] == "CITY" { return {}; }
    return place;
}

def:pub trip_booking(item: any, snapshot: any) -> any {
    for booking in snapshot["bookings"] or [] { if item["bookingId"] and booking["id"] == item["bookingId"] { return booking; } }
    return None;
}

def:pub trip_item_status(item: any, snapshot: any = None) -> str {
    booking = trip_booking(item, snapshot) if snapshot else None;
    if booking {
        if booking["status"] == "CANCELLED" { return "Cancelled"; }
        if booking["status"] == "USER_REPORTED" { return "User reported"; }
        if booking["status"] == "BOOKED" { return "Booked"; }
    }
    if item["status"] == "CANCELLED" { return "Cancelled"; }
    if item["status"] == "USER_REPORTED" { return "User reported"; }
    if item["bookingId"] { return "Booking details"; }
    if item["status"] == "BOOKED" { return "Booked"; }
    if item["offerId"] or item["status"] == "SELECTED" { return "Selected"; }
    if item["locked"] { return "Fixed"; }
    return "To plan";
}

def:pub day_context(day: any, snapshot: any) -> any {
    date = str(day["date"]);
    legs = [leg for leg in snapshot["legs"] or [] if leg["departDate"] == date or leg["arriveDate"] == date];
    stays = [stay for stay in snapshot["stays"] or [] if stay["checkIn"] and stay["checkOut"] and str(stay["checkIn"]) <= date and date <= str(stay["checkOut"])];
    rentals = [rental for rental in snapshot["rentals"] or [] if rental["pickupDate"] == date or rental["dropoffDate"] == date];
    return {"legs": legs, "stays": stays, "rentals": rentals};
}

def:pub day_focus_ids(day: any, snapshot: any) -> any {
    ids = [item["placeId"] for item in day["items"] or [] if item["placeId"]];
    if day["overnightPlaceId"] { ids.append(day["overnightPlaceId"]); }
    context = day_context(day, snapshot);
    for leg in context["legs"] {
        if leg["departDate"] == day["date"] { ids.append(leg["fromId"]); }
        if leg["arriveDate"] == day["date"] { ids.append(leg["toId"]); }
    }
    for stay in context["stays"] { ids.append(stay["placeId"]); }
    for rental in context["rentals"] {
        if rental["pickupDate"] == day["date"] and rental["pickupPlaceId"] { ids.append(rental["pickupPlaceId"]); }
        if rental["dropoffDate"] == day["date"] and rental["dropoffPlaceId"] { ids.append(rental["dropoffPlaceId"]); }
    }
    return ids;
}

def:pub day_photo(day: any, snapshot: any) -> any {
    for item in day["items"] or [] {
        photo = trip_photo(snapshot, item);
        if photo["photoUrl"] { return photo; }
    }
    return trip_place(snapshot, str(day["overnightPlaceId"] or ""));
}

def:pub load_trip_view(tripId: str) -> any {
    try {
        browser: any = window;
        raw = browser.localStorage.getItem("atlas.studio.view.v1." + tripId);
        return JSON.parse(str(raw)) if raw else {};
    } except Exception { return {}; }
}

def:pub save_trip_view(tripId: str, view: any) {
    try {
        browser: any = window;
        browser.localStorage.setItem("atlas.studio.view.v1." + tripId, JSON.stringify(view));
    } except Exception { }
}

"""Sourced journeys enrich a selected/user-supplied leg without inventing a fare."""
def:pub trip_flight(resources: any, item: any, snapshot: any = None) -> any {
    selected = selected_offer(resources, item);
    selectedFlight = selected["flight"] if selected else None;
    selectedMatches = True;
    if selectedFlight {
        for field in ["departDate", "departTime", "arriveDate", "arriveTime", "durationMinutes"] {
            if item[field] is not None and item[field] != "" and selectedFlight[field] is not None and selectedFlight[field] != "" and item[field] != selectedFlight[field] { selectedMatches = False; }
        }
    }
    if selectedFlight and selectedMatches and len(selectedFlight["segments"] or []) > 0 { return selectedFlight; }
    for journey in resources["flightJourneys"] or [] {
        flight = journey["flight"];
        if journey["legId"] != item["id"] or not flight { continue; }
        signature = journey["legSignature"];
        if not signature or not snapshot { continue; }
        matches = True;
        for field in ["fromId", "toId", "mode", "departDate", "arriveDate", "departTime", "arriveTime", "durationMinutes", "offerId", "bookingId"] { if item[field] != signature[field] { matches = False; } }
        first = trip_place(snapshot, str(item["fromId"])); last = trip_place(snapshot, str(item["toId"]));
        if first["query"] != signature["fromQuery"] or first["label"] != signature["fromLabel"] or last["query"] != signature["toQuery"] or last["label"] != signature["toLabel"] { matches = False; }
        if matches { return flight; }
    }
    return selectedFlight if selectedFlight and selectedMatches else item;
}


"""Day map projection excludes unrelated journeys without editing the saved trip."""
def:pub day_map_snapshot(snapshot: any, day: any) -> any {
    value = JSON.parse(JSON.stringify(snapshot));
    value["legs"] = day_context(day, snapshot)["legs"];
    return value;
}
