"""Turns an interpret_trip answer into search-form input and readable chips.

The answer is untrusted JSON from the server; every field falls back to the
form's own default, and the form's validation still decides what is searched.
"""

import from .composer_model { ComposerInput }

glob DEFAULT_ORIGIN: str = "Ann Arbor, MI";

def text_field(answer: any, key: str) -> str {
    value: any = answer[key] if answer else "";
    return value if isinstance(value, str) else "";
}

def number_field(answer: any, key: str) -> int {
    value: any = answer[key] if answer else 0;
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0 else 0;
}

"""Trips start in Ann Arbor unless that is where they are going."""
def default_origin(destination: str) -> str {
    return "Chicago, IL" if destination == DEFAULT_ORIGIN else DEFAULT_ORIGIN;
}

def:pub intent_input(answer: any, request: str) -> ComposerInput {
    price = number_field(answer, "max_price");
    buffer = number_field(answer, "min_transfer_minutes");
    origin = text_field(answer, "origin");
    time = text_field(answer, "time");
    kind = text_field(answer, "time_kind");
    destination = text_field(answer, "destination");
    return ComposerInput(
        request_text=request, origin_text=origin if origin != "" else default_origin(destination),
        destination_text=destination, local_date=text_field(answer, "date"),
        local_time=time if time != "" else "00:00", time_kind=kind if kind == "ARRIVE_BY" else "DEPART_AFTER",
        budget=str(price) if price > 0 else "", transfer_minutes=str(buffer) if buffer > 0 else "30",
        return_date=text_field(answer, "return_date")
    );
}

"""Read an ISO date at UTC noon so the label never slips a day across zones."""
def short_day(iso: str) -> str {
    noon: any = new(Date, iso + "T12:00:00Z");
    return str(noon.toLocaleDateString("en-US", {"weekday": "short", "month": "short", "day": "numeric", "timeZone": "UTC"}));
}

def clock_label(value: str) -> str {
    hour = int(value.split(":")[0]);
    return str(12 if hour % 12 == 0 else hour % 12) + ":" + value.split(":")[1] + (" AM" if hour < 12 else " PM");
}

"""A follow-up message adds to the trip so far: a field the new answer leaves
empty keeps its earlier value, so "Chicago" then "Friday after 4" make one trip."""
def:pub merged_input(previous: ComposerInput | None, answer: any, request: str) -> ComposerInput {
    fresh = intent_input(answer, request);
    if previous is None { return fresh; }
    timed = text_field(answer, "time") != "";
    return ComposerInput(
        request_text=previous.request_text + " " + request,
        origin_text=fresh.origin_text if text_field(answer, "origin") != "" else previous.origin_text if fresh.destination_text == "" or previous.origin_text != fresh.destination_text else default_origin(fresh.destination_text),
        destination_text=fresh.destination_text if fresh.destination_text != "" else previous.destination_text,
        local_date=fresh.local_date if fresh.local_date != "" else previous.local_date,
        local_time=fresh.local_time if timed else previous.local_time,
        time_kind=fresh.time_kind if timed else previous.time_kind,
        budget=fresh.budget if fresh.budget != "" else previous.budget,
        transfer_minutes=fresh.transfer_minutes if number_field(answer, "min_transfer_minutes") > 0 else previous.transfer_minutes,
        return_date=fresh.return_date if fresh.return_date != "" else previous.return_date
    );
}

def city(place: str) -> str { return place.split(",")[0]; }

"""Detour's reply: the one thing still missing, or the trip it is about to search."""
def:pub reply_text(form: ComposerInput) -> str {
    if form.destination_text == "" {
        return "Where are you headed? For now I can plan trips between Ann Arbor and Chicago.";
    }
    if form.local_date == "" {
        return "When are you going to " + city(form.destination_text) + "? A day like “Friday” or “Nov 3” works.";
    }
    parts = [city(form.origin_text) + " to " + city(form.destination_text), "on " + short_day(form.local_date)];
    if form.local_time != "00:00" {
        parts.append(("arriving by " if form.time_kind == "ARRIVE_BY" else "leaving after ") + clock_label(form.local_time));
    }
    if form.budget != "" { parts.append("under $" + form.budget); }
    if form.transfer_minutes != "30" { parts.append("with " + form.transfer_minutes + "+ minutes between connections"); }
    if form.return_date != "" { parts.append("back " + short_day(form.return_date)); }
    return "Looking for " + ", ".join(parts) + ". Finding routes…";
}
