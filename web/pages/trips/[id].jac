"""One saved trip: each direction as a route row, its map, and a way to remove it.
On opening, each leg's weather is checked again, so its risk reads as of now;
legs saved before routes were kept, or a failed check, keep the risk from save time."""

import "../../comparison.css";
import "../../trips.css";
import from "react" { useEffect }
import from "@jac/runtime" { Link, useNavigate, useParams }
import from server.api { trip_weather }
import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }
import from ...components.RouteMap { RouteMap }
import from ...components.ConfirmDialog { ConfirmDialog }
import from ...components.RiskBadge { RiskBadge, risk_summary, risk_words }
import from ...components.comparison_view { day_label, risk_label, weather_words }
import from ...components.comparison_view { ComparisonStop, ComparisonSegment }
import from ...client.saved_trips { find_trip, remove_trip, trip_countdown }

"""Stops saved with a leg; anything without numeric coordinates is skipped."""
def leg_stops(leg: any) -> list[ComparisonStop] {
    raw: any = leg["stops"];
    if not Array.isArray(raw) { return []; }
    stops: list[ComparisonStop] = [];
    for stop in raw {
        if stop and isinstance(stop["name"], str) and Number.isFinite(stop["latitude"]) and Number.isFinite(stop["longitude"]) {
            stops.append(ComparisonStop(name=stop["name"], latitude=float(stop["latitude"]), longitude=float(stop["longitude"])));
        }
    }
    return stops;
}

"""Drawn legs saved with a trip; trips saved before paths existed have none,
and any malformed segment drops them all so the map shows pins only."""
def leg_segments(leg: any) -> list[ComparisonSegment] {
    raw: any = leg["segments"];
    if not Array.isArray(raw) { return []; }
    segments: list[ComparisonSegment] = [];
    for segment in raw {
        points: any = segment["points"] if segment else None;
        if not segment or not isinstance(segment["mode"], str) or not Array.isArray(points) or points.length < 2 { return []; }
        for point in points {
            if not Array.isArray(point) or point.length != 2 or not Number.isFinite(point[0]) or not Number.isFinite(point[1]) { return []; }
        }
        segments.append(ComparisonSegment(mode=segment["mode"], points=points));
    }
    return segments;
}

"""A saved leg's risk with today's weather, or None when it can't be checked."""
async def leg_now(leg: any) -> any {
    route: any = leg["route"];
    levels: any = leg["levels"];
    if not Array.isArray(route) or route.length == 0 or not levels { return None; }
    reply: any = None;
    try {
        reply = JSON.parse(await trip_weather(JSON.stringify({"legs": route})));
        if reply["error"] and not reply["weather_from"] { return None; }
        zone = str(route[route.length - 1]["destination"]["timezone"]);
        opens = day_label(str(reply["weather_from"]), zone) if reply["weather_from"] else "";
        weather = "Not yet forecast" if opens else risk_label(reply["weather"]);
        words = weather_words(reply["evidence"], weather, opens);
        return {"risk": risk_words(str(levels["delay"]), weather, str(levels["transfer"])), "detail": risk_summary(str(levels["delay"]), weather, str(levels["transfer"])), "note": words[1]};
    } except Exception {
        return None;
    }
}

def:pub TripDetailPage -> JsxPage {
    params = useParams();
    navigate = useNavigate();
    id: any = params["id"];
    trip: any = find_trip(str(id)) if id else None;
    has fresh: list[any] = [], confirming: bool = False;
    async def refresh {
        if not trip { return; }
        found: list[any] = [];
        for leg in trip["legs"] {
            now: any = None;
            now = await leg_now(leg);
            found.append(now);
        }
        fresh = found;
    }
    # React takes an effect's return as its cleanup, so hand back an empty one,
    # never refresh's promise (Jac's None would be null, which React also rejects).
    useEffect(lambda {
        refresh();
        return lambda { };
    }, [id]);
    if not trip {
        return <>
            <PageHeading title="This trip isn’t available." description="It may have been removed, or saved in another browser."/>
            <EmptyState title="We couldn’t find this trip" message="Go back to your trips, or start a new search." actionLabel="Back to trips" actionPath="/trips"/>
        </>;
    }
    stops = leg_stops(trip["legs"][0]);
    return <>
        <div className="dt-comparison-heading"><PageHeading title={trip["title"]} description={trip["days"] + " · " + trip_countdown(trip)}/>
            <Link className="dt-secondary shadow-sm active:scale-98" to="/trips">All trips</Link></div>
        <div className="dt-comparison-grid">
            <div className="dt-legs">
                {for (index, leg) in enumerate(trip["legs"]) {
                    <section key={"leg-" + str(index)} className="dt-leg" aria-labelledby={"leg-" + str(index)}>
                        <h2 id={"leg-" + str(index)} className="dt-leg-title text-sm font-semibold text-gray-900">{leg["label"]}</h2>
                        <div className="grid grid-cols-2 gap-x-4 gap-y-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_minmax(0,1.1fr)_auto] sm:p-5">
                            <span className="col-span-2 grid gap-0.5 sm:col-span-1"><span className="text-xs font-medium text-gray-500">Time</span><span className="font-semibold tracking-tight text-gray-900">{leg["departure"]} – {leg["arrival"]}</span><span className="text-sm text-gray-500">{leg["duration"]}</span></span>
                            <span className="grid gap-0.5"><span className="text-xs font-medium text-gray-500">Mode</span><span className="text-gray-900">{leg["modes"]}</span>{(<span className="text-xs text-gray-500">{leg["connections"]}</span> if isinstance(leg["connections"], str) and leg["connections"] else None)}</span>
                            {(<span className="grid justify-items-start gap-1"><span className="text-xs font-medium text-gray-500">Risks now</span><RiskBadge label={fresh[index]["risk"]} detail={fresh[index]["detail"]}/><span className="text-xs text-gray-500">{fresh[index]["note"]}</span></span> if index < len(fresh) and fresh[index] else
                              <span className="grid justify-items-start gap-1"><span className="text-xs font-medium text-gray-500">Risks when saved</span><RiskBadge label={leg["risk"]} detail={leg["risk_detail"] if isinstance(leg["risk_detail"], str) else ""}/>{(<span className="text-xs text-gray-500">{leg["weather"]}</span> if isinstance(leg["weather"], str) and leg["weather"] else None)}</span> if isinstance(leg["risk"], str) and leg["risk"] else None)}
                            <span className="grid justify-items-end gap-0.5"><span className="text-xs font-medium text-gray-500">Fare</span><strong className="text-lg font-semibold tracking-tight text-gray-900">{leg["price"].replace(" USD", "")}</strong></span>
                        </div>
                    </section>
                }}
                <RouteMap stops={stops} segments={leg_segments(trip["legs"][0])} label={"Map of " + " to ".join([stop.name for stop in stops]) if len(stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
            </div>
            <aside className="dt-booking rounded-2xl border-gray-200 shadow-md" aria-labelledby="trip-total">
                <h2 id="trip-total" className="dt-booking-price font-semibold tracking-tight">{trip["total"]}</h2>
                <p className="dt-muted">{"Round trip" if len(trip["legs"]) > 1 else "One way"}</p>
                <button type="button" className="dt-secondary dt-booking-action dt-trip-remove h-12 rounded-xl border-red-200 text-red-700 hover:scale-100 hover:bg-red-50 active:scale-98" onClick={lambda { confirming = True; }}>Remove trip</button>
            </aside>
        </div>
        <ConfirmDialog open={confirming} title="Remove this trip?" confirmLabel="Remove trip"
            message={str(trip["title"]) + " · " + str(trip["days"]) + " will be removed from your saved trips. This can't be undone."}
            onConfirm={lambda { confirming = False; remove_trip(str(trip["id"])); navigate("/trips"); }} onCancel={lambda { confirming = False; }}/>
    </>;
}
