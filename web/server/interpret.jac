"""Plain-language trip requests become structured search fields.

Claude reads the request through byLLM when ANTHROPIC_API_KEY is set. Without
a key, or when the model call fails, a rule-based reader handles the common
phrasings, so a live demo never depends on the network. Either way the output
is only a proposal for the search form: the planner still validates every
field, and nothing is booked or saved.
"""

import os;
import re;
import json;
import from datetime { date, datetime, timedelta }
import from zoneinfo { ZoneInfo }

glob MAX_REQUEST_CHARS: int = 500;
glob HOME_ZONE: str = "America/Detroit";
glob WEEKDAYS: list[str] = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
glob MONTHS: list[str] = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
glob PLACES: dict[str, str] = {
    "ann arbor": "Ann Arbor, MI", "a2": "Ann Arbor, MI", "umich": "Ann Arbor, MI",
    "chicago": "Chicago, IL", "chi": "Chicago, IL", "windy city": "Chicago, IL"
};

obj:pub TripIntent {
    has origin: str = "", destination: str = "";
    has date: str = "", time: str = "", time_kind: str = "DEPART_AFTER";
    has max_price: int = 0, min_transfer_minutes: int = 0, return_date: str = "";
}
sem TripIntent = "A trip request turned into search fields. Leave a field at its default when the request does not say it.";
sem TripIntent.origin = "Starting city written as 'City, ST' (for example 'Ann Arbor, MI'), or '' when not stated.";
sem TripIntent.destination = "Destination city written as 'City, ST' (for example 'Chicago, IL'), or '' when not stated.";
sem TripIntent.date = "Outbound travel date as YYYY-MM-DD, resolved against today's date; '' when not stated.";
sem TripIntent.time = "Local time as 24-hour HH:MM; '' when not stated. 'after 4' in the afternoon means 16:00.";
sem TripIntent.time_kind = "DEPART_AFTER when the time is when to leave ('after 4', 'leave at 5'); ARRIVE_BY when it is a deadline ('by 9', 'before 9 pm').";
sem TripIntent.max_price = "Maximum total fare in whole US dollars; 0 when no budget is given.";
sem TripIntent.min_transfer_minutes = "Minimum minutes wanted between connections; 45 for 'avoid tight transfers'; 0 when not stated.";
sem TripIntent.return_date = "Return travel date as YYYY-MM-DD when the request mentions coming back; '' otherwise.";

def extract_intent(request: str, today: str, weekday: str) -> TripIntent by llm(temperature=0.0, max_tokens=300);
sem extract_intent = "Read a commuter's plain-language request for a train or bus trip and fill in the structured search fields.";
sem extract_intent.request = "What the commuter typed, for example 'Get me to Chicago Friday after 4 PM, under $50'.";
sem extract_intent.today = "Today's date as YYYY-MM-DD in the commuter's time zone.";
sem extract_intent.weekday = "Today's weekday name, for resolving words like 'Friday' or 'tomorrow'.";

def today_local -> date {
    return datetime.now(ZoneInfo(HOME_ZONE)).date();
}

"""A weekday name means its next occurrence, today included."""
def next_weekday(today: date, name: str) -> date {
    ahead = (WEEKDAYS.index(name) - today.weekday()) % 7;
    return today + timedelta(days=ahead);
}

"""The first date phrase in `text`, as an ISO date; "" when there is none."""
def read_date(text: str, today: date) -> str {
    if re.search(r"\btomorrow\b", text) { return (today + timedelta(days=1)).isoformat(); }
    if re.search(r"\b(today|tonight|this evening)\b", text) { return today.isoformat(); }
    named = re.search(r"\b(" + "|".join(MONTHS) + r")[a-z]*\.?\s+(\d{1,2})\b", text);
    if named {
        month = MONTHS.index(named.group(1)) + 1;
        day = int(named.group(2));
        try {
            found = date(today.year, month, day);
            return (found if found >= today else date(today.year + 1, month, day)).isoformat();
        } except ValueError { return ""; }
    }
    slashed = re.search(r"\b(\d{1,2})/(\d{1,2})\b", text);
    if slashed {
        try {
            found = date(today.year, int(slashed.group(1)), int(slashed.group(2)));
            return (found if found >= today else date(today.year + 1, found.month, found.day)).isoformat();
        } except ValueError { return ""; }
    }
    for name in WEEKDAYS {
        if re.search(r"\b" + name[:3] + r"(" + name[3:] + r")?\b", text) { return next_weekday(today, name).isoformat(); }
    }
    return "";
}

"""Hour and minute after a cue word; bare small hours read as afternoon, as people say them."""
def read_clock(hour_text: str, minute_text: str | None, meridiem: str | None) -> str {
    hour = int(hour_text);
    minute = int(minute_text) if minute_text else 0;
    if hour > 23 or minute > 59 { return ""; }
    if meridiem and meridiem.startswith("p") and hour < 12 { hour += 12; }
    elif meridiem and meridiem.startswith("a") and hour == 12 { hour = 0; }
    elif not meridiem and 1 <= hour <= 7 { hour += 12; }
    return f"{hour:02d}:{minute:02d}";
}

def read_time(text: str) -> tuple[str, str] {
    clock = r"(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|am|pm)?";
    arrive = re.search(r"\b(?:by|before|arrive by|arriving by|get there by)\s+" + clock, text);
    if arrive { return (read_clock(arrive.group(1), arrive.group(2), arrive.group(3)), "ARRIVE_BY"); }
    depart = re.search(r"\b(?:after|leave at|leaving at|leave|leaving|departing|depart|at|around)\s+" + clock, text);
    if depart { return (read_clock(depart.group(1), depart.group(2), depart.group(3)), "DEPART_AFTER"); }
    # A bare clock with am/pm, as in a follow-up reply like "4pm".
    bare = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|am|pm)(?![a-z])", text);
    if bare { return (read_clock(bare.group(1), bare.group(2), bare.group(3)), "DEPART_AFTER"); }
    if re.search(r"\b(evening|tonight)\b", text) { return ("17:00", "DEPART_AFTER"); }
    if re.search(r"\bafternoon\b", text) { return ("13:00", "DEPART_AFTER"); }
    if re.search(r"\bmorning\b", text) { return ("08:00", "DEPART_AFTER"); }
    return ("", "DEPART_AFTER");
}

def read_places(text: str) -> tuple[str, str] {
    names = "|".join([re.escape(name) for name in sorted(PLACES.keys(), key=len, reverse=True)]);
    origin = re.search(r"\bfrom\s+(" + names + r")\b", text);
    destination = re.search(r"\b(?:to|into|towards?)\s+(" + names + r")\b", text);
    found_origin = PLACES[origin.group(1)] if origin else "";
    found_destination = PLACES[destination.group(1)] if destination else "";
    if not found_destination {
        mentioned = [PLACES[name] for name in re.findall(r"\b(" + names + r")\b", text)];
        others = [place for place in mentioned if place != found_origin];
        found_destination = others[0] if others else "";
    }
    return (found_origin, found_destination);
}

"""Rule-based reading of the phrasings a commuter is likely to type."""
def:pub rule_intent(request: str, today: date) -> TripIntent {
    text = " ".join(request.lower().replace(",", " , ").split());
    (origin, destination) = read_places(text);
    outbound = text;
    returning = "";
    split = re.search(r"\b(?:return(?:ing)?|com(?:e|ing) back|back)\b(.*)$", text);
    if split {
        outbound = text[:split.start()];
        returning = read_date(split.group(1), today);
    }
    (time, kind) = read_time(outbound);
    price = re.search(r"(?:under|below|less than|max(?:imum)?|budget(?: of)?|up to|no more than)\s*\$?\s*(\d{1,4})|\$\s*(\d{1,4})", text);
    transfer = re.search(r"(\d{1,3})\s*(?:min(?:ute)?s?)\b[^.]*\b(?:transfer|connection|layover|between)", text);
    minutes = int(transfer.group(1)) if transfer else 45 if re.search(r"\b(tight|short|quick)\s+(transfers?|connections?)\b", text) else 0;
    return TripIntent(
        origin=origin, destination=destination, date=read_date(outbound, today), time=time, time_kind=kind,
        max_price=int(price.group(1) or price.group(2)) if price else 0,
        min_transfer_minutes=minutes, return_date=returning
    );
}

"""The model's answer, coerced to safe field values; anything malformed is dropped."""
def cleaned(intent: TripIntent) -> TripIntent {
    iso = r"^\d{4}-\d{2}-\d{2}$";
    return TripIntent(
        origin=str(intent.origin)[:80], destination=str(intent.destination)[:80],
        date=intent.date if re.match(iso, str(intent.date)) else "",
        time=intent.time if re.match(r"^\d{2}:\d{2}$", str(intent.time)) else "",
        time_kind="ARRIVE_BY" if intent.time_kind == "ARRIVE_BY" else "DEPART_AFTER",
        max_price=max(0, min(9999, int(intent.max_price or 0))),
        min_transfer_minutes=max(0, min(240, int(intent.min_transfer_minutes or 0))),
        return_date=intent.return_date if re.match(iso, str(intent.return_date)) else ""
    );
}

"""Anonymous RPC: a request of up to 500 characters in, JSON search fields out.

The parameter is `text`, not `request`: the server reserves `request` for
the HTTP request it passes to endpoints.

`source` says who read it ("claude" or "rules"), so the interface can be honest
about it. A failed model call falls back to the rules rather than erroring."""
def:pub interpret_trip(text: str) -> str {
    text = str(text)[:MAX_REQUEST_CHARS].strip();
    today = today_local();
    intent = TripIntent();
    source = "rules";
    if text {
        intent = rule_intent(text, today);
        if os.environ.get("ANTHROPIC_API_KEY") {
            try {
                intent = cleaned(extract_intent(text, today.isoformat(), WEEKDAYS[today.weekday()].capitalize()));
                source = "claude";
            } except Exception {
                source = "rules";
            }
        }
    }
    return json.dumps({
        "source": source, "today": today.isoformat(), "origin": intent.origin, "destination": intent.destination,
        "date": intent.date, "time": intent.time, "time_kind": intent.time_kind, "max_price": intent.max_price,
        "min_transfer_minutes": intent.min_transfer_minutes, "return_date": intent.return_date
    });
}
