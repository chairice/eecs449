"""Domain safety tests use synthetic plans, not live travel observations."""
import copy

import pytest

from server.planning_core import (
    PlanningError, apply_operations, blank_trip, budget_summary, calendar,
    change_summary, loads, money_minor, public_url, validate_trip,
)


def trip():
    value = blank_trip("trip-test")
    value.update(title="Arizona", startDate="2026-12-26", endDate="2027-01-04")
    value["places"] = [{"id": "sedona", "query": "Sedona, Arizona"}, {"id": "page", "query": "Page, Arizona"}]
    value["days"] = [{"id": "day-5", "date": "2026-12-30", "title": "Sedona", "overnightPlaceId": "sedona",
                      "items": [{"id": "sunrise", "title": "Sunrise walk", "startTime": "06:55", "endTime": "07:50"},
                                {"id": "rest", "title": "Rest", "kind": "REST", "startTime": "14:15", "endTime": "16:45"}]}]
    return validate_trip(value)


def test_compact_initial_replace_composes_with_later_staged_days():
    initial = blank_trip("trip_batch")
    operations = [{"action": "replace_trip", "value": {"id": "trip_batch", "title": "Batched trip"}},
                  {"action": "upsert_place", "value": {"id": "tucson", "query": "Tucson, AZ"}},
                  {"action": "upsert_day", "value": {"id": "day1", "date": "2026-12-26", "title": "Arrive", "overnightPlaceId": "tucson"}}]
    staged = initial
    for operation in operations:
        staged = apply_operations(staged, [operation])
    assert apply_operations(initial, operations) == staged


def test_car_times_compare_actual_instants_across_us_time_zones():
    value = blank_trip("trip_zone")
    value["places"] = [{"id": "kingman", "query": "Kingman, AZ", "timezone": "America/Phoenix"},
                       {"id": "laughlin", "query": "Laughlin, NV", "timezone": "America/Los_Angeles"}]
    value["rentals"] = [{"id": "car", "pickupPlaceId": "kingman", "dropoffPlaceId": "laughlin", "pickupDate": "2026-12-26",
                         "dropoffDate": "2026-12-26", "pickupTime": "10:00", "dropoffTime": "09:45"}]
    assert validate_trip(value)["rentals"][0]["dropoffTime"] == "09:45"


def test_targeted_update_preserves_every_unmentioned_detail_and_input():
    before = trip(); untouched = copy.deepcopy(before)
    after = apply_operations(before, [{"action": "upsert_item", "dayId": "day-5", "value": {"id": "rest", "startTime": "13:25"}}])
    assert before == untouched
    assert after["days"][0]["items"][0] == before["days"][0]["items"][0]
    assert after["days"][0]["items"][1]["endTime"] == "16:45"
    assert after["days"][0]["items"][1]["startTime"] == "13:25"


def test_initial_plan_can_replace_only_an_empty_trip():
    after = apply_operations(blank_trip("trip-new"), [{"action": "replace_trip", "value": trip()}])
    assert after["id"] == "trip-new"
    with pytest.raises(PlanningError, match="targeted"):
        apply_operations(after, [{"action": "replace_trip", "value": blank_trip()}])


def test_updating_a_day_cannot_accidentally_drop_activities():
    with pytest.raises(PlanningError, match="targeted item"):
        apply_operations(trip(), [{"action": "upsert_day", "value": {"id": "day-5", "items": []}}])


def test_move_has_explicit_source_and_destination_and_keeps_other_items():
    before = trip()
    before["days"].append({"id": "day-6", "date": "2026-12-31", "title": "Open day", "items": []})
    before = validate_trip(before)
    after = apply_operations(before, [{"action": "move_item", "dayId": "day-5", "toDayId": "day-6", "targetId": "sunrise"}])
    assert [x["id"] for x in after["days"][0]["items"]] == ["rest"]
    assert after["days"][1]["items"][0] == before["days"][0]["items"][0]


def test_insert_and_reorder_use_an_explicit_activity_anchor():
    before = trip(); original = copy.deepcopy(before)
    after = apply_operations(before, [{"action": "upsert_item", "dayId": "day-5", "beforeId": "rest",
        "value": {"id": "lunch", "title": "Lunch", "kind": "MEAL"}}])
    assert [item["id"] for item in after["days"][0]["items"]] == ["sunrise", "lunch", "rest"]
    after = apply_operations(after, [{"action": "move_item", "dayId": "day-5", "toDayId": "day-5", "targetId": "rest", "beforeId": "lunch"}])
    assert [item["id"] for item in after["days"][0]["items"]] == ["sunrise", "rest", "lunch"]
    assert before == original and after["days"][0]["items"][1] == before["days"][0]["items"][1]


def test_repositioning_an_existing_item_preserves_unspecified_fields():
    before = trip()
    after = apply_operations(before, [{"action": "upsert_item", "dayId": "day-5", "beforeId": "sunrise", "value": {"id": "rest", "notes": "Earlier in the displayed order"}}])
    assert [item["id"] for item in after["days"][0]["items"]] == ["rest", "sunrise"]
    assert after["days"][0]["items"][0]["startTime"] == "14:15"


@pytest.mark.parametrize("anchor", ["missing", "rest", 0])
def test_missing_or_self_reorder_anchor_is_rejected_without_mutation(anchor):
    before = trip(); original = copy.deepcopy(before)
    with pytest.raises(PlanningError, match="position|itself"):
        apply_operations(before, [{"action": "move_item", "dayId": "day-5", "toDayId": "day-5", "targetId": "rest", "beforeId": anchor}])
    assert before == original


def test_locked_activity_cannot_move_to_a_different_date_via_day_header():
    before = trip(); before["days"][0]["items"][0]["locked"] = True
    with pytest.raises(PlanningError, match="fixed or booked"):
        apply_operations(before, [{"action": "upsert_day", "value": {"id": "day-5", "date": "2026-12-31"}}])


def test_booked_hotel_cannot_be_removed_or_shifted():
    before = trip()
    before["stays"] = [{"id": "booked-stay", "placeId": "page", "checkIn": "2027-01-01", "checkOut": "2027-01-03", "propertyName": "Synthetic property", "status": "BOOKED"}]
    before = validate_trip(before)
    for operation in [{"action": "remove_stay", "targetId": "booked-stay"},
                      {"action": "upsert_stay", "value": {"id": "booked-stay", "checkIn": "2027-01-02"}}]:
        with pytest.raises(PlanningError, match="fixed or booked"):
            apply_operations(before, [operation])


def test_booking_reference_locks_transport_even_if_model_omits_flag():
    before = trip()
    before["bookings"] = [{"id": "booking", "title": "Synthetic flight", "source": "USER"}]
    before["legs"] = [{"id": "flight", "fromId": "sedona", "toId": "page", "mode": "FLIGHT", "departDate": "2027-01-01", "bookingId": "booking"}]
    before = validate_trip(before)
    assert before["legs"][0]["locked"]
    with pytest.raises(PlanningError, match="fixed or booked"):
        apply_operations(before, [{"action": "upsert_leg", "value": {"id": "flight", "departDate": "2027-01-02"}}])


def test_unknown_place_references_and_duplicate_ids_are_rejected():
    invalid = trip(); invalid["days"][0]["items"][0]["placeId"] = "missing"
    with pytest.raises(PlanningError, match="missing place"):
        validate_trip(invalid)
    invalid = trip(); invalid["days"][0]["items"][0]["id"] = "sedona"
    with pytest.raises(PlanningError, match="Duplicate"):
        validate_trip(invalid)


@pytest.mark.parametrize("value", ["2026-02-29", "2026-13-01", "2027-1-4", "tomorrow"])
def test_dates_are_structural_not_natural_language_guesses(value):
    with pytest.raises(PlanningError):
        calendar(value, "test date")


def test_year_boundary_dates_and_partial_unknowns_survive():
    value = trip()
    assert value["party"]["adults"] is None
    assert value["startDate"] == "2026-12-26" and value["endDate"] == "2027-01-04"
    assert value["places"][0]["lat"] is None


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-Infinity"])
def test_nonfinite_json_is_never_admitted(value):
    with pytest.raises(PlanningError):
        loads('{"amount":' + value + '}')


@pytest.mark.parametrize("value", ["javascript:alert(1)", "file:///etc/passwd", "https://user:secret@example.com", "http://localhost/foo"])
def test_source_links_do_not_allow_executable_or_private_targets(value):
    with pytest.raises(PlanningError):
        public_url(value)


def test_monetary_arithmetic_is_exact_and_rejects_fractional_cents():
    assert money_minor("$1,234.56") == 123456
    for invalid in ["NaN", "-5", "4.999", "unknown"]:
        with pytest.raises(PlanningError):
            money_minor(invalid)


def test_alternatives_and_booked_items_are_not_double_counted():
    value = trip()
    value["bookings"] = [{"id": "paid", "title": "Synthetic booking", "amountMinor": 10000}]
    value["stays"] = [
        {"id": "selected-a", "placeId": "sedona", "offerId": "offer-a"},
        {"id": "selected-again", "placeId": "page", "offerId": "offer-a"},
        {"id": "already-paid", "placeId": "page", "offerId": "offer-b", "bookingId": "paid"},
    ]
    value = validate_trip(value)
    summary = budget_summary(value, [{"id": "offer-a", "currency": "USD", "totalMinor": 5000},
                                     {"id": "offer-b", "currency": "USD", "totalMinor": 10000},
                                     {"id": "alternative", "currency": "USD", "totalMinor": 99999}])
    assert summary["selectedQuoteSubtotals"] == {"USD": 5000}
    assert summary["bookedSubtotals"] == {"USD": 10000}


def test_diff_is_derived_from_actual_changes():
    before = trip()
    after = apply_operations(before, [{"action": "set_trip", "value": {"title": "A calmer Arizona trip"}}])
    assert change_summary(before, after) == [{"kind": "UPDATE", "section": "trip", "label": "title", "before": "Arizona", "after": "A calmer Arizona trip"}]


def test_fixed_location_cannot_be_relocated_under_the_same_place_id():
    before = trip()
    before["stays"] = [{"id": "booked-stay", "placeId": "page", "checkIn": "2027-01-01", "checkOut": "2027-01-03", "status": "BOOKED"}]
    before = validate_trip(before)
    for value in [{"id": "page", "query": "New York, NY"}, {"id": "page", "kind": "AIRPORT"}]:
        with pytest.raises(PlanningError, match="fixed or booked"):
            apply_operations(before, [{"action": "upsert_place", "value": value}])
    # Corrected source coordinates and cosmetic labels do not relocate a booking.
    updated = apply_operations(before, [{"action": "upsert_place", "value": {"id": "page", "label": "Page, Arizona", "lat": 36.9147, "lon": -111.4558}}])
    assert updated["stays"] == before["stays"]


def test_locked_activity_without_explicit_place_keeps_its_overnight_base():
    before = trip(); day = before["days"][0]
    day["overnightPlaceId"] = "sedona"
    day["items"][0].update(locked=True, placeId="")
    before = validate_trip(before)
    with pytest.raises(PlanningError, match="fixed or booked"):
        apply_operations(before, [{"action": "upsert_day", "value": {"id": day["id"], "overnightPlaceId": "page"}}])
