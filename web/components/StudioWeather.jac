"""Quiet forecast context; official warnings remain prominent."""
import from ..client.planning_state { date_label, observed_label }

def:pub StudioWeather(weather: any, targetId: str = "", dayDate: str = "") -> JsxElement {
    if not weather or weather["status"] == "LOADING" { return <></>; }
    samples: any = [sample for sample in weather["samples"] or [] if (not targetId or sample["targetId"] == targetId or sample["placeId"] == targetId) and (not dayDate or sample["date"] == dayDate)];
    warnings: any = [sample for sample in samples if len(sample["alerts"] or []) > 0];
    available: any = [sample for sample in samples if sample["status"] == "READY"];
    if len(samples) == 0 and weather["status"] not in ["FUTURE", "UNAVAILABLE"] { return <></>; }
    return <section className="studio-weather" aria-label="Trip weather">
        {for sample in warnings { for alert in sample["alerts"] { <details className="studio-weather-alert" key={str(sample["id"]) + str(alert["id"])}><summary>{"⚠ " + str(alert["event"]) + " · " + str(sample["label"])}</summary><p>{str(alert["headline"])}</p><p>{str(alert["description"])}</p>{if alert["instruction"] { <p>{str(alert["instruction"])}</p> }}<a href={alert["url"] or sample["sourceUrl"]} target="_blank" rel="noopener noreferrer">Official NWS warning ↗</a></details> } }}
        {if len(available) > 0 { <details><summary>{"Weather · " + str(available[0]["summary"] or "Forecast available") + (" · +" + str(len(available) - 1) + " locations" if len(available) > 1 else "")}</summary>{for sample in available { <div className="studio-weather-location" key={sample["id"]}><strong>{str(sample["label"]) + " · " + date_label(str(sample["date"]))}</strong><p>{str(sample["summary"] or "") + (" · " + str(sample["temperature"]) + "°" + str(sample["temperatureUnit"] or "F") if sample["temperature"] is not None else "")}</p>{if sample["precipitation"] is not None { <p>{str(sample["precipitation"]) + "% precipitation" + (" · Wind " + str(sample["wind"]) if sample["wind"] else "")}</p> }}<a href={sample["sourceUrl"]} target="_blank" rel="noopener noreferrer">National Weather Service ↗</a><small>{"Updated " + observed_label(sample["checkedAt"])}</small></div> }}</details> } elif weather["status"] == "FUTURE" or (len(samples) > 0 and len([sample for sample in samples if sample["status"] == "FUTURE"]) == len(samples)) { <p>Weather will be available closer to departure.</p> } elif len(warnings) == 0 { <p>Forecasts will refresh when available.</p> }}
    </section>;
}
