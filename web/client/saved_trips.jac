"""Trips the user saved, kept in this browser's localStorage until the server stores them.

Records are plain JSON: what the Trips pages show, copied from the results at
save time. Storage can be missing or full (private windows, blocked site
data), so every read and write tolerates failure; a malformed record is
dropped rather than shown.
"""

glob STORAGE_KEY: str = "detour.savedTrips.v1";

"""The browser's localStorage, untyped like the other browser globals."""
def storage -> any {
    browser: any = window;
    return browser.localStorage;
}

def text_field(record: any, key: str) -> bool {
    value: any = record[key];
    return isinstance(value, str) and value != "";
}

"""A saved trip has the text fields the pages read, on itself and on every leg."""
def valid_trip(record: any) -> bool {
    if not record { return False; }
    for key in ["id", "title", "days", "total"] {
        if not text_field(record, key) { return False; }
    }
    legs: any = record["legs"];
    if not Array.isArray(legs) or legs.length == 0 { return False; }
    for leg in legs {
        if not leg { return False; }
        for key in ["label", "modes", "departure", "arrival", "duration", "price"] {
            if not text_field(leg, key) { return False; }
        }
    }
    return True;
}

def:pub load_trips -> list[any] {
    try {
        raw: any = storage().getItem(STORAGE_KEY);
        if not raw { return []; }
        parsed: any = JSON.parse(raw);
        if not Array.isArray(parsed) { return []; }
        return [trip for trip in parsed if valid_trip(trip)];
    } except Exception {
        return [];
    }
}

def store_trips(trips: list[any]) -> bool {
    try {
        storage().setItem(STORAGE_KEY, JSON.stringify(trips));
        return True;
    } except Exception {
        return False;
    }
}

"""Newest first. Returns False when the browser would not keep it."""
def:pub save_trip(trip: any) -> bool {
    if not valid_trip(trip) { return False; }
    return store_trips([trip] + [saved for saved in load_trips() if saved["id"] != trip["id"]]);
}

def:pub remove_trip(id: str) -> bool {
    return store_trips([saved for saved in load_trips() if saved["id"] != id]);
}

def:pub find_trip(id: str) -> any {
    for trip in load_trips() { if trip["id"] == id { return trip; } }
    return None;
}

"""Calendar countdown for a saved trip's ISO departure date."""
def:pub trip_countdown(trip: any) -> str {
    if not trip or not isinstance(trip["start_date"], str) or trip["start_date"] == "" {
        return "Start date unavailable";
    }
    start = Date.parse(trip["start_date"] + "T12:00:00Z");
    today = str((new(Date)).toISOString()).split("T")[0];
    current = Date.parse(today + "T12:00:00Z");
    if not Number.isFinite(start) or not Number.isFinite(current) {
        return "Start date unavailable";
    }
    days = int((start - current) / 86400000.0);
    if days < 0 { return "Trip started"; }
    if days == 0 { return "Today"; }
    if days == 1 { return "Tomorrow"; }
    return str(days) + " days";
}

def:pub new_trip_id -> str {
    return "trip-" + str(Date.now());
}
