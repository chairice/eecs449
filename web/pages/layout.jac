"""One layout for the file-based router; owns theme subscriptions only."""

import from react { useEffect }
import from "@jac/runtime" { Outlet, useLocation }
import from ..components.AppShell { AppShell }
import from ..components.SiteFooter { SiteFooter }
import from ..browser { mediaMatches, watchMedia, loadStylesheet, paintPage }
import from ..theme { FONTS_URL, DARK_QUERY, REDUCED_MOTION_QUERY }

def:pub RootLayout -> JsxLayout {
    has dark: bool = mediaMatches(DARK_QUERY);
    location = useLocation();
    path: str = location.pathname;
    # Router matching is case-insensitive; this value selects chrome only.
    path = path.lower();
    # React Router accepts trailing slashes; keep shell selection equivalent.
    while len(path) > 1 and path[len(path) - 1] == "/" {
        path = path[:len(path) - 1];
    }
    segments = path.split("/");
    isTripDetail = len(segments) == 3 and segments[1] == "trips" and segments[2] != "";
    appPage = path in ["/plan", "/plan/results", "/trips", "/settings"] or isTripDetail;
    activePath = "/trips" if path == "/trips" or isTripDetail else "/settings" if path == "/settings" else "/plan";

    can with entry { loadStylesheet(FONTS_URL); }
    useEffect(lambda { return watchMedia(DARK_QUERY, lambda (m: bool) { dark = m; }); }, []);
    can with [dark] entry {
        paintPage("var(--dt-bg)", dark, not mediaMatches(REDUCED_MOTION_QUERY));
    }

    return <AppShell dark={dark} publicPage={path == "/"} minimalHeader={path != "/" and not appPage}
        activePath={activePath} footer={<SiteFooter/>}>
        <Outlet/>
    </AppShell>;
}
