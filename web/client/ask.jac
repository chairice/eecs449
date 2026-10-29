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

def:pub intent_input(answer: any, request: str) -> ComposerInput {
    price = number_field(answer, "max_price");
    buffer = number_field(answer, "min_transfer_minutes");
    origin = text_field(answer, "origin");
    time = text_field(answer, "time");
    kind = text_field(answer, "time_kind");
    return ComposerInput(
        request_text=request, origin_text=origin if origin != "" else DEFAULT_ORIGIN,
        destination_text=text_field(answer, "destination"), local_date=text_field(answer, "date"),
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

"""What Detour heard, one short chip per field it filled."""
def:pub intent_chips(form: ComposerInput) -> list[str] {
    chips: list[str] = [];
    if form.destination_text != "" { chips.append(form.origin_text + " → " + form.destination_text); }
    if form.local_date != "" { chips.append(short_day(form.local_date)); }
    if form.local_time != "00:00" {
        chips.append(("Arrive by " if form.time_kind == "ARRIVE_BY" else "Leave after ") + clock_label(form.local_time));
    }
    if form.budget != "" { chips.append("Under $" + form.budget); }
    if form.transfer_minutes != "30" { chips.append(form.transfer_minutes + "+ min connections"); }
    if form.return_date != "" { chips.append("Back " + short_day(form.return_date)); }
    return chips;
}

"""What is still needed before the search can run; "" when nothing is."""
def:pub missing_note(form: ComposerInput) -> str {
    if form.destination_text == "" and form.local_date == "" { return "Say where and when, like “Chicago Friday after 4”."; }
    if form.destination_text == "" { return "Where to? Pick a destination below."; }
    if form.local_date == "" { return "Which day? Pick a date below to search."; }
    return "";
}
