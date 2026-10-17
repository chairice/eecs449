"""Everyday Agent - landing page layout.

This component owns the page-wide state (color scheme and screen size) and
passes the active theme down to each section.
"""

import from react { useEffect }
import from .content { GOALS, USE_CASES, STEPS }
import from .theme {
    LIGHT,
    DARK,
    FONT_SANS,
    FONTS_URL,
    DARK_QUERY,
    NARROW_QUERY,
    WIDE_QUERY,
    REDUCED_MOTION_QUERY
}
import from .browser { mediaMatches, watchMedia, loadStylesheet, paintPage }
import from .components.SiteHeader { SiteHeader }
import from .components.Hero { Hero }
import from .components.CardSection { CardSection }
import from .components.SiteFooter { SiteFooter }

def:pub app -> JsxElement {
    has dark: bool = mediaMatches(DARK_QUERY),
        narrow: bool = mediaMatches(NARROW_QUERY),
        wide: bool = mediaMatches(WIDE_QUERY);

    can with entry {
        loadStylesheet(FONTS_URL);
    }

    # Follow the browser's color scheme and window size as they change.
    useEffect(
        lambda {
            stopDark = watchMedia(DARK_QUERY, lambda (m: bool) { dark = m; });
            stopNarrow = watchMedia(
                NARROW_QUERY, lambda (m: bool) { narrow = m; }
            );
            stopWide = watchMedia(WIDE_QUERY, lambda (m: bool) { wide = m; });
            return lambda {
                stopDark();
                stopNarrow();
                stopWide();
            };
        },
        []
    );

    t = DARK if dark else LIGHT;

    can with [dark] entry {
        paintPage(t.bg, dark, not mediaMatches(REDUCED_MOTION_QUERY));
    }

    return
        <div
            style={{
                "background": t.bg,
                "color": t.text,
                "fontFamily": FONT_SANS,
                "fontSize": "17px",
                "lineHeight": "1.6",
                "WebkitFontSmoothing": "antialiased",
                "minHeight": "100vh"
            }}
        >
            <SiteHeader t={t} narrow={narrow}/>
            <main>
                <Hero t={t} narrow={narrow} wide={wide}/>
                <CardSection
                    t={t}
                    narrow={narrow}
                    sectionId="goals"
                    eyebrowText="What we're building toward"
                    heading="Project goals"
                    intro="Five goals guide the project, from what the agent does to how we judge whether it helps."
                    cards={GOALS}
                    numbered={True}
                />
                <CardSection
                    t={t}
                    narrow={narrow}
                    sectionId="use-cases"
                    eyebrowText="Where it helps"
                    heading="The small stuff, handled"
                    intro="None of these tasks are hard. Together, they take up hours every week."
                    cards={USE_CASES}
                    muted={True}
                />
                <CardSection
                    t={t}
                    narrow={narrow}
                    sectionId="how-it-works"
                    eyebrowText="How it works"
                    heading="From request to done"
                    intro="You describe the outcome. The agent works out the steps."
                    cards={STEPS}
                    numbered={True}
                />
            </main>
            <SiteFooter t={t} narrow={narrow}/>
        </div>;
}
