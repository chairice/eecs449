"""A titled section with a responsive grid of text cards."""

import from ..content { TextCard }
import from ..theme { Theme, RADIUS, FONT_SANS, container, eyebrow, displayHeading }

def:pub CardSection(
    t: Theme,
    narrow: bool,
    sectionId: str,
    eyebrowText: str,
    heading: str,
    intro: str,
    cards: list[TextCard],
    numbered: bool = False,
    muted: bool = False
) -> JsxElement {
    return
        <section
            id={sectionId}
            style={{
                "padding": "56px 0" if narrow else "88px 0",
                "borderTop": "1px solid " + t.border,
                "background": t.surfaceMuted if muted else "transparent",
                "scrollMarginTop": "56px"
            }}
        >
            <div style={container(narrow)}>
                <p style={eyebrow(t)}>{eyebrowText}</p>
                <h2 style={displayHeading("clamp(30px, 4vw, 40px)")}>{heading}</h2>
                <p
                    style={{
                        "margin": "14px 0 0",
                        "maxWidth": "56ch",
                        "color": t.textMuted
                    }}
                >
                    {intro}
                </p>
                <div
                    style={{
                        "marginTop": "32px" if narrow else "44px",
                        "display": "grid",
                        "gridTemplateColumns": "1fr"
                            if narrow
                            else "repeat(auto-fill, minmax(280px, 1fr))",
                        "gap": "16px"
                    }}
                >
                    {for (i, card) in enumerate(cards) {
                        <article
                            key={str(i)}
                            style={{
                                "padding": "24px",
                                "background": t.surface,
                                "border": "1px solid " + t.border,
                                "borderRadius": RADIUS
                            }}
                        >
                            {if numbered {
                                <span
                                    key="number"
                                    style={{
                                        "display": "inline-block",
                                        "marginBottom": "14px",
                                        "padding": "2px 10px",
                                        "borderRadius": "999px",
                                        "background": t.accentSoft,
                                        "color": t.accent,
                                        "fontSize": "13px",
                                        "fontWeight": "600",
                                        "fontVariantNumeric": "tabular-nums"
                                    }}
                                >
                                    {"0" + str(i + 1)}
                                </span>
                            }}
                            <h3
                                style={{
                                    "margin": "0",
                                    "fontFamily": FONT_SANS,
                                    "fontSize": "18px",
                                    "fontWeight": "600",
                                    "lineHeight": "1.3"
                                }}
                            >
                                {card.title}
                            </h3>
                            <p
                                style={{
                                    "margin": "8px 0 0",
                                    "color": t.textMuted,
                                    "fontSize": "16px"
                                }}
                            >
                                {card.body}
                            </p>
                        </article>
                    }}
                </div>
            </div>
        </section>;
}
