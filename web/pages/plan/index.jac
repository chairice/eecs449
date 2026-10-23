"""Structured planning through the stateless, synthetic fixture endpoint."""

import from "@jac/runtime" { useLocation, useNavigate }
import from react { useRef }
import from server.api { plan_trip }
import from ...components.PageHeading { PageHeading }
import from ...components.TripComposer { TripComposer }
import from ...client.composer_model { ComposerDraft }
import from ...client.planning_request { request_payload, restore_composer, return_payload }

def checked_envelope(response: str) -> any {
    envelope: any = JSON.parse(response);
    if not envelope or envelope["schema_version"] != 1 or envelope["mode"] != "FIXTURE" {
        raise ValueError("Unexpected planning response");
    }
    return envelope;
}

def:pub PlanPage -> JsxPage {
    location = useLocation();
    navigate = useNavigate();
    lifecycle = useRef({"active": True, "pending": False});
    can with entry { lifecycle.current["active"] = True; }
    can with exit { lifecycle.current["active"] = False; }
    has busy: bool = False, failure: str = "";
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
            navigate("/plan/results", {"state": {"preview": envelope, "returnPreview": returnEnvelope, "returnRequested": homeward is not None, "draft": payload, "returnDate": draft.return_date, "requestText": draft.request_text}});
        } except Exception {
            if lifecycle.current["active"] {
                failure = "We couldn't load the demo routes. Your details are still here. Check your connection and try Find demo routes again.";
            }
        } finally {
            lifecycle.current["pending"] = False;
            if lifecycle.current["active"] { busy = False; }
        }
    }
    return <>
        <div className="dt-plan-intro"><PageHeading title="Where are you headed?" description="Search demo trips between Ann Arbor and Chicago."/></div>
        {if failure { <div className="dt-error-summary" role="alert">{failure}</div> }}
        <p className="dt-sr-only" role="status" aria-live="polite">{"Checking synthetic schedules and ranking demo routes…" if busy else ""}</p>
        <TripComposer initial={restore_composer(location.state)} onValidDraft={findRoutes} busy={busy} submitLabel="Search"/>
    </>;
}
