"""Public Detour overview. The example is labeled and makes no provider claim."""

import from "@jac/runtime" { Link }

def:pub LandingPage -> JsxPage {
    return <div className="dt-landing">
        <section className="dt-hero">
            <div>
                <p className="dt-kicker">YOUR COMMUTE COPILOT</p>
                <h1 className="dt-hero-title">Your commute, with the uncertainty handled.</h1>
                <p className="dt-lead">A clearer way to compare ground-transit options, understand the risks, and keep your trip in one place.</p>
                <div className="dt-actions">
                    <Link className="dt-primary" to="/plan">Plan a trip <span aria-hidden="true">→</span></Link>
                    <span className="dt-caption">No booking. No surprise changes.</span>
                </div>
            </div>
            <aside className="dt-panel dt-example" aria-label="Example trip request">
                <p className="dt-kicker">A TRIP YOU MIGHT PLAN</p>
                <blockquote>Get me from Ann Arbor to Chicago Friday after 4 PM. Keep it under $50 and avoid tight transfers.</blockquote>
                <div className="dt-example-reply">
                    <p>Compare the time, cost, and connections. See what is known, and what is still uncertain.</p>
                    <span className="dt-caption">Illustrative example · no live routes fetched</span>
                </div>
            </aside>
        </section>
        <section id="why-detour" className="dt-section">
            <p className="dt-kicker">WHY DETOUR</p>
            <h2 className="dt-section-title">The whole trip, in perspective.</h2>
            <div className="dt-feature-grid">
                <article><span className="dt-feature-icon" aria-hidden="true">↔</span><h3>Compare routes</h3><p>See time, price, and transfers together so the tradeoffs are clear.</p></article>
                <article><span className="dt-feature-icon" aria-hidden="true">☂</span><h3>Account for disruption</h3><p>Weather and connection risk belong in the plan. Missing information stays unknown.</p></article>
                <article><span className="dt-feature-icon" aria-hidden="true">✓</span><h3>Stay in control</h3><p>You choose the route. Detour never books or changes a trip without your confirmation.</p></article>
            </div>
        </section>
        <section id="how-it-works" className="dt-section dt-panel">
            <p className="dt-kicker">HOW IT WORKS</p>
            <h2 className="dt-section-title">From a request to a plan.</h2>
            <ol className="dt-steps"><li><strong>Describe your trip.</strong><span>Start with where you need to be and what matters most.</span></li><li><strong>Consider your options.</strong><span>Compare routes and read the reasons behind the recommendation.</span></li><li><strong>Keep your chosen plan.</strong><span>Confirm a route to keep its itinerary in your saved trips. Ticket purchase is separate.</span></li></ol>
            <p className="dt-caption">Detour is under development. The current app lets you explore its pages; route search and saving are coming next.</p>
        </section>
    </div>;
}
