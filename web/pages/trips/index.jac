"""Trips saved in this browser, newest first; empty until one is saved."""

import "../../trips.css";
import from "@jac/runtime" { Link }
import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }
import from ...client.saved_trips { load_trips, trip_countdown }

def:pub TripsPage -> JsxPage {
    trips = load_trips();
    return <>
        <PageHeading title="Your trips" description="Trips you save are kept in this browser."/>
        {(<EmptyState title="No saved trips yet" message="Search for a trip and save the routes you like. They'll show up here." actionLabel="Plan a trip" actionPath="/plan"/> if len(trips) == 0 else
          <ul className="dt-trip-list">{for trip in trips {
              <li key={trip["id"]}><Link className="dt-trip-card" to={"/trips/" + trip["id"]}>
                  <span className="dt-trip-main"><span className="dt-trip-title">{trip["title"]}</span><span className="dt-muted">{trip["days"]} · {trip_countdown(trip)}</span></span>
                  <strong>{trip["total"]}</strong>
              </Link></li>
          }}</ul>)}
    </>;
}
