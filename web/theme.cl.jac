"""Design tokens and shared style helpers for the landing page.

All styling is done in Jac: components build inline style dicts from the
active `Theme`, and the page shell picks LIGHT or DARK from the browser's
color-scheme preference.
"""

obj Theme {
    has bg: str,
        surface: str,
        surfaceMuted: str,
        text: str,
        textMuted: str,
        border: str,
        accent: str,
        accentSoft: str,
        accentText: str,
        headerBg: str;
}

glob:pub LIGHT: Theme = Theme(
         bg="#fbfaf7",
         surface="#ffffff",
         surfaceMuted="#f3f1ec",
         text="#1c1b19",
         textMuted="#5f5b53",
         border="#e4e0d8",
         accent="#2f5d50",
         accentSoft="#e3eee9",
         accentText="#ffffff",
         headerBg="rgba(251, 250, 247, 0.88)"
     );

glob:pub DARK: Theme = Theme(
         bg="#141513",
         surface="#1c1e1b",
         surfaceMuted="#232622",
         text="#ecebe6",
         textMuted="#a5a39b",
         border="#30332e",
         accent="#8cc5b0",
         accentSoft="#22322c",
         accentText="#10201a",
         headerBg="rgba(20, 21, 19, 0.88)"
     );

glob:pub FONT_SANS: str = "'Inter', system-ui, -apple-system, 'Segoe UI', sans-serif";
glob:pub FONT_DISPLAY: str = "'Fraunces', Georgia, serif";
glob:pub FONTS_URL: str = "https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&family=Inter:wght@400;500;600&display=swap";
glob:pub RADIUS: str = "14px";

glob:pub DARK_QUERY: str = "(prefers-color-scheme: dark)";
glob:pub NARROW_QUERY: str = "(max-width: 640px)";
glob:pub WIDE_QUERY: str = "(min-width: 960px)";
glob:pub REDUCED_MOTION_QUERY: str = "(prefers-reduced-motion: reduce)";

"""Centered, max-width column used by every section."""
def:pub container(narrow: bool) -> dict[str, str] {
    return {
        "maxWidth": "1080px",
        "margin": "0 auto",
        "padding": "0 16px" if narrow else "0 24px",
        "boxSizing": "border-box"
    };
}

"""Small accent-colored label shown above headings."""
def:pub eyebrow(t: Theme) -> dict[str, str] {
    return {
        "fontSize": "14px",
        "fontWeight": "500",
        "color": t.accent,
        "margin": "0 0 12px"
    };
}

"""Serif display heading."""
def:pub displayHeading(size: str) -> dict[str, str] {
    return {
        "fontFamily": FONT_DISPLAY,
        "fontWeight": "600",
        "fontSize": size,
        "lineHeight": "1.15",
        "margin": "0"
    };
}
