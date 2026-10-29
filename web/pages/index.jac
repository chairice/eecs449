"""Public Detour home: a centred promise over a carousel of places to go.
The header's Plan a trip button is the one way in."""

import from ..components.DestinationCarousel { DestinationCarousel }

def:pub LandingPage -> JsxPage {
    return <div className="dt-landing dt-home">
        <header className="dt-home-intro">
            <h1 className="dt-hero-title">Plan a train or bus trip in one sentence.</h1>
            <p className="dt-lead">Tell Detour where you need to be. It compares the routes and spells out what's known, and what isn't, before you go.</p>
        </header>
        <DestinationCarousel/>
    </div>;
}
