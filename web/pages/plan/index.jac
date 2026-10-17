"""Trip composer layout. Input behavior is added in the next feature."""

import from ...components.PageHeading { PageHeading }

def:pub PlanPage -> JsxPage {
    return <>
        <PageHeading eyebrow="NEW TRIP" title="Where do you need to be?" description="Describe the outcome. Detour will work out the options and show its reasoning."/>
        <div className="dt-two-column">
            <section className="dt-panel">
                <p id="composer-status" className="dt-notice">Trip planning is being built. This preview shows where your request will go.</p>
                <label className="dt-field" htmlFor="trip-request"><span>Describe your trip</span>
                    <textarea id="trip-request" rows={5} disabled={True} aria-describedby="composer-status" placeholder="Example: Get me from Ann Arbor to Chicago Friday evening. I care more about reliability than price."/>
                </label>
                <div className="dt-actions dt-actions-between"><span className="dt-caption">Natural language is fine</span><button className="dt-primary" disabled={True} type="button">Plan trip →</button></div>
            </section>
            <aside className="dt-panel">
                <h2 className="dt-kicker">TRY AN EXAMPLE</h2>
                <ul className="dt-example-list"><li>“Get me to O’Hare by 7 AM tomorrow.”</li><li>“Cheapest route to Detroit after class.”</li><li>“Avoid transfers if snow is expected.”</li></ul>
            </aside>
        </div>
        <section className="dt-section"><h2 className="dt-kicker">WHAT DETOUR WILL CONSIDER</h2>
            <div className="dt-feature-grid"><article><h3>Schedule fit</h3><p>Arrival targets and buffers</p></article><article><h3>Transfer risk</h3><p>Connections and fallback time</p></article><article><h3>Conditions</h3><p>Weather and active alerts</p></article></div>
        </section>
    </>;
}
