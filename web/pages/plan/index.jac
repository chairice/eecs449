"""Trip search, after Airbnb's: one bar at a time under two tabs. Ask Detour
(the default) reads a sentence; Choose dates is the manual
Where/When bar. A sentence missing something hands over to the manual bar
with what was understood filled in and the missing panel open."""

import from "@jac/runtime" { useLocation, useNavigate }
import from react { useRef }
import from server.api { plan_trip }
import from server.interpret { interpret_trip }
import from ...components.Icon { Icon }
import from ...components.TripComposer { TripComposer }
import from ...components.DescribeBar { DescribeBar }
import from ...client.composer_model { ComposerDraft, ComposerInput, validate_composer }
import from ...client.ask { intent_input, missing_panel }
import from ...client.planning_request { request_payload, restore_composer, return_payload }

def checked_envelope(response: str) -> any {
    envelope: any = JSON.parse(response);
    if not envelope or envelope["schema_version"] != 1 or envelope["mode"] != "FIXTURE" {
        raise ValueError("Unexpected planning response");
    }
    return envelope;
}

"""A home-page card's trip: just its two ends, the rest left for the visitor."""
def place_input(state: any) -> ComposerInput | None {
    place: any = state["place"] if state else None;
    if not place or not isinstance(place["origin"], str) or not isinstance(place["destination"], str) { return None; }
    # 00:00 leaving after: any time that day, as the search bar does.
    return ComposerInput(origin_text=place["origin"], destination_text=place["destination"], local_time="00:00");
}

def:pub PlanPage -> JsxPage {
    location = useLocation();
    navigate = useNavigate();
    # readBy is set only while a plain-language ask runs its search.
    lifecycle = useRef({"active": True, "pending": False, "readBy": ""});
    can with entry { lifecycle.current["active"] = True; }
    can with exit { lifecycle.current["active"] = False; }
    has busy: bool = False, failure: str = "";
    place = place_input(location.state);
    # Back from results to edit, or from a home card: the manual bar, and for a
    # card, its When panel open, as Airbnb moves on to dates after a place.
    editing = bool(location.state and location.state["draft"]);
    has tab: str = "dates" if editing or place is not None else "describe";
    has manualPanel: str = "when" if place is not None else "";
    has asking: bool = False, described: str = "";
    has seed: ComposerInput | None = None, seedKey: int = 0;
    async def findRoutes(draft: ComposerDraft) {
        if lifecycle.current["pending"] { return; }
        lifecycle.current["pending"] = True;
        busy = True;
        failure = "";
        payload = request_payload(draft);
        homeward = return_payload(draft);

        # Replace this history entry so browser Back restores the submitted form.
        navigate("/plan", {"replace": True, "state": {"draft": payload, "returnDate": draft.return_date, "requestText": draft.request_text}});
        try {
            envelope = checked_envelope(await plan_trip(JSON.stringify(payload)));
            if not lifecycle.current["active"] { return; }
            
            # The trip home is its own search; if it fails, the outbound results still show.
            returnEnvelope: any = None;
            if homeward is not None {
                try { returnEnvelope = checked_envelope(await plan_trip(JSON.stringify(homeward))); }
                except Exception { returnEnvelope = None; }
                if not lifecycle.current["active"] { return; }
            }
            navigate("/plan/results", {"state": {"preview": envelope, "returnPreview": returnEnvelope, "returnRequested": homeward is not None, "draft": payload, "returnDate": draft.return_date, "requestText": draft.request_text, "readBy": lifecycle.current["readBy"]}});
        } except Exception {
            if lifecycle.current["active"] {
                failure = "We couldn't load the demo routes. Your details are still here. Check your connection and try Find demo routes again.";
            }
        } finally {
            lifecycle.current["pending"] = False;
            if lifecycle.current["active"] { busy = False; }
        }
    }
    async def describe(request: str) {
        asking = True;
        described = request;
        try {
            answer: any = JSON.parse(await interpret_trip(request));
            if not lifecycle.current["active"] { return; }
            form = intent_input(answer, request);
            result = validate_composer(form, str(answer["today"]));
            if result.draft is not None {
                lifecycle.current["readBy"] = str(answer["source"]);
                try { await findRoutes(result.draft); }
                finally { lifecycle.current["readBy"] = ""; }
            } else {
                # Hand over to the manual bar with the gap open.
                seed = form;
                seedKey += 1;
                manualPanel = missing_panel(form);
                tab = "dates";
            }
        } except Exception {
            if lifecycle.current["active"] { failure = "Detour couldn't read that just now. Try again, or choose dates yourself."; }
        } finally {
            if lifecycle.current["active"] { asking = False; }
        }
    }
    def showTab(name: str) {
        tab = name;
        manualPanel = "";
        seedKey += 1;
    }
    return <>
        <h1 className="dt-sr-only">Plan a trip</h1>
        {if failure { <div className="dt-error-summary" role="alert">{failure}</div> }}
        <p className="dt-sr-only" role="status" aria-live="polite">{"Checking synthetic schedules and ranking demo routes…" if busy else ""}</p>
        <div className="dt-search-tabs" role="tablist" aria-label="How to search">
            <button type="button" role="tab" id="tab-describe" aria-selected={tab == "describe"} aria-controls="search-panel" onClick={lambda { showTab("describe"); }}><Icon name="sparkles" size={24}/><span>Ask Detour</span></button>
            <button type="button" role="tab" id="tab-dates" aria-selected={tab == "dates"} aria-controls="search-panel" onClick={lambda { showTab("dates"); }}><Icon name="calendar" size={24}/><span>Choose dates</span></button>
        </div>
        <div id="search-panel" role="tabpanel" aria-labelledby={"tab-" + tab}>
            {(<DescribeBar onSearch={describe} busy={asking or busy} initial={described}/> if tab == "describe" else None)}
            <TripComposer key={"seed-" + str(seedKey)} initial={seed if seed is not None else place if place is not None else restore_composer(location.state)} onValidDraft={findRoutes} busy={busy} submitLabel="Search" searchHidden={tab != "dates"} startPanel={manualPanel}/>
        </div>
    </>;
}
