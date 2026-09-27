"""Page footer."""

import from ..theme { Theme, container }

def:pub SiteFooter(t: Theme, narrow: bool) -> JsxElement {
    return
        <footer
            style={{
                "borderTop": "1px solid " + t.border,
                "padding": "32px 0",
                "fontSize": "14px",
                "color": t.textMuted
            }}
        >
            <div
                style={{
                    ** container(narrow),
                    "display": "flex",
                    "flexWrap": "wrap",
                    "justifyContent": "space-between",
                    "gap": "12px"
                }}
            >
                <p style={{"margin": "0"}}>
                    Everyday Agent · EECS 449 course project, University of Michigan
                </p>
                <a href="https://github.com/chairice/eecs449" style={{"color": t.text}}>
                    View on GitHub
                </a>
            </div>
        </footer>;
}
