"""Design tokens and shared style helpers for the landing page.

Landing components consume the same CSS tokens as the shared application
shell. The browser's color-scheme preference selects the token palette.
"""

obj:pub Theme {
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
         bg="var(--dt-bg)",
         surface="var(--dt-surface)",
         surfaceMuted="var(--dt-surface-muted)",
         text="var(--dt-text)",
         textMuted="var(--dt-muted)",
         border="var(--dt-border)",
         accent="var(--dt-accent)",
         accentSoft="var(--dt-accent-soft)",
         accentText="var(--dt-accent-text)",
         headerBg="var(--dt-surface)"
     );

# Both palettes use semantic references; data-theme chooses their CSS values.
glob:pub DARK: Theme = LIGHT;

glob:pub FONT_SANS: str = "var(--dt-font-body)";
glob:pub FONT_DISPLAY: str = "var(--dt-font-display)";
glob:pub FONTS_URL: str = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap";
glob:pub RADIUS: str = "var(--dt-radius-card)";

glob:pub DARK_QUERY: str = "(prefers-color-scheme: dark)";
glob:pub NARROW_QUERY: str = "(max-width: 640px)";
glob:pub WIDE_QUERY: str = "(min-width: 960px)";
glob:pub REDUCED_MOTION_QUERY: str = "(prefers-reduced-motion: reduce)";

"""Centered, max-width column used by every section."""
def:pub container(narrow: bool) -> dict[str, str] {
    return {
        "maxWidth": "var(--dt-content-width)",
        "margin": "0 auto",
        "padding": "0 var(--dt-space-4)" if narrow else "0 var(--dt-space-6)",
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
