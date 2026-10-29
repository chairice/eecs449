"""Airbnb-style trip search: one bar for the essentials, defaults for the rest,
and a map of the places it recognises. Validation stays local."""

import from ..client.composer_model {
    ComposerInput, ComposerDraft, FieldError, copy_input, field_error, update_input, validate_composer
}
import from "react" { useEffect }
import from .composer_dom { focus_field }
import from .Icon { Icon }
import from .RouteMap { RouteMap }
import from .comparison_view { ComparisonStop }

# The demo planner has one origin, so the search bar asks only where and when.
glob DEFAULT_ORIGIN: str = "Ann Arbor, MI";

def starting_form(initial: ComposerInput | None) -> ComposerInput {
    form = copy_input(initial) if initial is not None else ComposerInput();
    if form.origin_text == "" { form.origin_text = DEFAULT_ORIGIN; }
    # No time is asked for: a trip leaves any time on its day, and the results show when.
    if form.local_time == "" { form.local_time = "00:00"; }
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

"""One cell of the calendar; blank cells pad the first week."""
obj:pub CalendarDay { has iso: str, day: int, disabled: bool, label: str; }
obj:pub CalendarMonth { has key: str, title: str, days: list[CalendarDay]; }

# How far ahead the calendar pages, in months.
glob MONTHS_AHEAD: int = 11;
glob WEEKDAYS: list[str] = ["S", "M", "T", "W", "T", "F", "S"];

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

"""The month `offset` months after this one, with days before today disabled."""
def calendar_month(offset: int, today: str) -> CalendarMonth {
    parts = today.split("-");
    index = (int(parts[1]) - 1) + offset;
    year = int(parts[0]) + index // 12;
    month = index % 12;
    first: any = new(Date, Date.UTC(year, month, 1, 12));
    last: any = new(Date, Date.UTC(year, month + 1, 0, 12));
    days: list[CalendarDay] = [CalendarDay(iso="", day=0, disabled=True, label="") for _ in range(int(first.getUTCDay()))];
    for day in range(1, int(last.getUTCDate()) + 1) {
        iso = str(year) + "-" + two_digits(month + 1) + "-" + two_digits(day);
        noon: any = new(Date, iso + "T12:00:00Z");
        label = str(noon.toLocaleDateString("en-US", {"weekday": "long", "month": "long", "day": "numeric", "year": "numeric", "timeZone": "UTC"}));
        days.append(CalendarDay(iso=iso, day=day, disabled=iso < today, label=label));
    }
    title = str(first.toLocaleDateString("en-US", {"month": "long", "year": "numeric", "timeZone": "UTC"}));
    return CalendarMonth(key=str(year) + "-" + two_digits(month + 1), title=title, days=days);
}

"""A destination the Where menu can offer."""
obj:pub Destination { has name: str, note: str, icon: str; }

# The demo planner reaches one destination; the menu offers only what it can plan.
glob DESTINATIONS: list[Destination] = [Destination(name="Chicago, IL", note="Demo trips from Ann Arbor by train and bus", icon="building")];

def destination_matches(text: str) -> list[Destination] {
    query = text.lower().strip();
    stop = known_stop(text);
    alias = stop.name.lower() if stop is not None else "";
    return [place for place in DESTINATIONS if query == "" or query in place.name.lower() or (alias != "" and alias in place.name.lower())];
}

def when_summary(form: ComposerInput) -> str {
    if form.local_date == "" { return ""; }
    today = today_iso();
    day = day_label(form.local_date, today);
    if form.return_date != "" { day += " – " + day_label(form.return_date, today); }
    return day;
}

"""A field's error; `missing` replaces it in plain words when the field was simply left empty."""
def:pub ComposerError(errors: list[FieldError], field: str, missing: str = "") -> JsxElement {
    message = field_error(errors, field);
    return <span id={"error-" + field} className="dt-field-error">{missing if message != "" and missing != "" else message}</span>;
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
    submitLabel: str = "Check trip details",
    # The plan page keeps the manual search tucked away until it is asked for;
    # the map below it still shows. startPanel opens "where" or "when" on mount.
    searchHidden: bool = False,
    startPanel: str = ""
) -> JsxElement {
    has form: ComposerInput = starting_form(initial);
    has errors: list[FieldError] = [], validated: ComposerDraft | None = None;
    has submitting: bool = False, panel: str = startPanel, monthOffset: int = 0;
    # Airbnb-style range: the first pick is the departure, the second the return,
    # which is searched as its own trip back. hoverDate previews the range.
    has hoverDate: str = "";
    has searchBox: Ref[HTMLDivElement] = Ref();
    # Where the sliding pill last sat, so it fades out in place when a panel closes.
    has pillAt: Ref[str] = Ref("where");

    def setField(field: str, text: str) {
        form = update_input(form, field, text);
        validated = None;
        # Editing a field settles its error; the rest wait for the next search.
        if field_error(errors, field) != "" { errors = [error for error in errors if error.field != field]; }
    }
    def pickDay(iso: str) {
        if form.local_date == "" or form.return_date != "" or iso <= form.local_date {
            # Both fields in one update: a second setField would start from the stale form.
            form = update_input(update_input(form, "local_date", iso), "return_date", "");
            validated = None;
            errors = [error for error in errors if error.field not in ["local_date", "return_date"]];
        } else {
            setField("return_date", iso);
        }
        hoverDate = "";
    }
    async def submit(e: FormEvent) {
        e.preventDefault();
        if busy or submitting { return; }
        panel = "";
        result = validate_composer(form, earliestDate);
        errors = result.errors;
        validated = result.draft;
        if result.draft is not None and onValidDraft is not None {
            submitting = True;
            try { await onValidDraft(result.draft); }
            finally { submitting = False; }
        }
    }
    # Like Airbnb's, the panel closes when you click anywhere outside the search.
    useEffect(lambda {
        handler = lambda (e: any) {
            box: any = searchBox.current;
            if box and not box.contains(e.target) { panel = ""; }
        };
        document.addEventListener("mousedown", handler);
        return lambda { document.removeEventListener("mousedown", handler); };
    }, []);
    # Like Airbnb, a search with something missing opens the field that needs it.
    can with [errors] entry {
        if field_error(errors, "destination_text") != "" { panel = "where"; focus_field("destination_text"); }
        elif len(errors) > 0 { panel = "when"; focus_field("local_date"); }
    }

    destinationError = field_error(errors, "destination_text");
    whenError = any(field_error(errors, field) != "" for field in ["local_date", "return_date", "local_time", "time_kind"]);
    showWhere = panel == "where";
    showWhen = (panel == "when" or whenError) and not showWhere;
    suggestions = destination_matches(form.destination_text);
    if showWhen { pillAt.current = "when"; } elif showWhere { pillAt.current = "where"; }
    summary = when_summary(form);
    choosingReturn = form.local_date != "" and form.return_date == "";
    rangeEnd = form.return_date if form.return_date != "" else hoverDate if choosingReturn and hoverDate > form.local_date else "";
    today = today_iso();
    months = [calendar_month(monthOffset, today), calendar_month(monthOffset + 1, today)];
    stops = [stop for stop in [known_stop(form.origin_text), known_stop(form.destination_text)] if stop is not None];

    return <div className="dt-composer">
        <form noValidate={True} onSubmit={submit} hidden={searchHidden}>
            <fieldset className="dt-composer-controls" disabled={busy or submitting}>
            <p className="dt-sr-only" role="alert">{" ".join([error.message for error in errors])}</p>
            <div className="dt-search" ref={searchBox}>
            <div className={"dt-search-bar" + (" is-active" if showWhen or showWhere else "")}>
                <span className={"dt-search-pill at-" + str(pillAt.current)} aria-hidden="true"></span>
                <label className={"dt-search-field" + (" is-open" if showWhere else "")} htmlFor="destination_text"><span>Where</span><input id="destination_text" type="text" placeholder="Search destinations" onFocus={lambda { panel = "where"; }} aria-expanded={showWhere} aria-controls="dt-where" role="combobox" aria-autocomplete="list" required={True} value={form.destination_text} onChange={lambda (e: ChangeEvent) { setField("destination_text", e.target.value); panel = "where"; }} autoComplete="off" aria-invalid={destinationError != ""} aria-describedby="error-destination_text"/></label>
                <div className={"dt-search-field dt-search-segment" + (" is-open" if showWhen else "")}>
                    <button className="dt-search-trigger" type="button" aria-expanded={showWhen} aria-controls="dt-when" onClick={lambda { panel = "" if showWhen else "when"; }}>
                        <span>When</span>
                        <span className={"dt-search-value" if summary != "" else "dt-search-placeholder"}>{summary if summary != "" else "Add dates"}</span>
                    </button>
                    <button className="dt-search-submit" type="submit" disabled={busy or submitting} aria-label={"Searching" if busy or submitting else submitLabel}><Icon name="magnifyingglass"/></button>
                </div>
            </div>
            <div id="dt-where" className="dt-where-panel" role="listbox" aria-label="Suggested destinations" hidden={not showWhere} onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Escape" { panel = ""; } }}>
                <p id="error-destination_text" className="dt-panel-heading dt-panel-error" hidden={destinationError == ""}>Choose where you're headed</p>
                <h3 className="dt-panel-heading" hidden={destinationError != ""}>{"Suggested destinations" if len(suggestions) > 0 else "Not in the demo yet"}</h3>
                {for place in suggestions {
                    <button key={place.name} type="button" role="option" aria-selected={form.destination_text == place.name} className="dt-place" onClick={lambda { setField("destination_text", place.name); panel = "when"; }}>
                        <span className="dt-place-icon"><Icon name={place.icon} size={24}/></span>
                        <span className="dt-place-text"><span className="dt-place-name">{place.name}</span><span>{place.note}</span></span>
                    </button>
                }}
                {if len(suggestions) == 0 { <p>Detour's demo plans trips from Ann Arbor to Chicago, IL for now.</p> }}
            </div>
            <div id="dt-when" className="dt-when-panel" role="group" aria-label="When" hidden={not showWhen} onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Escape" { panel = ""; } }}>
                <div id="local_date" className="dt-calendar" tabIndex={-1} aria-describedby="error-local_date" onMouseLeave={lambda { hoverDate = ""; }}>
                    <button type="button" className="dt-calendar-nav dt-calendar-prev" aria-label="Previous month" disabled={monthOffset == 0} onClick={lambda { monthOffset = max(0, monthOffset - 1); }}><Icon name="chevron.left" size={16}/></button>
                    <button type="button" className="dt-calendar-nav dt-calendar-next" aria-label="Next month" disabled={monthOffset >= MONTHS_AHEAD} onClick={lambda { monthOffset = min(MONTHS_AHEAD, monthOffset + 1); }}><Icon name="chevron.right" size={16}/></button>
                    {for month in months {
                        <section key={month.key} className="dt-month" aria-label={month.title}>
                            <h3 className="dt-month-title">{month.title}</h3>
                            <div className="dt-month-grid">
                                {for (index, name) in enumerate(WEEKDAYS) { <span key={"w" + str(index)} className="dt-weekday" aria-hidden="true">{name}</span> }}
                                {for (index, day) in enumerate(month.days) {
                                    <span key={"d" + str(index)} className={"dt-day-cell" + (" is-start" if day.iso != "" and day.iso == form.local_date and rangeEnd != "" else "") + (" is-end" if day.iso != "" and day.iso == rangeEnd else "") + (" in-range" if day.iso != "" and form.local_date < day.iso and day.iso < rangeEnd else "")}>{(
                                        <button type="button" className="dt-day" aria-label={day.label + (", departure" if day.iso == form.local_date else ", return" if day.iso == form.return_date else "")} aria-pressed={day.iso == form.local_date or day.iso == form.return_date} disabled={day.disabled} onClick={lambda { pickDay(day.iso); }} onMouseEnter={lambda { if choosingReturn { hoverDate = day.iso; } }} onFocus={lambda { if choosingReturn { hoverDate = day.iso; } }}>{day.day}</button> if day.iso != "" else None
                                    )}</span>
                                }}
                            </div>
                        </section>
                    }}
                </div>
                <ComposerError errors={errors} field="local_date" missing={"Pick a departure date" if form.local_date == "" else ""}/><ComposerError errors={errors} field="return_date"/>
            </div>
            </div>
            </fieldset>
        </form>
        <RouteMap stops={stops} label={"Map of " + " to ".join([stop.name for stop in stops]) if len(stops) > 0 else "Map of the Ann Arbor to Chicago demo corridor"}/>
        {if validated is not None and onValidDraft is None { <DraftSummary draft={validated}/> }}
    </div>;
}
