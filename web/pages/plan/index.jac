"""Local planning input. Validation does not invoke a provider or save a trip."""

import from ...components.PageHeading { PageHeading }
import from ...components.TripComposer { TripComposer }

def:pub PlanPage -> JsxPage {
    return <>
        <PageHeading eyebrow="NEW TRIP" title="Where do you need to be?" description="Describe the outcome. Detour will work out the options and show its reasoning."/>
        <div className="dt-two-column">
            <TripComposer/>
            <aside className="dt-panel">
                <h2 className="dt-kicker">START WITH THE CORRIDOR</h2>
                <p>Our first planning demo will connect Ann Arbor and Chicago.</p>
                <ul className="dt-example-list"><li>“Leave Ann Arbor after 4 PM. Keep the trip under $50.”</li><li>“Get me to Chicago before 9 PM, with at least 30 minutes between connections.”</li><li>“Prefer a direct train, even if it costs more.”</li></ul>
                <p className="dt-caption">For now, check the details locally. Route search and natural-language interpretation are not connected yet.</p>
            </aside>
        </div>
        <section className="dt-section"><h2 className="dt-kicker">WHAT DETOUR WILL CONSIDER</h2>
            <div className="dt-feature-grid"><article><h3>Schedule fit</h3><p>Arrival targets and buffers</p></article><article><h3>Transfer risk</h3><p>Connections and fallback time</p></article><article><h3>Conditions</h3><p>Weather and active alerts</p></article></div>
        </section>
    </>;
}
