"""Shared page frame. Routing supplies the active path; the shell owns no data."""

import "../tailwind.css";
import "../styles.css";
import from .Brand { Brand }
import from .PublicHeader { HEADER, PublicHeader }
import from .AccountMenu { AccountMenu }
import from "react" { useEffect }
import from "@jac/runtime" { Link }
import from ..client.account { watch_account }
import from ..client.saved_trips { load_trips, watch_trips }

glob NAV_LINK: str = "dt-nav-link whitespace-nowrap rounded-full px-4 font-medium transition-[color,background-color,scale] duration-150 active:scale-98";

def:pub NavItem(label: str, href: str, active: bool, enabled: bool, count: int = 0) -> JsxElement {
    if not enabled {
        return <button className={NAV_LINK} type="button" disabled={True}>{label}</button>;
    }
    tone = " bg-emerald-50 text-emerald-800" if active else " text-gray-500 hover:bg-gray-100 hover:text-gray-900";
    if count == 0 {
        return <Link className={NAV_LINK + tone} to={href} aria-current={"page" if active else None}>{label}</Link>;
    }
    # A count beside the label, as a shop shows items beside its cart.
    return <Link className={NAV_LINK + " inline-flex items-center gap-1.5" + tone} to={href} aria-current={"page" if active else None} aria-label={label + ", " + str(count) + " saved"}>
        {label}<span className="inline-grid h-5 min-w-5 place-items-center rounded-full bg-emerald-600 px-1.5 text-xs font-semibold text-white" aria-hidden="true">{count}</span>
    </Link>;
}

def:pub AppShell(
    dark: bool = False,
    publicPage: bool = False,
    minimalHeader: bool = False,
    activePath: str = "/plan",
    navigationEnabled: bool = True,
    footer: JsxElement | None = None,
    children: any = None
) -> JsxElement {
    has saved: int = len(load_trips());
    useEffect(lambda {
        stop_trips = watch_trips(lambda { saved = len(load_trips()); });
        stop_account = watch_account(lambda { saved = len(load_trips()); });
        return lambda { stop_trips(); stop_account(); };
    }, []);
    return <div className="dt-app bg-linear-to-br from-emerald-100/80 via-green-50 to-emerald-50" data-theme={"dark" if dark else "light"}>
        <a className="dt-skip-link" href="#main-content">Skip to content</a>
        {(
            <header className={HEADER}><div className="dt-header-inner"><Brand/><AccountMenu/></div></header> if minimalHeader else
            <PublicHeader/> if publicPage else
            <header className={HEADER}>
                <div className="dt-header-inner flex-wrap gap-y-3">
                    <Brand/>
                    <nav className="dt-nav order-last mx-auto flex-nowrap gap-1 px-1.5 py-1 shadow-sm md:order-none md:mx-0" aria-label="Application navigation">
                        <NavItem label="Atlas" href="/atlas" active={activePath == "/atlas"} enabled={navigationEnabled}/>
                        <NavItem label="Plan" href="/plan" active={activePath == "/plan"} enabled={navigationEnabled}/>
                        <NavItem label="Trips" href="/trips" active={activePath == "/trips"} enabled={navigationEnabled} count={saved}/>
                    </nav>
                    <AccountMenu/>
                </div>
            </header>
        )}
        <main id="main-content" tabIndex={-1} className={"dt-public-main" if publicPage else "dt-main"}>
            {children}
        </main>
        {footer}
    </div>;
}
