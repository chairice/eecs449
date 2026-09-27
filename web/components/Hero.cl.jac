"""Opening section: what the project is, in one breath."""

import from ..theme { Theme, RADIUS, container, eyebrow, displayHeading }

def:pub Hero(t: Theme, narrow: bool, wide: bool) -> JsxElement {
    button = {
        "display": "inline-block",
        "padding": "12px 22px",
        "borderRadius": "999px",
        "fontWeight": "500",
        "textDecoration": "none"
    };
    bubble = {
        "margin": "0",
        "padding": "14px 18px",
        "borderRadius": RADIUS,
        "fontSize": "16px",
        "maxWidth": "85%"
    };
    # Wide screens put the chat beside the copy; narrower ones stack it below.
    layout = {
        "display": "grid",
        "gridTemplateColumns": "1.25fr 1fr",
        "alignItems": "center",
        "gap": "56px"
    }
        if wide
        else {};
    return
        <section
            id="top"
            style={{"padding": "56px 0 48px" if narrow else "96px 0 88px"}}
        >
            <div style={{** container(narrow), ** layout}}>
                <div>
                    <p style={{** eyebrow(t), "marginBottom": "20px"}}>
                        EECS 449 · Conversational AI · University of Michigan
                    </p>
                    <h1
                        style={{
                            ** displayHeading("clamp(40px, 6vw, 64px)"),
                            "maxWidth": "14ch"
                        }}
                    >
                        Hand off the chores that fill your day.
                    </h1>
                    <p
                        style={{
                            "margin": "24px 0 0",
                            "maxWidth": "60ch",
                            "fontSize": "17px" if narrow else "19px",
                            "color": t.textMuted
                        }}
                    >
                        Everyday Agent is a conversational AI that takes care of small, repetitive tasks like sorting email, scheduling, and tracking deadlines. Tell it what you want done; it plans the steps, uses your tools, and checks in before anything important.
                    </p>
                    <div
                        style={{
                            "marginTop": "36px",
                            "display": "flex",
                            "flexWrap": "wrap",
                            "gap": "12px"
                        }}
                    >
                        <a
                            href="#goals"
                            style={{
                                ** button,
                                "background": t.accent,
                                "color": t.accentText
                            }}
                        >
                            See our goals
                        </a>
                        <a
                            href="#how-it-works"
                            style={{
                                ** button,
                                "background": t.surface,
                                "color": t.text,
                                "border": "1px solid " + t.border
                            }}
                        >
                            How it works
                        </a>
                    </div>
                </div>
                <div
                    aria-hidden="true"
                    style={{
                        "marginTop": "0" if wide else ("44px" if narrow else "56px"),
                        "maxWidth": "560px",
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "12px"
                    }}
                >
                    <p
                        style={{
                            ** bubble,
                            "alignSelf": "flex-end",
                            "background": t.accent,
                            "color": t.accentText,
                            "borderBottomRightRadius": "4px"
                        }}
                    >
                        Can you find a time for our project meeting this week?
                    </p>
                    <p
                        style={{
                            ** bubble,
                            "alignSelf": "flex-start",
                            "background": t.surface,
                            "border": "1px solid " + t.border,
                            "borderBottomLeftRadius": "4px"
                        }}
                    >
                        Everyone's free Thursday 4-5 PM. Want me to send the invite and a reminder the day before?
                    </p>
                </div>
            </div>
        </section>;
}
