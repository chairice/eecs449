"""Accessible selection over server-ranked routes; selection never triggers a write."""

import "../comparison.css";
import from "@jac/runtime" { Link }
import from .PageHeading { PageHeading }
import from .EmptyState { EmptyState }
import from .comparison_view { ComparisonRoute, comparison_view }
import from .RouteMap { RouteMap }

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
            <span className="dt-muted">{route.modes}{"" if route.transfers == "Direct" else " · " + route.transfers}</span>
        </span>
        <span className="dt-route-duration">{travel_time(route.duration)}</span>
        <strong className="dt-route-price">{route.price}</strong>
        <span id={key + "-summary"} className="dt-sr-only">{route.departure} to {route.arrival}, {route.price}</span>
    </label>;
}

"""One direction's options as a hairline-divided list under a plain heading."""
def:pub RouteList(title: str, routes: list[ComparisonRoute], selectedId: str, group: str, onSelect: Callable[[str], None]) -> JsxElement {
    return <section className="dt-leg" aria-labelledby={group + "-heading"}>
        <h2 id={group + "-heading"} className="dt-leg-title">{title}</h2>
        <fieldset className="dt-route-list"><legend className="dt-sr-only">Choose a route. Use the arrow keys to move between options.</legend>
            {for (index, route) in enumerate(routes) { <RouteCard key={route.id} route={route} index={index} selected={selectedId == route.id} onSelect={onSelect} group={group}/> }}
        </fieldset>
    </section>;
}

"""Booking-style summary, after Airbnb's reservation card: one way, or both legs and their total."""
def:pub RecommendationPanel(route: ComparisonRoute, recommended: bool, returnRoute: ComparisonRoute | None = None) -> JsxElement {
    roundTrip = returnRoute is not None;
    total = route.price_cents + returnRoute.price_cents if returnRoute is not None and route.price_cents >= 0 and returnRoute.price_cents >= 0 else -1;
    return <aside className="dt-booking" aria-labelledby="selection-heading">
        <h2 id="selection-heading" className="dt-booking-price">{(money(total) if total >= 0 else "Fare unavailable") if roundTrip else route.price}</h2>
        <p className="dt-muted">{"Round trip" if roundTrip else route.modes + " · " + route.transfers + " · " + route.duration}</p>
        <dl className="dt-booking-box">
            <div><dt>Depart</dt><dd>{route.departure}</dd></div>
            {(<div><dt>Return</dt><dd>{returnRoute.departure}</dd></div> if returnRoute is not None else <div><dt>Arrive</dt><dd>{route.arrival}</dd></div>)}
        </dl>
        <button type="button" className="dt-primary dt-booking-action" disabled={True} aria-describedby="confirm-unavailable">Confirm this plan</button>
        <p id="confirm-unavailable" className="dt-booking-note">Saving plans is coming soon</p>
    </aside>;
}

def:pub RouteComparison(preview: any = None, requestText: str = "", submittedRequest: any = None, returnPreview: any = None, returnRequested: bool = False, returnDate: str = "") -> JsxElement {
    has selectedId: str = "", returnSelectedId: str = "", mapLeg: str = "outbound";
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
    return <>
        <div className="dt-comparison-heading"><PageHeading title={view.title} description={days + " · Demo schedules and fares"}/>
            <Link className="dt-secondary" to="/plan" state={editState}>Edit request</Link></div>
        <div className="dt-comparison-grid">
            <div className="dt-legs">
                {(<RouteList title="Outbound" routes={view.routes} selectedId={selected.id} group="outbound" onSelect={lambda (id: str) { selectedId = id; mapLeg = "outbound"; }}/> if returnRequested else
                  <RouteList title={str(len(view.routes)) + " options"} routes={view.routes} selectedId={selected.id} group="route" onSelect={lambda (id: str) { selectedId = id; }}/>)}
                {(<RouteList title="Return" routes={returnRoutes} selectedId={returnSelected.id} group="return" onSelect={lambda (id: str) { returnSelectedId = id; mapLeg = "return"; }}/> if returnRequested and returnSelected is not None else None)}
                {(<section className="dt-leg" role="status"><h2 className="dt-leg-title">Return</h2><p className="dt-muted">No return routes for this day. Try another return date.</p></section> if returnRequested and returnSelected is None and returnDate else None)}
                <RouteMap stops={mapped.stops} label={"Map of the selected route: " + " to ".join([stop.name for stop in mapped.stops]) if len(mapped.stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
            </div>
            <RecommendationPanel route={selected} recommended={selected.id == view.routes[0].id} returnRoute={returnSelected if returnRequested else None}/>
        </div>
        <p className="dt-sr-only" role="status" aria-live="polite">Selected {mapped.name}. {mapped.price}. {mapped.duration}.</p>
    </>;
}
