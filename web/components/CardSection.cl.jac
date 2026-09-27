"""A titled section with a responsive grid of text cards."""

import from ..content { TextCard }

def:pub CardSection(
    sectionId: str,
    eyebrow: str,
    heading: str,
    intro: str,
    cards: list[TextCard],
    numbered: bool = False,
    muted: bool = False
) -> JsxElement {
    section_cls = "section section-muted" if muted else "section";
    return
        <section id={sectionId} className={section_cls}>
            <div className="section-inner">
                <p className="section-eyebrow">{eyebrow}</p>
                <h2 className="section-heading">{heading}</h2>
                <p className="section-intro">{intro}</p>
                <div className="section-grid">
                    {for (i, card) in enumerate(cards) {
                        <article key={str(i)} className="section-card">
                            {if numbered {
                                <span className="section-number">
                                    {"0" + str(i + 1)}
                                </span>
                            }}
                            <h3 className="section-card-title">{card.title}</h3>
                            <p className="section-card-body">{card.body}</p>
                        </article>
                    }}
                </div>
            </div>
        </section>;
}
