"""One visual options workspace; conversation messages link to these results."""
import from ..client.planning_state { date_label, time_label }
import from .Icon { Icon }

def:pub conversation_offers(turn: any, offers: any, fallback: any) -> any {
    if "offerIds" in Object.keys(turn) {
        refs = turn["offerIds"] or [];
        return [offer for offer in offers or [] if offer["id"] in refs];
    }
    return fallback;
}

def:pub option_category(offer: any) -> str {
    category = str(offer["category"] or "");
    return "STAY" if category in ["HOTEL", "STAY"] else category;
}

def:pub offer_group_id(offer: any) -> str {
    query = offer["query"] or {};
    category = option_category(offer);
    ages = [int(age) for age in query["childrenAges"] or []];
    ages.sort();
    if category == "FLIGHT" {
        return str(JSON.stringify([category, query["origin"] or "", query["destination"] or "", query["departDate"] or "", query["returnDate"] or "", query["adults"] or 1, ages]));
    }
    if category == "STAY" {
        return str(JSON.stringify([category, query["location"] or "", query["checkIn"] or "", query["checkOut"] or "", query["adults"] or 1, ages, query["rooms"] or 1]));
    }
    return str(JSON.stringify([category, query["pickupLocation"] or "", query["dropoffLocation"] or "", query["pickupDate"] or "", query["dropoffDate"] or "", query["pickupTime"] or "", query["dropoffTime"] or "", query["driverAge"] or ""]));
}

def:pub offer_groups(offers: any) -> any {
    groups: any = [];
    for offer in offers or [] {
        identifier = offer_group_id(offer);
        found: any = None;
        for group in groups { if group["id"] == identifier { found = group; } }
        if found { found["offers"].append(offer); found["count"] += 1; }
        else {
            query = offer["query"] or {};
            category = option_category(offer);
            label = str(query["origin"] or "Departure") + " → " + str(query["destination"] or "Arrival") if category == "FLIGHT" else str(query["location"] or "Places to stay") if category == "STAY" else str(query["pickupLocation"] or "Car rental");
            first = str(query["departDate"] or "") if category == "FLIGHT" else str(query["checkIn"] or "") if category == "STAY" else str(query["pickupDate"] or "");
            last = str(query["returnDate"] or "") if category == "FLIGHT" else str(query["checkOut"] or "") if category == "STAY" else str(query["dropoffDate"] or "");
            date = date_label(first) + (" – " + date_label(last) if last else "");
            groups.append({"id": identifier, "category": category, "label": label, "date": date, "count": 1, "offers": [offer]});
        }
    }
    return groups;
}

def:pub option_money(amount: int, currency: str) -> str {
    browser: any = window;
    digits = 0 if amount % 100 == 0 else 2;
    options: any = {"minimumFractionDigits": digits, "maximumFractionDigits": 2};
    if currency { options["style"] = "currency"; options["currency"] = currency; }
    return str(browser.Intl.NumberFormat("en-US", options).format(amount / 100));
}

def:pub offer_price(offer: any) -> str {
    price = offer["price"];
    amount = price["amountMinor"] if price else offer["totalMinor"];
    if amount is None or not Number.isFinite(Number(amount)) { return "Price on request"; }
    currency = str((price["currency"] or offer["currency"] or "") if price else offer["currency"] or "");
    return ("From " if price and price["from"] else "") + option_money(int(amount), currency);
}

def:pub offer_basis(offer: any) -> str {
    price = offer["price"];
    if not price { return "total"; }
    if price["basis"] == "PER_NIGHT" { return "per night"; }
    if price["basis"] == "PER_PERSON" { return "per person"; }
    if price["basis"] == "PER_DAY" { return "per day"; }
    return "stay total" if offer["category"] in ["HOTEL", "STAY"] else "total";
}

def:pub option_group_meta(offer: any) -> str {
    query = offer["query"] or {};
    adults = int(query["adults"] or 1);
    party = str(adults) + (" adult" if adults == 1 else " adults");
    children = len(query["childrenAges"] or []);
    if children > 0 { party += " · " + str(children) + (" child" if children == 1 else " children"); }
    if offer["category"] == "FLIGHT" { return ("Round trip" if query["returnDate"] else "One way") + " · " + party; }
    if offer["category"] in ["HOTEL", "STAY"] {
        rooms = int(query["rooms"] or 1);
        return party + " · " + str(rooms) + (" room" if rooms == 1 else " rooms");
    }
    return "Pickup " + time_label(str(query["pickupTime"] or "")) + " · return " + time_label(str(query["dropoffTime"] or "")) + (" · driver " + str(query["driverAge"]) if query["driverAge"] else "");
}

def:pub airline_identity(flight: any) -> any {
    name = str(flight["airline"] or "") if flight else "";
    key = name.lower().strip();
    aliases = {
        "frontier": ["F9", "Frontier"], "frontier airlines": ["F9", "Frontier"],
        "united": ["UA", "United"], "united airlines": ["UA", "United"], "united express": ["UA", "United"],
        "delta": ["DL", "Delta"], "delta air lines": ["DL", "Delta"], "delta airlines": ["DL", "Delta"],
        "american": ["AA", "American"], "american airlines": ["AA", "American"], "american (envoy)": ["AA", "American"], "american (envoy air)": ["AA", "American"], "american eagle": ["AA", "American"],
        "alaska": ["AS", "Alaska"], "alaska airlines": ["AS", "Alaska"],
        "southwest": ["WN", "Southwest"], "southwest airlines": ["WN", "Southwest"],
        "jetblue": ["B6", "JetBlue"], "jetblue airways": ["B6", "JetBlue"],
        "spirit": ["NK", "Spirit"], "spirit airlines": ["NK", "Spirit"],
        "allegiant": ["G4", "Allegiant"], "allegiant air": ["G4", "Allegiant"],
        "sun country": ["SY", "Sun Country"], "sun country airlines": ["SY", "Sun Country"],
        "hawaiian": ["HA", "Hawaiian"], "hawaiian airlines": ["HA", "Hawaiian"],
        "breeze": ["MX", "Breeze"], "breeze airways": ["MX", "Breeze"],
        "avelo": ["XP", "Avelo"], "avelo airlines": ["XP", "Avelo"]
    };
    identity = aliases[key];
    return {"name": str(identity[1]), "logo": "/static/assets/airlines/" + str(identity[0]).lower() + ".png"} if identity else {"name": name, "logo": ""};
}

def:pub AirlineMark(flight: any) -> JsxElement {
    identity = airline_identity(flight);
    has failed: bool = False;
    can with [str(identity["logo"])] entry { failed = False; }
    return <span className="studio-airline-mark" aria-hidden="true">{if identity["logo"] and not failed { <img src={identity["logo"]} alt="" width={32} height={32} onError={lambda { failed = True; }}/> } else { <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/></svg> }}</span>;
}

def:pub FlightIdentity(flight: any, fallback: str = "Flight option") -> JsxElement {
    identity = airline_identity(flight);
    return <div className="studio-airline"><AirlineMark flight={flight}/><span>{str(identity["name"]) or fallback}</span></div>;
}

def:pub flight_day_offset(flight: any) -> str {
    if not flight or not flight["departDate"] or not flight["arriveDate"] { return ""; }
    first: any = new(Date, str(flight["departDate"]) + "T12:00:00Z");
    last: any = new(Date, str(flight["arriveDate"]) + "T12:00:00Z");
    offset = Math.round((last.getTime() - first.getTime()) / 86400000);
    if not Number.isFinite(offset) or offset == 0 { return ""; }
    return ("+" if offset > 0 else "") + str(offset);
}

def:pub flight_duration(flight: any) -> str {
    if not flight or "durationMinutes" not in Object.keys(flight) or flight["durationMinutes"] is None { return ""; }
    minutes = int(flight["durationMinutes"]);
    return (str(Math.floor(minutes / 60)) + "h " if minutes >= 60 else "") + (str(minutes % 60) + "m" if minutes % 60 > 0 else "");
}

def:pub flight_stops(flight: any) -> str {
    if not flight or "stops" not in Object.keys(flight) or flight["stops"] is None { return ""; }
    stops = int(flight["stops"]);
    return "Nonstop" if stops == 0 else str(stops) + (" stop" if stops == 1 else " stops");
}

def:pub FlightSchedule(flight: any, showDates: bool = False) -> JsxElement {
    offset = flight_day_offset(flight);
    return <div className="studio-flight-schedule"><div className="studio-flight-time"><strong aria-label="Departure time">{(time_label(str(flight["departTime"] or "")) or "—") if flight else "—"}</strong>{if showDates and flight and flight["departDate"] { <small>{date_label(str(flight["departDate"]))}</small> }}</div><span className="studio-flight-connector" aria-hidden="true"><span/><Icon name="arrow.right" size={16}/></span><div className="studio-flight-time"><strong aria-label="Arrival time">{(time_label(str(flight["arriveTime"] or "")) or "—") if flight else "—"}{if offset { <sup title={"Arrives " + date_label(str(flight["arriveDate"]))}>{offset}</sup> }}</strong>{if showDates and flight and flight["arriveDate"] { <small>{date_label(str(flight["arriveDate"]))}</small> }}</div></div>;
}

def:pub StudioOffer(offer: any, onContext: Callable[[str, str], None], compact: bool = False, onChoose: any = None, selected: bool = False, busy: bool = False) -> JsxElement {
    flight = offer["flight"];
    price = offer["price"];
    isFlight = offer["category"] == "FLIGHT";
    kind = "flight" if isFlight else "stay" if offer["category"] in ["HOTEL", "STAY"] else "car";
    title = str(offer["title"]);
    return <article className={"studio-offer studio-" + kind + "-offer" + (" is-selected" if selected else "") + (" is-compact" if compact else "")} aria-label={title}>
        {if isFlight { <FlightIdentity flight={flight} fallback={title}/><FlightSchedule flight={flight}/><div className="studio-flight-summary">{if flight_duration(flight) { <strong>{flight_duration(flight)}</strong> }}{if flight_stops(flight) { <small>{flight_stops(flight)}</small> }}</div> } else { <><div className="studio-option-description"><h3>{title}</h3>{if offer["location"] { <p>{str(offer["location"])}</p> }}</div>{if offer["photoUrl"] { <img className="studio-offer-photo" src={offer["photoUrl"]} alt="" loading="lazy"/> }}</> }}
        <div className="studio-option-price"><strong>{offer_price(offer)}</strong><small>{offer_basis(offer)}</small>{if price and price["estimatedTotalMinor"] is not None and price["basis"] in ["PER_NIGHT", "PER_DAY"] { <small className="studio-derived-price">{"≈ " + option_money(int(price["estimatedTotalMinor"]), str(price["currency"])) + " for " + str(price["quantity"]) + (" nights" if price["basis"] == "PER_NIGHT" else " days")}</small> }}</div>
        <div className="studio-option-actions">{if onChoose { <button type="button" className="studio-option-choose" disabled={busy or selected} aria-label={("Selected " if selected else "Choose ") + kind + ": " + title} onClick={lambda { onChoose(str(offer["id"]), title); }}>{if selected { <><Icon name="checkmark" size={15}/><span>Chosen</span></> } else { <span>Choose</span> }}</button> }}<button type="button" className="studio-option-discuss" aria-label={"Ask Detour about " + title} title="Ask about this option" onClick={lambda { onContext(str(offer["id"]), title); }}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-3 3V11.5A8.5 8.5 0 0 1 9.5 3h3a8.5 8.5 0 0 1 8.5 8.5Z"/></svg></button><a className="studio-option-external" href={offer["bookingUrl"] or offer["sourceUrl"]} target="_blank" rel="noopener noreferrer" aria-label={"View " + kind + " on " + str(offer["provider"])} title={("View fare on " if isFlight else "View stay on " if kind == "stay" else "View rental on ") + str(offer["provider"])}><Icon name="arrow.up.right" size={17}/></a></div>
        <details className="studio-offer-details"><summary aria-label={"Details for " + title} title={"More " + kind + " details"}><Icon name="chevron.right" size={17}/></summary><div className="studio-offer-extra">{if offer["details"] { <p>{str(offer["details"])}</p> }}{if isFlight and flight and flight["arriveDate"] and flight_day_offset(flight) { <p>{"Arrives " + date_label(str(flight["arriveDate"])) + " · local time"}</p> }}{if price and price["feesIncluded"] is False { <p>Additional taxes or fees may apply.</p> }}<button type="button" className="studio-offer-ask" onClick={lambda { onContext(str(offer["id"]), title); }}>Ask about this option</button><p>{"Found on " + str(offer["provider"])}</p></div></details>
    </article>;
}

def:pub StudioOptions(offers: any, links: any, onChoose: Callable[[str, str], None], onContext: Callable[[str, str], None], groupId: str, onGroup: Callable[[str], None], selectedOfferIds: any = None, busy: bool = False) -> JsxElement {
    groups = offer_groups(offers);
    active: any = None;
    for group in groups { if group["id"] == groupId { active = group; } }
    if active is None and len(groups) > 0 { active = groups[0]; }
    categories = [category for category in ["FLIGHT", "STAY", "CAR"] if len([group for group in groups if group["category"] == category]) > 0];
    return <section className="studio-options-picker" aria-label="Travel options">
        {if len(categories) > 1 { <div className="studio-option-categories" role="tablist" aria-label="Option type">{for category in categories { <button type="button" role="tab" key={category} aria-selected={active and active["category"] == category} className={"is-active" if active and active["category"] == category else ""} onClick={lambda { for group in groups { if group["category"] == category { onGroup(str(group["id"])); return; } } }}>{"Flights" if category == "FLIGHT" else "Stays" if category == "STAY" else "Cars"}</button> }}</div> }}
        {if active { <><div className="studio-option-groups" role="tablist" aria-label={"Flight legs" if active["category"] == "FLIGHT" else "Search dates and places"}>{for group in groups { if group["category"] == active["category"] { <button type="button" role="tab" key={group["id"]} aria-selected={group["id"] == active["id"]} className={"is-active" if group["id"] == active["id"] else ""} onClick={lambda { onGroup(str(group["id"])); }}><span>{str(group["label"])}</span><small>{str(group["date"])}</small></button> } }}</div><header className="studio-option-group-heading"><h2>{"Choose your flight" if active["category"] == "FLIGHT" else "Find your place to stay" if active["category"] == "STAY" else "Choose your car"}</h2><small>{option_group_meta(active["offers"][0])}</small></header><div className="studio-option-list" role="tabpanel" aria-label={str(active["label"]) + " options"}>{for offer in active["offers"] { <StudioOffer key={offer["id"]} offer={offer} onContext={onContext} onChoose={onChoose} selected={offer["id"] in (selectedOfferIds or [])} busy={busy}/> }}</div></> } else { <div className="studio-gentle-empty"><h2>Find something that fits.</h2><p>Tell Detour which flights, stays or cars to look for.</p></div> }}
        {if len(offers or []) == 0 and len(links or []) > 0 { <details className="studio-options-handoffs"><summary>Continue with a travel site</summary>{for link in links { <a key={link["url"]} href={link["url"]} target="_blank" rel="noopener noreferrer">{str(link["label"]) + " ↗"}</a> }}</details> }}
    </section>;
}
