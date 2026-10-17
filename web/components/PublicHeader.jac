"""Public navigation preserves the current landing page's section links."""

import from .Brand { Brand }

def:pub PublicHeader -> JsxElement {
    return <header className="dt-header">
        <div className="dt-header-inner">
            <Brand/>
            <nav className="dt-nav" aria-label="Page sections">
                <a className="dt-nav-link" href="#goals">Goals</a>
                <a className="dt-nav-link" href="#use-cases">Use cases</a>
                <a className="dt-nav-link" href="#how-it-works">How it works</a>
            </nav>
        </div>
    </header>;
}
