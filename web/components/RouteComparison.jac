"""Accessible selection over server-ranked routes; only Save trip writes, to this browser."""

import "../comparison.css";
import from "@jac/runtime" { Link, useNavigate }
import from react { useRef }
import from .PageHeading { PageHeading }
import from .EmptyState { EmptyState }
import from .comparison_view { ComparisonRoute, comparison_view, provider_label }
import from .RouteMap { RouteMap }
import from .SourceStatus { SourceStatus }
import from ..client.saved_trips { save_trip }
import from ..client.planning_states { PlanningOutcome, data_notices, plan_trip_id, planning_outcome }
import from ..browser { scrollToTop }
import from .Icon { Icon }
import from .RiskBadge { RiskBadge, risk_summary, risk_words }

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

"""Where a route's data came from and how fresh it is, in one line."""
def source_line(route: ComparisonRoute) -> str {
    return "Source: " + provider_label(route.provider) + " · " + route.freshness + " · fetched " + route.source_time;
}

def risk_badge(route: ComparisonRoute) -> str {
    return risk_words(route.delay, route.weather, route.transfer_risk);
}

glob CELL_LABEL: str = "text-xs font-medium tracking-tight text-gray-500";

"""One option as a card: Time, Mode, Risks and Fare side by side, stacked on phones."""
def:pub RouteCard(route: ComparisonRoute, index: int, selected: bool, onSelect: Callable[[str], None], group: str = "route", recommended: bool = False) -> JsxElement {
    key = group + "-" + str(index);
    frame = "border-emerald-600 ring-2 ring-emerald-600/70" if selected else "border-gray-200 hover:border-gray-300";
    return <label className={"relative grid cursor-pointer grid-cols-2 items-start gap-x-4 gap-y-3 rounded-2xl border bg-white p-4 shadow-sm transition-[box-shadow,border-color,scale] duration-200 hover:shadow-md active:scale-98 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-emerald-700 sm:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_minmax(0,1.1fr)_auto] sm:p-5 " + frame} htmlFor={key}>
        <input id={key} className="sr-only" type="radio" name={group + "-selection"} checked={selected} onChange={lambda (_e: ChangeEvent) { onSelect(route.id); }} aria-labelledby={key + "-title"} aria-describedby={key + "-summary"}/>
        <span className="col-span-2 grid gap-0.5 sm:col-span-1">
            <span className={CELL_LABEL}>{("Recommended · " if recommended else "") + (route.day if route.day else "Time")}</span>
            <span id={key + "-title"} className="font-semibold tracking-tight text-gray-900">{clock(route.departure)} – {clock(route.arrival)}</span>
            <span className="text-sm text-gray-500">{travel_time(route.duration)}</span>
        </span>
        <span className="grid gap-0.5">
            <span className={CELL_LABEL}>Mode</span>
            <span className="text-gray-900">{route.modes}</span>
            <span className="text-sm text-gray-500">{route.transfers}</span>
        </span>
        <span className="grid justify-items-start gap-1">
            <span className={CELL_LABEL}>Risks</span>
            <RiskBadge label={risk_badge(route)} detail={risk_line(route)}/>
            {(<span className="text-xs text-gray-500" title={route.weather_note}>{route.weather_brief}</span> if route.weather_brief else None)}
        </span>
        <span className="col-span-2 flex items-baseline justify-between gap-2 border-t border-gray-100 pt-3 sm:col-span-1 sm:grid sm:justify-items-end sm:border-0 sm:pt-0">
            <span className={CELL_LABEL}>Fare</span>
            <strong className="text-lg font-semibold tracking-tight text-gray-900">{route.price.replace(" USD", "")}</strong>
            {(<span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-900">Out of date</span> if "stale" in route.freshness else None)}
        </span>
        <span id={key + "-summary"} className="dt-sr-only">{route.day} {route.departure} to {route.arrival}, {route.modes}, {route.price}, {risk_line(route)}. {route.weather_note} {source_line(route)}.</span>
    </label>;
}

# Sorts a traveler can choose. Risk is left out while it is only a level, not a number.
glob SORTS: list[tuple[str, str]] = [("recommended", "Recommended"), ("price", "Price: low to high"), ("soonest", "Soonest departure"), ("latest", "Latest departure")];

def departure_order(route: ComparisonRoute) -> float {
    return route.departure_ms;
}

def latest_order(route: ComparisonRoute) -> float {
    return -route.departure_ms;
}

"""Unknown fares sort after every known one."""
def price_order(route: ComparisonRoute) -> float {
    return float(route.price_cents) if route.price_cents >= 0 else 1000000000000.0;
}

"""Routes in the chosen order; ties keep the server's ranking."""
def sorted_routes(routes: list[ComparisonRoute], sortKey: str) -> list[ComparisonRoute] {
    if sortKey == "price" { return sorted(routes, key=price_order); }
    if sortKey == "soonest" { return sorted(routes, key=departure_order); }
    if sortKey == "latest" { return sorted(routes, key=latest_order); }
    return routes;
}

def:pub SortBar(value: str, onChange: Callable[[str], None]) -> JsxElement {
    return <div className="mb-6 flex flex-wrap items-center gap-2" role="group" aria-label="Sort routes">
        <span className="mr-1 text-sm text-gray-500">Sort by</span>
        {for option in SORTS {
            <button key={option[0]} type="button" aria-pressed={value == option[0]} onClick={lambda { onChange(option[0]); }}
                className={"inline-flex h-9 cursor-pointer items-center rounded-full border px-4 text-sm font-medium transition-[background-color,border-color,scale] duration-150 active:scale-98 " + ("border-emerald-700 bg-emerald-700 text-white" if value == option[0] else "border-gray-300 bg-white text-gray-700 hover:border-gray-500")}>{option[1]}</button>
        }}
    </div>;
}

"""One direction's options as a stack of cards under a plain heading, in the
order the traveler chose; sorted by departure across several days, they sit
under day headings. The server's top choice is marked Recommended in any order."""
def:pub RouteList(title: str, routes: list[ComparisonRoute], selectedId: str, group: str, onSelect: Callable[[str], None], titleHidden: bool = False, sortKey: str = "recommended", bestId: str = "") -> JsxElement {
    best = bestId if bestId else routes[0].id if len(routes) > 0 else "";
    days: list[str] = [];
    for route in routes { if route.day not in days { days.append(route.day); } }
    ordered = sorted_routes(routes, sortKey);
    spread = len(days) > 1 and sortKey in ["soonest", "latest"];
    return <section className="dt-leg" aria-labelledby={group + "-heading"}>
        <h2 id={group + "-heading"} className={"dt-sr-only" if titleHidden else "dt-leg-title text-sm font-semibold text-gray-900"}>{title}</h2>
        <fieldset className="dt-route-list grid gap-3 overflow-visible rounded-none border-0"><legend className="dt-sr-only">Choose a route. Use the arrow keys to move between options.</legend>
            {for (index, route) in enumerate(ordered) {
                <div key={route.id} className="grid gap-3">
                    {(<h3 className="m-0 mt-3 text-sm font-semibold tracking-tight text-gray-700">{route.day}</h3> if spread and (index == 0 or ordered[index - 1].day != route.day) else None)}
                    <RouteCard route={route} index={index} selected={selectedId == route.id} onSelect={onSelect} group={group} recommended={route.id == best}/>
                </div>
            }}
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
        "risk": risk_badge(route), "risk_detail": risk_line(route), "weather": route.weather_note,
        "levels": {"delay": route.delay, "transfer": route.transfer_risk}, "route": route.weather_legs,
        "stops": [{"name": stop.name, "latitude": stop.latitude, "longitude": stop.longitude} for stop in route.stops],
        "segments": [{"mode": segment.mode, "points": segment.points} for segment in route.segments]};
}

def risk_line(route: ComparisonRoute) -> str {
    return risk_summary(route.delay, route.weather, route.transfer_risk);
}

def:pub RecommendationPanel(route: ComparisonRoute, recommended: bool, returnRoute: ComparisonRoute | None = None, onSave: Callable[[], None] | None = None, saveFailed: bool = False, returnMissing: bool = False, saving: bool = False) -> JsxElement {
    roundTrip = returnRoute is not None;
    return <aside className="dt-booking rounded-2xl border-gray-200 shadow-md" aria-labelledby="selection-heading">
        <h2 id="selection-heading" className="dt-booking-price font-semibold tracking-tight">{booking_total(route, returnRoute)}</h2>
        <p className="dt-muted">{"Round trip" if roundTrip else "Outbound only · no return fits it yet" if returnMissing else "One way"}</p>
        <dl className="dt-booking-box rounded-xl border-gray-300">
            <div><dt>Depart</dt><dd>{route.day}<br/>{route.departure}</dd></div>
            {(<div><dt>Return</dt><dd>{returnRoute.day}<br/>{returnRoute.departure}</dd></div> if returnRoute is not None else <div><dt>Arrive</dt><dd>{route.day}<br/>{route.arrival}</dd></div>)}
        </dl>
        <div className="dt-booking-why">
            <h3>{"Why Detour recommends it" if recommended else "About this route"}</h3>
            <ul>{for reason in route.reasons[:2] { <li key={reason}>{reason}</li> }}</ul>
            <p>{risk_line(route)}</p>
            {(<p>{route.weather_note}</p> if route.weather_note else None)}
            <p className="text-xs text-gray-500">{source_line(route)}</p>
            {for warning in route.source_warnings { <p key={warning} className="text-xs text-gray-500">{warning}</p> }}
        </div>
        <button type="button" className="dt-primary dt-booking-action h-12 rounded-xl border-0 bg-linear-to-r from-emerald-600 to-green-700 text-base font-semibold shadow-sm hover:scale-100 active:scale-98" disabled={onSave is None or saving} onClick={lambda { if onSave is not None { onSave(); } }}>{"Saving…" if saving else "Try saving again" if saveFailed else "Save trip"}</button>
        {(<p className="dt-booking-note dt-field-error" role="alert">This browser wouldn't keep the trip. Your selection is still here; check that site data is allowed, then try again.</p> if saveFailed else None)}
    </aside>;
}

"""The search's extras in a few words: "Leave after 4:00 PM · Under $50"."""
def search_extras(request: any) -> str {
    if not request { return "Any time"; }
    parts: list[str] = [];
    time: any = request["local_time"];
    if isinstance(time, str) and time != "" and time != "00:00" {
        parts.append(("Arrive by " if request["time_kind"] == "ARRIVE_BY" else "Leave after ") + clock_words(time));
    }
    cents: any = request["max_price_cents"];
    if isinstance(cents, (int, float)) and not isinstance(cents, bool) {
        whole = int(cents) % 100 == 0;
        parts.append("Under $" + str(int(cents) // 100) if whole else "Under " + money(int(cents)).replace(" USD", ""));
    }
    buffer: any = request["min_transfer_minutes"];
    if isinstance(buffer, (int, float)) and not isinstance(buffer, bool) and buffer != 30 { parts.append(str(buffer) + "+ min connections"); }
    priority: any = request["priority"];
    sort_labels = {"LOWEST_COST": "Cheapest first", "FASTEST": "Fastest first", "FEWEST_TRANSFERS": "Fewest transfers", "MOST_RELIABLE": "Most reliable first"};
    if isinstance(priority, str) and priority in sort_labels { parts.append(sort_labels[priority]); }
    return " · ".join(parts) if len(parts) > 0 else "Any time";
}

def clock_words(time: str) -> str {
    hour = int(time.split(":")[0]);
    return str(12 if hour % 12 == 0 else hour % 12) + ":" + time.split(":")[1] + (" AM" if hour < 12 else " PM");
}

"""A conversational heading, as Airbnb's AI search titles its results: "on" a
day for departures, "by" the deadline for arrivals, which may span several days."""
def results_heading(count: int, destination: str, day: str, timeKind: str = "", time: str = "") -> str {
    city = destination.split(",")[0];
    when = "by " + day + ", " + clock_words(time) if timeKind == "ARRIVE_BY" and ":" in time else "on " + day;
    return ("1 way" if count == 1 else str(count) + " ways") + " to get to " + city + " " + when;
}

"""A search that ended without routes to compare. No routes (the constraints
removed every candidate) reads calmly as a status; a provider failure or an
unreadable result is an alert with a retry. Both keep the request for editing."""
def:pub PlanningStateMessage(outcome: PlanningOutcome, editState: any, onRetry: Callable[[], None] | None = None) -> JsxElement {
    failed = outcome.role == "alert";
    frame = "border-red-300 bg-red-50" if failed else "border-gray-200 bg-white";
    return <section className={"dt-panel rounded-2xl border p-5 shadow-sm " + frame} role={outcome.role} aria-labelledby="planning-state-heading" data-state={outcome.kind}>
        <h2 id="planning-state-heading" className="flex items-center gap-2 text-xl font-semibold tracking-tight text-gray-900">
            <Icon name={"exclamationmark.triangle" if failed else "magnifyingglass"} size={20}/><span>{outcome.title}</span>
        </h2>
        <p className="dt-muted">{outcome.message}</p>
        {(<ul className="mt-2 grid gap-1 pl-5 text-sm text-gray-700">{for line in outcome.details { <li key={line}>{line}</li> }}</ul> if len(outcome.details) > 0 else None)}
        <div className="mt-4 flex flex-wrap gap-3">
            {(<button type="button" className="dt-primary bg-linear-to-r from-emerald-600 to-green-700 font-semibold shadow-sm active:scale-98" onClick={lambda { onRetry(); }}>Try again</button> if outcome.retry and onRetry is not None else None)}
            <Link className={"inline-flex h-11 items-center rounded-full border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700" if outcome.retry and onRetry is not None else "dt-primary"} to="/plan" state={editState}>Edit trip details</Link>
        </div>
    </section>;
}

def:pub RouteComparison(preview: any = None, requestText: str = "", submittedRequest: any = None, returnPreview: any = None, returnRequested: bool = False, returnDate: str = "", readBy: str = "", returnFailed: bool = False) -> JsxElement {
    has selectedId: str = "", returnSelectedId: str = "", mapLeg: str = "outbound", saveFailed: bool = False, sortKey: str = "recommended", saving: bool = False;
    # Guards the synchronous save against a second click before React re-renders.
    savingRef = useRef(False);
    navigate = useNavigate();
    view = comparison_view(preview);
    editRequest: any = submittedRequest if submittedRequest else preview["request"] if preview else None;
    editState = {"draft": editRequest, "returnDate": returnDate, "requestText": requestText};
    # Search again from /plan with the same request, so the traveler sees honest progress.
    def retrySearch {
        navigate("/plan", {"state": {"draft": editRequest, "returnDate": returnDate, "requestText": requestText, "retry": True}});
    }
    outcome = planning_outcome(view);
    if outcome.kind == "empty" {
        return <><PageHeading title="A plan starts with your trip." description="Once you describe your trip, this is where you’ll compare options and understand the tradeoffs."/>
            <EmptyState title={outcome.title} message={outcome.message} actionLabel="Back to planning" actionPath="/plan"/></>;
    }
    if outcome.kind != "ready" {
        heading = "No matching routes yet." if outcome.kind == "no_routes" else "We couldn’t check routes." if outcome.kind == "provider_error" else "Let’s try that again.";
        return <><PageHeading title={heading} description="Your trip details are kept and can be adjusted before another search."/>
            <PlanningStateMessage outcome={outcome} editState={editState} onRetry={retrySearch if editRequest else None}/></>;
    }
    notices = data_notices(view);
    returnView = comparison_view(returnPreview);
    # The return search failing is not the same as no return fitting.
    returnUnchecked = returnRequested and (returnFailed or returnPreview is None or not returnView.valid or (bool(returnView.error) and returnView.error_code != "NO_ROUTES"));
    returnRoutes = returnView.routes if returnView.valid and not returnView.error else [];
    # For a round trip, the best outbound is the top-ranked one some return can follow.
    best = view.routes[0];
    if returnRequested {
        for route in view.routes {
            if `any([back.departure_ms >= route.arrival_ms for back in returnRoutes]) {
                best = route;
                break;
            }
        }
    }
    selected = best;
    for route in view.routes { if route.id == selectedId { selected = route; } }
    # Only returns that leave after the chosen outbound arrives can complete the trip.
    eligible = [route for route in returnRoutes if route.departure_ms >= selected.arrival_ms];
    hidden = len(returnRoutes) - len(eligible);
    returnSelected: ComparisonRoute | None = eligible[0] if len(eligible) > 0 else None;
    for route in eligible { if route.id == returnSelectedId { returnSelected = route; } }
    incomplete = returnRequested and returnSelected is None;
    mapped = returnSelected if mapLeg == "return" and returnSelected is not None else selected;
    days = trip_day(view.date) + (" – " + trip_day(returnDate) if returnRequested and returnDate else "");
    # A saved trip is dated by the route chosen, which an arrive-by search may place days early.
    travel_days = trip_day(selected.date_iso if selected.date_iso else view.date) + (" – " + trip_day(returnDate) if returnRequested and returnDate else "");
    def saveTrip {
        if savingRef.current { return; }
        savingRef.current = True;
        saving = True;
        legs = [saved_leg("Outbound", selected)];
        if returnRequested and returnSelected is not None { legs.append(saved_leg("Return", returnSelected)); }
        now: any = new(Date);
        # The same plan always gets the same ID, so saving it again replaces it.
        tripId = plan_trip_id([view.title, travel_days, selected.id, returnSelected.id if returnRequested and returnSelected is not None else ""]);
        trip = {"id": tripId, "title": view.title, "days": travel_days, "start_date": selected.date_iso if selected.date_iso else view.date, "total": booking_total(selected, returnSelected if returnRequested else None),
            "saved_at": str(now.toISOString()), "legs": legs};
        if save_trip(trip) {
            navigate("/trips");
            scrollToTop();
        } else {
            # Keep the selection; the button becomes Try saving again.
            savingRef.current = False;
            saving = False;
            saveFailed = True;
        }
    }
    return <>
        <Link className="dt-search-summary" to="/plan" state={editState} aria-label={"Edit search: " + view.title + ", " + days + ", " + search_extras(editRequest)}>
            <span>{view.title}</span><span>{days}</span><span>{search_extras(editRequest)}</span>
            <span className="dt-search-summary-icon" aria-hidden="true"><Icon name="magnifyingglass" size={16}/></span>
        </Link>
        <div className="dt-comparison-heading"><PageHeading title={results_heading(len(view.routes), view.title.split(" → ")[1] if " → " in view.title else view.title, trip_day(view.date), view.time_kind, view.local_time)}
            description={("“" + requestText + "” · " + ("Read by Claude" if readBy == "claude" else "Read by Detour's built-in parser")) if requestText != "" and readBy != "" else "Demo schedules and fares"}/></div>
        <SourceStatus sources={view.sources} notices={notices} onRetry={retrySearch if editRequest else None}/>
        {(<SortBar value={sortKey} onChange={lambda (key: str) { sortKey = key; }}/> if len(view.routes) > 1 or len(returnRoutes) > 1 else None)}
        <div className="dt-comparison-grid">
            <div className="dt-legs">
                {(<RouteList title="1. Choose your outbound" routes={view.routes} selectedId={selected.id} group="outbound" sortKey={sortKey} bestId={best.id} onSelect={lambda (id: str) { selectedId = id; mapLeg = "outbound"; }}/> if returnRequested else
                  <RouteList title={str(len(view.routes)) + " options"} routes={view.routes} selectedId={selected.id} group="route" sortKey={sortKey} onSelect={lambda (id: str) { selectedId = id; }} titleHidden={True}/>)}
                {(<RouteList title="2. Choose your return" routes={eligible} selectedId={returnSelected.id} group="return" sortKey={sortKey} onSelect={lambda (id: str) { returnSelectedId = id; mapLeg = "return"; }}/> if returnRequested and returnSelected is not None else None)}
                {(<p className="m-0 -mt-2 text-sm text-gray-500" role="status">{str(hidden) + (" return leaves" if hidden == 1 else " returns leave") + " before your outbound arrives (" + selected.arrives + ") and " + ("is" if hidden == 1 else "are") + " hidden."}</p> if returnRequested and returnSelected is not None and hidden > 0 else None)}
                {(<section className="dt-leg" role="status"><h2 className="dt-leg-title">2. Choose your return</h2><p className="dt-muted">Return routes couldn't be checked, so this is not a no-routes result. The outbound options above are still usable.</p><button type="button" className="mt-2 inline-flex h-11 cursor-pointer items-center rounded-full border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700 hover:border-gray-500" onClick={lambda { retrySearch(); }}>Check again</button></section> if returnUnchecked and editRequest else None)}
                {(<section className="dt-leg" role="status"><h2 className="dt-leg-title">2. Choose your return</h2><p className="dt-muted">{"No return routes for this day. Try another return date." if len(returnRoutes) == 0 else "No return leaves after this outbound arrives (" + selected.arrives + "). Pick an earlier outbound, or search another return date."}</p></section> if incomplete and returnDate and not returnUnchecked else None)}
                <RouteMap stops={mapped.stops} segments={mapped.segments} label={"Map of the selected route: " + " to ".join([stop.name for stop in mapped.stops]) if len(mapped.stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
            </div>
            <RecommendationPanel route={selected} recommended={selected.id == best.id} returnRoute={returnSelected if returnRequested else None} onSave={None if incomplete else saveTrip} saveFailed={saveFailed} returnMissing={incomplete} saving={saving}/>
        </div>
        <p className="dt-sr-only" role="status" aria-live="polite">Selected {mapped.name}. {mapped.price}. {mapped.duration}.</p>
    </>;
}
