"""Top navigation bar."""

import from ..theme { Theme, container }

def:pub SiteHeader(t: Theme, narrow: bool) -> JsxElement {
    link = {"color": t.textMuted, "textDecoration": "none"};
    return
        <header
            style={{
                "position": "sticky",
                "top": "0",
                "zIndex": "10",
                "background": t.headerBg,
                "backdropFilter": "blur(8px)",
                "WebkitBackdropFilter": "blur(8px)",
                "borderBottom": "1px solid " + t.border
            }}
        >
            <div
                style={{
                    ** container(narrow),
                    "paddingTop": "12px" if narrow else "14px",
                    "paddingBottom": "12px" if narrow else "14px",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "space-between",
                    "gap": "16px"
                }}
            >
                <a
                    href="#top"
                    style={{
                        "display": "inline-flex",
                        "alignItems": "center",
                        "gap": "10px",
                        "fontWeight": "600",
                        "color": t.text,
                        "textDecoration": "none"
                    }}
                >
                    <span
                        aria-hidden="true"
                        style={{
                            "width": "22px",
                            "height": "22px",
                            "borderRadius": "7px",
                            "background": t.accent
                        }}
                    ></span>
                    Everyday Agent
                </a>
                {if not narrow {
                    <nav
                        aria-label="Sections"
                        style={{"display": "flex", "gap": "24px", "fontSize": "15px"}}
                    >
                        <a href="#goals" style={link}>Goals</a>
                        <a href="#use-cases" style={link}>Use cases</a>
                        <a href="#how-it-works" style={link}>How it works</a>
                    </nav>
                }}
            </div>
        </header>;
}
