"""A focused item view inside the pane's single scroll surface."""
import from ..client.planning_state { date_label, time_label, place_label, nights }
import from .StudioWeather { StudioWeather }
import from .StudioOffers { offer_price, offer_basis }

def:pub StudioDetails(item: any, snapshot: any, resources: any, weather: any, onBack: Callable[[], None], onContext: Callable[[str, str], None]) -> JsxElement {
    value = item["value"];
    selected: any = None;
    for offer in resources["offers"] or [] { if offer["id"] == value["offerId"] { selected = offer; } }
    return <section className="studio-inspector" aria-label="Selected trip item"><button type="button" className="studio-back" onClick={onBack}>{"← " + str(item["backLabel"] or "Trip overview")}</button>
        <div className="studio-heading-row"><p className="studio-eyebrow">{str(value["mode"] or item["kind"] or "A CLOSER LOOK").replace("_", " ")}</p>{if value["locked"] { <span className="studio-tag">Fixed</span> }}</div>
        {if value["photoUrl"] { <img src={value["photoUrl"]} alt="" loading="lazy"/> }}
        <h2>{str(item["label"])}</h2>
        {if value["departDate"] or value["departTime"] { <div className="studio-inspector-travel"><div><small>Departure · local time</small><strong>{time_label(str(value["departTime"] or "")) or "Time open"}</strong><p>{date_label(str(value["departDate"] or ""))}</p><p>{place_label(snapshot, str(value["fromId"]))}</p></div><span aria-hidden="true">→</span><div><small>Arrival · local time</small><strong>{time_label(str(value["arriveTime"] or "")) or "Time open"}</strong><p>{date_label(str(value["arriveDate"] or ""))}</p><p>{place_label(snapshot, str(value["toId"]))}</p></div></div> }}
        {if value["checkIn"] { <div><p>{date_label(str(value["checkIn"])) + " — " + date_label(str(value["checkOut"])) + " · " + nights(value)}</p>{if value["propertyName"] { <p>{str(value["propertyName"])}</p> }}</div> }}
        {if value["startTime"] { <p>{time_label(str(value["startTime"])) + (" — " + time_label(str(value["endTime"])) if value["endTime"] else "")}</p> }}
        {if value["pickupDate"] { <div className="studio-inspector-travel"><div><small>Pickup</small><p>{place_label(snapshot, str(value["pickupPlaceId"]))}</p><p>{date_label(str(value["pickupDate"])) + " · " + (time_label(str(value["pickupTime"])) or "Time open")}</p></div><div><small>Drop-off</small><p>{place_label(snapshot, str(value["dropoffPlaceId"]))}</p><p>{date_label(str(value["dropoffDate"])) + " · " + (time_label(str(value["dropoffTime"])) or "Time open")}</p></div></div> }}
        {if value["query"] { <p>{str(value["query"])}</p> }}{if value["details"] { <p>{str(value["details"])}</p> }}
        {if selected { <div className="studio-detail-quote"><p>{str(selected["flight"]["airline"] or selected["provider"]) if selected["flight"] else str(selected["provider"])}</p>{if selected["flight"] and "stops" in Object.keys(selected["flight"]) and selected["flight"]["stops"] is not None { <p>{"Nonstop" if selected["flight"]["stops"] == 0 else str(selected["flight"]["stops"]) + " stop(s)"}</p> }}<strong>{offer_price(selected)}<small>{offer_basis(selected)}</small></strong><a href={selected["bookingUrl"] or selected["sourceUrl"]} target="_blank" rel="noopener noreferrer">{"View on " + str(selected["provider"]) + " ↗"}</a></div> }}
        <button type="button" className="studio-primary studio-detail-discuss" onClick={lambda { onContext(str(item["id"]), str(item["label"])); }}>Ask Detour about this ↗</button>
        <StudioWeather weather={weather} targetId={str(item["id"])}/>
        {if value["notes"] or value["sourceUrl"] or len(value["sourceRefs"] or []) > 0 { <details className="studio-inspector-sources"><summary>Notes & sources</summary>{if value["notes"] { <p>{str(value["notes"])}</p> }}{if value["sourceUrl"] { <a href={value["sourceUrl"]} target="_blank" rel="noopener noreferrer">Location source ↗</a> }}{for ref in value["sourceRefs"] or [] { <div key={ref}>{for source in resources["researchSources"] or [] { if source["captureId"] == ref { <a href={source["url"]} target="_blank" rel="noopener noreferrer">{str(source["title"]) + " ↗"}</a> } }}{for source in resources["routes"] or [] { if source["id"] == ref { <p>{str(source["durationMinutes"]) + " min driving estimate · OSRM"}</p> } }}</div> }}</details> }}
    </section>;
}
