"""Structured planning through the stateless, synthetic fixture endpoint."""

import from "@jac/runtime" { useLocation, useNavigate }
import from react { useRef }
import from server.api { plan_trip }
import from server.interpret { interpret_trip }
import from ...components.PageHeading { PageHeading }
import from ...components.TripComposer { TripComposer }
import from ...components.AskDetour { AskDetour }
import from ...client.composer_model { ComposerDraft, ComposerInput, validate_composer }
import from ...client.ask { intent_input, intent_chips, missing_note }
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
    return ComposerInput(origin_text=place["origin"], destination_text=place["destination"]);
}

def:pub PlanPage -> JsxPage {
    location = useLocation();
    navigate = useNavigate();
    # readBy is set only while a plain-language ask runs its search.
    lifecycle = useRef({"active": True, "pending": False, "readBy": ""});
    can with entry { lifecycle.current["active"] = True; }
    can with exit { lifecycle.current["active"] = False; }
    has busy: bool = False, failure: str = "";
    # Plain-language asks: what was heard, who read it, and the form they filled.
    has asking: bool = False, heard: list[str] = [], readBy: str = "", askNote: str = "";
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
    async def ask(request: str) {
        asking = True;
        askNote = "";
        try {
            answer: any = JSON.parse(await interpret_trip(request));
            if not lifecycle.current["active"] { return; }
            form = intent_input(answer, request);
            heard = intent_chips(form);
            readBy = str(answer["source"]);
            seed = form;
            seedKey += 1;
            askNote = missing_note(form);
            result = validate_composer(form, str(answer["today"]));
            if result.draft is not None {
                lifecycle.current["readBy"] = readBy;
                try { await findRoutes(result.draft); }
                finally { lifecycle.current["readBy"] = ""; }
            }
        } except Exception {
            if lifecycle.current["active"] { askNote = "Detour couldn't read that just now. Try again, or use the search below."; }
        } finally {
            if lifecycle.current["active"] { asking = False; }
        }
    }
    return <>
        <div className="dt-plan-intro"><PageHeading title="Where are you headed?" description="Search demo trips between Ann Arbor and Chicago."/></div>
        {if failure { <div className="dt-error-summary" role="alert">{failure}</div> }}
        <p className="dt-sr-only" role="status" aria-live="polite">{"Checking synthetic schedules and ranking demo routes…" if busy else ""}</p>
        <AskDetour onAsk={ask} busy={asking or busy} heard={heard} readBy={readBy} note={askNote}/>
        <TripComposer key={"seed-" + str(seedKey)} initial={seed if seed is not None else place_input(location.state) if place_input(location.state) is not None else restore_composer(location.state)} onValidDraft={findRoutes} busy={busy} submitLabel="Search"/>
    </>;
}
