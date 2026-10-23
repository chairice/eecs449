"""Explicit RPC payload and defensive restoration from browser history state."""

import from .composer_model { ComposerDraft, ComposerInput, valid_date, validate_composer }

def plain_record(value: any) -> bool {
    # Jac 0.37.14's isinstance(dict) does not recognize browser JSON objects.
    # Check the actual browser representation, rather than accepting arrays.
    objectApi: any = Object;
    return value is not None and objectApi.getPrototypeOf(value) == objectApi.prototype;
}

def:pub request_payload(draft: ComposerDraft) -> dict[str, any] {
    # Do not send the optional prose: this endpoint does not interpret language.
    return {"origin_text": draft.origin_text, "destination_text": draft.destination_text,
        "local_date": draft.local_date, "local_time": draft.local_time,
        "time_kind": draft.time_kind, "max_price_cents": draft.max_price_cents,
        "min_transfer_minutes": draft.min_transfer_minutes,
        "allowed_modes": list(draft.allowed_modes), "priority": draft.priority};
}

"""The trip home on the return date: ends swapped, open to any departure that day."""
def:pub return_payload(draft: ComposerDraft) -> dict[str, any] | None {
    if not draft.return_date { return None; }
    payload = request_payload(draft);
    payload["origin_text"] = draft.destination_text;
    payload["destination_text"] = draft.origin_text;
    payload["local_date"] = draft.return_date;
    payload["local_time"] = "00:00";
    payload["time_kind"] = "DEPART_AFTER";
    return payload;
}

"""History is untrusted plain JSON. Invalid state produces a fresh empty form."""
def:pub restore_composer(state: any) -> ComposerInput {
    empty = ComposerInput();
    if not plain_record(state) { return empty; }
    request: any = state.get("draft");
    if not plain_record(request) { return empty; }
    for field in ["origin_text", "destination_text", "local_date", "local_time", "time_kind", "priority"] {
        if not isinstance(request.get(field), str) { return empty; }
    }
    cents: any = request.get("max_price_cents");
    if cents is not None and (isinstance(cents, bool) or not isinstance(cents, int)) { return empty; }
    if cents is not None and (cents < 0 or cents > 999999999999999) { return empty; }
    transfer: any = request.get("min_transfer_minutes");
    if isinstance(transfer, bool) or not isinstance(transfer, int) { return empty; }
    modes: any = request.get("allowed_modes");
    if not isinstance(modes, list) or len(modes) == 0 { return empty; }
    for mode in modes { if not isinstance(mode, str) or mode not in ["TRAIN", "BUS"] { return empty; } }
    budget = "";
    if cents is not None {
        amount = cents as int;
        remainder = amount % 100;
        budget = str(amount // 100) + "." + ("0" if remainder < 10 else "") + str(remainder);
    }
    text: any = state.get("requestText", "");
    restored = ComposerInput(request_text=text if isinstance(text, str) else "",
        origin_text=request["origin_text"], destination_text=request["destination_text"],
        local_date=request["local_date"], local_time=request["local_time"],
        time_kind=request["time_kind"], budget=budget, transfer_minutes=str(transfer),
        priority=request["priority"], allow_train="TRAIN" in modes, allow_bus="BUS" in modes);
    # A return day that no longer fits is dropped rather than discarding the form.
    returning: any = state.get("returnDate", "");
    if isinstance(returning, str) and valid_date(returning) and returning > restored.local_date { restored.return_date = returning; }
    if validate_composer(restored).draft is None { return empty; }
    return restored;
}
