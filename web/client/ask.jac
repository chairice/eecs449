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

"""Which manual-search panel a described trip still needs: "where", "when",
or "" once it can be searched."""
def:pub missing_panel(form: ComposerInput) -> str {
    if form.destination_text == "" { return "where"; }
    if form.local_date == "" { return "when"; }
    return "";
}
