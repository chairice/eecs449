"""Marketing navigation and the entry into trip planning."""

import from .Brand { Brand }
import from "@jac/runtime" { Link }

def:pub PublicHeader -> JsxElement {
    return <header className="dt-header">
        <div className="dt-header-inner">
            <Brand/>
            <nav className="dt-nav" aria-label="Page sections">
                <a className="dt-nav-link" href="#how-it-works">How it works</a>
                <a className="dt-nav-link" href="#why-detour">Why Detour</a>
            </nav>
            <Link className="dt-secondary" to="/plan">Plan a trip <span aria-hidden="true">↗</span></Link>
        </div>
    </header>;
}
