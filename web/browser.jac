"""Typed wrappers around the few browser APIs the page needs.

`jac check` has no type stubs for browser globals (`window`, `document`), so
the untyped calls are kept here behind typed signatures and the rest of the
app type-checks normally.
"""

"""True when the browser currently matches a CSS media query."""
def:pub mediaMatches(query: str) -> bool {
    mql: any = window.matchMedia(query);
    return bool(mql.matches);
}

"""Call `onChange` whenever `query` starts or stops matching.

Returns a function that stops watching.
"""
def:pub watchMedia(query: str, onChange: Callable[[bool], None]) -> Callable[[], None] {
    mql: any = window.matchMedia(query);
    handler = lambda (e: any) { onChange(bool(e.matches)); };
    mql.addEventListener("change", handler);
    return lambda { mql.removeEventListener("change", handler); };
}

"""Add a <link rel="stylesheet"> to the document head (used for web fonts)."""
def:pub loadStylesheet(href: str) {
    head: any = document.head;
    link: any = document.createElement("link");
    link.rel = "stylesheet";
    link.href = href;
    head.appendChild(link);
}

"""Style the <html> and <body> elements, which sit outside the React tree."""
def:pub paintPage(background: str, dark: bool, smoothScroll: bool) {
    html: any = document.documentElement;
    body: any = document.body;
    body.style.margin = "0";
    body.style.background = background;
    html.style.colorScheme = "dark" if dark else "light";
    html.style.scrollBehavior = "smooth" if smoothScroll else "auto";
}
