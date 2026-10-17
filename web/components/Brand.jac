"""Shared brand link; the route mark is decorative beside the product name."""

import from "@jac/runtime" { Link }

def:pub Brand -> JsxElement {
    return <Link className="dt-brand" to="/">
        <span className="dt-logo" aria-hidden="true">↝</span>
        <span>Detour</span>
    </Link>;
}
