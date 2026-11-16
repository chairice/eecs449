"""Public Detour home: a centred promise over a carousel of places to go, then
the account panels. The header's Plan a trip button is the way into planning;
its Log in button lands here with the panels scrolled into view."""

import from "@jac/runtime" { useLocation }
import from ..components.DestinationCarousel { DestinationCarousel }
import from ..components.AuthPanels { AuthPanels }
import from ..browser { mediaMatches, scrollToId }
import from ..theme { REDUCED_MOTION_QUERY }

def:pub CommuterLandingPage -> JsxPage {
    location = useLocation();
    wantsAccount = bool(location.state and location.state["account"]);
    can with [location.key] entry {
        if wantsAccount { scrollToId("account", not mediaMatches(REDUCED_MOTION_QUERY)); }
    }
    return <div className="dt-landing dt-home">
        <header className="dt-home-intro">
            <p className="text-sm font-semibold tracking-tight text-emerald-700">A little further. A little more you.</p>
            <h1 className="dt-hero-title text-4xl font-semibold tracking-tight text-balance text-gray-900 sm:text-5xl">Your next trip starts with a conversation.</h1>
            <p className="dt-lead text-base text-gray-500 text-pretty">A quick work trip or a week of discovery. Talk through flights, stays, drives and days with Detour, and shape a U.S. trip that feels like yours.</p>
        </header>
        <DestinationCarousel/>
        <AuthPanels/>
    </div>;
}
