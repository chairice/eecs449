"""Unknown public URLs offer recovery without application navigation."""

import from "@jac/runtime" { Link }

def:pub NotFoundPage -> JsxPage {
    return <section className="dt-not-found">
        <span className="dt-404" aria-hidden="true">404</span>
        <p className="dt-kicker">WRONG TURN</p>
        <h1 className="dt-page-title">This route went off the map.</h1>
        <p className="dt-muted">The page may have moved. Following this link hasn’t changed any saved trips.</p>
        <Link className="dt-primary" to="/plan">Back to planning <span aria-hidden="true">→</span></Link>
    </section>;
}
