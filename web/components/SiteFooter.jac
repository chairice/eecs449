"""Page footer."""

def:pub SiteFooter -> JsxElement {
    return <footer className="dt-footer border-sky-200/70 bg-linear-to-r from-sky-100 via-sky-50 to-cyan-100">
        <div className="dt-footer-inner">
            <p>Detour · EECS 449 · University of Michigan</p>
            <a href="https://github.com/chairice/eecs449">View on GitHub</a>
        </div>
    </footer>;
}
