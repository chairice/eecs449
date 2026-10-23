"""Honest empty/recovery state with one useful navigation action."""

import from "@jac/runtime" { Link }
import from .Icon { Icon }

def:pub EmptyState(title: str, message: str, actionLabel: str, actionPath: str) -> JsxElement {
    return <section className="dt-panel dt-empty-state">
        <h2>{title}</h2>
        <p className="dt-muted">{message}</p>
        <Link className="dt-primary" to={actionPath}>{actionLabel}<Icon name="arrow.right"/></Link>
    </section>;
}
