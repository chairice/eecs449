"""One sourced option presentation shared by chat and the comparison pane."""
import from ..client.planning_state { date_label, time_label, money_label, observed_label, offer_context }

def:pub conversation_offers(turn: any, offers: any, fallback: any) -> any {
    if "offerIds" in Object.keys(turn) {
        refs = turn["offerIds"] or [];
        return [offer for offer in offers or [] if offer["id"] in refs];
    }
    return fallback;
}

def:pub offer_price(offer: any) -> str {
    price = offer["price"];
    amount = price["amountMinor"] if price else offer["totalMinor"];
    if amount is None { return "See provider for price"; }
    return ("From " if price and price["from"] else "") + money_label(int(amount), str(price["currency"] if price else offer["currency"]));
}

def:pub offer_basis(offer: any) -> str {
    price = offer["price"];
    if not price { return "total"; }
    if price["basis"] == "PER_NIGHT" { return "per night"; }
    if price["basis"] == "PER_PERSON" { return "per person"; }
    if price["basis"] == "PER_DAY" { return "per day"; }
    return "stay total" if offer["category"] in ["HOTEL", "STAY"] else "total";
}

def:pub StudioOffer(offer: any, onContext: Callable[[str, str], None], compact: bool = False) -> JsxElement {
    flight = offer["flight"];
    price = offer["price"];
    return <article className={"studio-offer" + (" is-compact" if compact else "")} aria-label={str(offer["title"])}>
        {if not compact and offer["photoUrl"] { <img className="studio-offer-photo" src={offer["photoUrl"]} alt="" loading="lazy"/> }}
        <div className="studio-heading-row"><span className="studio-provider">{str(offer["provider"])}</span><span className="studio-offer-kind">{str(offer["category"]).capitalize()}</span></div>
        <h3>{str(offer["title"])}</h3><p className="studio-offer-context">{offer_context(offer)}</p>
        {if flight and (flight["departTime"] or flight["arriveTime"]) { <p className="studio-flight-times">{time_label(str(flight["departTime"] or "")) + " → " + time_label(str(flight["arriveTime"] or ""))}<small>{str(flight["airline"] or "") + (" · " + ("Nonstop" if flight["stops"] == 0 else str(flight["stops"]) + " stop(s)") if "stops" in Object.keys(flight) and flight["stops"] is not None else "")}</small></p> }}
        {if offer["location"] { <p>{str(offer["location"])}</p> }}
        <div className="studio-price-row"><strong className="studio-offer-price">{offer_price(offer)}<small>{offer_basis(offer)}</small></strong></div>
        {if price and price["estimatedTotalMinor"] is not None and price["basis"] in ["PER_NIGHT", "PER_DAY"] { <p className="studio-derived-price">{"Est. " + money_label(int(price["estimatedTotalMinor"]), str(price["currency"])) + " for " + str(price["quantity"]) + (" nights" if price["basis"] == "PER_NIGHT" else " days")}</p> }}
        <div className="studio-offer-actions"><button type="button" onClick={lambda { onContext(str(offer["id"]), str(offer["title"])); }}>Discuss option</button><a href={offer["bookingUrl"] or offer["sourceUrl"]} target="_blank" rel="noopener noreferrer">{"View on " + str(offer["provider"]) + " ↗"}</a></div>
        {if not compact { <details><summary>Details & source</summary><p>{str(offer["details"])}</p><p>{"Checked " + observed_label(float(offer["observedAt"]))}</p>{if price and price["feesIncluded"] is False { <p>Additional taxes or fees may apply.</p> }}<a href={offer["sourceUrl"]} target="_blank" rel="noopener noreferrer">Provider source ↗</a></details> }}
    </article>;
}
