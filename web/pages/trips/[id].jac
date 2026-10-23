"""Until persistence is connected, no identifier resolves to a saved plan."""

import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }

def:pub TripDetailPage -> JsxPage {
    return <>
        <PageHeading title="This trip isn’t available." description="The link may be out of date, or the trip may not be available to you."/>
        <EmptyState title="We couldn’t find this trip" message="Return to your trips to find an available plan, or start a new request." actionLabel="Back to trips" actionPath="/trips"/>
    </>;
}
