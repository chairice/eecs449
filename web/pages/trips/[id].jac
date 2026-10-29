"""One saved trip: each direction as a route row, its map, and a way to remove it."""

import "../../comparison.css";
import "../../trips.css";
import from "@jac/runtime" { Link, useNavigate, useParams }
import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }
import from ...components.RouteMap { RouteMap }
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

def:pub TripDetailPage -> JsxPage {
    params = useParams();
    navigate = useNavigate();
    id: any = params["id"];
    trip: any = find_trip(str(id)) if id else None;
    if not trip {
        return <>
            <PageHeading title="This trip isn’t available." description="It may have been removed, or saved in another browser."/>
            <EmptyState title="We couldn’t find this trip" message="Go back to your trips, or start a new search." actionLabel="Back to trips" actionPath="/trips"/>
        </>;
    }
    stops = leg_stops(trip["legs"][0]);
    return <>
        <div className="dt-comparison-heading"><PageHeading title={trip["title"]} description={trip["days"] + " · " + trip_countdown(trip)}/>
            <Link className="dt-secondary" to="/trips">All trips</Link></div>
        <div className="dt-comparison-grid">
            <div className="dt-legs">
                {for (index, leg) in enumerate(trip["legs"]) {
                    <section key={"leg-" + str(index)} className="dt-leg" aria-labelledby={"leg-" + str(index)}>
                        <h2 id={"leg-" + str(index)} className="dt-leg-title">{leg["label"]}</h2>
                        <div className="dt-route-list"><div className="dt-route-row dt-route-static">
                            <span className="dt-route-main"><span className="dt-route-times">{leg["departure"]} – {leg["arrival"]}</span><span className="dt-muted">{leg["modes"]}</span></span>
                            <span className="dt-route-duration">{leg["duration"]}</span>
                            <strong className="dt-route-price">{leg["price"]}</strong>
                        </div></div>
                    </section>
                }}
                <RouteMap stops={stops} segments={leg_segments(trip["legs"][0])} label={"Map of " + " to ".join([stop.name for stop in stops]) if len(stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
            </div>
            <aside className="dt-booking" aria-labelledby="trip-total">
                <h2 id="trip-total" className="dt-booking-price">{trip["total"]}</h2>
                <p className="dt-muted">{"Round trip" if len(trip["legs"]) > 1 else "One way"}</p>
                <button type="button" className="dt-secondary dt-booking-action dt-trip-remove" onClick={lambda { remove_trip(str(trip["id"])); navigate("/trips"); }}>Remove trip</button>
            </aside>
        </div>
    </>;
}
