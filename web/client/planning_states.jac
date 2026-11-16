"""What the planning flow tells the traveler while it works and when it ends.

Pure functions over elapsed time and the checked comparison view, so every
state (loading, no routes, provider failure, stale or partial data) is
fixture-tested without a browser. Components render these words and roles."""

import from ..components.comparison_view { ComparisonView }

glob:pub SLOW_AFTER_MS: float = 10000.0;

obj:pub PlanningStep {
    # state is "done", "current" or "waiting".
    has label: str, state: str;
}
obj:pub PlanningProgressView {
    has phase: str, steps: list[PlanningStep], slow: bool, message: str;
}

"""The phase actually running and, after ten seconds, a longer-wait message.
Stages: "understanding" (reading a sentence), "routes" (the outbound search),
"return" (the trip home). One server request checks routes and then weather,
so while it is out both of those phases are in progress; no percentage is
shown because none is known."""
def:pub planning_progress(stage: str, elapsed_ms: float) -> PlanningProgressView {
    reading = stage == "understanding";
    steps = [PlanningStep(label="Understanding the request", state="current" if reading else "done"),
        PlanningStep(label="Checking routes", state="waiting" if reading else "current"),
        PlanningStep(label="Comparing weather and disruption risk", state="waiting" if reading else "current")];
    phase = "Understanding the request";
    if stage == "return" { phase = "Checking return routes and weather"; }
    elif not reading { phase = "Checking routes and comparing weather and disruption risk"; }
    slow = elapsed_ms >= SLOW_AFTER_MS;
    message = phase + "…";
    if slow { message += " External data is taking longer than expected. You can keep waiting, or cancel and your trip details stay as you entered them."; }
    return PlanningProgressView(phase=phase, steps=steps, slow=slow, message=message);
}

"""How a finished search ends. role is the ARIA role of its message:
"status" (polite) for outcomes the traveler can act on calmly, "alert" when
a provider failed or the result could not be read."""
obj:pub PlanningOutcome {
    has kind: str, role: str, title: str, message: str;
    has details: list[str] = [], retry: bool = False;
}

def:pub planning_outcome(view: ComparisonView) -> PlanningOutcome {
    if not view.valid and not view.error {
        return PlanningOutcome(kind="empty", role="status", title="No trip request to compare yet",
            message="There is no active planning request in this session. Return to planning to start a new trip.");
    }
    if view.error_code == "NO_ROUTES" {
        details = list(view.rejections);
        if view.suggestion { details.append("Suggestion: " + view.suggestion); }
        return PlanningOutcome(kind="no_routes", role="status", title="No routes fit every constraint",
            message="Detour checked the available schedules, but none match all of your trip details.", details=details);
    }
    if view.error_code == "INVALID_REQUEST" {
        return PlanningOutcome(kind="invalid_request", role="alert", title="Some trip details need another look", message=view.error);
    }
    if view.error_code == "INVALID_PREVIEW" {
        return PlanningOutcome(kind="invalid", role="alert", title="This comparison couldn't be read", message=view.error, retry=True);
    }
    if view.error {
        return PlanningOutcome(kind="provider_error", role="alert", title="Routes couldn't be checked",
            message="Detour couldn't reach its route provider, so this is not a no-routes result. " + view.error, retry=True);
    }
    return PlanningOutcome(kind="ready", role="status", title="", message="");
}

"""A caveat on results that are still usable: weather unknown or source data out of date."""
obj:pub DataNotice {
    has kind: str, message: str, retry: bool = False;
}

def:pub data_notices(view: ComparisonView) -> list[DataNotice] {
    notices: list[DataNotice] = [];
    if not view.valid or view.error { return notices; }
    if view.weather_unavailable {
        notices.append(DataNotice(kind="weather_unavailable", retry=True,
            message="Weather couldn't be checked, so these routes are ranked with weather unknown. Unknown is not the same as clear."));
    } elif not view.weather_checked {
        notices.append(DataNotice(kind="weather_unchecked", message="Weather wasn't checked for this search, so it is unknown on every route."));
    }
    if view.stale {
        notices.append(DataNotice(kind="stale", retry=True,
            message="Some route data is out of date. Each route shows where its data came from and when it was fetched."));
    }
    return notices;
}

"""A saved plan's ID from what it is, so saving the same plan again (a double
click, a retry, a return from Trips) replaces it instead of adding a copy."""
def:pub plan_trip_id(parts: list[str]) -> str {
    text: any = "|".join(parts);
    first = 2166136261.0;
    second = 5381.0;
    for index in range(int(text.length)) {
        code = float(text.charCodeAt(index));
        first = (first * 31.0 + code) % 4294967296.0;
        second = (second * 33.0 + code) % 4294967291.0;
    }
    # Both stay whole numbers below 2^32, well inside exact float range.
    left: any = first;
    right: any = second;
    return "trip-" + str(left.toString(36)) + "-" + str(right.toString(36));
}
