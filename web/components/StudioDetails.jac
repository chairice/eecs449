"""Focused itinerary details with visual schedules and optional supporting notes."""
import from ..client.planning_state { date_label, time_label, place_label, nights, trip_place, trip_photo, trip_booking, trip_item_status, trip_flight, money_label }
import from .StudioWeather { StudioWeather }
import from .StudioOffers { FlightIdentity, FlightSchedule, flight_duration, flight_stops, offer_price, offer_basis }
import from .Icon { Icon }
import from .StudioTripPlan { TripPhoto, FlightSegments }

def:pub StudioDetails(item: any, snapshot: any, resources: any, weather: any, onBack: Callable[[], None], onContext: Callable[[str, str], None], onCompare: Callable[[str, str], None] = lambda (id: str, label: str) {}, onResearch: Callable[[str, str, str], None] = lambda (id: str, label: str, message: str) {}) -> JsxElement {
    value = item["value"];
    selected: any = None;
    for offer in resources["offers"] or [] { if offer["id"] == value["offerId"] { selected = offer; } }
    isFlight = value["mode"] == "FLIGHT";
    place = trip_place(snapshot, str(value["placeId"] or ""));
    names = {"places": "Place", "stays": "Stay", "legs": "Travel", "rentals": "Rental car", "days": "Day plan", "bookings": "Booking"};
    kind = "Flight" if isFlight else str(names[item["kind"]] or value["kind"] or "Details");
    quoteFlight = trip_flight(resources, value, snapshot) if isFlight else None;
    booking = trip_booking(value, snapshot);
    status = trip_item_status(value, snapshot);
    if item["kind"] == "bookings" and status == "To plan" { status = "Booking details"; }
    actions = <div className="studio-detail-actions"><button type="button" className="studio-detail-discuss" onClick={lambda { onContext(str(item["id"]), str(item["label"])); }}><Icon name="sparkles" size={16}/>Ask Detour</button>{if selected { <a className="studio-detail-fare" href={selected["bookingUrl"] or selected["sourceUrl"]} target="_blank" rel="noopener noreferrer" title={"View on " + str(selected["provider"])}>{"View fare" if isFlight else "View stay" if value["checkIn"] else "View rental" if value["pickupDate"] else "View option"}<Icon name="arrow.up.right" size={15}/></a> }}</div>;
    return <section className={"studio-inspector" + (" is-flight" if isFlight else "")} aria-label="Selected trip item">
        <button type="button" className="studio-back" onClick={onBack}><Icon name="chevron.left" size={15}/>{str(item["backLabel"] or "Trip overview")}</button>
        <header className="studio-detail-heading"><div className="studio-heading-row"><p className="studio-eyebrow">{kind}</p><div className="studio-status-tags"><span className={"studio-plan-status is-" + status.lower().replace(" ", "-")}>{status}</span>{if value["locked"] and status not in ["Booked", "Fixed"] { <span className="studio-tag">Fixed</span> }}</div></div><h2>{str(item["label"])}</h2></header>
        <TripPhoto photo={trip_photo(snapshot, value, selected)} className="studio-detail-photo"/>
        {if isFlight {
            <><div className="studio-detail-flight">
                {if quoteFlight { <FlightIdentity flight={quoteFlight}/> }}
                <FlightSchedule flight={value} showDates={True}/>
                <div className="studio-detail-flight-meta">{if flight_duration(value) or flight_duration(quoteFlight) { <span>{flight_duration(value) or flight_duration(quoteFlight)}</span> }}{if flight_stops(quoteFlight) { <span>{flight_stops(quoteFlight)}</span> }}<span>Local times</span></div>
            </div>
            <FlightSegments flight={quoteFlight}/>
            {if quoteFlight and int(quoteFlight["stops"] or 0) > 0 and len(quoteFlight["segments"] or []) == 0 { <div className="studio-connection-pending"><p>Connection details haven’t been checked yet.</p><button type="button" onClick={lambda { onResearch(str(selected["id"] if selected else item["id"]), str(selected["title"] if selected else item["label"]), "Check the connection airports and each flight’s times for this selected flight. Keep my chosen fare and itinerary unchanged."); }}>Check connection details ↗</button></div> }}
            </>
        } elif value["departDate"] or value["departTime"] {
            <div className="studio-inspector-travel"><div><small>Departure</small><strong>{time_label(str(value["departTime"] or "")) or "Time open"}</strong><p>{date_label(str(value["departDate"] or ""))}</p><p>{place_label(snapshot, str(value["fromId"]))}</p></div><Icon name="arrow.right" size={18}/><div><small>Arrival</small><strong>{time_label(str(value["arriveTime"] or "")) or "Time open"}</strong><p>{date_label(str(value["arriveDate"] or ""))}</p><p>{place_label(snapshot, str(value["toId"]))}</p></div></div>
        }}
        {if value["checkIn"] { <><div className="studio-detail-dates"><span><small>Check in</small><strong>{date_label(str(value["checkIn"]))}</strong></span><Icon name="arrow.right" size={17}/><span><small>Check out</small><strong>{date_label(str(value["checkOut"]))}</strong></span><small>{nights(value)}</small></div>{if value["propertyName"] and value["propertyName"] != item["label"] { <p>{str(value["propertyName"])}</p> }}</> }}
        {if value["startTime"] { <p className="studio-detail-time"><Icon name="calendar" size={17}/>{time_label(str(value["startTime"])) + (" – " + time_label(str(value["endTime"])) if value["endTime"] else "")}</p> }}
        {if value["pickupDate"] { <div className="studio-inspector-travel"><div><small>Pickup</small><strong>{time_label(str(value["pickupTime"])) or "Time open"}</strong><p>{date_label(str(value["pickupDate"]))}</p><p>{place_label(snapshot, str(value["pickupPlaceId"]))}</p></div><Icon name="arrow.right" size={18}/><div><small>Return</small><strong>{time_label(str(value["dropoffTime"])) or "Time open"}</strong><p>{date_label(str(value["dropoffDate"]))}</p><p>{place_label(snapshot, str(value["dropoffPlaceId"]))}</p></div></div> }}
        {if place["address"] { <p className="studio-detail-address">{str(place["address"])}</p> }}
        {if value["notes"] { <p className="studio-detail-notes">{str(value["notes"])}</p> }}
        {if selected and selected["details"] and selected["details"] != value["notes"] { <details className="studio-selected-details" open={not quoteFlight or len(quoteFlight["segments"] or []) == 0}><summary>{"Original quote notes" if quoteFlight and len(quoteFlight["segments"] or []) > 0 else "Quote details"}</summary><p>{str(selected["details"])}</p></details> }}
        {if len(value["actions"] or []) > 0 { <div className="studio-item-actions">{for action in value["actions"] { <a key={action["url"]} href={str(action["url"])} target="_blank" rel="noopener noreferrer">{str(action["label"])} ↗</a> }}</div> }}
        {if value["details"] { <div className="studio-detail-booking">{str(value["details"])}</div> }}
        {if selected or (booking and booking["amountMinor"] is not None) { <div className="studio-detail-quote"><span className="studio-option-price">{if booking and booking["status"] != "CANCELLED" and booking["amountMinor"] is not None { <><strong>{money_label(int(booking["amountMinor"]), str(booking["currency"]))}</strong><small>Booking amount</small></> } elif selected { <><strong>{offer_price(selected)}</strong><small>{offer_basis(selected)}</small></> }}</span>{actions}</div> } else { <>{actions}</> }}
        {if item["kind"] in ["legs", "stays", "rentals"] and not value["locked"] { <button type="button" className="studio-subtle-button" onClick={lambda { onCompare(str(item["id"]), str(item["label"])); }}>{"Compare alternatives" if selected else "Find options"}</button> }}
        <StudioWeather weather={weather} targetId={str(item["id"])}/>
        {if value["query"] or value["sourceUrl"] or len(value["sourceRefs"] or []) > 0 { <details className="studio-inspector-sources"><summary>Notes & details</summary>{if value["query"] { <p>{str(value["query"])}</p> }}{if value["sourceUrl"] { <a href={value["sourceUrl"]} target="_blank" rel="noopener noreferrer">Location details ↗</a> }}{for ref in value["sourceRefs"] or [] { <div key={ref}>{for source in resources["researchSources"] or [] { if source["captureId"] == ref { <a href={source["url"]} target="_blank" rel="noopener noreferrer">{str(source["title"]) + " ↗"}</a> } }}{for source in resources["routes"] or [] { if source["id"] == ref { <p>{str(source["durationMinutes"]) + " min driving estimate"}</p> } }}</div> }}</details> }}
    </section>;
}
