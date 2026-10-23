import from client.composer_model {
    ComposerInput, copy_input, example_input, field_error, parse_budget, update_input, update_mode,
    valid_date, valid_time, validate_composer
}

def valid_form -> ComposerInput {
    return ComposerInput(origin_text=" Ann Arbor ", destination_text="Chicago", local_date="2026-10-23", local_time="16:00", budget="50.01");
}

test "structured fallback emits canonical values with exact cents" {
    result = validate_composer(valid_form(), "2026-10-17");
    assert len(result.errors) == 0;
    assert result.draft is not None;
    assert result.draft.origin_text == "Ann Arbor";
    assert result.draft.request_text == "";
    assert result.draft.max_price_cents == 5001;
    assert result.draft.min_transfer_minutes == 30;
    assert result.draft.allowed_modes == ["TRAIN", "BUS"];
    assert result.draft.time_kind == "DEPART_AFTER";
}

test "changing free text never erases explicit structured fields" {
    original = valid_form();
    changed = update_input(original, "request_text", "Actually please arrive before noon");
    assert original.request_text == "";
    assert changed.request_text == "Actually please arrive before noon";
    assert changed.local_time == "16:00";
    assert changed.origin_text == original.origin_text;
    assert changed.budget == original.budget;
}

test "dates reject rollover and honor Gregorian leap rules" {
    for value in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-10", "2026-1-01", "0000-01-01", "1900-02-29", "bad"] { assert not valid_date(value); }
    for value in ["2024-02-29", "2000-02-29", "2026-12-31"] { assert valid_date(value); }
    result = validate_composer(valid_form(), "2026-10-24");
    assert field_error(result.errors, "local_date") != "";
    assert validate_composer(valid_form(), "2026-10-23").draft is not None;
}

test "times require exact twenty four hour minute precision" {
    for value in ["24:00", "23:60", "1:30", "12:3", "12:30:00", "aa:bb", ""] { assert not valid_time(value); }
    assert valid_time("00:00") and valid_time("23:59");
}

test "budget distinguishes absent free exact decimals and malformed text" {
    assert parse_budget(" ") is None;
    assert parse_budget("0") == 0;
    assert parse_budget("0.1") == 10;
    assert parse_budget("1.01") == 101;
    assert parse_budget(" 50.25 ") == 5025;
    for value in ["-1", "1e3", "NaN", "Infinity", "1.001", "1,000", "1.", ".50", "99999999999999999999"] { assert parse_budget(value) == -1; }
}

test "errors preserve input and report all actionable fields" {
    value = ComposerInput(origin_text="A", destination_text="a", local_date="2026-02-30", local_time="25:00", budget="-2", transfer_minutes="3.5", allow_train=False, allow_bus=False);
    before = copy_input(value);
    result = validate_composer(value);
    assert result.draft is None;
    for field in ["destination_text", "local_date", "local_time", "budget", "transfer_minutes", "modes"] { assert field_error(result.errors, field) != ""; }
    assert value.budget == before.budget;
    assert value.local_date == before.local_date;
    assert value.transfer_minutes == before.transfer_minutes;
}

test "required places time and transfers are checked before conversion" {
    result = validate_composer(ComposerInput(transfer_minutes=""));
    for field in ["origin_text", "destination_text", "local_date", "local_time", "transfer_minutes"] { assert field_error(result.errors, field) != ""; }
    for invalid in ["-1", "1.5", "1e3", "1000000"] {
        value = update_input(valid_form(), "transfer_minutes", invalid);
        assert field_error(validate_composer(value).errors, "transfer_minutes") != "";
    }
}

test "mode updates copy state and preserve other fields" {
    original = valid_form();
    updated = update_mode(original, "BUS", False);
    assert original.allow_bus;
    assert not updated.allow_bus and updated.allow_train;
    result = validate_composer(updated);
    assert result.draft is not None and result.draft.allowed_modes == ["TRAIN"];
}

test "dated demo prefills missing fields while retaining user edits" {
    original = ComposerInput(origin_text="My starting point", local_date="2026-11-02", budget="12.34", request_text="My own request");
    demo = example_input(original);
    assert demo.origin_text == "My starting point";
    assert demo.local_date == "2026-11-02" and demo.budget == "12.34";
    assert demo.request_text == "My own request";
    assert demo.destination_text == "Chicago, IL" and demo.local_time == "16:00";
    assert original.destination_text == "";
    assert validate_composer(example_input(ComposerInput())).draft is not None;
}

test "a return date must come after departure and is carried into the draft" {
    value = valid_form();
    value.return_date = "2026-10-23";
    assert field_error(validate_composer(value).errors, "return_date") != "";
    value.return_date = "2026-10-30";
    draft = validate_composer(value).draft;
    assert draft is not None and draft.return_date == "2026-10-30";
    assert copy_input(value).return_date == "2026-10-30";
}
