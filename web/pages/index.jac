"""Public Detour home: a centred promise over a carousel of places to go.
The header's Plan a trip button is the one way in."""

import from ..components.DestinationCarousel { DestinationCarousel }

def:pub LandingPage -> JsxPage {
    return <div className="dt-landing dt-home">
        <header className="dt-home-intro">
            <h1 className="dt-hero-title">Travel made accessible.</h1>
            <p className="dt-lead">Compare trains and buses side by side, with what's known and what isn't spelled out before you go.</p>
        </header>
        <DestinationCarousel/>
    </div>;
}
