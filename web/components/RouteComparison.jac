"""Accessible selection over server-ranked routes; selection never triggers a write."""

import "../comparison.css";
import from "@jac/runtime" { Link }
import from .PageHeading { PageHeading }
import from .EmptyState { EmptyState }
import from .comparison_view { ComparisonRoute, comparison_view }
import from .RouteMap { RouteMap }

def:pub RouteCard(route: ComparisonRoute, index: int, selected: bool, recommended: bool, onSelect: Callable[[str], None]) -> JsxElement {
    return <label className={"dt-route-row" + (" is-selected" if selected else "")} htmlFor={"route-" + str(index)}>
        <input id={"route-" + str(index)} className="dt-route-radio" type="radio" name="route-selection" checked={selected} onChange={lambda (_e: ChangeEvent) { onSelect(route.id); }} aria-labelledby={"route-title-" + str(index)} aria-describedby={"route-summary-" + str(index)}/>
        <span className="dt-route-main">
            <span id={"route-title-" + str(index)} className="dt-route-name">{route.modes} · {route.transfers}{if recommended { <span className="dt-route-recommended"> · Recommended</span> }}</span>
            <span id={"route-summary-" + str(index)} className="dt-muted">{route.departure} – {route.arrival} · {route.duration}</span>
        </span>
        <strong className="dt-route-price">{route.price}</strong>
    </label>;
}

"""Booking-style summary of the selected route, after Airbnb's reservation card."""
def:pub RecommendationPanel(route: ComparisonRoute, recommended: bool) -> JsxElement {
    return <aside className="dt-booking" aria-labelledby="selection-heading">
        <h2 id="selection-heading" className="dt-booking-price">{route.price}</h2>
        <p className="dt-muted">{route.modes} · {route.transfers} · {route.duration}</p>
        <dl className="dt-booking-box">
            <div><dt>Depart</dt><dd>{route.departure}</dd></div>
            <div><dt>Arrive</dt><dd>{route.arrival}</dd></div>
        </dl>
        <button type="button" className="dt-primary dt-booking-action" disabled={True} aria-describedby="confirm-unavailable">Confirm this plan</button>
        <p id="confirm-unavailable" className="dt-booking-note">Saving plans is coming soon</p>
    </aside>;
}

def:pub RouteComparison(preview: any = None, requestText: str = "", submittedRequest: any = None) -> JsxElement {
    has selectedId: str = "";
    view = comparison_view(preview);
    editRequest: any = submittedRequest if submittedRequest else preview["request"] if preview else None;
    if view.error {
        return <><PageHeading title={"No matching routes yet." if view.error_code == "NO_ROUTES" else "Let’s try that again."} description="Your trip details can be adjusted before another search."/>
            <section className="dt-panel" role="status"><h2>{"Adjust your trip" if view.error_code == "NO_ROUTES" else "Comparison unavailable"}</h2><p>{view.error}</p><Link className="dt-primary" to="/plan" state={{"draft": editRequest, "requestText": requestText}}>Edit trip details</Link></section></>;
    }
    if not view.valid {
        return <><PageHeading title="A plan starts with your trip." description="Once you describe your trip, this is where you’ll compare options and understand the tradeoffs."/>
            <EmptyState title="No trip request to compare yet" message="There is no active planning request in this session. Return to planning to start a new trip." actionLabel="Back to planning" actionPath="/plan"/></>;
    }
    selected = view.routes[0];
    for route in view.routes { if route.id == selectedId { selected = route; } }
    return <>
        <div className="dt-comparison-heading"><PageHeading title={view.title} description={view.date + " · Demo schedules and fares"}/>
            <Link className="dt-secondary" to="/plan" state={{"draft": editRequest, "requestText": requestText}}>Edit request</Link></div>
        <div className="dt-comparison-grid">
            <section aria-labelledby="route-options-heading"><h2 id="route-options-heading" className="dt-sr-only">{str(len(view.routes))} options to compare</h2>
                <fieldset className="dt-route-list"><legend className="dt-sr-only">Choose a route to inspect. Use the arrow keys to move between options.</legend>
                    {for (index, route) in enumerate(view.routes) { <RouteCard key={route.id} route={route} index={index} selected={selected.id == route.id} recommended={index == 0} onSelect={lambda (id: str) { selectedId = id; }}/> }}
                </fieldset>
                <RouteMap stops={selected.stops} label={"Map of the selected route: " + " to ".join([stop.name for stop in selected.stops]) if len(selected.stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
            </section>
            <RecommendationPanel route={selected} recommended={selected.id == view.routes[0].id}/>
        </div>
        <p className="dt-sr-only" role="status" aria-live="polite">Selected {selected.name}. {selected.price}. {selected.duration}.</p>
    </>;
}
