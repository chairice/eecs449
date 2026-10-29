"""The rule-based reader behind plain-language requests, with today pinned."""

import json;
import from datetime { date }
import from server.interpret { TripIntent, cleaned, rule_intent, interpret_trip }

# Thursday, October 29, 2026.
glob TODAY: date = date(2026, 10, 29);

test "the README's example request fills every field" {
    intent = rule_intent("Get me from Ann Arbor to Chicago Friday after 4 PM. Keep it under $50 and avoid tight transfers.", TODAY);
    assert intent.origin == "Ann Arbor, MI" and intent.destination == "Chicago, IL";
    assert intent.date == "2026-10-30" and intent.time == "16:00" and intent.time_kind == "DEPART_AFTER";
    assert intent.max_price == 50 and intent.min_transfer_minutes == 45;
}

test "a deadline is an arrival time" {
    intent = rule_intent("need to be in chicago by 9pm tomorrow", TODAY);
    assert intent.destination == "Chicago, IL" and intent.origin == "";
    assert intent.date == "2026-10-30" and intent.time == "21:00" and intent.time_kind == "ARRIVE_BY";
}

test "month names, return trips and explicit buffers" {
    intent = rule_intent("Chicago Nov 3 at 7:30am, coming back Nov 5, at least 30 minutes between connections", TODAY);
    assert intent.date == "2026-11-03" and intent.time == "07:30";
    assert intent.return_date == "2026-11-05" and intent.min_transfer_minutes == 30;
}

test "the reverse direction is read from 'from'" {
    intent = rule_intent("from Chicago to Ann Arbor today after 3pm", TODAY);
    assert intent.origin == "Chicago, IL" and intent.destination == "Ann Arbor, MI";
    assert intent.date == "2026-10-29" and intent.time == "15:00";
}

test "an empty request answers with empty fields from the rules" {
    answer = json.loads(interpret_trip("   "));
    assert answer["source"] == "rules" and answer["destination"] == "" and answer["date"] == "";
}

test "malformed model output is dropped, not passed to the form" {
    tidy = cleaned(TripIntent(origin="Ann Arbor, MI", destination="Chicago, IL", date="next friday", time="4pm", time_kind="SOMETIME", max_price=-5, min_transfer_minutes=9000, return_date="2026-11-05"));
    assert tidy.date == "" and tidy.time == "" and tidy.time_kind == "DEPART_AFTER";
    assert tidy.max_price == 0 and tidy.min_transfer_minutes == 240 and tidy.return_date == "2026-11-05";
}

test "a follow-up reply can be just a day or just a time" {
    day = rule_intent("Friday", TODAY);
    assert day.date == "2026-10-30" and day.destination == "" and day.time == "";
    time = rule_intent("4pm", TODAY);
    assert time.time == "16:00" and time.time_kind == "DEPART_AFTER" and time.date == "";
}
