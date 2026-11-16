"""Honest multi-phase loading state: names the running phase, says when external
data is slow, and never shows a percentage. Cancel keeps the trip details."""

import from react { useEffect }
import from ..client.planning_states { planning_progress }

def step_mark(state: str) -> str {
    if state == "done" { return "Done"; }
    if state == "current" { return "In progress"; }
    return "Waiting";
}

def:pub PlanningProgress(stage: str, startedAt: float, onCancel: Callable[[], None]) -> JsxElement {
    has now: float = Date.now();
    def tick {
        now = Date.now();
    }
    useEffect(lambda {
        timer = setInterval(lambda { tick(); }, 1000);
        return lambda { clearInterval(timer); };
    }, []);
    view = planning_progress(stage, now - startedAt);
    return <section className="dt-panel rounded-2xl border border-gray-200 bg-white p-5 shadow-sm" aria-labelledby="planning-progress-heading" aria-busy="true">
        <h2 id="planning-progress-heading" className="text-lg font-semibold tracking-tight text-gray-900">Planning your trip</h2>
        <ol className="mt-3 grid list-none gap-2 p-0">
            {for step in view.steps {
                <li key={step.label} className={"flex items-center justify-between gap-3 text-sm " + ("font-semibold text-gray-900" if step.state == "current" else "text-gray-500")} aria-current={"step" if step.state == "current" else None}>
                    <span>{step.label}</span><span className="text-xs">{step_mark(step.state)}</span>
                </li>
            }}
        </ol>
        <p className="mt-3 text-sm text-gray-700" role="status" aria-live="polite">{view.message}</p>
        <button type="button" className="mt-3 inline-flex h-11 cursor-pointer items-center rounded-full border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700 hover:border-gray-500" onClick={lambda { onCancel(); }}>Cancel search</button>
    </section>;
}
