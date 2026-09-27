"""Top navigation bar."""

def:pub SiteHeader -> JsxElement {
    return
        <header className="header">
            <div className="header-inner">
                <a href="#top" className="header-brand">
                    <span className="header-mark" aria-hidden="true"></span>
                    Everyday Agent
                </a>
                <nav className="header-nav" aria-label="Sections">
                    <a href="#goals">Goals</a>
                    <a href="#use-cases">Use cases</a>
                    <a href="#how-it-works">How it works</a>
                </nav>
            </div>
        </header>;
}
