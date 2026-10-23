"""Pure form boundary: raw input stays separate from a validated client draft.

This module is usable in the browser and Jac tests. It deliberately imports no
server models: local input must never trigger RPC merely to validate a field.
"""

obj:pub ComposerInput {
    has request_text: str = "", origin_text: str = "", destination_text: str = "";
    has local_date: str = "", local_time: str = "", time_kind: str = "DEPART_AFTER";
    has budget: str = "", transfer_minutes: str = "30", priority: str = "BALANCED";
    has allow_train: bool = True, allow_bus: bool = True;
    # Optional return day, searched as its own trip from the destination back home.
    has return_date: str = "";
}

obj:pub ComposerDraft {
    has request_text: str, origin_text: str, destination_text: str;
    has local_date: str, local_time: str, time_kind: str;
    has max_price_cents: int | None, min_transfer_minutes: int;
    has allowed_modes: list[str], priority: str;
    has return_date: str = "";
}

obj:pub FieldError { has field: str, message: str; }
obj:pub ComposerValidation {
    has errors: list[FieldError];
    has draft: ComposerDraft | None = None;
}

def:pub copy_input(value: ComposerInput) -> ComposerInput {
    return ComposerInput(request_text=value.request_text, origin_text=value.origin_text,
        destination_text=value.destination_text, local_date=value.local_date,
        local_time=value.local_time, time_kind=value.time_kind, budget=value.budget,
        transfer_minutes=value.transfer_minutes, priority=value.priority,
        allow_train=value.allow_train, allow_bus=value.allow_bus, return_date=value.return_date);
}

"""Return a fresh object so React observes changes; leave other input untouched."""
def:pub update_input(value: ComposerInput, field: str, text: str) -> ComposerInput {
    updated = copy_input(value);
    if field == "request_text" { updated.request_text = text; }
    elif field == "origin_text" { updated.origin_text = text; }
    elif field == "destination_text" { updated.destination_text = text; }
    elif field == "local_date" { updated.local_date = text; }
    elif field == "return_date" { updated.return_date = text; }
    elif field == "local_time" { updated.local_time = text; }
    elif field == "time_kind" { updated.time_kind = text; }
    elif field == "budget" { updated.budget = text; }
    elif field == "transfer_minutes" { updated.transfer_minutes = text; }
    elif field == "priority" { updated.priority = text; }
    else { raise ValueError("Unknown composer field"); }
    return updated;
}

def:pub update_mode(value: ComposerInput, mode: str, enabled: bool) -> ComposerInput {
    updated = copy_input(value);
    if mode == "TRAIN" { updated.allow_train = enabled; }
    elif mode == "BUS" { updated.allow_bus = enabled; }
    else { raise ValueError("Unknown travel mode"); }
    return updated;
}

"""Fill empty fields with the explicitly dated demo; preserve every existing edit."""
def:pub example_input(value: ComposerInput) -> ComposerInput {
    updated = copy_input(value);
    if not updated.request_text.strip() { updated.request_text = "Ann Arbor to Chicago on October 23, 2026 after 4 PM, under $50."; }
    if not updated.origin_text.strip() { updated.origin_text = "Ann Arbor, MI"; }
    if not updated.destination_text.strip() { updated.destination_text = "Chicago, IL"; }
    if not updated.local_date { updated.local_date = "2026-10-23"; }
    if not updated.local_time { updated.local_time = "16:00"; }
    if not updated.budget.strip() { updated.budget = "50.00"; }
    return updated;
}

def:pub field_error(errors: list[FieldError], field: str) -> str {
    for error in errors { if error.field == field { return error.message; } }
    return "";
}

def digits(value: str) -> bool {
    if not value { return False; }
    for char in value { if char not in "0123456789" { return False; } }
    return True;
}

"""Strict Gregorian YYYY-MM-DD, without JS Date's rollover of invalid dates."""
def:pub valid_date(value: str) -> bool {
    if len(value) != 10 or value[4] != "-" or value[7] != "-" { return False; }
    if not digits(value[:4]) or not digits(value[5:7]) or not digits(value[8:]) { return False; }
    year = int(value[:4]); month = int(value[5:7]); day = int(value[8:]);
    if year < 1 or month < 1 or month > 12 or day < 1 { return False; }
    days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) { days[1] = 29; }
    return day <= days[month - 1];
}

def:pub valid_time(value: str) -> bool {
    if len(value) != 5 or value[2] != ":" or not digits(value[:2]) or not digits(value[3:]) { return False; }
    return int(value[:2]) <= 23 and int(value[3:]) <= 59;
}

"""Parse exact decimal USD into cents; never round a binary floating value."""
def:pub parse_budget(value: str) -> int | None {
    clean = value.strip();
    if not clean { return None; }
    parts = clean.split(".");
    if len(parts) > 2 or not digits(parts[0]) or len(parts[0]) > 13 { return -1; }
    fractional = "00";
    if len(parts) == 2 {
        if not digits(parts[1]) or len(parts[1]) > 2 { return -1; }
        fractional = parts[1] + "0" if len(parts[1]) == 1 else parts[1];
    }
    # The 13-digit whole-dollar bound keeps cents below JavaScript's safe integer.
    return int(parts[0]) * 100 + int(fractional);
}

def:pub validate_composer(value: ComposerInput, earliest_date: str = "") -> ComposerValidation {
    errors: list[FieldError] = [];
    origin = value.origin_text.strip(); destination = value.destination_text.strip();
    if not origin { errors.append(FieldError("origin_text", "Enter a starting point.")); }
    if not destination { errors.append(FieldError("destination_text", "Enter a destination.")); }
    elif origin and origin.lower() == destination.lower() { errors.append(FieldError("destination_text", "Choose a destination different from your starting point.")); }
    if not valid_date(value.local_date) { errors.append(FieldError("local_date", "Enter a valid trip date.")); }
    elif earliest_date and valid_date(earliest_date) and value.local_date < earliest_date { errors.append(FieldError("local_date", "Choose a date on or after " + earliest_date + ".")); }
    if value.return_date and not valid_date(value.return_date) { errors.append(FieldError("return_date", "Enter a valid return date.")); }
    elif value.return_date and valid_date(value.local_date) and value.return_date <= value.local_date { errors.append(FieldError("return_date", "Choose a return date after your departure date.")); }
    if not valid_time(value.local_time) { errors.append(FieldError("local_time", "Enter a valid time, from 00:00 to 23:59.")); }
    if value.time_kind not in ["DEPART_AFTER", "ARRIVE_BY"] { errors.append(FieldError("time_kind", "Choose departure or arrival time.")); }
    cents = parse_budget(value.budget);
    if cents is not None and cents < 0 { errors.append(FieldError("budget", "Enter a nonnegative USD amount with at most two decimal places.")); }
    transfer = value.transfer_minutes.strip();
    if not digits(transfer) or len(transfer) > 6 { errors.append(FieldError("transfer_minutes", "Enter a whole number of minutes from 0 to 999999.")); }
    if not value.allow_train and not value.allow_bus { errors.append(FieldError("modes", "Select at least one travel mode.")); }
    if value.priority not in ["BALANCED", "FASTEST", "LOWEST_COST", "MOST_RELIABLE", "FEWEST_TRANSFERS"] { errors.append(FieldError("priority", "Choose a routing priority.")); }
    if errors { return ComposerValidation(errors=errors); }
    modes: list[str] = [];
    if value.allow_train { modes.append("TRAIN"); }
    if value.allow_bus { modes.append("BUS"); }
    return ComposerValidation(errors=[], draft=ComposerDraft(
        request_text=value.request_text.strip(), origin_text=origin, destination_text=destination,
        local_date=value.local_date, local_time=value.local_time, time_kind=value.time_kind,
        max_price_cents=cents, min_transfer_minutes=int(transfer), allowed_modes=modes, priority=value.priority,
        return_date=value.return_date
    ));
}
