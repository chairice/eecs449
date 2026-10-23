"""Accessible selection over server-ranked routes; selection never triggers a write."""

import "../comparison.css";
import from "@jac/runtime" { Link }
import from .PageHeading { PageHeading }
import from .EmptyState { EmptyState }
import from .comparison_view { ComparisonRoute, comparison_view }
import from .Icon { Icon }
import from .RouteMap { RouteMap }

"""Provenance codes stay uppercase in data; the interface reads sentence case."""
def:pub source_label(source: str) -> str {
    return "Fixture" if source == "FIXTURE" else "Live" if source == "LIVE" else "Cached" if source == "CACHED" else source;
}

def:pub RouteCard(route: ComparisonRoute, index: int, selected: bool, recommended: bool, onSelect: Callable[[str], None]) -> JsxElement {
    return <label className={"dt-route-card" + (" is-selected" if selected else "")} htmlFor={"route-" + str(index)}>
        <input id={"route-" + str(index)} className="dt-route-radio" type="radio" name="route-selection" checked={selected} onChange={lambda (_e: ChangeEvent) { onSelect(route.id); }} aria-labelledby={"route-title-" + str(index)} aria-describedby={"route-summary-" + str(index)}/>
        <span className="dt-route-visual"><Icon name={"tram" if route.legs[0].mode == "Train" else "bus"} size={28}/></span>
        <span className="dt-route-body">
            <span className="dt-route-card-top">
                <span id={"route-title-" + str(index)} className="dt-route-name">{route.modes} · {route.transfers}{if recommended { <span className="dt-sr-only"> · Recommended</span> }}</span>
                {if recommended { <span className="dt-route-badge">Recommended</span> }}
            </span>
            <span className="dt-route-times"><span>{route.departure}</span><span className="dt-route-arrow"><Icon name="arrow.right" size={16}/></span><span>{route.arrival}</span></span>
            <span id={"route-summary-" + str(index)} className="dt-route-metrics"><span>{route.duration} · {route.name}</span><strong>{route.price}</strong></span>
        </span>
    </label>;
}

def:pub RecommendationPanel(route: ComparisonRoute, recommended: bool) -> JsxElement {
    return <aside className="dt-panel dt-recommendation" aria-labelledby="selection-heading">
        <h2 id="selection-heading">{route.modes} · {route.transfers}</h2>
        <p className="dt-muted">{route.name}</p>
        <div className="dt-score-line"><span>Preference score</span><strong>{route.score}<span> / 100</span></strong></div>
        <p>Delay: {route.delay} · Weather: {route.weather} · Connections: {route.transfer_risk}</p>
        <h3>Why this option</h3>
        <ul className="dt-reasons">{for reason in route.reasons { <li key={reason}>{reason}</li> }}</ul>
        <h3>Your journey</h3>
        <ol className="dt-itinerary">{for leg in route.legs {
            <li key={leg.id}><strong>{leg.mode} · {leg.service}</strong><span>{leg.origin} → {leg.destination}</span><span>{leg.departure} — {leg.arrival}</span></li>
        }}</ol>
        <details className="dt-source-details"><summary>Source and freshness</summary>
            <p><strong>{source_label(route.source)}</strong> · {route.freshness}</p>
            <p>{route.provider}</p><p>{"Dataset authored: " if route.source == "FIXTURE" else "Source fetched: "}{route.source_time}</p>
            <ul>{for warning in route.source_warnings { <li key={warning}>{warning}</li> }}</ul>
        </details>
        <button type="button" className="dt-primary dt-confirm-placeholder" disabled={True} aria-describedby="confirm-unavailable">Confirm this plan</button>
        <p id="confirm-unavailable" className="dt-sr-only">Saving plans is coming next. Choosing an option here does not save a trip or book a ticket.</p>
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
        <div className="dt-comparison-heading"><PageHeading title={view.title} description={view.date + " · " + view.preference + " · all times local to each stop"}/>
            <Link className="dt-secondary" to="/plan" state={{"draft": editRequest, "requestText": requestText}}>Edit request</Link></div>
        <p className="dt-notice"><strong>Synthetic demo routes.</strong> Schedules and fares are examples, not live service or ticket availability. Unknown conditions are labeled below.</p>
        <div className="dt-comparison-grid">
            <section aria-labelledby="route-options-heading"><h2 id="route-options-heading" className="dt-options-title">{str(len(view.routes))} options to compare</h2>
                <fieldset className="dt-route-options"><legend className="dt-sr-only">Choose a route to inspect. Use the arrow keys to move between options.</legend>
                    {for (index, route) in enumerate(view.routes) { <RouteCard key={route.id} route={route} index={index} selected={selected.id == route.id} recommended={index == 0} onSelect={lambda (id: str) { selectedId = id; }}/> }}
                </fieldset>
            </section>
            <div className="dt-results-side">
                <RouteMap stops={selected.stops} label={"Map of the selected route: " + " to ".join([stop.name for stop in selected.stops]) if len(selected.stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
                <RecommendationPanel route={selected} recommended={selected.id == view.routes[0].id}/>
            </div>
        </div>
        <p className="dt-sr-only" role="status" aria-live="polite">Selected {selected.name}. {selected.price}. {selected.duration}.</p>
    </>;
}
