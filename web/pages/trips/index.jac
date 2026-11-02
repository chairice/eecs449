"""Trips saved in this browser as a stack of tickets, the soonest departure on
top; empty until one is saved. A signed-in account sees only its own trips.
Each ticket opens the trip, and its bin button asks before removing it."""

import "../../trips.css";
import from "@jac/runtime" { Link }
import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }
import from ...components.Icon { Icon }
import from ...components.ConfirmDialog { ConfirmDialog }
import from ...components.RiskBadge { risk_dot, worst_risk }
import from ...client.account { account_email }
import from ...client.saved_trips { by_departure, load_trips, remove_trip, trip_countdown }

# The middle panel ends in an arrow pointing into the fare, from sm up.
glob ARROW: str = "sm:[clip-path:polygon(0_0,calc(100%_-_1.75rem)_0,100%_50%,calc(100%_-_1.75rem)_100%,0_100%)]";

"""Risk labels saved with each leg; trips saved before risk was kept have none."""
def saved_risks(trip: any) -> list[str] {
    return [str(leg["risk"]) for leg in trip["legs"] if isinstance(leg["risk"], str) and leg["risk"] != ""];
}

def:pub TripsPage -> JsxPage {
    has trips: list[any] = by_departure(load_trips()), pending: any = None;
    email = account_email();
    def remove {
        if pending { remove_trip(str(pending["id"])); }
        pending = None;
        trips = by_departure(load_trips());
    }
    return <>
        <PageHeading title="Your trips" description={"Trips saved to " + email + " in this browser." if email else "Trips you save are kept in this browser. Log in to keep them with your account."}/>
        {(<EmptyState title="No saved trips yet" message="Search for a trip and save the routes you like. They'll show up here." actionLabel="Plan a trip" actionPath="/plan"/> if len(trips) == 0 else
          <ol className="dt-trip-list m-0 grid max-w-4xl list-none gap-6 p-0" aria-label="Saved trips, soonest first">{for trip in trips {
              <li key={trip["id"]}>
                  <div className="flex items-end justify-between">
                      <span className="rounded-t-xl bg-linear-to-r from-emerald-600 to-green-700 px-4 pt-1.5 pb-2 text-sm font-medium text-white">{trip_countdown(trip)}</span>
                      <button type="button" onClick={lambda { pending = trip; }} aria-label={"Remove " + trip["title"] + ", " + trip["days"]}
                          className="mb-1.5 inline-flex h-8 cursor-pointer items-center justify-center rounded-full border-0 bg-transparent px-2 text-gray-400 transition-transform duration-150 hover:bg-red-50 hover:text-red-600 active:scale-98">
                          <Icon name="trash" size={16}/>
                      </button>
                  </div>
                  <Link className="flex flex-col overflow-hidden rounded-2xl rounded-tl-none text-white no-underline shadow-md transition-[box-shadow,scale] duration-200 hover:shadow-lg active:scale-98 sm:flex-row" to={"/trips/" + trip["id"]}>
                      <span className="grid min-w-0 flex-1 content-center gap-1 bg-linear-to-br from-sky-600 to-cyan-700 px-6 py-5">
                          <span className="truncate text-xl font-semibold tracking-tight">{trip["title"]}</span>
                          <span className="text-sm text-sky-50">{trip["days"]} · {"Round trip" if len(trip["legs"]) > 1 else "One way"} · {trip["legs"][0]["modes"]}</span>
                      </span>
                      <span className={"relative z-1 flex items-center justify-center gap-2 bg-stone-50 px-6 py-3 text-center text-sm font-medium text-gray-800 sm:-mr-7 sm:w-56 sm:shrink-0 sm:pl-5 sm:pr-11 " + ARROW}>
                          <span className={"size-2 shrink-0 rounded-full " + risk_dot(worst_risk(saved_risks(trip)))} aria-hidden="true"></span>
                          <span className="leading-snug">{worst_risk(saved_risks(trip)) if len(saved_risks(trip)) > 0 else "Risk not recorded"}</span>
                      </span>
                      <span className="flex items-center justify-between bg-linear-to-r from-emerald-600 to-green-700 px-6 py-4 sm:w-60 sm:shrink-0 sm:justify-center sm:pl-12">
                          <span className="text-sm text-emerald-50 sm:sr-only">Total</span>
                          <strong className="text-2xl font-semibold tracking-tight text-white">{trip["total"]}</strong>
                      </span>
                  </Link>
              </li>
          }}</ol>)}
        <ConfirmDialog open={pending is not None} title="Remove this trip?" confirmLabel="Remove trip"
            message={(str(pending["title"]) + " · " + str(pending["days"]) + " will be removed from your saved trips. This can't be undone.") if pending else ""}
            onConfirm={remove} onCancel={lambda { pending = None; }}/>
    </>;
}
