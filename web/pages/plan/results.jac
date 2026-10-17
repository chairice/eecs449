"""A direct results link has no draft until a planning request exists."""

import from ...components.PageHeading { PageHeading }
import from ...components.EmptyState { EmptyState }

def:pub ResultsPage -> JsxPage {
    return <>
        <PageHeading eyebrow="COMPARE ROUTES" title="A plan starts with your trip." description="Once you describe your trip, this is where you’ll compare options and understand the tradeoffs."/>
        <EmptyState title="No trip request to compare yet" message="There is no active planning request in this session. Return to planning to start a new trip." actionLabel="Back to planning" actionPath="/plan"/>
    </>;
}
