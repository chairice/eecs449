"""Trips the user saved, kept in this browser's localStorage until the server stores them.

Records are plain JSON: what the Trips pages show, copied from the results at
save time. Storage can be missing or full (private windows, blocked site
data), so every read and write tolerates failure; a malformed record is
dropped rather than shown. A signed-in account keeps its own list; signed out,
the browser's shared list is used.
"""

import from .account { account_email }

glob STORAGE_KEY: str = "detour.savedTrips.v1";

def trips_key -> str {
    email = account_email();
    return STORAGE_KEY + ":" + email if email else STORAGE_KEY;
}

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
        raw: any = storage().getItem(trips_key());
        if not raw { return []; }
        parsed: any = JSON.parse(raw);
        if not Array.isArray(parsed) { return []; }
        return [trip for trip in parsed if valid_trip(trip)];
    } except Exception {
        return [];
    }
}

glob watchers: list[Callable[[], None]] = [];

"""Calls `onChange` after every save or removal; returns the unsubscribe."""
def:pub watch_trips(onChange: Callable[[], None]) -> Callable[[], None] {
    watchers.append(onChange);
    return lambda { watchers.remove(onChange); };
}

def store_trips(trips: list[any]) -> bool {
    try {
        storage().setItem(trips_key(), JSON.stringify(trips));
        for notify in list(watchers) { notify(); }
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

"""Whole days from today to a saved trip's ISO departure date, or None when it has none."""
def:pub days_until(trip: any) -> int | None {
    if not trip or not isinstance(trip["start_date"], str) or trip["start_date"] == "" { return None; }
    start = Date.parse(trip["start_date"] + "T12:00:00Z");
    today = str((new(Date)).toISOString()).split("T")[0];
    current = Date.parse(today + "T12:00:00Z");
    if not Number.isFinite(start) or not Number.isFinite(current) { return None; }
    return int((start - current) / 86400000.0);
}

"""Coming trips soonest first, then trips already started, most recent first;
trips without a date go last."""
def:pub by_departure(trips: list[any]) -> list[any] {
    def order(trip: any) -> float {
        days = days_until(trip);
        if days is None { return 1000000000.0; }
        return float(days) if days >= 0 else 500000000.0 - float(days);
    }
    return sorted(trips, key=order);
}

"""Calendar countdown for a saved trip's ISO departure date."""
def:pub trip_countdown(trip: any) -> str {
    days = days_until(trip);
    if days is None { return "Start date unavailable"; }
    # LATER feature: only say trip started when the user confirms that they have started to travel.
    if days < 0 { return "Trip started"; }
    if days == 0 { return "Today"; }
    if days == 1 { return "Tomorrow"; }
    return str(days) + " days";
}

def:pub new_trip_id -> str {
    return "trip-" + str(Date.now());
}
