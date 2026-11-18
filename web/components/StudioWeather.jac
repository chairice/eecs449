"""Visual trip weather. Provenance stays in the sourced resource, not the UI."""
import "../studio-weather.css";
import from ..client.planning_state { date_label }

"""Decorative glyph from observed conditions, without inferring risk."""
def:pub weather_kind(summary: str) -> str {
    value = summary.lower();
    if "thunder" in value { return "storm"; }
    if "freezing" in value or "sleet" in value or "ice" in value { return "ice"; }
    if "snow" in value or "flurr" in value { return "snow"; }
    if "rain" in value or "drizzle" in value or "shower" in value { return "rain"; }
    if "fog" in value or "haze" in value or "smoke" in value or "mist" in value { return "fog"; }
    if "wind" in value or "breez" in value or "hurricane" in value or "tropical storm" in value { return "wind"; }
    if "sunny" in value and ("partly" in value or "mostly" in value) { return "partly-sunny"; }
    if "cloud" in value or "overcast" in value { return "cloud"; }
    if "sunny" in value { return "sun"; }
    if "clear" in value { return "moon"; }
    return "temperature";
}

def:pub weather_caption(summary: str) -> str {
    value = summary.strip();
    lower = value.lower();
    for prefix in ["slight chance of ", "slight chance ", "chance of ", "chance "] {
        if lower.startswith(prefix) { return value[len(prefix):].capitalize() + " possible"; }
    }
    return value.capitalize();
}

def:pub weather_context(weather: any, targetId: str = "", dayDate: str = "") -> any {
    return [sample for sample in weather["samples"] or [] if (not targetId or sample["targetId"] == targetId or sample["placeId"] == targetId) and (not dayDate or sample["date"] == dayDate)];
}

def:pub weather_condition(sample: any) -> str {
    if sample["forecastSummary"] { return str(sample["forecastSummary"]); }
    return str(sample["summary"] or "") if len(sample["alerts"] or []) == 0 else "";
}

"""Ground-weather cards use the actual airport code; the full name stays accessible."""
def:pub weather_place_caption(sample: any) -> str {
    label = str(sample["label"] or "Weather");
    if sample["role"] in ["DEPARTURE_GROUND", "ARRIVAL_GROUND"] {
        candidates: any = [str(sample["airportCode"] or ""), str(sample["iata"] or ""), str(sample["placeId"] or "")];
        if label.endswith(")") and "(" in label { candidates.append(label[label.rfind("(") + 1:-1]); }
        for code in candidates {
            valid = len(code) == 3;
            for character in code { if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { valid = False; } }
            if valid { return str(code); }
        }
    }
    return label;
}

def:pub weather_forecasts(samples: any, targetId: str = "") -> any {
    candidates: any = [];
    for sample in samples {
        facts = weather_condition(sample) or Number.isFinite(sample["temperature"]) or Number.isFinite(sample["precipitation"]) or sample["wind"];
        if facts and (sample["forecastAvailable"] or sample["forecastSummary"] or (sample["status"] == "READY" and len(sample["alerts"] or []) == 0)) { candidates.append(sample); }
    }
    if not targetId {
        anchors: any = [sample for sample in candidates if sample["role"] in ["BASE", "DAY", "DEPARTURE_GROUND", "ARRIVAL_GROUND", "DEPARTURE", "ARRIVAL"]];
        if len(anchors) > 0 { candidates = anchors; }
    }
    seen: any = [];
    rows: any = [];
    for sample in candidates {
        key = str(sample["placeId"] or sample["label"] or sample["id"]) + "|" + str(sample["date"] or "");
        if targetId { key += "|" + str(sample["role"] or ""); }
        if key not in seen { seen.append(key); rows.append(sample); }
    }
    return sorted(rows, key=lambda (sample: any) -> str { return str(sample["date"] or "") + str(sample["start"] or "") + str(sample["label"] or ""); });
}

"""One official event can cover many trip samples; present it once."""
def:pub weather_warnings(samples: any) -> any {
    rows: any = [];
    for sample in samples {
        for alert in sample["alerts"] or [] {
            key = str(alert["id"] or (str(sample["id"]) + str(alert["event"])));
            found: any = None;
            for row in rows { if row["id"] == key { found = row; } }
            if not found {
                found = {"id": key, "alert": alert, "labels": [], "dates": []};
                rows.append(found);
            }
            if sample["label"] and sample["label"] not in found["labels"] { found["labels"].append(sample["label"]); }
            if sample["date"] and sample["date"] not in found["dates"] { found["dates"].append(sample["date"]); }
        }
    }
    return rows;
}

"""Local SVG weather symbols remain available with the offline itinerary."""
def:pub WeatherGlyph(kind: str, size: int = 30) -> JsxElement {
    return <svg className={"studio-weather-glyph is-" + kind} data-weather-icon={kind} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
        {if kind in ["sun", "partly-sunny"] { <><circle cx={"12" if kind == "sun" else "8"} cy={"12" if kind == "sun" else "8"} r={"4" if kind == "sun" else "3"}/>{if kind == "sun" { <path d="M12 2v2m0 16v2M2 12h2m16 0h2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/> } else { <><path d="M8 1v1M1 8h1m1.1-4.9.8.8M13 3l-.8.8"/><path d="M7 18h11a4 4 0 0 0 .2-8 5 5 0 0 0-9.5 1A3.5 3.5 0 1 0 7 18Z"/></> }}</> }
        elif kind == "moon" { <path d="M20.8 13.3A8.5 8.5 0 0 1 10.7 3.2 8.5 8.5 0 1 0 20.8 13.3Z"/> }
        elif kind in ["cloud", "rain", "snow", "ice", "storm", "fog"] { <><path d="M6.5 16h11.7a4.3 4.3 0 0 0 .3-8.6 6 6 0 0 0-11.4 1.2A3.7 3.7 0 1 0 6.5 16Z"/>{if kind == "rain" { <path d="m8 19-1 2m6-2-1 2m6-2-1 2"/> } elif kind == "storm" { <path d="m13 15-3 4h4l-3 4"/> } elif kind == "snow" { <path d="M8 19v4m-1.7-3 3.4 2m0-2-3.4 2M17 19v4m-1.7-3 3.4 2m0-2-3.4 2"/> } elif kind == "ice" { <><path d="m8 19-1 2m7-2-1 2"/><circle cx="18" cy="21" r="1"/></> } elif kind == "fog" { <path d="M3 19h18M5 22h14"/> }}</> }
        elif kind == "wind" { <path d="M3 8h12a3 3 0 1 0-3-3M3 12h16a3 3 0 1 1-3 3M3 16h6a3 3 0 1 1-3 3"/> }
        elif kind == "drop" { <path d="M12 3c-3 4-6 7-6 11a6 6 0 0 0 12 0c0-4-3-7-6-11Z"/> }
        elif kind == "alert" { <><path d="m10.3 4-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-3l-8-14a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4m0 4h.01"/></> }
        elif kind == "chevron" { <path d="m8 10 4 4 4-4"/> }
        elif kind == "later" { <><path d="M6 17a4 4 0 0 1 0-8 6 6 0 0 1 11-2"/><circle cx="16" cy="16" r="6"/><path d="M16 12v4l2 1"/></> }
        else { <><path d="M9 14.5V5a3 3 0 0 1 6 0v9.5a5 5 0 1 1-6 0Z"/><path d="M12 8v10"/></> }}
    </svg>;
}

def:pub WeatherTile(sample: any, showRole: bool = False, showDate: bool = True) -> JsxElement {
    condition = weather_condition(sample);
    role = str(sample["role"] or "");
    label = "Departure" if role in ["DEPARTURE_GROUND", "DEPARTURE"] else "Arrival" if role in ["ARRIVAL_GROUND", "ARRIVAL"] else "";
    return <article className="studio-weather-tile" aria-label={"Weather at " + str(sample["label"] or "this location")}>
        <div className="studio-weather-place"><strong title={str(sample["label"] or "")}>{weather_place_caption(sample)}</strong>{if showDate and sample["date"] { <span>{date_label(str(sample["date"]))}</span> }}</div>
        {if showRole and label { <span className="studio-weather-role">{label}</span> }}
        <div className="studio-weather-current"><WeatherGlyph kind={weather_kind(condition)}/><div className="studio-weather-reading">{if Number.isFinite(sample["temperature"]) { <strong>{str(sample["temperature"])}<span>{"°" + str(sample["temperatureUnit"] or "")}</span></strong> }}{if condition { <p title={condition}>{weather_caption(condition)}</p> }}</div></div>
        {if Number.isFinite(sample["precipitation"]) or sample["wind"] { <div className="studio-weather-metrics">{if Number.isFinite(sample["precipitation"]) and sample["precipitation"] >= 0 and sample["precipitation"] <= 100 { <span aria-label={str(sample["precipitation"]) + " percent chance of precipitation"}><WeatherGlyph kind="drop" size={13}/>{str(sample["precipitation"]) + "%"}</span> }}{if sample["wind"] { <span aria-label={"Wind " + str(sample["wind"])}><WeatherGlyph kind="wind" size={14}/>{str(sample["wind"])}</span> }}</div> }}
    </article>;
}

def:pub WeatherWarning(warning: any) -> JsxElement {
    alert = warning["alert"];
    places = warning["labels"];
    dates: any = sorted(warning["dates"]);
    where = str(places[0]) if len(places) > 0 else "Your trip";
    if len(places) > 1 { where += " +" + str(len(places) - 1) + " places"; }
    when = date_label(str(dates[0])) if len(dates) > 0 else "";
    if len(dates) > 1 { when += "–" + date_label(str(dates[len(dates) - 1])); }
    high = alert["severity"] in ["Severe", "Extreme"] or str(alert["event"] or "").lower().endswith("warning");
    return <details className={"studio-weather-alert" + (" is-high" if high else "")}>
        <summary><WeatherGlyph kind="alert" size={18}/><span><strong>{str(alert["event"] or "Weather alert")}</strong><small>{where + (" · " + when if when else "")}</small></span><WeatherGlyph kind="chevron" size={16}/></summary>
        <div className="studio-weather-alert-body">{if alert["headline"] { <p>{str(alert["headline"])}</p> }}{if alert["instruction"] { <p className="studio-weather-instruction">{str(alert["instruction"])}</p> }}{if alert["description"] { <details className="studio-weather-bulletin"><summary>Full advisory</summary><p>{str(alert["description"])}</p></details> }}</div>
    </details>;
}

def:pub StudioWeather(weather: any, targetId: str = "", dayDate: str = "") -> JsxElement {
    if not weather or weather["status"] == "LOADING" { return <></>; }
    samples = weather_context(weather, targetId, dayDate);
    if len(samples) == 0 and (targetId or dayDate or weather["status"] != "FUTURE") { return <></>; }
    warnings = weather_warnings(samples);
    forecasts = weather_forecasts(samples, targetId);
    later = weather["status"] == "FUTURE" or (len(samples) > 0 and len([sample for sample in samples if sample["status"] == "FUTURE"]) == len(samples));
    return <section className="studio-weather" aria-label="Trip weather">
        {for warning in warnings { <WeatherWarning warning={warning} key={warning["id"]}/> }}
        {if len(forecasts) > 0 { <><div className="studio-weather-strip">{for sample in forecasts[:4] { <WeatherTile key={sample["id"]} sample={sample} showRole={bool(targetId)} showDate={not bool(dayDate)}/> }}</div>{if len(forecasts) > 4 { <details className="studio-weather-more"><summary>{"+" + str(len(forecasts) - 4) + " more forecasts"}<WeatherGlyph kind="chevron" size={14}/></summary><div className="studio-weather-strip">{for sample in forecasts[4:] { <WeatherTile key={sample["id"]} sample={sample} showRole={bool(targetId)} showDate={not bool(dayDate)}/> }}</div></details> }}</> }
        elif len(warnings) == 0 { <p className="studio-weather-availability"><WeatherGlyph kind="later" size={18}/>{"Forecast closer to departure" if later else "Forecast not available yet"}</p> }}
    </section>;
}
