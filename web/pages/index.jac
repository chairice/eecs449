"""Public Detour overview. The example is labeled and makes no provider claim."""

import from "@jac/runtime" { Link }
import from ..components.Icon { Icon }

def:pub LandingPage -> JsxPage {
    return <div className="dt-landing">
        <section className="dt-hero">
            <div>
                <h1 className="dt-hero-title">Your commute, with the uncertainty handled.</h1>
                <p className="dt-lead">A clearer way to compare ground-transit options, understand the risks, and keep your trip in one place.</p>
                <div className="dt-actions">
                    <Link className="dt-primary" to="/plan">Plan a trip<Icon name="arrow.right"/></Link>
                </div>
            </div>
            <aside className="dt-panel dt-example" aria-label="Example trip request">
                <blockquote>Get me from Ann Arbor to Chicago Friday after 4 PM. Keep it under $50 and avoid tight transfers.</blockquote>
                <div className="dt-example-reply">
                    <p>Compare the time, cost, and connections. See what is known, and what is still uncertain.</p>
                </div>
            </aside>
        </section>
        <section id="why-detour" className="dt-section">
            <h2 className="dt-section-title">The whole trip, in perspective.</h2>
            <div className="dt-feature-grid">
                <article><span className="dt-feature-icon"><Icon name="arrow.left.arrow.right" size={24}/></span><h3>Compare routes</h3><p>See time, price, and transfers together so the tradeoffs are clear.</p></article>
                <article><span className="dt-feature-icon"><Icon name="umbrella" size={24}/></span><h3>Account for disruption</h3><p>Weather and connection risk belong in the plan. Missing information stays unknown.</p></article>
                <article><span className="dt-feature-icon"><Icon name="checkmark" size={24}/></span><h3>Stay in control</h3><p>You choose the route. Detour never books or changes a trip without your confirmation.</p></article>
            </div>
        </section>
    </div>;
}
