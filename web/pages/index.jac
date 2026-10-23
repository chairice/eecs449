"""Public Detour home: a centred promise over a carousel of places to go."""

import from "@jac/runtime" { Link }
import from ..components.Icon { Icon }
import from ..components.DestinationCarousel { DestinationCarousel }

def:pub LandingPage -> JsxPage {
    return <div className="dt-landing dt-home">
        <header className="dt-home-intro">
            <h1 className="dt-hero-title">Travel made accessible.</h1>
            <p className="dt-lead">Compare trains and buses side by side, with what's known and what isn't spelled out before you go.</p>
            <Link className="dt-primary" to="/plan">Plan a trip<Icon name="arrow.right"/></Link>
        </header>
        <DestinationCarousel/>
    </div>;
}
