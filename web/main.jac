"""Everyday Agent - landing page entry point.

The site is client-only for now: no server endpoints, just the static
landing page mounted at `/`.
"""

cl {
    import ".assets.global.css";
    import ".assets.header.css";
    import ".assets.hero.css";
    import ".assets.section.css";
    import ".assets.footer.css";
    import from .frontend { app as LandingPage }

    def:pub app -> JsxElement {
        return <LandingPage/>;
    }
}
