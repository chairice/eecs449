"""Shared page frame. Routing supplies the active path; the shell owns no data."""

import "../styles.css";
import from .Brand { Brand }
import from .PublicHeader { PublicHeader }
import from "@jac/runtime" { Link }

def:pub NavItem(label: str, href: str, active: bool, enabled: bool) -> JsxElement {
    if not enabled {
        return <button className="dt-nav-link" type="button" disabled={True}>{label}</button>;
    }
    return <Link className="dt-nav-link" to={href} aria-current={"page" if active else None}>{label}</Link>;
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
    return <div className="dt-app" data-theme={"dark" if dark else "light"}>
        <a className="dt-skip-link" href="#main-content">Skip to content</a>
        {(
            <header className="dt-header"><div className="dt-header-inner"><Brand/></div></header> if minimalHeader else
            <PublicHeader/> if publicPage else
            <header className="dt-header">
                <div className="dt-header-inner">
                    <Brand/>
                    <nav className="dt-nav" aria-label="Application navigation">
                        <NavItem label="Atlas" href="/atlas" active={activePath == "/atlas"} enabled={navigationEnabled}/>
                        <NavItem label="Plan" href="/plan" active={activePath == "/plan"} enabled={navigationEnabled}/>
                        <NavItem label="Trips" href="/trips" active={activePath == "/trips"} enabled={navigationEnabled}/>
                    </nav>
                </div>
            </header>
        )}
        <main id="main-content" tabIndex={-1} className={"dt-public-main" if publicPage else "dt-main"}>
            {children}
        </main>
        {footer}
    </div>;
}
