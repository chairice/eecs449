"""Consistent page introduction across application routes."""

def:pub PageHeading(title: str, description: str) -> JsxElement {
    return <header className="dt-page-heading">
        <h1 className="dt-page-title">{title}</h1>
        <p className="dt-muted">{description}</p>
    </header>;
}
