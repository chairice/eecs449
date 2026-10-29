"""Ask Detour in one line, after Airbnb's AI search: a white pill that answers
with results, never a chat. A sparkle and a placeholder in Detour's voice,
cycling through real requests, show it can be talked to; while it reads,
the pill says so. Focus drops a "Try asking" panel like Where's suggestions."""

import from react { useEffect }
import from ..browser { mediaMatches }
import from ..theme { REDUCED_MOTION_QUERY }
import from .Icon { Icon }

glob SUGGESTIONS: list[str] = ["Chicago this Friday after 4pm", "Chicago tomorrow, under $40", "Ann Arbor on Nov 3, back Nov 5"];
# Example requests the placeholder cycles through before anyone types.
glob EXAMPLES: list[str] = ["Chicago Friday after 4pm", "cheapest to Chicago tomorrow", "Ann Arbor Nov 3, back Nov 5"];
glob EXAMPLE_MS: int = 3500;

def:pub DescribeBar(onSearch: Callable[[str], None], busy: bool = False, initial: str = "") -> JsxElement {
    has text: str = initial, open: bool = False, example: int = 0;
    has box: Ref[HTMLDivElement] = Ref();

    def search(request: str) {
        if busy or request.strip() == "" { return; }
        text = request;
        open = False;
        onSearch(request.strip());
    }
    # Like the Where panel, it closes on any click outside the search.
    useEffect(lambda {
        handler = lambda (e: any) {
            current: any = box.current;
            if current and not current.contains(e.target) { open = False; }
        };
        document.addEventListener("mousedown", handler);
        return lambda { document.removeEventListener("mousedown", handler); };
    }, []);
    # Cycle the example while the pill is idle and empty.
    useEffect(lambda {
        if open or text != "" or busy or mediaMatches(REDUCED_MOTION_QUERY) { return lambda { }; }
        timer: any = window.setInterval(lambda { example = (example + 1) % len(EXAMPLES); }, EXAMPLE_MS);
        return lambda { window.clearInterval(timer); };
    }, [open, text, busy, example]);

    placeholder = "Detour is reading your request…" if busy else "Tell Detour where you need to be" if open else "Try “" + EXAMPLES[example] + "”";

    return <div className="dt-search dt-describe" ref={box}>
        <form className={"dt-describe-bar" + (" is-active" if open else "") + (" is-busy" if busy else "")} onSubmit={lambda (e: FormEvent) { e.preventDefault(); search(text); }}>
            <span className="dt-describe-mark" aria-hidden="true"><Icon name="sparkles" size={20}/></span>
            <label className="dt-sr-only" htmlFor="describe-request">Ask Detour: describe your trip</label>
            <input id="describe-request" type="text" maxLength={500} autoComplete="off" value={text}
                placeholder={placeholder} role="combobox" aria-expanded={open}
                aria-controls="dt-describe-panel" aria-autocomplete="list" readOnly={busy}
                onFocus={lambda { open = True; }}
                onChange={lambda (e: ChangeEvent) { text = e.target.value; open = True; }}
                onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Escape" { open = False; } }}/>
            <button className="dt-search-submit" type="submit" disabled={busy} aria-label={"Detour is reading" if busy else "Ask Detour"}><Icon name="arrow.up" size={18}/></button>
        </form>
        <p className="dt-sr-only" role="status" aria-live="polite">{"Detour is reading your request." if busy else ""}</p>
        <div id="dt-describe-panel" className="dt-where-panel" role="listbox" aria-label="Try asking" hidden={not open or text.strip() != ""}>
            <h3 className="dt-panel-heading">Try asking Detour</h3>
            {for suggestion in SUGGESTIONS {
                <button key={suggestion} type="button" role="option" aria-selected={False} className="dt-place" onClick={lambda { search(suggestion); }}>
                    <span className="dt-place-icon"><Icon name="sparkles" size={20}/></span>
                    <span className="dt-place-text"><span className="dt-place-name">{suggestion}</span></span>
                </button>
            }}
            <p className="dt-panel-note">Demo trips run between Ann Arbor and Chicago.</p>
        </div>
    </div>;
}
