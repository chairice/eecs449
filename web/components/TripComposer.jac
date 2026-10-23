"""Airbnb-style trip search: one bar for the essentials, defaults for the rest,
and a map of the places it recognises. Validation stays local."""

import from ..client.composer_model {
    ComposerInput, ComposerDraft, FieldError, copy_input, example_input, field_error, update_input, validate_composer
}
import from .composer_dom { focus_composer_errors }
import from .Icon { Icon }
import from .RouteMap { RouteMap }
import from .comparison_view { ComparisonStop }

# The demo planner has one origin, so the search bar asks only where and when.
glob DEFAULT_ORIGIN: str = "Ann Arbor, MI";

def starting_form(initial: ComposerInput | None) -> ComposerInput {
    form = copy_input(initial) if initial is not None else ComposerInput();
    if form.origin_text == "" { form.origin_text = DEFAULT_ORIGIN; }
    return form;
}

"""Pin places the demo planner accepts, using its normalisation; anything else stays off the map."""
def known_stop(text: str) -> ComparisonStop | None {
    key = " ".join(text.lower().replace(",", " ").split());
    if key in ["ann arbor", "ann arbor mi", "ann arbor michigan"] {
        return ComparisonStop(name="Ann Arbor", latitude=42.2877, longitude=-83.743);
    }
    if key in ["chicago", "chicago il", "chicago illinois"] {
        return ComparisonStop(name="Chicago", latitude=41.8786, longitude=-87.6405);
    }
    return None;
}

"""One tappable day in the When panel."""
obj:pub DayOption { has iso: str, label: str; }

# Hourly departure or arrival times offered as chips, 5 AM to 10 PM.
glob TIME_SLOTS: list[str] = ["05:00", "06:00", "07:00", "08:00", "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00", "17:00", "18:00", "19:00", "20:00", "21:00", "22:00"];

def two_digits(value: int) -> str { return ("0" if value < 10 else "") + str(value); }

def today_iso -> str {
    now: any = new(Date);
    return str(now.getFullYear()) + "-" + two_digits(int(now.getMonth()) + 1) + "-" + two_digits(int(now.getDate()));
}

"""Read the ISO date at UTC noon so the label never slips a day across zones."""
def day_label(iso: str, today: str) -> str {
    if iso == today { return "Today"; }
    noon: any = new(Date, iso + "T12:00:00Z");
    return str(noon.toLocaleDateString("en-US", {"weekday": "short", "month": "short", "day": "numeric", "timeZone": "UTC"}));
}

"""Two weeks from today, plus the chosen date if it falls outside them."""
def day_options(selected: str) -> list[DayOption] {
    today = today_iso();
    start: any = new(Date, today + "T12:00:00Z");
    days: list[DayOption] = [];
    for offset in range(14) {
        day: any = new(Date, float(start.getTime()) + offset * 86400000);
        iso = str(day.toISOString().slice(0, 10));
        days.append(DayOption(iso=iso, label=day_label(iso, today)));
    }
    if selected != "" and selected not in [day.iso for day in days] {
        days.insert(0, DayOption(iso=selected, label=day_label(selected, today)));
    }
    return days;
}

def time_options(selected: str) -> list[str] {
    if selected != "" and selected not in TIME_SLOTS { return sorted(TIME_SLOTS + [selected]); }
    return TIME_SLOTS;
}

"""24-hour "16:00" as "4:00 PM"."""
def time_label(value: str) -> str {
    hour = int(value.split(":")[0]);
    minutes = value.split(":")[1];
    return str(12 if hour % 12 == 0 else hour % 12) + ":" + minutes + (" AM" if hour < 12 else " PM");
}

def when_summary(form: ComposerInput) -> str {
    if form.local_date == "" and form.local_time == "" { return ""; }
    day = day_label(form.local_date, today_iso()) if form.local_date != "" else "Add date";
    time = ("Leave after " if form.time_kind == "DEPART_AFTER" else "Arrive by ") + time_label(form.local_time) if form.local_time != "" else "Add time";
    return day + " · " + time;
}

def:pub ComposerError(errors: list[FieldError], field: str) -> JsxElement {
    return <span id={"error-" + field} className="dt-field-error">{field_error(errors, field)}</span>;
}

def price_label(cents: int | None) -> str {
    if cents is None { return "No limit"; }
    remainder = cents % 100;
    return "$" + str(cents // 100) + "." + ("0" if remainder < 10 else "") + str(remainder) + " USD";
}

def:pub DraftSummary(draft: ComposerDraft) -> JsxElement {
    return <section className="dt-panel dt-draft-summary" aria-label="Validated trip details">
        <h2>Trip details checked</h2>
        <p role="status">Your structured request is ready. No route search has run and no trip has been saved.</p>
        <dl><div><dt>Journey</dt><dd>{draft.origin_text} → {draft.destination_text}</dd></div>
            <div><dt>{"Depart after" if draft.time_kind == "DEPART_AFTER" else "Arrive by"}</dt><dd>{draft.local_date} at {draft.local_time} (local time at the {"starting point" if draft.time_kind == "DEPART_AFTER" else "destination"})</dd></div>
            <div><dt>Minimum transfer buffer</dt><dd>{str(draft.min_transfer_minutes)} minutes</dd></div>
            <div><dt>Maximum price</dt><dd>{price_label(draft.max_price_cents)}</dd></div>
            <div><dt>Travel modes</dt><dd>{", ".join(draft.allowed_modes).lower()}</dd></div>
            <div><dt>Routing priority</dt><dd>{draft.priority.replace("_", " ").lower()}</dd></div>
        </dl>
    </section>;
}

def:pub TripComposer(
    initial: ComposerInput | None = None,
    earliestDate: str = "",
    onValidDraft: Callable[[ComposerDraft], None] | None = None,
    busy: bool = False,
    submitLabel: str = "Check trip details"
) -> JsxElement {
    has form: ComposerInput = starting_form(initial);
    has errors: list[FieldError] = [], validated: ComposerDraft | None = None;
    has submitting: bool = False, whenOpen: bool = False;

    def setField(field: str, text: str) {
        form = update_input(form, field, text);
        validated = None;
    }
    def useExample {
        form = example_input(form);
        errors = [];
        validated = None;
    }
    async def submit(e: FormEvent) {
        e.preventDefault();
        if busy or submitting { return; }
        whenOpen = False;
        result = validate_composer(form, earliestDate);
        errors = result.errors;
        validated = result.draft;
        if result.draft is not None and onValidDraft is not None {
            submitting = True;
            try { await onValidDraft(result.draft); }
            finally { submitting = False; }
        }
    }
    can with [errors] entry { if len(errors) > 0 { focus_composer_errors(); } }

    whenError = any(field_error(errors, field) != "" for field in ["local_date", "local_time", "time_kind"]);
    showWhen = whenOpen or whenError;
    summary = when_summary(form);
    stops = [stop for stop in [known_stop(form.origin_text), known_stop(form.destination_text)] if stop is not None];

    return <div className="dt-composer">
        <form noValidate={True} onSubmit={submit}>
            <fieldset className="dt-composer-controls" disabled={busy or submitting}>
            <div id="composer-errors" className="dt-error-summary" role="alert" tabIndex={-1} hidden={len(errors) == 0}>
                <h2>Check your trip details</h2>
                <ul>{for error in errors { <li key={error.field}><a href={"#" + error.field}>{error.message}</a></li> }}</ul>
            </div>
            <div className="dt-search">
            <div className="dt-search-bar">
                <label className="dt-search-field" htmlFor="destination_text"><span>Where</span><input id="destination_text" type="text" list="dt-places" placeholder="Search destinations" required={True} value={form.destination_text} onChange={lambda (e: ChangeEvent) { setField("destination_text", e.target.value); }} autoComplete="off" aria-invalid={field_error(errors, "destination_text") != ""} aria-describedby="error-destination_text"/><ComposerError errors={errors} field="destination_text"/></label>
                <button className="dt-search-field dt-search-trigger" type="button" aria-expanded={showWhen} aria-controls="dt-when" onClick={lambda { whenOpen = not whenOpen; }}>
                    <span>When</span>
                    <span className={"dt-search-value" if summary != "" else "dt-search-placeholder"}>{summary if summary != "" else "Add date and time"}</span>
                </button>
                <button className="dt-search-submit" type="submit" disabled={busy or submitting} aria-label={"Searching" if busy or submitting else submitLabel}><Icon name="magnifyingglass"/></button>
            </div>
            <div id="dt-when" className="dt-when-panel" role="group" aria-label="When" hidden={not showWhen} onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Escape" { whenOpen = False; } }}>
                <div className="dt-when-kind" role="radiogroup" aria-label="Time preference" id="time_kind">
                    <button type="button" role="radio" aria-checked={form.time_kind == "DEPART_AFTER"} onClick={lambda { setField("time_kind", "DEPART_AFTER"); }}>Leave after</button>
                    <button type="button" role="radio" aria-checked={form.time_kind == "ARRIVE_BY"} onClick={lambda { setField("time_kind", "ARRIVE_BY"); }}>Arrive by</button>
                </div>
                <h3 className="dt-when-heading">Date</h3>
                <div id="local_date" className="dt-chip-row" tabIndex={-1} aria-describedby="error-local_date">
                    {for day in day_options(form.local_date) { <button key={day.iso} type="button" className="dt-chip" aria-pressed={form.local_date == day.iso} onClick={lambda { setField("local_date", day.iso); }}>{day.label}</button> }}
                </div>
                <ComposerError errors={errors} field="local_date"/>
                <h3 className="dt-when-heading">{"Leave after" if form.time_kind == "DEPART_AFTER" else "Arrive by"}</h3>
                <div id="local_time" className="dt-chip-grid" tabIndex={-1} aria-describedby="error-local_time time-help">
                    {for slot in time_options(form.local_time) { <button key={slot} type="button" className="dt-chip" aria-pressed={form.local_time == slot} onClick={lambda { setField("local_time", slot); }}>{time_label(slot)}</button> }}
                </div>
                <span id="time-help" className="dt-sr-only">Local time at your {"starting point" if form.time_kind == "DEPART_AFTER" else "destination"}.</span>
                <ComposerError errors={errors} field="local_time"/><ComposerError errors={errors} field="time_kind"/>
                <div className="dt-when-actions"><button type="button" className="dt-primary" onClick={lambda { whenOpen = False; }}>Done</button></div>
            </div>
            </div>
            <datalist id="dt-places"><option value="Ann Arbor, MI"/><option value="Chicago, IL"/></datalist>
            <div className="dt-search-extras">
                <button className="dt-secondary" type="button" onClick={useExample}>Try the demo trip</button>
            </div>
            </fieldset>
        </form>
        <RouteMap stops={stops} label={"Map of " + " to ".join([stop.name for stop in stops]) if len(stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
        {if validated is not None and onValidDraft is None { <DraftSummary draft={validated}/> }}
    </div>;
}
