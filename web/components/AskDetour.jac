"""One line to describe a trip in plain language; what Detour heard shows as chips."""

import from .Icon { Icon }

def:pub AskDetour(
    onAsk: Callable[[str], None],
    busy: bool = False,
    heard: list[str] = [],
    readBy: str = "",
    note: str = ""
) -> JsxElement {
    has request: str = "";

    def submit(e: FormEvent) {
        e.preventDefault();
        if busy or request.strip() == "" { return; }
        onAsk(request.strip());
    }

    return <section className="dt-ask" aria-label="Describe your trip">
        <form className="dt-ask-bar" onSubmit={submit}>
            <label className="dt-sr-only" htmlFor="ask-request">Describe your trip</label>
            <input id="ask-request" type="text" maxLength={500} autoComplete="off" value={request}
                placeholder="Try “Chicago Friday after 4, under $50”"
                onChange={lambda (e: ChangeEvent) { request = e.target.value; }}/>
            <button className="dt-primary" type="submit" disabled={busy or request.strip() == ""}>{"Reading…" if busy else "Plan it"}<Icon name="arrow.right"/></button>
        </form>
        <div className="dt-ask-heard" role="status" aria-live="polite">
            {if len(heard) > 0 {
                <>{for chip in heard { <span key={chip} className="dt-chip-heard">{chip}</span> }}
                <span className="dt-muted">{"Read by Claude" if readBy == "claude" else "Read by Detour's built-in parser"}</span></>
            }}
            {if note != "" { <span className="dt-ask-note">{note}</span> }}
        </div>
    </section>;
}
