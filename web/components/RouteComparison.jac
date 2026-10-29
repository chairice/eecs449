"""Accessible selection over server-ranked routes; only Save trip writes, to this browser."""

import "../comparison.css";
import from "@jac/runtime" { Link, useNavigate }
import from .PageHeading { PageHeading }
import from .EmptyState { EmptyState }
import from .comparison_view { ComparisonRoute, comparison_view }
import from .RouteMap { RouteMap }
import from ..client.saved_trips { new_trip_id, save_trip }
import from .Icon { Icon }

"""Fri, Oct 23 from an ISO day, read at UTC noon so it never slips across zones."""
def trip_day(iso: str) -> str {
    noon: any = new(Date, iso + "T12:00:00Z");
    return str(noon.toLocaleDateString("en-US", {"weekday": "short", "month": "short", "day": "numeric", "timeZone": "UTC"}));
}

def money(cents: int) -> str {
    remainder = cents % 100;
    return "$" + str(cents // 100) + "." + ("0" if remainder < 10 else "") + str(remainder) + " USD";
}

"""Clock time without its zone: "6:00 PM EDT" reads as "6:00 PM"."""
def clock(label: str) -> str {
    return " ".join(label.split(" ")[:2]);
}

"""Travel time as people say it: "5h 30m" as "5 hr 30 min", "6h 0m" as "6 hr"."""
def travel_time(duration: str) -> str {
    parts = duration.split(" ");
    hours = parts[0].replace("h", "");
    minutes = parts[1].replace("m", "") if len(parts) > 1 else "0";
    return hours + " hr" + ("" if minutes == "0" else " " + minutes + " min");
}

def:pub RouteCard(route: ComparisonRoute, index: int, selected: bool, onSelect: Callable[[str], None], group: str = "route") -> JsxElement {
    key = group + "-" + str(index);
    return <label className={"dt-route-row" + (" is-selected" if selected else "")} htmlFor={key}>
        <input id={key} className="dt-route-radio" type="radio" name={group + "-selection"} checked={selected} onChange={lambda (_e: ChangeEvent) { onSelect(route.id); }} aria-labelledby={key + "-title"} aria-describedby={key + "-summary"}/>
        <span className="dt-route-main">
            <span id={key + "-title"} className="dt-route-times">{clock(route.departure)} – {clock(route.arrival)}</span>
            <span className="dt-muted">{route.modes}</span>
        </span>
        <span className="dt-route-duration">{travel_time(route.duration)}</span>
        <strong className="dt-route-price">{route.price}</strong>
        <span id={key + "-summary"} className="dt-sr-only">{route.departure} to {route.arrival}, {route.price}</span>
    </label>;
}

"""One direction's options as a hairline-divided list under a plain heading."""
def:pub RouteList(title: str, routes: list[ComparisonRoute], selectedId: str, group: str, onSelect: Callable[[str], None], titleHidden: bool = False) -> JsxElement {
    return <section className="dt-leg" aria-labelledby={group + "-heading"}>
        <h2 id={group + "-heading"} className={"dt-sr-only" if titleHidden else "dt-leg-title"}>{title}</h2>
        <fieldset className="dt-route-list"><legend className="dt-sr-only">Choose a route. Use the arrow keys to move between options.</legend>
            {for (index, route) in enumerate(routes) { <RouteCard key={route.id} route={route} index={index} selected={selectedId == route.id} onSelect={onSelect} group={group}/> }}
        </fieldset>
    </section>;
}

"""Booking-style summary, after Airbnb's reservation card: one way, or both legs and their total."""
def booking_total(route: ComparisonRoute, returnRoute: ComparisonRoute | None) -> str {
    if returnRoute is None { return route.price; }
    if route.price_cents < 0 or returnRoute.price_cents < 0 { return "Fare unavailable"; }
    return money(route.price_cents + returnRoute.price_cents);
}

"""What Trips shows for one direction, in the same words as the results rows."""
def saved_leg(label: str, route: ComparisonRoute) -> dict[str, any] {
    return {"label": label, "modes": route.modes, "departure": clock(route.departure), "arrival": clock(route.arrival),
        "duration": travel_time(route.duration), "price": route.price,
        "stops": [{"name": stop.name, "latitude": stop.latitude, "longitude": stop.longitude} for stop in route.stops]};
}

"""Risk in plain words: "Unknown" reads as "unknown", the rest as a level."""
def risk_line(route: ComparisonRoute) -> str {
    return "Delay " + route.delay.lower() + " · Weather " + route.weather.lower() + " · Connection risk " + route.transfer_risk.lower();
}

def:pub RecommendationPanel(route: ComparisonRoute, recommended: bool, returnRoute: ComparisonRoute | None = None, onSave: Callable[[], None] | None = None, saveFailed: bool = False) -> JsxElement {
    roundTrip = returnRoute is not None;
    return <aside className="dt-booking" aria-labelledby="selection-heading">
        <h2 id="selection-heading" className="dt-booking-price">{booking_total(route, returnRoute)}</h2>
        <p className="dt-muted">{"Round trip" if roundTrip else "One way"}</p>
        <dl className="dt-booking-box">
            <div><dt>Depart</dt><dd>{route.departure}</dd></div>
            {(<div><dt>Return</dt><dd>{returnRoute.departure}</dd></div> if returnRoute is not None else <div><dt>Arrive</dt><dd>{route.arrival}</dd></div>)}
        </dl>
        <div className="dt-booking-why">
            <h3>{"Why Detour recommends it" if recommended else "About this route"}</h3>
            <ul>{for reason in route.reasons[:2] { <li key={reason}>{reason}</li> }}</ul>
            <p>{risk_line(route)}</p>
        </div>
        <button type="button" className="dt-primary dt-booking-action" disabled={onSave is None} onClick={lambda { if onSave is not None { onSave(); } }}>Save trip</button>
        {(<p className="dt-booking-note dt-field-error" role="alert">This browser wouldn't keep the trip. Check that site data is allowed.</p> if saveFailed else None)}
    </aside>;
}

"""The search's extras in a few words: "Leave after 4:00 PM · Under $50"."""
def search_extras(request: any) -> str {
    if not request { return "Any time"; }
    parts: list[str] = [];
    time: any = request["local_time"];
    if isinstance(time, str) and time != "" and time != "00:00" {
        hour = int(time.split(":")[0]);
        clock_text = str(12 if hour % 12 == 0 else hour % 12) + ":" + time.split(":")[1] + (" AM" if hour < 12 else " PM");
        parts.append(("Arrive by " if request["time_kind"] == "ARRIVE_BY" else "Leave after ") + clock_text);
    }
    cents: any = request["max_price_cents"];
    if isinstance(cents, (int, float)) and not isinstance(cents, bool) {
        whole = int(cents) % 100 == 0;
        parts.append("Under $" + str(int(cents) // 100) if whole else "Under " + money(int(cents)).replace(" USD", ""));
    }
    buffer: any = request["min_transfer_minutes"];
    if isinstance(buffer, (int, float)) and not isinstance(buffer, bool) and buffer != 30 { parts.append(str(buffer) + "+ min connections"); }
    return " · ".join(parts) if len(parts) > 0 else "Any time";
}

"""A conversational heading, as Airbnb's AI search titles its results."""
def results_heading(count: int, destination: str, day: str) -> str {
    city = destination.split(",")[0];
    return ("1 way" if count == 1 else str(count) + " ways") + " to get to " + city + " on " + day;
}

def:pub RouteComparison(preview: any = None, requestText: str = "", submittedRequest: any = None, returnPreview: any = None, returnRequested: bool = False, returnDate: str = "", readBy: str = "") -> JsxElement {
    has selectedId: str = "", returnSelectedId: str = "", mapLeg: str = "outbound", saveFailed: bool = False;
    navigate = useNavigate();
    view = comparison_view(preview);
    editRequest: any = submittedRequest if submittedRequest else preview["request"] if preview else None;
    editState = {"draft": editRequest, "returnDate": returnDate, "requestText": requestText};
    if view.error {
        return <><PageHeading title={"No matching routes yet." if view.error_code == "NO_ROUTES" else "Let’s try that again."} description="Your trip details can be adjusted before another search."/>
            <section className="dt-panel" role="status"><h2>{"Adjust your trip" if view.error_code == "NO_ROUTES" else "Comparison unavailable"}</h2><p>{view.error}</p><Link className="dt-primary" to="/plan" state={editState}>Edit trip details</Link></section></>;
    }
    if not view.valid {
        return <><PageHeading title="A plan starts with your trip." description="Once you describe your trip, this is where you’ll compare options and understand the tradeoffs."/>
            <EmptyState title="No trip request to compare yet" message="There is no active planning request in this session. Return to planning to start a new trip." actionLabel="Back to planning" actionPath="/plan"/></>;
    }
    selected = view.routes[0];
    for route in view.routes { if route.id == selectedId { selected = route; } }
    returnView = comparison_view(returnPreview);
    returnRoutes = returnView.routes if returnView.valid and not returnView.error else [];
    returnSelected: ComparisonRoute | None = returnRoutes[0] if len(returnRoutes) > 0 else None;
    for route in returnRoutes { if route.id == returnSelectedId { returnSelected = route; } }
    mapped = returnSelected if mapLeg == "return" and returnSelected is not None else selected;
    days = trip_day(view.date) + (" – " + trip_day(returnDate) if returnRequested and returnDate else "");
    def saveTrip {
        legs = [saved_leg("Outbound", selected)];
        if returnRequested and returnSelected is not None { legs.append(saved_leg("Return", returnSelected)); }
        now: any = new(Date);
        trip = {"id": new_trip_id(), "title": view.title, "days": days, "start_date": view.date, "total": booking_total(selected, returnSelected if returnRequested else None),
            "saved_at": str(now.toISOString()), "legs": legs};
        if save_trip(trip) { navigate("/trips"); } else { saveFailed = True; }
    }
    return <>
        <Link className="dt-search-summary" to="/plan" state={editState} aria-label={"Edit search: " + view.title + ", " + days + ", " + search_extras(editRequest)}>
            <span>{view.title}</span><span>{days}</span><span>{search_extras(editRequest)}</span>
            <span className="dt-search-summary-icon" aria-hidden="true"><Icon name="magnifyingglass" size={16}/></span>
        </Link>
        <div className="dt-comparison-heading"><PageHeading title={results_heading(len(view.routes), view.title.split(" → ")[1] if " → " in view.title else view.title, trip_day(view.date))}
            description={("“" + requestText + "” · " + ("Read by Claude" if readBy == "claude" else "Read by Detour's built-in parser")) if requestText != "" and readBy != "" else "Demo schedules and fares"}/></div>
        <div className="dt-comparison-grid">
            <div className="dt-legs">
                {(<RouteList title="Outbound" routes={view.routes} selectedId={selected.id} group="outbound" onSelect={lambda (id: str) { selectedId = id; mapLeg = "outbound"; }}/> if returnRequested else
                  <RouteList title={str(len(view.routes)) + " options"} routes={view.routes} selectedId={selected.id} group="route" onSelect={lambda (id: str) { selectedId = id; }} titleHidden={True}/>)}
                {(<RouteList title="Return" routes={returnRoutes} selectedId={returnSelected.id} group="return" onSelect={lambda (id: str) { returnSelectedId = id; mapLeg = "return"; }}/> if returnRequested and returnSelected is not None else None)}
                {(<section className="dt-leg" role="status"><h2 className="dt-leg-title">Return</h2><p className="dt-muted">No return routes for this day. Try another return date.</p></section> if returnRequested and returnSelected is None and returnDate else None)}
                <RouteMap stops={mapped.stops} label={"Map of the selected route: " + " to ".join([stop.name for stop in mapped.stops]) if len(mapped.stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
            </div>
            <RecommendationPanel route={selected} recommended={selected.id == view.routes[0].id} returnRoute={returnSelected if returnRequested else None} onSave={saveTrip} saveFailed={saveFailed}/>
        </div>
        <p className="dt-sr-only" role="status" aria-live="polite">Selected {mapped.name}. {mapped.price}. {mapped.duration}.</p>
    </>;
}
