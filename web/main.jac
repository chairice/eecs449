"""Everyday Agent - landing page entry point.

The site is client-only for now and written entirely in Jac, styles included: no server endpoints, just the
landing page mounted at `/`.
"""

cl {
    import from .frontend { app as LandingPage }

    def:pub app -> JsxElement {
        return <LandingPage/>;
    }
}
