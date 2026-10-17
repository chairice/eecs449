"""Page footer."""

def:pub SiteFooter -> JsxElement {
    return <footer className="dt-footer">
        <div className="dt-footer-inner">
            <p>Detour · EECS 449 · University of Michigan</p>
            <a href="https://github.com/chairice/eecs449">View on GitHub</a>
        </div>
    </footer>;
}
