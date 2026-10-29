"""Describe a trip in one line, after Airbnb's AI search: the same pill as the
manual search bar, and a "Try asking" panel under it in place of Where's
suggested destinations. It answers with results, never a chat."""

import from react { useEffect }
import from .Icon { Icon }

glob SUGGESTIONS: list[str] = ["Chicago this Friday after 4pm", "Chicago tomorrow, under $40", "Ann Arbor on Nov 3, back Nov 5"];

def:pub DescribeBar(onSearch: Callable[[str], None], busy: bool = False, initial: str = "") -> JsxElement {
    has text: str = initial, open: bool = False;
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

    return <div className="dt-search dt-describe" ref={box}>
        <form className={"dt-describe-bar" + (" is-active" if open else "")} onSubmit={lambda (e: FormEvent) { e.preventDefault(); search(text); }}>
            <label className="dt-describe-field" htmlFor="describe-request">
                <span>Describe your trip</span>
                <input id="describe-request" type="text" maxLength={500} autoComplete="off" value={text}
                    placeholder="Where and when?" role="combobox" aria-expanded={open}
                    aria-controls="dt-describe-panel" aria-autocomplete="list"
                    onFocus={lambda { open = True; }}
                    onChange={lambda (e: ChangeEvent) { text = e.target.value; open = True; }}
                    onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Escape" { open = False; } }}/>
            </label>
            <button className="dt-search-submit" type="submit" disabled={busy} aria-label={"Searching" if busy else "Search"}><Icon name="magnifyingglass"/></button>
        </form>
        <div id="dt-describe-panel" className="dt-where-panel" role="listbox" aria-label="Try asking" hidden={not open or text.strip() != ""}>
            <h3 className="dt-panel-heading">Try asking</h3>
            {for suggestion in SUGGESTIONS {
                <button key={suggestion} type="button" role="option" aria-selected={False} className="dt-place" onClick={lambda { search(suggestion); }}>
                    <span className="dt-place-icon"><Icon name="magnifyingglass" size={20}/></span>
                    <span className="dt-place-text"><span className="dt-place-name">{suggestion}</span></span>
                </button>
            }}
        </div>
    </div>;
}
