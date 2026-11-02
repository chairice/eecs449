"""Consistent page introduction across application routes."""

def:pub PageHeading(title: str, description: str) -> JsxElement {
    return <header className="dt-page-heading">
        <h1 className="dt-page-title text-3xl font-semibold tracking-tight text-gray-900">{title}</h1>
        <p className="dt-muted mt-1 text-sm text-gray-500">{description}</p>
    </header>;
}
