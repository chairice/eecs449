"""Honest empty/recovery state with one useful navigation action."""

import from "@jac/runtime" { Link }
import from .Icon { Icon }

def:pub EmptyState(title: str, message: str, actionLabel: str, actionPath: str) -> JsxElement {
    return <section className="dt-panel dt-empty-state rounded-2xl border border-gray-200 bg-white shadow-sm">
        <h2 className="text-xl font-semibold tracking-tight text-gray-900">{title}</h2>
        <p className="dt-muted">{message}</p>
        <Link className="dt-primary bg-linear-to-r from-emerald-600 to-green-700 font-semibold shadow-sm active:scale-98" to={actionPath}>{actionLabel}<Icon name="arrow.right"/></Link>
    </section>;
}
