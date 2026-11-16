"""Public Detour home: a centred promise over a carousel of places to go, then
the account panels. The header's Plan a trip button is the way into planning;
its Log in button lands here with the panels scrolled into view."""

import from "@jac/runtime" { useLocation }
import from ..components.DestinationCarousel { DestinationCarousel }
import from ..components.AuthPanels { AuthPanels }
import from ..browser { mediaMatches, scrollToId }
import from ..theme { REDUCED_MOTION_QUERY }

def:pub LandingPage -> JsxPage {
    location = useLocation();
    wantsAccount = bool(location.state and location.state["account"]);
    can with [location.key] entry {
        if wantsAccount { scrollToId("account", not mediaMatches(REDUCED_MOTION_QUERY)); }
    }
    return <div className="dt-landing dt-home">
        <header className="dt-home-intro">
            <p className="text-sm font-semibold tracking-tight text-emerald-700">Ann Arbor ⇄ Chicago, Detroit, Cleveland and more, by train or bus</p>
            <h1 className="dt-hero-title text-4xl font-semibold tracking-tight text-balance text-gray-900 sm:text-5xl">Plan a train or bus trip in one sentence.</h1>
            <p className="dt-lead text-base text-gray-500 text-pretty">Tell Detour where you need to be. It compares the routes and spells out what's known, and what isn't, before you go.</p>
        </header>
        <DestinationCarousel/>
        <AuthPanels/>
    </div>;
}
