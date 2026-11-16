"""Display and confirmation helpers shared by the itinerary and map."""
def:pub stop_label(stop: any) -> str {
    place = stop["place"];
    if not place { return str(stop["query"] or "Choose a place"); }
    return (str(place["code"]) + " · " if place["code"] else "") + str(place["name"]);
}

def:pub leg_title(journey: any, index: int) -> str {
    first = journey["stops"][index]; last = journey["stops"][index + 1];
    start = str(first["place"]["code"] or first["place"]["name"]) if first["place"] else str(first["query"]);
    end = str(last["place"]["code"] or last["place"]["name"]) if last["place"] else str(last["query"]);
    return start + " → " + end;
}

def:pub leg_details(journey: any, index: int) -> str {
    leg = journey["legs"][index];
    lines = ["Leg " + str(index + 1) + " · " + ("Flight" if leg["mode"] == "FLIGHT" else "Driving" if leg["mode"] == "DRIVE" else "Mode not set"),
        stop_label(journey["stops"][index]), "→ " + stop_label(journey["stops"][index + 1]),
        "Departure: " + str(leg["departDate"] or "Date not set") + " · " + str(leg["departTime"] or "Time not set"),
        "Arrival: " + str(leg["arriveDate"] or "Date not set") + " · " + str(leg["arriveTime"] or "Time not set")];
    route = leg["route"];
    if leg["mode"] == "DRIVE" {
        if route["status"] == "READY" {
            if Number.isFinite(route["distanceMeters"]) { lines.append(str(Math.round(route["distanceMeters"] / 1609.344)) + " miles · calculated road route"); }
            if Number.isFinite(route["durationSeconds"]) { lines.append(str(Math.round(route["durationSeconds"] / 60)) + " min estimated, excluding stops / live traffic"); }
        } else { lines.append("Road route not calculated yet"); }
    }
    if leg["timingNote"] { lines.append(str(leg["timingNote"])); }
    return "\n".join(lines);
}

def:pub itinerary_signature(journey: any) -> str {
    return JSON.stringify({"title": journey["title"], "status": journey["status"], "stops": journey["stops"],
        "legs": [{"mode": leg["mode"], "departDate": leg["departDate"], "arriveDate": leg["arriveDate"], "departTime": leg["departTime"], "arriveTime": leg["arriveTime"], "timingNote": leg["timingNote"]} for leg in journey["legs"]], "unresolved": journey["unresolved"]});
}

def:pub is_finalized(journey: any) -> bool {
    return bool(journey) and "finalizedSignature" in Object.keys(journey) and journey["finalizedSignature"] == itinerary_signature(journey);
}
