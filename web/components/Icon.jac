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
            <><circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/></>
        )}
    </svg>;
}
