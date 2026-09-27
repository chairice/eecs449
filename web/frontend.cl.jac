"""Everyday Agent - landing page layout."""

import from .content { GOALS, USE_CASES, STEPS }
import from .components.SiteHeader { SiteHeader }
import from .components.Hero { Hero }
import from .components.CardSection { CardSection }
import from .components.SiteFooter { SiteFooter }

def:pub app -> JsxElement {
    return
        <div>
            <SiteHeader/>
            <main>
                <Hero/>
                <CardSection
                    sectionId="goals"
                    eyebrow="What we're building toward"
                    heading="Project goals"
                    intro="Five goals guide the project, from what the agent does to how we judge whether it helps."
                    cards={GOALS}
                    numbered={True}
                />
                <CardSection
                    sectionId="use-cases"
                    eyebrow="Where it helps"
                    heading="The small stuff, handled"
                    intro="None of these tasks are hard. Together, they take up hours every week."
                    cards={USE_CASES}
                    numbered={False}
                    muted={True}
                />
                <CardSection
                    sectionId="how-it-works"
                    eyebrow="How it works"
                    heading="From request to done"
                    intro="You describe the outcome. The agent works out the steps."
                    cards={STEPS}
                    numbered={True}
                />
            </main>
            <SiteFooter/>
        </div>;
}
