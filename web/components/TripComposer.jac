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
    has submitting: bool = False;

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

    stops = [stop for stop in [known_stop(form.origin_text), known_stop(form.destination_text)] if stop is not None];

    return <div className="dt-composer">
        <form noValidate={True} onSubmit={submit}>
            <fieldset className="dt-composer-controls" disabled={busy or submitting}>
            <div id="composer-errors" className="dt-error-summary" role="alert" tabIndex={-1} hidden={len(errors) == 0}>
                <h2>Check your trip details</h2>
                <ul>{for error in errors { <li key={error.field}><a href={"#" + error.field}>{error.message}</a></li> }}</ul>
            </div>
            <div className="dt-search-bar">
                <label className="dt-search-field" htmlFor="destination_text"><span>Where</span><input id="destination_text" type="text" list="dt-places" placeholder="Search destinations" required={True} value={form.destination_text} onChange={lambda (e: ChangeEvent) { setField("destination_text", e.target.value); }} autoComplete="off" aria-invalid={field_error(errors, "destination_text") != ""} aria-describedby="error-destination_text"/><ComposerError errors={errors} field="destination_text"/></label>
                <div className="dt-search-field">
                    <label htmlFor="local_date">When</label>
                    <span className="dt-search-when">
                        <input id="local_date" type="date" required={True} min={earliestDate} value={form.local_date} onInput={lambda (e: InputEvent) { setField("local_date", e.target.value); }} onChange={lambda (e: ChangeEvent) { setField("local_date", e.target.value); }} aria-invalid={field_error(errors, "local_date") != ""} aria-describedby="error-local_date"/>
                        <input id="local_time" type="time" required={True} aria-label={"Departure time" if form.time_kind == "DEPART_AFTER" else "Arrival time"} value={form.local_time} onInput={lambda (e: InputEvent) { setField("local_time", e.target.value); }} onChange={lambda (e: ChangeEvent) { setField("local_time", e.target.value); }} aria-invalid={field_error(errors, "local_time") != ""} aria-describedby="error-local_time time-help"/>
                    </span>
                    <span id="time-help" className="dt-sr-only">Local time at your {"starting point" if form.time_kind == "DEPART_AFTER" else "destination"}.</span>
                    <ComposerError errors={errors} field="local_date"/><ComposerError errors={errors} field="local_time"/>
                </div>
                <button className="dt-search-submit" type="submit" disabled={busy or submitting} aria-label={"Searching" if busy or submitting else submitLabel}><Icon name="magnifyingglass"/></button>
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
