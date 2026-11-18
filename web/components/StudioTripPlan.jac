"""The saved trip, joined with its researched choices for useful browsing."""
import from ..client.planning_state { date_label, time_label, place_label, nights, selected_offer, trip_place, trip_photo, trip_item_status, trip_booking, trip_flight, money_label, day_context, day_photo }
import from .StudioOffers { FlightIdentity, FlightSchedule, flight_duration, flight_stops, offer_price, offer_basis }
import from .Icon { Icon }

def:pub PhotoCredit(photo: any) -> JsxElement {
    attribution = str(photo["photoAttribution"] or "");
    license = str(photo["photoLicense"] or "");
    return <>{if attribution or photo["photoSourceUrl"] { <a className="studio-photo-credit" href={str(photo["photoSourceUrl"] or photo["sourceUrl"] or photo["photoUrl"])} target="_blank" rel="noopener noreferrer" title={attribution + (" · " + license if license else "")} aria-label={"Photo credit: " + attribution + (" · " + license if license else "")}>Photo credit{if license { <span>{" · " + license}</span> }}</a> }}</>;
}

def:pub TripPhoto(photo: any, className: str = "") -> JsxElement {
    return <>{if photo and photo["photoUrl"] { <figure className={"studio-trip-photo " + className}><img src={str(photo["photoUrl"])} alt="" loading="lazy" onError={lambda (event: any) { event.currentTarget.closest("figure").hidden = True; }}/>{if photo["photoAttribution"] or photo["photoSourceUrl"] { <figcaption><PhotoCredit photo={photo}/></figcaption> }}</figure> }}</>;
}

def:pub TripChoiceCard(item: any, kind: str, snapshot: any, resources: any, onOpen: Callable[[str, str], None], onCompare: Callable[[str, str], None], compact: bool = False) -> JsxElement {
    offer = selected_offer(resources, item);
    booking = trip_booking(item, snapshot);
    status = trip_item_status(item, snapshot);
    isFlight = kind == "legs" and item["mode"] == "FLIGHT";
    flight = trip_flight(resources, item, snapshot) if isFlight else None;
    place = trip_place(snapshot, str(item["placeId"] or item["pickupPlaceId"] or ""));
    title = place_label(snapshot, str(item["fromId"])) + " → " + place_label(snapshot, str(item["toId"])) if kind == "legs" else str(item["propertyName"] or (offer["title"] if offer else "") or place["label"] or "Stay to find") if kind == "stays" else str(item["provider"] or (offer["title"] if offer else "") or "Car rental");
    kindLabel = "Flight" if isFlight else str(item["mode"] or "Travel").capitalize() if kind == "legs" else "Stay" if kind == "stays" else "Car rental";
    return <article className={"studio-choice-card" + (" is-compact" if compact else "") + (" is-flight" if isFlight else "") }>
        {if kind == "stays" and not compact { <TripPhoto photo={trip_photo(snapshot, item, offer)}/> }}
        <div className="studio-choice-body"><div className="studio-heading-row"><span className="studio-eyebrow">{kindLabel}</span><div className="studio-status-tags"><span className={"studio-plan-status is-" + status.lower().replace(" ", "-")}>{status}</span>{if item["locked"] and status not in ["Booked", "Fixed"] { <span className="studio-tag">Fixed</span> }}</div></div>
            <button type="button" className="studio-choice-title" data-plan-item={str(item["id"])} onClick={lambda { onOpen(str(item["id"]), title); }}>{title}<Icon name="chevron.right" size={16}/></button>
            {if isFlight { <><div className="studio-choice-flight"><div>{if flight and flight["airline"] { <FlightIdentity flight={flight}/> }}<small>{date_label(str(item["departDate"]))}</small></div><FlightSchedule flight={item}/></div><p className="studio-choice-facts">{flight_duration(item) or flight_duration(flight)}{if flight_stops(flight) { <span>{flight_stops(flight)}</span> }}{if item["arriveDate"] and item["arriveDate"] != item["departDate"] { <span>{"Arrives " + date_label(str(item["arriveDate"]))}</span> }}</p></> }
            elif kind == "stays" { <><p className="studio-choice-dates">{date_label(str(item["checkIn"])) + " — " + date_label(str(item["checkOut"]))}<span>{nights(item)}</span></p><p className="studio-choice-location">{str(place["address"] or (offer["location"] if offer else "") or place["label"] or "")}</p></> }
            elif kind == "legs" { <p className="studio-choice-dates">{date_label(str(item["departDate"])) + (" · " + time_label(str(item["departTime"])) if item["departTime"] else "")}</p> }
            else { <p className="studio-choice-dates">{date_label(str(item["pickupDate"])) + " — " + date_label(str(item["dropoffDate"]))}<span>{str(item["vehicle"] or "")}</span></p> }}
            {if not offer and item["notes"] { <p className="studio-choice-user-notes">{str(item["notes"])}</p> }}
            <div className="studio-choice-footer"><span>{if booking and booking["status"] != "CANCELLED" and booking["amountMinor"] is not None { <><strong>{money_label(int(booking["amountMinor"]), str(booking["currency"]))}</strong><small>Booking amount</small></> } elif offer { <><strong>{offer_price(offer)}</strong><small>{offer_basis(offer)}</small></> } else { <small>{"Price not added" if status in ["Booked", "Fixed", "User reported"] else "Choose an option"}</small> }}</span><div><button type="button" onClick={lambda { onOpen(str(item["id"]), title); }}>Details</button>{if not item["bookingId"] and not item["locked"] { <button type="button" className="studio-context-compare" onClick={lambda { onCompare(str(item["id"]), title); }}>{"Compare" if offer else "Find options"}</button> }}</div></div>
        </div>
    </article>;
}

def:pub TripDayCard(day: any, index: int, snapshot: any, onDay: Callable[[str], None]) -> JsxElement {
    commitments = [item for item in day["items"] or [] if item["kind"] not in ["FREE", "REST"]];
    related = day_context(day, snapshot);
    return <article className="studio-agenda-day"><TripPhoto photo={day_photo(day, snapshot)}/><button type="button" className="studio-agenda-day-body" data-plan-item={str(day["id"])} onClick={lambda { onDay(str(day["id"])); }}><div className="studio-heading-row"><span className="studio-eyebrow">{date_label(str(day["date"]))}</span><span className="studio-day-number">{str(index + 1).zfill(2)}</span></div><h3>{str(day["title"])}</h3>
        <div className="studio-agenda-preview">{for item in commitments[:2] { <p key={item["id"]}><span>{time_label(str(item["startTime"])) or "Flexible"}</span><strong>{str(item["title"])}</strong>{if item["locked"] { <Icon name="lock" size={12}/> }}</p> }}{if len(commitments) > 2 { <small>{"+ " + str(len(commitments) - 2) + " more plans"}</small> }}{if len(commitments) == 0 { <>{if len(related["legs"]) > 0 { for leg in related["legs"][:2] { <p key={leg["id"]}><span><small>{"Depart" if leg["departDate"] == day["date"] else "Arrive"}</small>{time_label(str(leg["departTime"] if leg["departDate"] == day["date"] else leg["arriveTime"])) or "Time open"}</span><strong>{place_label(snapshot, str(leg["fromId"])) + " → " + place_label(snapshot, str(leg["toId"]))}</strong></p> } } else { <p><strong>{str(day["notes"] or "No plans added")}</strong></p> }}</> }}</div>
        <div className="studio-agenda-context">{if len(related["legs"]) > 0 { <span><Icon name="arrow.up.right" size={13}/>{str(len(related["legs"])) + (" journey" if len(related["legs"]) == 1 else " journeys")}</span> }}{if day["overnightPlaceId"] { <span><Icon name="pin" size={13}/>{place_label(snapshot, str(day["overnightPlaceId"]))}</span> }}<Icon name="chevron.right" size={16}/></div></button>
    </article>;
}

def:pub FlightSegments(flight: any) -> JsxElement {
    return <>{if flight and len(flight["segments"] or []) > 0 { <section className="studio-flight-segments" aria-label="Flight journey">{for (index, segment) in enumerate(flight["segments"]) { <div className="studio-flight-segment" key={index}><div className="studio-segment-heading"><strong>{str(segment["fromCode"]) + " → " + str(segment["toCode"])}</strong><small>{str(segment["airline"] or "") + (" · " + str(segment["flightNumber"]) if segment["flightNumber"] else "")}</small></div>{if flight_duration(segment) { <p className="studio-segment-duration">{flight_duration(segment) + " flight"}</p> }}<div className="studio-segment-schedule"><span><strong>{time_label(str(segment["departTime"])) or "Time not captured"}</strong><small>{date_label(str(segment["departDate"]))}</small></span><Icon name="arrow.right" size={16}/><span><strong>{time_label(str(segment["arriveTime"])) or "Time not captured"}</strong><small>{date_label(str(segment["arriveDate"]))}</small></span></div>{if segment["layoverMinutes"] is not None and index < len(flight["segments"]) - 1 { <p className="studio-layover">{flight_duration({"durationMinutes": segment["layoverMinutes"]}) + " connection in " + str(segment["toCode"])}</p> }}</div> }}</section> }}</>;
}
