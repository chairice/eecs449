"""Saved trips empty state; no illustrative records masquerade as saved data."""

import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }

def:pub TripsPage -> JsxPage {
    return <>
        <PageHeading eyebrow="Your trips" title="Your plans, in one place." description="A home for the routes you choose, with the details you need before you leave."/>
        <EmptyState title="No saved trips yet" message="Your confirmed plans will appear here. Saving trips is not available in this preview." actionLabel="Plan a trip" actionPath="/plan"/>
    </>;
}
