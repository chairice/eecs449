"""Structured planning through the stateless, synthetic fixture endpoint."""

import from "@jac/runtime" { useLocation, useNavigate }
import from react { useRef }
import from server.api { plan_trip }
import from ...components.PageHeading { PageHeading }
import from ...components.TripComposer { TripComposer }
import from ...client.composer_model { ComposerDraft }
import from ...client.planning_request { request_payload, restore_composer }

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
        # Replace this history entry so browser Back restores the submitted form.
        navigate("/plan", {"replace": True, "state": {"draft": payload, "requestText": draft.request_text}});
        try {
            response = await plan_trip(JSON.stringify(payload));
            if not lifecycle.current["active"] { return; }
            envelope: any = JSON.parse(response);
            if not envelope or envelope["schema_version"] != 1 or envelope["mode"] != "FIXTURE" {
                raise ValueError("Unexpected planning response");
            }
            navigate("/plan/results", {"state": {"preview": envelope, "draft": payload, "requestText": draft.request_text}});
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
        <PageHeading eyebrow="New trip" title="Where do you need to be?" description="Describe the outcome. Detour will work out the options and show its reasoning."/>
        <div className="dt-two-column">
            <div>
                {if failure { <div className="dt-error-summary" role="alert">{failure}</div> }}
                <p role="status" aria-live="polite">{"Checking synthetic schedules and ranking demo routes…" if busy else ""}</p>
                <TripComposer initial={restore_composer(location.state)} onValidDraft={findRoutes} busy={busy} submitLabel="Find demo routes"/>
            </div>
            <aside className="dt-panel">
                <h2 className="dt-kicker">Start with the corridor</h2>
                <p>This fixture demo connects Ann Arbor and Chicago using synthetic schedules and prices. Delay and weather signals remain unknown.</p>
                <ul className="dt-example-list"><li>“Leave Ann Arbor after 4 PM. Keep the trip under $50.”</li><li>“Get me to Chicago before 9 PM, with at least 30 minutes between connections.”</li><li>“Prefer a direct train, even if it costs more.”</li></ul>
                <p className="dt-caption">No live schedules, booking, or saved trips. Natural-language interpretation is not connected; the explicit fields determine your search.</p>
            </aside>
        </div>
        <section className="dt-section"><h2 className="dt-kicker">What Detour will consider</h2>
            <div className="dt-feature-grid"><article><h3>Schedule fit</h3><p>Arrival targets and buffers</p></article><article><h3>Transfer risk</h3><p>Connections and fallback time</p></article><article><h3>Conditions</h3><p>Weather and active alerts</p></article></div>
        </section>
    </>;
}
