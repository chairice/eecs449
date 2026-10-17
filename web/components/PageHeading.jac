"""Consistent page introduction across application routes."""

def:pub PageHeading(eyebrow: str, title: str, description: str) -> JsxElement {
    return <header className="dt-page-heading">
        <p className="dt-kicker">{eyebrow}</p>
        <h1 className="dt-page-title">{title}</h1>
        <p className="dt-muted">{description}</p>
    </header>;
}
