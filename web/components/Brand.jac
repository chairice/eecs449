"""Shared brand link; the route mark is decorative beside the product name."""

def:pub Brand -> JsxElement {
    return <a className="dt-brand" href="/">
        <span className="dt-logo" aria-hidden="true">↝</span>
        <span>Detour</span>
    </a>;
}
