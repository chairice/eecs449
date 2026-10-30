"""Conversation-first travel atlas. Proposals and saved journeys stay separate.

The page owns interaction state; atlas_state validates browser data. Only an
explicit provider request leaves the browser. Saving never books a trip.
"""
import "../atlas.css";
import from react { useEffect, useRef }
import from "@jac/runtime" { useNavigate }
import from server.atlas { atlas_catalog, atlas_status, atlas_interpret, atlas_route }
import from .AtlasMap { AtlasMap }
import from ..client.atlas_navigation { set_atlas_history_handler }
import from ..client.atlas_state {
    new_journey, clone_value, search_places, load_atlas, write_atlas,
    validate_journey, add_stop, update_stop, remove_stop, move_stop,
    set_leg_field, apply_proposal
}

def:pub AtlasStopEditor(stop: any, index: int, total: int, catalog: any,
    onChange: Callable[[int, any, str], None], onRemove: Callable[[int], None],
    onMove: Callable[[int, int], None]) -> JsxElement {
    has open: bool = False;
    choices = search_places(catalog, str(stop["query"])) if open and len(str(stop["query"])) >= 2 else [];
    def choose(place: any) { onChange(index, place, str(place["name"]) + ", " + str(place["state"])); open = False; }
    return <div className="atlas-stop">
        <div className="atlas-row"><label htmlFor={"atlas-stop-" + str(index)}><span className="atlas-stop-number">{index + 1}</span>{" Stop " + str(index + 1)}</label>
            <div className="atlas-actions">
                <button type="button" className="atlas-icon-button" aria-label={"Move stop " + str(index + 1) + " up"} disabled={index == 0} onClick={lambda { onMove(index, -1); }}>↑</button>
                <button type="button" className="atlas-icon-button" aria-label={"Move stop " + str(index + 1) + " down"} disabled={index == total - 1} onClick={lambda { onMove(index, 1); }}>↓</button>
                <button type="button" className="atlas-icon-button" aria-label={"Remove stop " + str(index + 1)} onClick={lambda { onRemove(index); }}>×</button>
            </div>
        </div>
        <input id={"atlas-stop-" + str(index)} value={stop["query"]} maxLength={240} placeholder="City, state or airport code" autoComplete="off"
            onFocus={lambda { open = True; }} onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Escape" { open = False; } }}
            onChange={lambda (e: ChangeEvent) { onChange(index, None, str(e.target.value)); open = True; }}/>
        {(<p className="atlas-note">{str(stop["place"]["kind"]).lower() + " · " + str(stop["place"]["name"]) + ", " + str(stop["place"]["state"])}</p> if stop["place"] else <p className="atlas-note">Choose a result to resolve this stop.</p>)}
        {(<ul className="atlas-search-results" aria-label={"Places for stop " + str(index + 1)}>
            {for place in choices { <li key={place["id"]}><button type="button" onClick={lambda { choose(place); }}>
                {str(place["name"]) + ", " + str(place["state"])}<small>{str(place["kind"]).lower() + " · " + str(place["county"]) + (" · " + str(place["code"]) if place["code"] else "")}</small>
            </button></li> }}
        </ul> if len(choices) > 0 else None)}
        {(<p className="atlas-note">No local match. Try a city and state or an airport code. Street addresses and international places are not supported.</p> if open and len(str(stop["query"])) >= 2 and len(choices) == 0 else None)}
    </div>;
}

def:pub AtlasLegEditor(leg: any, index: int, routable: bool, onField: Callable[[int, str, str], None], onRoute: Callable[[int], None]) -> JsxElement {
    return <div className="atlas-leg">
        <label className="atlas-field">{"Leg " + str(index + 1) + " travel mode"}
            <select value={leg["mode"]} onChange={lambda (e: ChangeEvent) { onField(index, "mode", str(e.target.value)); }}>
                <option value="UNKNOWN">Choose a mode</option><option value="FLIGHT">Flight</option><option value="DRIVE">Driving</option>
            </select>
        </label>
        <div className="atlas-grid">
            <label className="atlas-field">Departure date<input type="date" value={leg["departDate"]} onInput={lambda (e: any) { onField(index, "departDate", str(e.target.value)); }} onChange={lambda (e: ChangeEvent) { onField(index, "departDate", str(e.target.value)); }}/></label>
            <label className="atlas-field">Arrival date<input type="date" value={leg["arriveDate"]} onInput={lambda (e: any) { onField(index, "arriveDate", str(e.target.value)); }} onChange={lambda (e: ChangeEvent) { onField(index, "arriveDate", str(e.target.value)); }}/></label>
            <label className="atlas-field">Departure time<input type="time" value={leg["departTime"]} onInput={lambda (e: any) { onField(index, "departTime", str(e.target.value)); }} onChange={lambda (e: ChangeEvent) { onField(index, "departTime", str(e.target.value)); }}/></label>
            <label className="atlas-field">Arrival time<input type="time" value={leg["arriveTime"]} onInput={lambda (e: any) { onField(index, "arriveTime", str(e.target.value)); }} onChange={lambda (e: ChangeEvent) { onField(index, "arriveTime", str(e.target.value)); }}/></label>
        </div>
        <label className="atlas-field">Timing note<input value={leg["timingNote"]} maxLength={2000} placeholder="Optional, e.g. Monday night" onChange={lambda (e: ChangeEvent) { onField(index, "timingNote", str(e.target.value)); }}/></label>
        <p className="atlas-note">Dates and times are optional local intentions, not verified schedules.</p>
        {(<><span className="atlas-status">{("Calculated road route" if leg["route"]["status"] == "READY" else "Route not calculated")}</span>
            {(<p className="atlas-note">{leg["route"]["message"]}</p> if leg["route"]["message"] else None)}
            <button type="button" disabled={not routable} onClick={lambda { onRoute(index); }}>{"Recalculate road route" if leg["route"]["status"] == "READY" else "Calculate / retry road route"}</button>
        </> if leg["mode"] == "DRIVE" else <p className="atlas-note">{"Illustrative arc only—not an aircraft track or ticket." if leg["mode"] == "FLIGHT" else "Choose a travel mode; it will not be guessed."}</p>)}
    </div>;
}

def:pub AtlasStudio -> JsxElement {
    navigate = useNavigate();
    lifecycle = useRef({"active": True, "revision": 0});
    historyGuard = useRef({"restoring": False, "allow": False, "action": None});
    has catalog: any = [], states: any = None;
    has journeys: any = [], draft: any = None, baseline: any = None;
    has ready: bool = False, aiAvailable: bool = False, busy: bool = False;
    has error: str = "", notice: str = "", prompt: str = "";
    has panel: str = "list", statusFilter: str = "ALL", modeFilter: str = "ALL";
    has selectedId: str = "", fitVersion: int = 0, resetVersion: int = 0;
    has presenting: bool = False, pending: any = None;
    dirty = draft is not None and JSON.stringify(draft) != JSON.stringify(baseline);

    def remember(nextJourneys: any, nextDraft: any) -> bool {
        failure = write_atlas(nextJourneys, nextDraft);
        if failure { error = failure; return False; }
        return True;
    }
    def replaceDraft(value: any) {
        lifecycle.current["revision"] += 1;
        draft = value;
        selectedId = str(value["id"]) if value else "";
        notice = "";
        if ready { _ = remember(journeys, value); }
    }
    def editField(field: str, value: str) {
        updated = clone_value(draft); updated[field] = value; replaceDraft(updated);
    }
    def editPrompt(value: str) { prompt = value; editField("pendingPrompt", value); }
    def chooseStop(index: int, place: any, query: str) { replaceDraft(update_stop(draft, index, place, query)); }
    def removeStop(index: int) { replaceDraft(remove_stop(draft, index)); }
    def moveStop(index: int, offset: int) { replaceDraft(move_stop(draft, index, offset)); }
    def legField(index: int, field: str, value: str) { replaceDraft(set_leg_field(draft, index, field, value)); }

    async def loadData {
        try {
            result: any = JSON.parse(await atlas_catalog());
            if not lifecycle.current["active"] { return; }
            if not Array.isArray(result["places"]) or not result["states"] { raise ValueError("Catalog unavailable"); }
            catalog = result["places"]; states = result["states"];
            status: any = JSON.parse(await atlas_status());
            if lifecycle.current["active"] { aiAvailable = bool(status["aiAvailable"]); }
        } except Exception {
            if lifecycle.current["active"] { error = "Atlas could not load its geographic catalog. Retry without losing your draft."; }
        }
    }
    useEffect(lambda {
        lifecycle.current["active"] = True;
        stored = load_atlas(); journeys = stored["journeys"]; draft = stored["draft"]; error = str(stored["error"]);
        if draft {
            selectedId = str(draft["id"]); panel = "edit"; notice = "Recovered your unsaved draft.";
            prompt = str(draft["pendingPrompt"] or "");
            for item in journeys { if item["id"] == draft["id"] { baseline = clone_value(item); } }
        }
        ready = True;
        loadData();
        return lambda { lifecycle.current["active"] = False; lifecycle.current["revision"] += 1; };
    }, []);

    def openNow(action: any) {
        pending = None; error = ""; notice = ""; prompt = "";
        lifecycle.current["revision"] += 1;
        if action["kind"] == "leave" { navigate(str(action["href"])); return; }
        if action["kind"] == "history" {
            historyGuard.current["allow"] = True;
            window.history.go(int(action["delta"])); return;
        }
        if action["kind"] == "new" { baseline = None; panel = "edit"; replaceDraft(new_journey()); return; }
        if action["kind"] == "edit" {
            for item in journeys {
                if item["id"] == action["id"] { baseline = clone_value(item); panel = "edit"; prompt = str(item["pendingPrompt"] or ""); replaceDraft(clone_value(item)); return; }
            }
        }
        baseline = None; draft = None; selectedId = ""; panel = str(action["kind"]);
        _ = remember(journeys, None);
    }
    def requestOpen(action: any) {
        if busy { return; }
        if dirty { pending = action; return; }
        openNow(action);
    }
    def selectJourney(id: str) { if id != selectedId { requestOpen({"kind": "edit", "id": id}); } }
    def saveJourney -> bool {
        if draft is None { return False; }
        problems = validate_journey(draft);
        if len(problems) > 0 { error = " ".join(problems); return False; }
        saved = clone_value(draft);
        updated = [saved] + [item for item in journeys if item["id"] != saved["id"]];
        if not remember(updated, None) { return False; }
        journeys = updated; baseline = clone_value(saved); draft = saved; error = ""; notice = "Journey saved in this browser. Nothing has been booked.";
        return True;
    }
    def confirmSave {
        destination = pending;
        if saveJourney() and destination { openNow(destination); }
    }
    def confirmDiscard {
        destination = pending;
        if remember(journeys, None) { openNow(destination); }
    }
    def trashJourney(id: str, restore: bool = False) {
        updated = clone_value(journeys);
        for item in updated { if item["id"] == id { item["deletedAt"] = "" if restore else str((new(Date)).toISOString()); } }
        if remember(updated, None) {
            journeys = updated; draft = None; baseline = None; selectedId = "";
            panel = "trash" if restore else "list";
            notice = "Journey restored." if restore else "Moved to Trash. You can restore it at any time.";
        }
    }

    useEffect(lambda {
        historyState: any = window.history.state;
        currentIndex = int(historyState["idx"]) if historyState and Number.isInteger(historyState["idx"]) else 0;
        leaving = lambda (event: any) {
            if dirty { event.preventDefault(); event.returnValue = ""; }
        };
        clicking = lambda (event: any) {
            target: any = event.target;
            anchor: any = target.closest("a[href]") if target and target.closest else None;
            if dirty and anchor and anchor.getAttribute("href").startsWith("/") and not anchor.getAttribute("href").startsWith("/atlas") {
                event.preventDefault(); event.stopPropagation(); pending = {"kind": "leave", "href": anchor.getAttribute("href")};
            }
        };
        keyboard = lambda (event: any) { if event.key == "Escape" { presenting = False; } };
        # Browser Back/Forward do not trigger anchor clicks or beforeunload.
        # Undo the history move before asking; only explicit approval replays it.
        historyChanging = lambda (event: any) {
            if historyGuard.current["restoring"] {
                event.stopImmediatePropagation();
                historyGuard.current["restoring"] = False;
                pending = historyGuard.current["action"];
                return;
            }
            if historyGuard.current["allow"] { historyGuard.current["allow"] = False; return; }
            targetState: any = event.state;
            if dirty and targetState and Number.isInteger(targetState["idx"]) {
                delta = int(targetState["idx"]) - currentIndex;
                if delta != 0 {
                    event.stopImmediatePropagation();
                    historyGuard.current["restoring"] = True;
                    historyGuard.current["action"] = {"kind": "history", "delta": delta};
                    window.history.go(-delta);
                }
            }
        };
        window.addEventListener("beforeunload", leaving);
        set_atlas_history_handler(historyChanging);
        document.addEventListener("click", clicking, True);
        document.addEventListener("keydown", keyboard);
        return lambda {
            window.removeEventListener("beforeunload", leaving);
            set_atlas_history_handler(None);
            document.removeEventListener("click", clicking, True);
            document.removeEventListener("keydown", keyboard);
        };
    }, [dirty]);

    async def ask {
        if busy or not draft or not prompt.strip() { return; }
        if draft["conversation"].length > 78 { error = "This journey has reached its conversation limit. Your history is preserved; continue with the manual editor."; return; }
        submitted = prompt.strip();
        current = clone_value(draft);
        current["pendingPrompt"] = "";
        current["conversation"].push({"role": "user", "content": submitted});
        replaceDraft(current); prompt = ""; busy = True; error = "";
        revision = lifecycle.current["revision"];
        try {
            # Route geometry, notes and conversation history never leave the browser.
            context = {"title": current["title"], "status": current["status"],
                "stops": [{"query": stop["query"], "place": {"id": stop["place"]["id"]} if stop["place"] else None} for stop in current["stops"]],
                "legs": [{"mode": leg["mode"], "departDate": leg["departDate"], "arriveDate": leg["arriveDate"], "departTime": leg["departTime"], "arriveTime": leg["arriveTime"], "timingNote": leg["timingNote"]} for leg in current["legs"]]};
            result: any = JSON.parse(await atlas_interpret(submitted, JSON.stringify(context) if current["stops"].length > 0 else ""));
            if not lifecycle.current["active"] or lifecycle.current["revision"] != revision { return; }
            proposal = result["proposal"];
            updated = apply_proposal(current, proposal, catalog) if proposal else current;
            updated["conversation"].push({"role": "assistant", "content": ("AI proposal: " if result["source"] == "llm" else "Rules / manual fallback: ") + str(result["message"])});
            replaceDraft(updated);
            notice = "Review every stop, mode and date before saving. Nothing has been booked.";
        } except Exception {
            if lifecycle.current["active"] and lifecycle.current["revision"] == revision { error = "Interpretation failed. Your original request and draft are preserved; retry or edit manually."; prompt = submitted; }
        } finally { if lifecycle.current["active"] { busy = False; } }
    }
    async def calculateRoute(index: int) {
        if busy or not draft { return; }
        start = draft["stops"][index]["place"]; end = draft["stops"][index + 1]["place"];
        if not start or not end { error = "Resolve both places before calculating a road route."; return; }
        busy = True; error = ""; revision = lifecycle.current["revision"];
        try {
            result: any = JSON.parse(await atlas_route(str(start["id"]), str(end["id"])));
            if not lifecycle.current["active"] or lifecycle.current["revision"] != revision { return; }
            updated = clone_value(draft);
            if result["status"] == "READY" or updated["legs"][index]["route"]["status"] != "READY" {
                updated["legs"][index]["route"] = result;
            }
            replaceDraft(updated);
            notice = "Road geometry updated. This is a calculated approximation, not a recorded drive." if result["status"] == "READY" else str(result["message"]);
        } except Exception {
            if lifecycle.current["active"] { error = "Routing is unavailable. Your stops and previous route are preserved; you can save and retry later."; }
        } finally { if lifecycle.current["active"] { busy = False; } }
    }
    def example {
        baseline = None; panel = "edit";
        value = new_journey();
        proposal = {"title": "Example · Coast to coast", "status": "PLANNED", "note": "Illustrative example, not your travel history.",
            "stops": [{"query": "DTW"}, {"query": "JFK"}, {"query": "BOS"}],
            "legs": [{"mode": "FLIGHT"}, {"mode": "DRIVE"}], "unresolved": []};
        value = apply_proposal(value, proposal, catalog);
        replaceDraft(value); fitVersion += 1;
    }
    # One draft replaces its saved counterpart only in the preview, never storage.
    displayed = [item for item in journeys if not item["deletedAt"] and (draft is None or item["id"] != draft["id"])];
    if draft is not None { displayed = displayed + [draft]; }
    displayed = [item for item in displayed if item["id"] == selectedId or statusFilter == "ALL" or item["status"] == statusFilter];
    active = [item for item in journeys if not item["deletedAt"]];
    filtered = [item for item in active if (statusFilter == "ALL" or item["status"] == statusFilter) and (modeFilter == "ALL" or len([leg for leg in item["legs"] if leg["mode"] == modeFilter]) > 0)];
    trashed = [item for item in journeys if item["deletedAt"]];

    return <section className={"atlas-workspace" + (" is-presenting" if presenting else "")} aria-label="Travel atlas">
        <div className="atlas-toolbar">
            <div className="atlas-heading"><span className="atlas-kicker">Your world, one journey at a time</span><h1>Atlas</h1><span className="atlas-count">{str(len(active)) + " saved journeys · this browser"}</span></div>
            <div className="atlas-actions">
                {(<><button type="button" disabled={busy or len(catalog) == 0} onClick={lambda { requestOpen({"kind": "new"}); }}>Add journey</button>
                    <button type="button" disabled={not selectedId} onClick={lambda { fitVersion += 1; }}>Fit journey</button>
                    <button type="button" onClick={lambda { resetVersion += 1; }}>Reset view</button></> if not presenting else None)}
                <button type="button" onClick={lambda { presenting = not presenting; }}>{"Exit presentation" if presenting else "Present"}</button>
            </div>
            {(<div className="atlas-legend"><span><i></i>Past</span><span><i className="is-planned"></i>Planned</span></div> if presenting else None)}
        </div>
        <div className="atlas-body">
            <aside className="atlas-panel" aria-label="Journey editor">
                {(<div className="atlas-error" role="alert">{error}<button type="button" onClick={lambda { error = ""; }}>Dismiss</button></div> if error else None)}
                {(<p className="atlas-note" role="status">{notice}</p> if notice else None)}
                {(<div className="atlas-loading" role="status">Loading the local US place catalog…<button type="button" onClick={loadData}>Retry catalog</button></div> if len(catalog) == 0 else None)}
                {(<div className="atlas-confirm" role="dialog" aria-label="Unsaved journey"><h2>Keep your changes?</h2><p>Your recovery draft is separate from the saved journey.</p><div className="atlas-actions"><button type="button" onClick={confirmSave}>Save and continue</button><button type="button" onClick={confirmDiscard}>Discard changes</button><button type="button" onClick={lambda { pending = None; }}>Keep editing</button></div></div> if pending else None)}
                <div className="atlas-tabs"><button type="button" aria-pressed={panel == "list"} disabled={busy} onClick={lambda { requestOpen({"kind": "list"}); }}>Journeys</button><button type="button" aria-pressed={panel == "trash"} disabled={busy} onClick={lambda { requestOpen({"kind": "trash"}); }}>{"Trash (" + str(len(trashed)) + ")"}</button></div>
                {(<>
                    <div className="atlas-grid"><label className="atlas-field">Show<select value={statusFilter} onChange={lambda (e: ChangeEvent) { statusFilter = str(e.target.value); }}><option value="ALL">All journeys</option><option value="PAST">Past</option><option value="PLANNED">Planned</option></select></label>
                        <label className="atlas-field">Travel mode<select value={modeFilter} onChange={lambda (e: ChangeEvent) { modeFilter = str(e.target.value); }}><option value="ALL">All modes</option><option value="FLIGHT">Flights</option><option value="DRIVE">Driving</option></select></label></div>
                    {for item in filtered { <button type="button" className="atlas-card" key={item["id"]} disabled={busy} onClick={lambda { selectJourney(str(item["id"])); }}><strong>{item["title"]}</strong><span className="atlas-badge">{item["status"]}</span><p>{str(item["stops"].length) + " stops · " + str(item["legs"].length) + " legs"}</p></button> }}
                    {(<p className="atlas-note">No journeys match these filters.</p> if len(active) > 0 and len(filtered) == 0 else None)}
                    {(<div className="atlas-empty"><h2>A little room for everywhere.</h2><p>Record where you have been. Sketch where you will go next.</p><button type="button" disabled={len(catalog) == 0} onClick={lambda { requestOpen({"kind": "new"}); }}>Create your first journey</button><button type="button" disabled={len(catalog) == 0} onClick={example}>Load example</button></div> if len(active) == 0 else None)}
                </> if panel == "list" else None)}
                {(<><h2>Recoverable Trash</h2>{for item in trashed { <div className="atlas-card" key={item["id"]}><strong>{item["title"]}</strong><button type="button" onClick={lambda { trashJourney(str(item["id"]), True); }}>Restore journey</button></div> }}{(<p className="atlas-note">Nothing in Trash.</p> if len(trashed) == 0 else None)}</> if panel == "trash" else None)}
                {(<div className="atlas-form">
                    <div className="atlas-row"><h2>{"Edit journey" if baseline else "Create a journey"}</h2><span className="atlas-badge">{("Unsaved draft" if dirty else "Saved")}</span></div>
                    <div className="atlas-chat">
                        <p className="atlas-note">{"Describe or refine your journey with AI. Review the proposal before saving." if aiAvailable else "AI creation is not configured. Use the limited rules parser or edit stops manually—no key required."}</p>
                        {for (i, message) in enumerate(draft["conversation"]) { <div key={str(i)} className={"atlas-message" + (" is-user" if message["role"] == "user" else "")}>{message["content"]}</div> }}
                        <form className="atlas-chat-input" onSubmit={lambda (e: FormEvent) { e.preventDefault(); ask(); }}><label className="atlas-field" htmlFor="atlas-request">Describe or refine this journey</label><textarea id="atlas-request" value={prompt} maxLength={4000} placeholder="Fly from Detroit to New York, then drive to Boston…" disabled={busy} onChange={lambda (e: ChangeEvent) { editPrompt(str(e.target.value)); }}/><button type="submit" className="is-primary" disabled={busy or not prompt.strip() or len(catalog) == 0 or draft["conversation"].length > 78}>{"Working…" if busy else "Preview AI changes" if aiAvailable else "Preview with limited rules"}</button></form>
                        {(<p className="atlas-note">Conversation limit reached. Your history is preserved; continue editing manually.</p> if draft["conversation"].length > 78 else None)}
                        <p className="atlas-note">An AI request sends this sentence and current itinerary fields to the configured model—not your other journeys or notes. Nothing is booked.</p>
                    </div>
                    {(<div className="atlas-confirm"><h3>Review unresolved details</h3><ul>{for detail in draft["unresolved"] { <li key={str(detail)}>{detail}</li> }}</ul><p>Use the original request above and the fields below to correct the proposal.</p><button type="button" disabled={busy} onClick={lambda { updated = clone_value(draft); updated["unresolved"] = []; replaceDraft(updated); }}>I reviewed these details</button></div> if draft["unresolved"].length > 0 else None)}
                    <fieldset disabled={busy} className="atlas-form" style={{"border": "0", "padding": "0", "margin": "0", "minWidth": "0"}}>
                        <label className="atlas-field">Journey title<input value={draft["title"]} maxLength={200} placeholder="Give this journey a name" onChange={lambda (e: ChangeEvent) { editField("title", str(e.target.value)); }}/></label>
                        <div className="atlas-grid"><label className="atlas-field">Journey status<select value={draft["status"]} onChange={lambda (e: ChangeEvent) { editField("status", str(e.target.value)); }}><option value="PLANNED">Planned</option><option value="PAST">Past</option></select></label>
                            <label className="atlas-field">Route color<select value={draft["color"]} onChange={lambda (e: ChangeEvent) { editField("color", str(e.target.value)); }}><option value="#36b9ac">Coastal teal</option><option value="#486249">Forest</option><option value="#bb7954">Terracotta</option><option value="#697ca6">Slate blue</option><option value="#9b77a0">Heather</option></select></label></div>
                        {for (index, stop) in enumerate(draft["stops"]) { <div key={str(index)}><AtlasStopEditor stop={stop} index={index} total={int(draft["stops"].length)} catalog={catalog} onChange={chooseStop} onRemove={removeStop} onMove={moveStop}/>
                            {(<AtlasLegEditor leg={draft["legs"][index]} index={index} routable={bool(stop["place"] and draft["stops"][index + 1]["place"])} onField={legField} onRoute={calculateRoute}/> if index < draft["legs"].length else None)}
                        </div> }}
                        <button type="button" disabled={draft["stops"].length >= 24} onClick={lambda { replaceDraft(add_stop(draft)); }}>Add stop</button>
                        <label className="atlas-field">Journey note<textarea value={draft["note"]} maxLength={8000} placeholder="Optional memories, ideas, or details for future planning" onChange={lambda (e: ChangeEvent) { editField("note", str(e.target.value)); }}/></label>
                    </fieldset>
                    <div className="atlas-actions"><button type="button" className="is-primary" disabled={busy} onClick={saveJourney}>Save journey</button><button type="button" disabled={busy} onClick={lambda { requestOpen({"kind": "list"}); }}>Back to journeys</button>
                        {(<button type="button" className="is-danger" disabled={busy or dirty} onClick={lambda { trashJourney(str(draft["id"])); }}>Move to Trash</button> if baseline else None)}</div>
                </div> if panel == "edit" and draft is not None else None)}
                <div className="atlas-legend"><span><i></i>Past</span><span><i className="is-planned"></i>Planned</span></div>
                <p className="atlas-note">Saved only in this browser. Flight arcs are illustrative; road lines are calculated approximations. US destinations only. Dates never mark a journey completed automatically.</p>
                <details className="atlas-note"><summary>Data, privacy & limitations</summary><p>Local place search uses GeoNames (CC BY 4.0) and OurAirports (public domain). Boundaries: Natural Earth (public domain). Road calculations send selected endpoints to the public OSRM service, which logs requests. No payment or booking occurs.</p><a href="https://routing.openstreetmap.de/about.html" target="_blank" rel="noreferrer">Routing service policy</a>{" · "}<a href="https://www.openstreetmap.org/fixthemap" target="_blank" rel="noreferrer">Fix the map</a></details>
            </aside>
            <div className="atlas-map-shell"><AtlasMap journeys={displayed} states={states} selectedId={selectedId} modeFilter={"ALL" if panel == "edit" else modeFilter} fitVersion={fitVersion} resetVersion={resetVersion} onSelect={selectJourney} presentation={presenting}/></div>
        </div>
    </section>;
}
