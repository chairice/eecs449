"""Conversational trip studio: viewing and selection in the workspace, edits in chat."""
import "../tailwind.css";
import "../styles.css";
import "../studio.css";
import from react { useEffect, useRef, useMemo }
import from "@jac/runtime" { useLocation }
import from .Brand { Brand }
import from .PublicHeader { HEADER }
import from .PlannerMap { PlannerMap }
import from .ChatMarkdown { ChatMarkdown }
import from .StudioOffers { StudioOffer, conversation_offers }
import from .StudioDetails { StudioDetails }
import from .StudioWeather { StudioWeather }
import from ..client.account { signed_in, account_email, log_in, create_account, log_out, credential_problem }
import from ..client.planning_state {
    parse_response, parse_job_response, planner_id, guest_token, load_session, save_session, planner_today,
    planner_zone, date_label, time_label, place_label, nights, money_label, file_content, observed_label, offer_context,
    load_preferences, save_preferences, forget_local, trap_dialog, finish_guest_import, mapped_snapshot, clear_account_cache
}
import from ..browser { paintPage }
import from server.planning {
    planner_status, planner_blank, planner_guest_start, planner_guest_poll, planner_guest_stage,
    planner_guest_cancel, planner_guest_upload, planner_guest_undo, planner_guest_weather, planner_guest_rename
}
import from ..client.planning_rpc {
    planner_list, planner_import, planner_get, planner_start, planner_poll, planner_stage,
    planner_undo, planner_rename, planner_delete, planner_restore, planner_deleted, planner_weather,
    planner_cancel, planner_upload, planner_preferences, planner_forget_preference
}

def:pub StudioOverview(snapshot: any, onDay: Callable[[str], None], onContext: Callable[[str, str], None], costs: any = None, weather: any = None) -> JsxElement {
    return <div className="studio-overview">
        <StudioWeather weather={weather}/><header className="studio-section-heading"><p className="studio-eyebrow">THE BIG PICTURE</p><h2>{str(snapshot["title"])}</h2><p>{date_label(snapshot["startDate"]) + (" — " + date_label(snapshot["endDate"]) if snapshot["endDate"] else "")}</p></header>
        {if len(snapshot["stays"]) > 0 { <section aria-label="Overnight bases"><h3>Places to settle in</h3><div className="studio-bases">
            {for (index, stay) in enumerate(snapshot["stays"]) { <button type="button" className="studio-base" key={stay["id"]} data-plan-item={stay["id"]} onClick={lambda { onContext(str(stay["id"]), place_label(snapshot, str(stay["placeId"]))); }}>
                <span className="studio-base-number">{str(index + 1).zfill(2)}</span><span><strong>{place_label(snapshot, str(stay["placeId"]))}</strong><small>{nights(stay) + " · " + (str(stay["propertyName"]) or "Stay to find")}</small></span><span className="studio-arrow">↗</span>
            </button> }}
        </div></section> }}
        {if len(snapshot["legs"]) > 0 { <section aria-label="Travel connections"><h3>Getting there & around</h3><div className="studio-connections">
            {for leg in snapshot["legs"] { <button type="button" key={leg["id"]} data-plan-item={leg["id"]} onClick={lambda { onContext(str(leg["id"]), place_label(snapshot, str(leg["fromId"])) + " → " + place_label(snapshot, str(leg["toId"]))); }}>
                <span className="studio-mode">{"↗" if leg["mode"] == "FLIGHT" else "↝"}</span><span><strong>{place_label(snapshot, str(leg["fromId"])) + " → " + place_label(snapshot, str(leg["toId"]))}</strong><small>{str(leg["mode"]).capitalize() + " · " + date_label(str(leg["departDate"])) + (" · " + time_label(str(leg["departTime"])) if leg["departTime"] else "")}</small></span>
                {if leg["locked"] { <span className="studio-tag">Fixed</span> }}
            </button> }}
        </div></section> }}
        {if snapshot["rentals"] and len(snapshot["rentals"]) > 0 { <section aria-label="Car rentals"><h3>A car for the journey</h3><div className="studio-bases">{for rental in snapshot["rentals"] { <button type="button" key={rental["id"]} data-plan-item={rental["id"]} className="studio-base" onClick={lambda { onContext(str(rental["id"]), str(rental["provider"] or "Car rental")); }}><span className="studio-mode">↝</span><span><strong>{str(rental["provider"] or "Car to find") + (" · " + str(rental["vehicle"]) if rental["vehicle"] else "")}</strong><small>{place_label(snapshot, str(rental["pickupPlaceId"])) + " · " + date_label(str(rental["pickupDate"])) + " — " + date_label(str(rental["dropoffDate"]))}</small></span>{if rental["locked"] { <span className="studio-tag">Fixed</span> }}</button> }}</div></section> }}
        {if len(snapshot["days"]) > 0 and snapshot["detail"] != "LOGISTICS" { <section><div className="studio-heading-row"><h3>Day by day</h3><span>{str(len(snapshot["days"])) + " days"}</span></div><div className="studio-days">
            {for (index, day) in enumerate(snapshot["days"]) { <button type="button" key={day["id"]} data-plan-item={day["id"]} onClick={lambda { onDay(str(day["id"])); }}>
                <span className="studio-day-number">{str(index + 1).zfill(2)}</span><span><small>{date_label(str(day["date"]))}</small><strong>{str(day["title"])}</strong><small>{str(len(day["items"])) + " stops" + (" · " + place_label(snapshot, str(day["overnightPlaceId"])) if day["overnightPlaceId"] else "")}</small></span><span className="studio-arrow">→</span>
            </button> }}
        </div></section> }}
        {if len(snapshot["unresolved"]) > 0 { <details className="studio-open-details"><summary>Details to work out</summary>{for note in snapshot["unresolved"] { <p key={note}>{str(note)}</p> }}</details> }}
        {if len(snapshot["bookings"]) > 0 { <section><h3>Your bookings</h3>{for booking in snapshot["bookings"] { <article className="studio-booking" key={booking["id"]}><strong>{str(booking["title"])}</strong><small>{str(booking["status"]).replace("_", " ")}</small><p>{str(booking["details"])}</p></article> }}</section> }}
        {if costs { <section className="studio-costs"><h3>Known costs</h3>{if snapshot["budget"]["amountMinor"] is not None { <p className="studio-heading-row"><span>{"Budget limit" if snapshot["budget"]["hard"] else "Budget target"}</span><strong>{money_label(int(snapshot["budget"]["amountMinor"]), str(snapshot["budget"]["currency"]))}</strong></p> }}{for currency in Object.keys(costs["bookedSubtotals"] or {}) { <p className="studio-heading-row" key={"booked-" + str(currency)}><span>Bookings you added</span><strong>{money_label(int(costs["bookedSubtotals"][currency]), str(currency))}</strong></p> }}{for currency in Object.keys(costs["selectedQuoteSubtotals"] or {}) { <p className="studio-heading-row" key={"selected-" + str(currency)}><span>Selected offers</span><strong>{money_label(int(costs["selectedQuoteSubtotals"][currency]), str(currency))}</strong></p> }}{for currency in Object.keys(costs["selectedEstimateSubtotals"] or {}) { <p className="studio-heading-row" key={"estimated-" + str(currency)}><span>Selected estimates</span><strong>{money_label(int(costs["selectedEstimateSubtotals"][currency]), str(currency))}</strong></p> }}<small>Partial costs. Estimates use researched starting or unit prices; unpriced travel, activities, food and daily spending are not included.</small></section> }}
    </div>;
}

def:pub StudioDay(day: any, snapshot: any, onBack: Callable[[], None], onContext: Callable[[str, str], None], weather: any = None) -> JsxElement {
    timed = len([item for item in day["items"] if item["startTime"]]) > 0;
    return <div className="studio-day-detail"><button type="button" className="studio-back" onClick={onBack}>← Trip overview</button><p className="studio-eyebrow">{date_label(str(day["date"]))}</p><h2>{str(day["title"])}</h2>
        <StudioWeather weather={weather} dayDate={str(day["date"])}/>
        {if day["notes"] { <p className="studio-muted">{str(day["notes"])}</p> }}
        <button type="button" className="studio-subtle-button" onClick={lambda { onContext(str(day["id"]), str(day["title"])); }}>Day details ↗</button>
        <div className={"studio-timeline" + (" is-outline" if not timed else "")}>{for item in day["items"] { <button type="button" className={"studio-timeline-item " + ("is-rest" if item["kind"] in ["REST", "FREE"] else "")} key={item["id"]} data-plan-item={item["id"]} onClick={lambda { onContext(str(item["id"]), str(item["title"])); }}>
            <span className="studio-time">{time_label(str(item["startTime"])) or "Flexible"}{if item["endTime"] { <small>{time_label(str(item["endTime"]))}</small> }}</span>
            <span className="studio-timeline-dot"/><span className="studio-timeline-body"><strong>{str(item["title"])}</strong>{if item["placeId"] { <small>{place_label(snapshot, str(item["placeId"]))}</small> }}{if item["notes"] { <p>{str(item["notes"])}</p> }}{if item["locked"] or item["timingState"] == "CONFLICT" { <span className="studio-timing-state">{"Fixed" if item["locked"] else "Timing to resolve"}</span> }}</span>
        </button> }}</div>
        {if len(day["items"]) == 0 { <div className="studio-gentle-empty"><h3>Room for possibility.</h3><p>Ask Detour to explore this day, or keep it open.</p></div> }}
    </div>;
}

def:pub StudioComparison(offers: any, links: any, onContext: Callable[[str, str], None]) -> JsxElement {
    return <div className="studio-comparison"><p className="studio-eyebrow">YOUR OPTIONS</p><h2>A few good possibilities.</h2>
        {for offer in offers { <StudioOffer key={offer["id"]} offer={offer} onContext={onContext}/> }}
        {if len(offers) == 0 { <div className="studio-gentle-empty"><h3>Let's find the right fit.</h3><p>Tell Detour what you're looking for, and we'll explore real options together.</p></div> }}
        {if len(links) > 0 { <details className="studio-open-details"><summary>Explore more sources</summary>{for link in links { <a key={link["url"]} href={link["url"]} target="_blank" rel="noopener noreferrer">{str(link["label"]) + " ↗"}</a> }}</details> }}
    </div>;
}

def:pub TripStudio -> JsxElement {
    navigation = useLocation();
    current = useRef(None);
    contentRef = useRef(None);
    libraryRef = useRef(None);
    libraryButton = useRef(None);
    viewHistory = useRef([]);
    restorePoint = useRef(None);
    alive = useRef(True);
    chatEnd = useRef(None);
    inputRef = useRef(None);
    has state: any = None, savedTrips: any = [], attachments: any = [];
    has prompt: str = "", error: str = "", notice: str = "", jobId: str = "", progress: str = "";
    has pane: str = "overview", dayId: str = "", selectedId: str = "", context: any = None;
    has phoneTab: str = "chat", chatOpen: bool = True, busy: bool = False;
    has online: bool = True, workerReady: bool = False, authenticated: bool = signed_in();
    has accountOpen: bool = False, libraryOpen: bool = False, signup: bool = False;
    has preferences: any = None, preferencesOpen: bool = False;
    has inspected: any = None;
    has uploading: bool = False;
    has deletedTrips: any = [], showDeleted: bool = False, deletedUndo: str = "";
    has undoDismissed: int = -1, deletedCurrent: bool = False;
    has renaming: bool = False, titleDraft: str = "";
    has email: str = "", password: str = "", authProblem: str = "", authBusy: bool = False;

    def cacheKey -> str { return account_email() if signed_in() else "guest"; }
    def latestTrip(trips: any) -> str {
        latest: any = None;
        for trip in trips {
            if latest is None or str(trip["updatedAt"]) > str(latest["updatedAt"]) { latest = trip; }
        }
        return str(latest["id"]) if latest else "";
    }
    def hasGuestWork -> bool {
        return bool(state and (len(state["conversation"]) > 0 or len(state["snapshot"]["places"]) > 0 or len(state["snapshot"]["days"]) > 0 or len(state["snapshot"]["bookings"]) > 0 or state["pending"]));
    }
    def commit(value: any) {
        if not alive.current { return; }
        current.current = value; state = value;
        failure = save_session(cacheKey(), value);
        if failure { error = failure; }
    }
    async def initialize {
        busy = True;
        try {
            preferences = load_preferences(cacheKey());
            cached = load_session(cacheKey());
            if cached and not signed_in() { cached["preferences"] = preferences; }
            if cached { commit(cached); jobId = str(cached["activeJob"] or ""); }
            else { commit(parse_response(await planner_blank())); }
            browser: any = window;
            if not browser.navigator.onLine { busy = False; return; }
            workerReady = bool(parse_response(await planner_status())["workerReady"]);
            if signed_in() {
                preferences = parse_response(await planner_preferences());
                savedTrips = parse_response(await planner_list(str(current.current["id"]) if current.current else ""));
                guest = load_session("guest");
                if guest and (len(guest["conversation"] or []) > 0 or len(guest["snapshot"]["places"] or []) > 0 or len(guest["snapshot"]["bookings"] or []) > 0 or guest["pending"]) {
                    response = parse_response(await planner_import(JSON.stringify(guest), guest_token()));
                    commit(response); jobId = str(response["activeJob"] or ""); finish_guest_import();
                } elif cached {
                    response = parse_response(await planner_get(str(cached["id"])));
                    if current.current and current.current["id"] == cached["id"] and not current.current["activeJob"] { commit(response); }
                    jobId = str(response["activeJob"] or "");
                } elif len(savedTrips) > 0 {
                    response = parse_response(await planner_get(latestTrip(savedTrips)));
                    commit(response); jobId = str(response["activeJob"] or "");
                } else { commit(parse_response(await planner_import(JSON.stringify(current.current), ""))); }
            }
        } except Exception {
            error = "Couldn't reconnect to Detour. Your last saved trip is available on this device. Refresh to try again." if current.current else "Couldn't open Detour. Please check your connection and refresh.";

        }
        if navigation.state and navigation.state["destination"] { prompt = "I'd like to plan a trip to " + str(navigation.state["destination"]) + "."; }
        busy = bool(jobId);
    }
    useEffect(lambda {
        alive.current = True;
        paintPage("var(--dt-bg)", False);
        browser: any = window;
        online = bool(browser.navigator.onLine);
        def statusChange { online = bool(browser.navigator.onLine); }
        browser.addEventListener("online", statusChange); browser.addEventListener("offline", statusChange);
        initialize();
        return lambda { alive.current = False; browser.removeEventListener("online", statusChange); browser.removeEventListener("offline", statusChange); };
    }, []);

    async def poll {
        if not jobId or not current.current { return; }
        expected = jobId;
        finalizing: bool = False;
        try {
            result = parse_job_response(await planner_poll(str(current.current["id"]), expected) if signed_in() else await planner_guest_poll(guest_token(), expected));
            if jobId != expected or not alive.current { return; }
            progress = str(result["progress"]);
            if result["status"] == "SUCCEEDED" {
                finalizing = True;
                value = parse_response(await planner_stage(str(current.current["id"]), expected) if signed_in() else await planner_guest_stage(guest_token(), JSON.stringify(current.current), expected));
                if jobId != expected or not alive.current { return; }
                value["activeJob"] = ""; commit(value); jobId = ""; busy = False; progress = "";
                preferences = parse_response(await planner_preferences()) if signed_in() else value["preferences"];
                save_preferences(cacheKey(), preferences);


                inspected = None; selectedId = ""; viewHistory.current = [];
                pane = "overview"; dayId = "";
                if value["nextDecision"] and value["nextDecision"]["focusPanel"] == "comparison" { pane = "overview"; }
                elif value["nextDecision"] and value["nextDecision"]["focusPanel"] == "day" {
                    focus_snapshot = value["snapshot"];
                    for focus_id in value["nextDecision"]["focusIds"] or [] {
                        for planned_day in focus_snapshot["days"] {
                            if planned_day["id"] == focus_id { dayId = str(focus_id); pane = "day"; }
                        }
                    }
                }
            } elif result["status"] in ["FAILED", "CANCELLED"] {
                error = (str(result["error"]) if result["error"] else "That search didn’t finish. Your trip is saved; you can try again or keep planning.") if result["status"] == "FAILED" else "";
                value = JSON.parse(JSON.stringify(current.current)); value["activeJob"] = ""; commit(value);
                jobId = ""; busy = False;

            }
        } except Exception as exc {
            error = "We couldn’t reconnect just now. Your trip is saved. Stop and try again when you’re ready.";
            if finalizing {
                value = JSON.parse(JSON.stringify(current.current)); value["activeJob"] = ""; commit(value);
                jobId = ""; busy = False;
            }
        }
    }
    useEffect(lambda {
        if not jobId { return; }
        busy = True;
        browser: any = window;
        poll();
        timer = browser.setInterval(lambda { poll(); }, 1800);
        return lambda { browser.clearInterval(timer); };
    }, [jobId]);
    useEffect(lambda { if chatEnd.current { chatEnd.current.scrollIntoView({"block": "nearest", "behavior": "smooth"}); } }, [len(state["conversation"]) if state else 0, busy]);
    useEffect(lambda {
        if accountOpen or preferencesOpen { return trap_dialog(lambda { accountOpen = False; preferencesOpen = False; }); }
    }, [accountOpen, preferencesOpen]);

    useEffect(lambda {
        if not libraryOpen { return; }
        doc: any = document;
        previous: any = doc.activeElement;
        def outside(event: any) {
            if libraryRef.current and not libraryRef.current.contains(event.target) and (not libraryButton.current or not libraryButton.current.contains(event.target)) { libraryOpen = False; }
        }
        def escape(event: any) { if event.key == "Escape" { event.preventDefault(); libraryOpen = False; } }
        doc.addEventListener("pointerdown", outside); doc.addEventListener("keydown", escape);
        first = libraryRef.current.querySelector("button") if libraryRef.current else None;
        if first { first.focus(); }
        return lambda { doc.removeEventListener("pointerdown", outside); doc.removeEventListener("keydown", escape); if previous and previous.isConnected { previous.focus(); } };
    }, [libraryOpen]);
    useEffect(lambda {
        if not contentRef.current { return; }
        if restorePoint.current {
            previous = restorePoint.current; restorePoint.current = None;
            contentRef.current.scrollTop = previous["top"];
            opener = previous["focus"] if previous["focus"] and previous["focus"].isConnected else contentRef.current.querySelector("[data-plan-item='" + str(previous["focusId"]) + "']") if previous["focusId"] else None;
            if opener { opener.focus({"preventScroll": True}); }
        } else {
            contentRef.current.scrollTop = 0;
            if inspected or pane == "day" {
                back = contentRef.current.querySelector(".studio-back");
                if back { back.focus({"preventScroll": True}); }
            }
        }
    }, [pane, dayId, inspected["id"] if inspected else ""]);
    useEffect(lambda {
        if not inspected { return; }
        doc: any = document;
        def key(event: any) { if event.key == "Escape" and not accountOpen and not preferencesOpen and not libraryOpen { event.preventDefault(); backView(); } }
        doc.addEventListener("keydown", key);
        return lambda { doc.removeEventListener("keydown", key); };
    }, [inspected, accountOpen, preferencesOpen, libraryOpen]);
    useEffect(lambda {
        if not state or not online { return; }
        expected = str(state["id"]); revision = int(state["revision"]); browser: any = window;
        cancelled: bool = False;
        async def refresh {
            if cancelled or not current.current or current.current["id"] != expected or current.current["revision"] != revision { return; }
            try {
                weather = parse_response(await planner_weather(expected) if signed_in() else await planner_guest_weather(JSON.stringify(current.current)));
                if cancelled or not alive.current or current.current["id"] != expected or current.current["revision"] != revision { return; }
                value = JSON.parse(JSON.stringify(current.current)); value["weather"] = weather; commit(value);
                if weather["status"] != "LOADING" and not weather["refreshing"] { browser.clearInterval(timer); }
            } except Exception { browser.clearInterval(timer); }
        }
        timer = browser.setInterval(lambda { refresh(); }, 2500); refresh();
        return lambda { cancelled = True; browser.clearInterval(timer); };
    }, [state["id"] if state else "", state["revision"] if state else 0, online]);

    async def send(message: str = "") {
        content = message or prompt.strip();
        if not content and len(attachments) > 0 { content = "Help me bring this material into my trip plan. Preserve all supplied details and add them to my plan."; }
        if not state or busy or uploading or not content or not online { return; }
        error = ""; notice = ""; deletedUndo = ""; deletedCurrent = False; busy = True;
        request = {"tripId": state["id"], "baseRevision": state["revision"], "snapshot": state["snapshot"], "message": content,
            "clientTurnId": planner_id("turn"), "workingContext": state["workingContext"], "conversation": state["conversation"],
            "summary": state["summary"], "today": planner_today(), "timeZone": planner_zone(), "preferences": preferences or {},
            "contextRefs": [context] if context else [], "attachments": [item["id"] for item in attachments],
            "proposal": state["pending"], "researchContext": {"weather": state["weather"], "offers": state["offers"], "comparisonOfferIds": [offer["id"] for offer in state["comparisonOffers"] or []], "daylight": state["daylight"] or []}};
        try {
            result = parse_response(await planner_start(str(state["id"]), JSON.stringify(request)) if signed_in() else await planner_guest_start(guest_token(), JSON.stringify(request)));
            value = JSON.parse(JSON.stringify(state));
            value["conversation"].append({"role": "user", "content": content}); value["activeJob"] = result["jobId"];
            commit(value); jobId = str(result["jobId"]); progress = "Understanding your trip";
            prompt = ""; attachments = []; context = None; phoneTab = "chat"; chatOpen = True;
        } except Exception { error = "Couldn’t start that request. Your message is still here; please try again."; busy = False; }
    }
    async def stop {
        try {
            if signed_in() { await planner_cancel(str(state["id"]), jobId); }
            else { await planner_guest_cancel(guest_token(), jobId); }
            value = JSON.parse(JSON.stringify(state)); value["activeJob"] = ""; commit(value);
            jobId = ""; busy = False; progress = ""; notice = "Research stopped. Your trip is saved.";

        } except Exception as exc { error = str(exc); }
    }
    async def undoEdit {
        if not state or busy or not state["undo"] { return; }
        busy = True;
        try {
            command = planner_id("undo");
            value = parse_response(await planner_undo(str(state["id"]), int(state["revision"]), command) if signed_in() else await planner_guest_undo(JSON.stringify(state), int(state["revision"]), command));
            commit(value); inspected = None; selectedId = ""; notice = "Last trip update undone.";
        } except Exception { error = "Couldn't undo that update. Reopen the trip and try again."; }
        busy = False;
    }
    def startRename {
        if not state or busy { return; }
        titleDraft = str(state["snapshot"]["title"]); renaming = True;
    }
    async def renameTrip {
        if not renaming { return; }
        renaming = False;
        title = " ".join(titleDraft.split());
        if not state or not title or title == str(state["snapshot"]["title"]) { return; }
        busy = True;
        try {
            command = planner_id("rename");
            value = parse_response(await planner_rename(str(state["id"]), title, int(state["revision"]), command) if signed_in() else await planner_guest_rename(JSON.stringify(state), title, int(state["revision"]), command));
            commit(value);
            savedTrips = [({**trip, "title": value["snapshot"]["title"]} if trip["id"] == value["id"] else trip) for trip in savedTrips];
            notice = "Trip renamed.";
        } except Exception as exc { error = str(exc) or "Couldn't rename the trip. Please try again."; }
        busy = False;
    }
    def rememberView {
        doc: any = document;
        viewHistory.current = viewHistory.current + [{"pane": pane, "dayId": dayId, "inspected": inspected, "selectedId": selectedId, "top": contentRef.current.scrollTop if contentRef.current else 0, "focus": doc.activeElement, "focusId": doc.activeElement.getAttribute("data-plan-item") if doc.activeElement and doc.activeElement.getAttribute else ""}];
    }
    def backView {
        history = viewHistory.current;
        if len(history) > 0 {
            previous = history[len(history) - 1];
            viewHistory.current = history[:len(history) - 1];
            pane = str(previous["pane"]); dayId = str(previous["dayId"]); inspected = previous["inspected"]; selectedId = str(previous["selectedId"]); restorePoint.current = previous;
        } else { inspected = None; selectedId = ""; pane = "overview"; dayId = ""; }
    }
    def openDay(id: str) { rememberView(); dayId = id; pane = "day"; inspected = None; selectedId = id; }
    def choosePane(name: str) { pane = name; inspected = None; dayId = ""; selectedId = ""; viewHistory.current = []; }
    def discuss(item_id: str, label: str) {
        context = {"id": item_id, "label": label, "scope": "APPROVED"}; selectedId = item_id;
        chatOpen = True; phoneTab = "chat";
        if inputRef.current { inputRef.current.focus(); }
    }
    def inspect(item_id: str, label: str) {
        viewed: any = state["snapshot"];
        target: any = None; kind: str = "";
        for field in ["places", "stays", "legs", "rentals", "days", "bookings"] {
            for item in viewed[field] or [] { if item["id"] == item_id { target = item; kind = str(field); } }
        }
        for planned_day in viewed["days"] {
            for item in planned_day["items"] { if item["id"] == item_id { target = item; } }
        }
        if target { rememberView(); selectedId = item_id; inspected = {"id": item_id, "label": label, "value": target, "kind": kind, "backLabel": "Day plan" if pane == "day" else "Trip overview"}; phoneTab = "trip"; }
    }
    async def uploadFile(event: any) {
        files: any = event.target.files;
        if not files or files.length == 0 { return; }
        file: any = files[0];
        if file.size > 10485760 { error = "Please keep each attachment below 10 MB."; return; }
        if len(attachments) >= 8 { error = "Attach up to eight files per message."; return; }
        uploading = True;
        try {
            notice = "Preparing attachment…";
            content = await file_content(file);
            media = str(file.type or "text/plain");
            result = parse_response(await planner_upload(str(file.name), media, content) if signed_in() else await planner_guest_upload(guest_token(), str(file.name), media, content));
            attachments = attachments + [result]; notice = "";
        } except Exception as exc { error = str(exc); notice = ""; }
        uploading = False;
        event.target.value = "";
    }
    async def authenticate {
        authProblem = credential_problem(email, password);
        if authProblem { return; }
        authBusy = True;
        failure = await create_account(email, password) if signup else await log_in(email, password);
        if failure { authProblem = failure; authBusy = False; return; }
        authenticated = True; password = "";
        try {
            savedTrips = parse_response(await planner_list(str(current.current["id"]) if current.current else ""));
            value: any = None;
            if hasGuestWork() or len(savedTrips) == 0 { value = parse_response(await planner_import(JSON.stringify(state), guest_token())); }
            else { value = parse_response(await planner_get(latestTrip(savedTrips))); }
            finish_guest_import();
            preferences = parse_response(await planner_preferences());
            commit(value); savedTrips = parse_response(await planner_list(str(current.current["id"]) if current.current else ""));
            accountOpen = False; notice = "Your trip is saved to your account.";
        } except Exception as exc { authProblem = str(exc); }
        authBusy = False;
    }
    async def openTrip(trip_id: str) {
        if busy { return; }
        try {
            value = parse_response(await planner_get(trip_id)); commit(value);
            jobId = str(value["activeJob"] or ""); busy = bool(jobId);
            viewHistory.current = []; undoDismissed = -1; deletedUndo = ""; notice = ""; pane = "overview"; dayId = ""; libraryOpen = False;
            inspected = None; context = None; selectedId = "";
        }
        except Exception as exc { error = str(exc); }
    }
    async def newTrip {
        if busy { return; }
        if not signed_in() and hasGuestWork() {
            libraryOpen = False; accountOpen = True;
            notice = "Save this trip to your account before starting another. Your current plan stays here.";
            return;
        }
        try {
            value = parse_response(await planner_blank());
            value["preferences"] = preferences or {};
            if signed_in() { value = parse_response(await planner_import(JSON.stringify(value), "")); }
            commit(value); viewHistory.current = []; undoDismissed = -1; deletedUndo = ""; notice = ""; pane = "overview"; dayId = ""; selectedId = ""; context = None; inspected = None; libraryOpen = False;
        } except Exception as exc { error = str(exc); }
    }
    async def showLibrary {
        if libraryOpen { libraryOpen = False; return; }
        libraryOpen = True; showDeleted = False;
        try { if signed_in() { savedTrips = parse_response(await planner_list(str(current.current["id"]) if current.current else "")); deletedTrips = parse_response(await planner_deleted()); } }
        except Exception { error = "Couldn't load your trips. Your current plan is still here."; }
    }
    async def deleteTrip(trip_id: str) {
        if busy { return; }
        try {
            parse_response(await planner_delete(trip_id));
            deletedCurrent = bool(state and state["id"] == trip_id);
            deletedUndo = trip_id; notice = "Trip moved to Recently Deleted.";
            if state and state["id"] == trip_id {
                value = parse_response(await planner_blank());
                value = parse_response(await planner_import(JSON.stringify(value), ""));
                commit(value); viewHistory.current = []; inspected = None; context = None; selectedId = ""; dayId = ""; pane = "overview"; libraryOpen = False;
            }
            savedTrips = parse_response(await planner_list(str(current.current["id"]) if current.current else ""));
            deletedTrips = parse_response(await planner_deleted());
        } except Exception { error = "Couldn't remove that trip. Please try again."; }
    }
    async def restoreTrip(trip_id: str) {
        try {
            value = parse_response(await planner_restore(trip_id));
            if deletedCurrent and deletedUndo == trip_id {
                commit(value); pane = "overview"; dayId = ""; selectedId = ""; inspected = None; viewHistory.current = []; undoDismissed = -1;
            }
            deletedCurrent = False; deletedUndo = ""; notice = "Trip restored.";
            savedTrips = parse_response(await planner_list(str(current.current["id"]) if current.current else ""));
            deletedTrips = parse_response(await planner_deleted());
        } except Exception { error = "Couldn't restore that trip. Please try again."; }
    }
    async def signOut {
        if busy { return; }
        clear_account_cache(cacheKey()); viewHistory.current = []; restorePoint.current = None; deletedTrips = []; deletedUndo = "";
        log_out(); authenticated = False; state = None; current.current = None;
        attachments = []; inspected = None; context = None; prompt = "";
        savedTrips = []; libraryOpen = False; preferencesOpen = False; pane = "overview"; dayId = ""; selectedId = ""; jobId = "";
        await initialize();
    }
    async def forgetPreference(key: str) {
        try {
            preferences = parse_response(await planner_forget_preference(key)) if signed_in() else forget_local(preferences, key);
            save_preferences(cacheKey(), preferences);
            value = JSON.parse(JSON.stringify(state)); value["preferences"] = preferences; commit(value);
        } except Exception as exc { error = str(exc); }
    }

    snapshot: any = None;
    if state {
        snapshot = state["snapshot"];
    }
    mapSnapshot: any = useMemo(lambda { return mapped_snapshot(snapshot, state["mapLocations"] or []) if snapshot else None; }, [snapshot, state["mapLocations"] if state else None]);
    day: any = None;
    focusIds: any = [];
    if snapshot {
        for candidate in snapshot["days"] { if candidate["id"] == dayId { day = candidate; } }
        if day and pane == "day" { focusIds = [item["placeId"] for item in day["items"] if item["placeId"]]; if day["overnightPlaceId"] { focusIds.append(day["overnightPlaceId"]); } }
    }
    visibleOffers: any = state["comparisonOffers"] if state and "comparisonOffers" in Object.keys(state) else state["offers"] if state else [];
    lastAssistant: int = -1;
    if state {
        for (index, turn) in enumerate(state["conversation"]) { if turn["role"] != "user" { lastAssistant = index; } }
    }
    empty = snapshot and len(snapshot["places"]) == 0 and len(snapshot["days"]) == 0;
    return <div className={"trip-studio bg-linear-to-br from-emerald-100/80 via-green-50 to-emerald-50 " + ("chat-collapsed " if not chatOpen else "") + "phone-" + phoneTab}>
        <header className={HEADER + " studio-header static"}><Brand/>
            <div className="studio-trip-title min-w-0">
                {if renaming {
                    <form className="flex items-center" onSubmit={lambda (e: FormEvent) { e.preventDefault(); renameTrip(); }}>
                        <label htmlFor="studio-trip-name" className="studio-sr-only">Trip name</label>
                        <input id="studio-trip-name" autoFocus={True} value={titleDraft} maxLength={160} onChange={lambda (e: ChangeEvent) { titleDraft = str(e.target.value); }} onFocus={lambda (e: any) { e.target.select(); }} onBlur={lambda { renameTrip(); }}
                            onKeyDown={lambda (e: any) { if e.key == "Escape" { renaming = False; } elif e.key == "Enter" and not e.nativeEvent.isComposing { e.preventDefault(); renameTrip(); } }}
                            className="w-full max-w-sm rounded-lg border border-emerald-400 bg-white px-2 py-1 text-sm font-semibold text-gray-900 shadow-sm outline-none focus:ring-2 focus:ring-emerald-500/40"/>
                    </form>
                } else {
                    <button type="button" onClick={startRename} disabled={not state or busy} title="Rename this trip"
                        className="group inline-flex max-w-full items-center gap-1.5 rounded-lg px-2 py-1 text-left text-sm font-semibold text-gray-900 transition-colors hover:bg-white/70">
                        <span className="truncate">{str(state["snapshot"]["title"]) if state else "Your next journey"}</span>
                        {if state { <span aria-hidden="true" className="text-xs text-gray-400 group-hover:text-emerald-700">✎ Rename</span> }}
                    </button>
                }}
                <span className="px-2 text-gray-500">{"Saved to account" if authenticated else "Saved on this device"}</span>
            </div><nav aria-label="Workspace"><button ref={libraryButton} type="button" className={"is-open" if libraryOpen else ""} aria-expanded={libraryOpen} aria-controls="studio-trip-library" onClick={showLibrary} disabled={busy}>Your trips</button><button type="button" className="studio-preferences-button" onClick={lambda { preferencesOpen = True; }}>Preferences</button>{if authenticated { <button type="button" onClick={signOut} disabled={busy}>Sign out</button> } else { <button type="button" className="studio-account-button" disabled={busy or uploading} onClick={lambda { accountOpen = True; }}>Save & resume anywhere ↗</button> }}</nav></header>
        {if not online { <div className="studio-offline" role="status">You're offline. Your saved itinerary and booking details are available; maps and research need a connection.</div> }}
        {if error { <div className="studio-error" role="alert"><span>{error}</span><button type="button" aria-label="Dismiss error" onClick={lambda { error = ""; }}>×</button></div> }}
        {if notice or (state and state["undo"] and not busy and int(state["revision"]) != undoDismissed) { <div className="studio-notice" role="status"><span>{notice or "Trip updated."}</span>{if deletedUndo { <button type="button" onClick={lambda { restoreTrip(deletedUndo); }}>Undo</button> } elif state and state["undo"] and not busy and int(state["revision"]) != undoDismissed { <button type="button" onClick={undoEdit}>Undo last update</button> }}<button type="button" aria-label="Dismiss notice" onClick={lambda { notice = ""; undoDismissed = int(state["revision"]) if state else -1; }}>×</button></div> }}
        {if libraryOpen { <section ref={libraryRef} id="studio-trip-library" className="studio-library" aria-label="Your trips"><div className="studio-heading-row"><h2>{"Recently Deleted" if showDeleted else "Your trips"}</h2><button type="button" onClick={lambda { libraryOpen = False; }} aria-label="Close your trips">×</button></div><div className="studio-library-actions"><button type="button" onClick={newTrip} disabled={busy}>+ New trip</button>{if authenticated { <button type="button" onClick={lambda { showDeleted = not showDeleted; }}>{"← Your trips" if showDeleted else "Recently Deleted"}</button> }}</div>{if not authenticated { <p>Your current trip stays on this device. Sign in to keep multiple trips and resume anywhere.</p> }}{if showDeleted { <div><p>Removed trips stay here for 30 days.</p>{for trip in deletedTrips { <div className="studio-library-row" key={trip["id"]}><span>{str(trip["title"])}</span><button type="button" onClick={lambda { restoreTrip(str(trip["id"])); }}>Restore</button></div> }}{if len(deletedTrips) == 0 { <p>No recently deleted trips.</p> }}</div> } else { <div>{for trip in savedTrips { <div className="studio-library-row" key={trip["id"]}><button type="button" aria-current={"page" if state and state["id"] == trip["id"] else None} onClick={lambda { openTrip(str(trip["id"])); }}>{str(trip["title"]) + " →"}</button><button type="button" className="studio-delete-trip" aria-label={"Delete " + str(trip["title"])} onClick={lambda { deleteTrip(str(trip["id"])); }}>Remove</button></div> }}</div> }}</section> }}
        {if state { <main className="studio-workspace">
            <section className="studio-planning-pane" aria-label="Trip planner"><nav className="studio-tabs" aria-label="Trip views"><button type="button" className={"active" if pane in ["overview", "day"] else ""} onClick={lambda { choosePane("overview"); }}>Your trip</button><button type="button" className={"active" if pane == "comparison" else ""} onClick={lambda { choosePane("comparison"); }}>Compare options{if len(visibleOffers) > 0 { <span>{len(visibleOffers)}</span> }}</button></nav>
                <div className="studio-content" ref={contentRef}>{if inspected { <StudioDetails item={inspected} snapshot={snapshot} resources={state} weather={state["weather"]} onBack={backView} onContext={discuss}/> } elif pane == "comparison" { <StudioComparison offers={visibleOffers} links={state["researchLinks"]} onContext={discuss}/> } elif day and pane == "day" { <StudioDay day={day} snapshot={snapshot} onBack={backView} onContext={inspect} weather={state["weather"]}/> } elif empty { <div className="studio-welcome"><p className="studio-eyebrow">A JOURNEY STARTS WITH A THOUGHT</p><h1>Where are we<br/>headed?</h1><p>A weekend away. A cross-country adventure.<br/>Or just a flight and somewhere to stay.</p><div className="studio-welcome-line"/><small>Talk it through with Detour.<br/>We'll shape the trip together.</small><div className="studio-start-prompts"><button type="button" onClick={lambda { send("I'd like to plan a road trip through Arizona's national parks. Help me start with a route and overnight bases."); }}>Explore Arizona ↗</button><button type="button" onClick={lambda { send("I need help planning a short work trip. Just travel and a hotel, no activity itinerary."); }}>Plan a work trip ↗</button></div></div> } else { <StudioOverview snapshot={snapshot} costs={state["budgetSummary"]} weather={state["weather"]} onDay={openDay} onContext={inspect}/> }}</div>
            </section>
            <div className="studio-geography"><PlannerMap snapshot={mapSnapshot} onLocate={lambda { send("Check the map locations for " + (str(day["title"]) if day else "this trip") + ". Use source-backed locations and keep the itinerary unchanged."); }} roads={state["routes"] or []} focusIds={focusIds} selectedId={selectedId} onSelect={lambda (id: str) { inspect(id, place_label(snapshot, id)); }}/>{if not empty { <div className="studio-map-legend"><span>◦ Places in your plan</span><span>┄ Connections · ━ Sourced road estimates</span></div> }}</div>
            <aside className="studio-chat" aria-label="Conversation with Detour"><header className="studio-chat-heading"><div><span className="studio-ai-mark">✳</span><strong>Plan with Detour</strong></div><button type="button" aria-label="Collapse chat" onClick={lambda { chatOpen = False; }}>⇥</button></header><div className="studio-chat-log" role="log" aria-label="Planning conversation" aria-live="polite">
                {if len(state["conversation"]) == 0 { <div className="studio-chat-intro"><span className="studio-ai-mark">✳</span><h2>Let's find your kind of trip.</h2><p>Tell me where you're thinking of going, or paste a plan you've already started.</p></div> }}
                {for (index, turn) in enumerate(state["conversation"]) { <article className={"studio-message " + ("is-user" if turn["role"] == "user" else "is-atlas")} key={index}><span>{"YOU" if turn["role"] == "user" else "DETOUR"}</span><ChatMarkdown content={str(turn["content"])}/>{if turn["role"] != "user" and len(conversation_offers(turn, state["offers"], visibleOffers if index == lastAssistant else [])) > 0 { <div className="studio-chat-offers">{for offer in conversation_offers(turn, state["offers"], visibleOffers if index == lastAssistant else []) { <StudioOffer key={offer["id"]} offer={offer} onContext={discuss} compact={True}/> }}</div> }}</article> }}
                <div ref={chatEnd}/>
            </div>
                {if not busy and (len(visibleOffers) > 0 or len(state["researchLinks"]) > 0) { <button type="button" className="studio-results-shortcut" onClick={lambda { choosePane("comparison"); phoneTab = "trip"; }}>View search results →</button> }}
                <div className="studio-composer-area">{if busy { <div className="studio-working" role="status" aria-live="polite"><span className="studio-pulse"/><span>{progress or "Working on your trip"}</span><button type="button" onClick={stop} disabled={not jobId}>Stop</button></div> }}{if not busy and state["nextDecision"] and state["nextDecision"]["quickReplies"] { <div className="studio-quick-replies">{for reply in state["nextDecision"]["quickReplies"] { <button type="button" key={reply["label"]} onClick={lambda { if reply["action"] == "COMPOSE" { prompt = str(reply["message"]); if inputRef.current { inputRef.current.focus(); } } else { send(str(reply["message"])); } }}>{str(reply["label"])}</button> }}</div> }}
                    {if context { <div className="studio-context-chip"><span>{"About: " + str(context["label"])}</span><button type="button" aria-label="Remove selected context" onClick={lambda { context = None; selectedId = ""; }}>×</button></div> }}
                    {if len(attachments) > 0 { <div className="studio-attachments">{for item in attachments { <button type="button" key={item["id"]} data-plan-item={item["id"]} aria-label={"Remove " + str(item["name"])} onClick={lambda { attachments = [a for a in attachments if a["id"] != item["id"]]; }}>{str(item["name"]) + " ×"}</button> }}</div> }}
                    <form className="studio-composer" onSubmit={lambda (e: FormEvent) { e.preventDefault(); send(); }}><label htmlFor="studio-prompt" className="studio-sr-only">Message Detour</label><textarea ref={inputRef} id="studio-prompt" value={prompt} maxLength={160000} placeholder="Where would you like to go?" rows={3} onChange={lambda (e: ChangeEvent) { prompt = str(e.target.value); }} onKeyDown={lambda (e: any) { if e.key == "Enter" and not e.shiftKey and not e.nativeEvent.isComposing { e.preventDefault(); send(); } }}/><div className="studio-composer-toolbar"><label className="studio-attach" title="Attach a PDF, image, or text file"><span aria-hidden="true">＋</span><span className="studio-sr-only">Attach a file</span><input type="file" accept=".pdf,.png,.jpg,.jpeg,.webp,.txt" onChange={uploadFile} disabled={busy or uploading or not online}/></label><small>Shift + Enter for a new line</small><button type="submit" className="studio-send" aria-label="Send message" disabled={busy or uploading or not online or (not prompt.strip() and len(attachments) == 0)}>↑</button></div></form><p className="studio-composer-note">Plan in conversation. Changes are easy to undo.</p>
                </div>
            </aside><button type="button" className="studio-reopen-chat" onClick={lambda { chatOpen = True; }}>✳ Plan with Detour</button>
        </main> } else { <div className="studio-loading" role="status">Opening your travel studio…</div> }}
        <nav className="studio-phone-nav" aria-label="Mobile workspace"><button type="button" aria-current={"page" if phoneTab == "trip" else None} onClick={lambda { phoneTab = "trip"; }}>◈ Trip</button><button type="button" aria-current={"page" if phoneTab == "map" else None} onClick={lambda { phoneTab = "map"; }}>⌖ Map</button><button type="button" aria-current={"page" if phoneTab == "chat" else None} onClick={lambda { phoneTab = "chat"; chatOpen = True; }}>✳ Chat{if busy { <span className="studio-pulse"/> }}</button></nav>
        {if preferencesOpen { <div className="studio-modal-backdrop" onClick={lambda (e: any) { if e.target == e.currentTarget { accountOpen = False; preferencesOpen = False; } }}><section className="studio-modal" role="dialog" aria-modal="true" aria-labelledby="studio-preferences-title"><button type="button" className="studio-modal-close" aria-label="Close preferences" onClick={lambda { preferencesOpen = False; }}>×</button><p className="studio-eyebrow">YOUR WAY OF TRAVELING</p><h2 id="studio-preferences-title">What Detour remembers.</h2><p>Detour learns travel preferences as you plan. Each trip can be different. Forget a preference to stop using it in future suggestions.</p>{if preferences and preferences["values"] and len(Object.keys(preferences["values"])) > 0 { <div className="studio-memory-list">{for key in Object.keys(preferences["values"]) { <div key={key}><strong>{str(key).replace("_", " ")}</strong><p>{str(preferences["values"][key]["value"])}</p><button type="button" onClick={lambda { forgetPreference(str(key)); }}>Forget</button></div> }}</div> } else { <p className="studio-memory-empty">No travel preferences remembered yet.</p> }}</section></div> }}
        {if accountOpen { <div className="studio-modal-backdrop" onClick={lambda (e: any) { if e.target == e.currentTarget { accountOpen = False; preferencesOpen = False; } }}><section className="studio-modal" role="dialog" aria-modal="true" aria-labelledby="studio-account-title"><button type="button" className="studio-modal-close" aria-label="Close account dialog" onClick={lambda { accountOpen = False; }}>×</button><p className="studio-eyebrow">TAKE YOUR PLANS WITH YOU</p><h2 id="studio-account-title">{"Make yourself at home." if signup else "Welcome back."}</h2><p>Your current trip comes with you when you sign in.</p><form onSubmit={lambda (e: FormEvent) { e.preventDefault(); authenticate(); }}><label>Email<input type="email" value={email} required={True} autoComplete="email" onChange={lambda (e: ChangeEvent) { email = str(e.target.value); }}/></label><label>Password<input type="password" value={password} required={True} minLength={8 if signup else 1} autoComplete={"new-password" if signup else "current-password"} onChange={lambda (e: ChangeEvent) { password = str(e.target.value); }}/></label>{if authProblem { <p className="studio-warning" role="alert">{authProblem}</p> }}<button type="submit" className="studio-primary" disabled={authBusy}>{"One moment…" if authBusy else "Create account & save trip" if signup else "Sign in & save trip"}</button></form><button type="button" className="studio-text-button" onClick={lambda { signup = not signup; authProblem = ""; }}>{"Already have an account? Sign in" if signup else "New here? Create an account"}</button></section></div> }}
    </div>;
}
