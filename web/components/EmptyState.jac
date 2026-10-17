"""Honest empty/recovery state with one useful navigation action."""

import from "@jac/runtime" { Link }

def:pub EmptyState(title: str, message: str, actionLabel: str, actionPath: str) -> JsxElement {
    return <section className="dt-panel dt-empty-state">
        <span className="dt-state-icon" aria-hidden="true">↝</span>
        <h2>{title}</h2>
        <p className="dt-muted">{message}</p>
        <Link className="dt-primary" to={actionPath}>{actionLabel}<span aria-hidden="true">→</span></Link>
    </section>;
}
