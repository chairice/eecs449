"""Shared brand link; the route mark is decorative beside the product name."""

import from "@jac/runtime" { Link }
import from .Icon { Icon }

def:pub Brand -> JsxElement {
    return <Link className="dt-brand" to="/">
        <span className="dt-logo"><Icon name="route"/></span>
        <span>Detour</span>
    </Link>;
}
