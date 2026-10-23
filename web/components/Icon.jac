"""Decorative line icons drawn to sit with SF Symbols: 24px grid, round caps,
regular-weight strokes in the current text colour. Paths are from Lucide (ISC);
SF Symbols themselves are licensed for Apple platforms only."""

def:pub Icon(name: str, size: int = 20) -> JsxElement {
    return <svg className="dt-icon" width={size} height={size} viewBox="0 0 24 24" fill="none"
        stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round"
        aria-hidden="true" focusable="false">
        {(
            <><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></> if name == "arrow.right" else
            <><path d="M7 7h10v10"/><path d="M7 17 17 7"/></> if name == "arrow.up.right" else
            <><path d="M8 3 4 7l4 4"/><path d="M4 7h16"/><path d="m16 21 4-4-4-4"/><path d="M20 17H4"/></> if name == "arrow.left.arrow.right" else
            <><path d="M22 12a10.06 10.06 1 0 0-20 0Z"/><path d="M12 12v8a2 2 0 0 0 4 0"/><path d="M12 2v1"/></> if name == "umbrella" else
            <><path d="M20 6 9 17l-5-5"/></> if name == "checkmark" else
            <><path d="M5 12h14"/></> if name == "minus" else
            <><path d="M5 12h14"/><path d="M12 5v14"/></> if name == "plus" else
            <><path d="M6 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18Z"/><path d="M6 12H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2"/><path d="M18 9h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2"/><path d="M10 6h4"/><path d="M10 10h4"/><path d="M10 14h4"/><path d="M10 18h4"/></> if name == "building" else
            <><path d="m15 18-6-6 6-6"/></> if name == "chevron.left" else
            <><path d="m9 18 6-6-6-6"/></> if name == "chevron.right" else
            <><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></> if name == "magnifyingglass" else
            <><path d="M21 4h-7"/><path d="M10 4H3"/><path d="M21 12h-9"/><path d="M8 12H3"/><path d="M21 20h-5"/><path d="M12 20H3"/><path d="M14 2v4"/><path d="M8 10v4"/><path d="M16 18v4"/></> if name == "slider.horizontal" else
            <><path d="M8 6v6"/><path d="M15 6v6"/><path d="M2 12h19.6"/><path d="M18 18h3s.5-1.7.8-2.8c.1-.4.2-.8.2-1.2 0-.4-.1-.8-.2-1.2l-1.4-5C20.1 6.8 19.1 6 18 6H4a2 2 0 0 0-2 2v10h3"/><circle cx="7" cy="18" r="2"/><path d="M9 18h5"/><circle cx="16" cy="18" r="2"/></> if name == "bus" else
            <><path d="M8 3.1V7a4 4 0 0 0 8 0V3.1"/><path d="m9 15-1-1"/><path d="m15 15 1-1"/><path d="M9 19c-2.8 0-5-2.2-5-5v-4a8 8 0 0 1 16 0v4c0 2.8-2.2 5-5 5Z"/><path d="m8 19-2 3"/><path d="m16 19 2 3"/></> if name == "tram" else
            <><circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/></>
        )}
    </svg>;
}
