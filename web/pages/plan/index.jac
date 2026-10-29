"""
Structured planning through the stateless, synthetic fixture endpoint."""

import from "@jac/runtime" { useLocation, useNavigate }
import from react { useRef }
import from server.api { plan_trip }
import from server.interpret { interpret_trip }
import from ...components.PageHeading { PageHeading }
import from ...components.TripComposer { TripComposer }
import from ...components.AskDetour { AskDetour, ChatMessage }
import from ...client.composer_model { ComposerDraft, ComposerInput, validate_composer }
import from ...client.ask { merged_input, reply_action, reply_text }
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

"""A home-page card starts the conversation: Detour asks for the day."""
def opening_messages(place: ComposerInput | None) -> list[ChatMessage] {
    if place is None { return []; }
    return [ChatMessage(id=0, sender="detour", text=reply_text(place), action=reply_action(place))];
}

"""Resolve after `ms` milliseconds."""
def pause(ms: int) -> any {
    return new(Promise, lambda (resolve: any) { window.setTimeout(resolve, ms); });
}

def:pub PlanPage -> JsxPage {
    location = useLocation();
    navigate = useNavigate();
    # readBy is set only while a plain-language ask runs its search.
    lifecycle = useRef({"active": True, "pending": False, "readBy": ""});
    can with entry { lifecycle.current["active"] = True; }
    can with exit { lifecycle.current["active"] = False; }
    has busy: bool = False, failure: str = "";
    # Chat with Detour: the conversation, who read it, and the form it filled.
    place = place_input(location.state);
    # Back from results with "Edit request": go straight to the manual search.
    editing = bool(location.state and location.state["draft"]);
    has asking: bool = False, messages: list[ChatMessage] = opening_messages(place), readBy: str = "";
    # The trip the conversation has described so far; each message adds to it.
    has chatForm: ComposerInput | None = place;
    # The manual Where/When search stays tucked away until asked for.
    has manual: bool = editing, manualPanel: str = "";
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
        # Built from this call's starting list, so an await never appends to a stale one.
        sent = messages + [ChatMessage(id=len(messages), sender="user", text=request)];
        previous = chatForm;
        messages = sent;
        asking = True;
        try {
            answer: any = JSON.parse(await interpret_trip(request));
            if not lifecycle.current["active"] { return; }
            form = merged_input(previous, answer, request);
            readBy = str(answer["source"]);
            chatForm = form;
            seed = form;
            seedKey += 1;
            messages = sent + [ChatMessage(id=len(sent), sender="detour", text=reply_text(form), action=reply_action(form))];
            result = validate_composer(form, str(answer["today"]));
            if result.draft is not None {
                # Leave Detour's "Looking for…" on screen long enough to read.
                await pause(1200);
                if not lifecycle.current["active"] { return; }
                lifecycle.current["readBy"] = readBy;
                try { await findRoutes(result.draft); }
                finally { lifecycle.current["readBy"] = ""; }
            }
        } except Exception {
            if lifecycle.current["active"] {
                messages = sent + [ChatMessage(id=len(sent), sender="detour", text="I couldn't read that just now. Try again, or choose a destination and dates yourself.", action="where")];
            }
        } finally {
            if lifecycle.current["active"] { asking = False; }
        }
    }
    def openManual(panel: str) {
        manual = True;
        manualPanel = panel;
        if chatForm is not None { seed = chatForm; }
        seedKey += 1;
    }
    return <>
        <div className="dt-plan-intro"><PageHeading title="Where are you headed?" description="Tell Detour where and when. Demo trips run between Ann Arbor and Chicago."/></div>
        {if failure { <div className="dt-error-summary" role="alert">{failure}</div> }}
        <p className="dt-sr-only" role="status" aria-live="polite">{"Checking synthetic schedules and ranking demo routes…" if busy else ""}</p>
        <AskDetour onSend={ask} messages={messages} busy={asking or busy} readBy={readBy} onManual={openManual} manualOpen={manual}/>
        <TripComposer key={"seed-" + str(seedKey)} initial={seed if seed is not None else place if place is not None else restore_composer(location.state)} onValidDraft={findRoutes} busy={busy} submitLabel="Search" searchHidden={not manual} startPanel={manualPanel}/>
    </>;
}
