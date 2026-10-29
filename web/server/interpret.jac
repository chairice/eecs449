"""Plain-language trip requests become structured search fields.

Claude reads the request when ANTHROPIC_API_KEY is set, through one direct
call to Anthropic's Messages API using only the standard library (byLLM's
dependencies are too heavy to install on a small host). Without a key, or
when the call fails, a rule-based reader handles the common phrasings, so a
live demo never depends on the network. Either way the output is only a
proposal for the search form: the planner still validates every field, and
nothing is booked or saved.
"""

import os;
import re;
import json;
import urllib.request;
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
    has priority: str = "BALANCED";
}
glob ANTHROPIC_URL: str = "https://api.anthropic.com/v1/messages";
glob DEFAULT_MODEL: str = "claude-haiku-5-5";
glob CLAUDE_TIMEOUT_SECONDS: int = 8;
glob CLAUDE_INSTRUCTIONS: str = """You turn a commuter's plain-language request for a train or bus trip into search fields.
Reply with only one JSON object, no prose, with exactly these keys:
- "origin": starting city as "City, ST" (e.g. "Ann Arbor, MI"), or "" when not stated
- "destination": destination city as "City, ST" (e.g. "Chicago, IL"), or "" when not stated
- "date": outbound date as YYYY-MM-DD resolved against today's date, or "" when not stated
- "time": local time as 24-hour HH:MM, or "" when not stated ("after 4" in the afternoon is 16:00)
- "time_kind": "ARRIVE_BY" when the time is a deadline ("by 9", "before 9 pm"), otherwise "DEPART_AFTER"
- "max_price": maximum total fare in whole US dollars, or 0 when no budget is given
- "min_transfer_minutes": minimum minutes between connections, 45 for "avoid tight transfers", or 0 when not stated
- "return_date": return date as YYYY-MM-DD when the request mentions coming back, or ""
- "priority": "LOWEST_COST" for cheap, "FASTEST" for fast, "FEWEST_TRANSFERS" for direct, "MOST_RELIABLE" for reliable, otherwise "BALANCED"
""";

"""The first JSON object in Claude's reply, as a TripIntent; raises if there is none."""
def:pub intent_from_reply(reply: str) -> TripIntent {
    found = re.search(r"\{.*\}", reply, re.DOTALL);
    if not found { raise ValueError("no JSON object in reply"); }
    raw = json.loads(found.group(0));
    if not isinstance(raw, dict) { raise ValueError("reply is not an object"); }
    return TripIntent(
        origin=str(raw.get("origin", "")), destination=str(raw.get("destination", "")),
        date=str(raw.get("date", "")), time=str(raw.get("time", "")), time_kind=str(raw.get("time_kind", "DEPART_AFTER")),
        max_price=int(raw.get("max_price", 0) or 0), min_transfer_minutes=int(raw.get("min_transfer_minutes", 0) or 0),
        return_date=str(raw.get("return_date", "")), priority=str(raw.get("priority", "BALANCED"))
    );
}

"""Ask Claude to read the request; raises on any network, HTTP or format error."""
def claude_intent(request: str, today: str, weekday: str, key: str) -> TripIntent {
    body = json.dumps({
        "model": os.environ.get("DETOUR_MODEL", DEFAULT_MODEL), "max_tokens": 300, "temperature": 0,
        "system": CLAUDE_INSTRUCTIONS,
        "messages": [{"role": "user", "content": "Today is " + weekday + ", " + today + ".\nRequest: " + request}]
    }).encode("utf-8");
    call = urllib.request.Request(ANTHROPIC_URL, data=body, method="POST", headers={
        "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"
    });
    with urllib.request.urlopen(call, timeout=CLAUDE_TIMEOUT_SECONDS) as response {
        payload = json.loads(response.read().decode("utf-8"));
    }
    reply = "".join([block.get("text", "") for block in payload.get("content", []) if block.get("type") == "text"]);
    return intent_from_reply(reply);
}

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

glob PRIORITIES: list[str] = ["BALANCED", "LOWEST_COST", "FASTEST", "FEWEST_TRANSFERS", "MOST_RELIABLE"];

def read_priority(text: str) -> str {
    if re.search(r"\b(cheap\w*|lowest (?:cost|price|fare)|least expensive|budget-friendly|save money)\b", text) { return "LOWEST_COST"; }
    if re.search(r"\b(fast\w*|quick\w*|shortest)\b", text) { return "FASTEST"; }
    if re.search(r"\b(direct|no (?:transfers?|connections?)|fewest (?:transfers?|connections?))\b", text) { return "FEWEST_TRANSFERS"; }
    if re.search(r"\b(reliab\w*|on time|safest)\b", text) { return "MOST_RELIABLE"; }
    return "BALANCED";
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
        min_transfer_minutes=minutes, return_date=returning, priority=read_priority(text)
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
        return_date=intent.return_date if re.match(iso, str(intent.return_date)) else "",
        priority=intent.priority if intent.priority in PRIORITIES else "BALANCED"
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
        key = os.environ.get("ANTHROPIC_API_KEY", "");
        if key {
            try {
                intent = cleaned(claude_intent(text, today.isoformat(), WEEKDAYS[today.weekday()].capitalize(), key));
                source = "claude";
            } except Exception {
                source = "rules";
            }
        }
    }
    return json.dumps({
        "source": source, "today": today.isoformat(), "origin": intent.origin, "destination": intent.destination,
        "date": intent.date, "time": intent.time, "time_kind": intent.time_kind, "max_price": intent.max_price,
        "min_transfer_minutes": intent.min_transfer_minutes, "return_date": intent.return_date,
        "priority": intent.priority
    });
}
