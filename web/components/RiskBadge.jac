"""A route's risk as a coloured pill, shared by the results and the Trips pages.
Labels are the words `risk_badge` in RouteComparison gives; unknown stays grey."""

glob RANKS: list[str] = ["High", "Some", "Low"];

"""A route's riskiest known signal in a few words, from its delay, weather and
connection levels ("Low", "Moderate", "High", "Unknown"). Unknown never reads as
safe, so a route with nothing known says so; weather not yet forecast is left
to the other signals."""
def:pub risk_words(delay: str, weather: str, transfer: str) -> str {
    levels = [delay, weather, transfer];
    if "High" in levels { return "High risk"; }
    if "Moderate" in levels { return "Some risk"; }
    if "Low" in levels { return "Low connection risk" if transfer == "Low" else "Low risk"; }
    return "Risk unknown";
}

"""Risk in plain words: "Unknown" reads as "unknown", the rest as a level."""
def:pub risk_summary(delay: str, weather: str, transfer: str) -> str {
    return "Delay " + delay.lower() + " · Weather " + weather.lower() + " · Connection risk " + transfer.lower();
}

def:pub risk_tone(label: str) -> str {
    if label.startswith("High") { return "bg-red-50 text-red-700 ring-red-200"; }
    if label.startswith("Some") { return "bg-amber-50 text-amber-800 ring-amber-200"; }
    if label.startswith("Low") { return "bg-emerald-50 text-emerald-800 ring-emerald-200"; }
    return "bg-gray-100 text-gray-600 ring-gray-200";
}

"""Just the colour, for a dot beside the words where a pill would be too loud."""
def:pub risk_dot(label: str) -> str {
    if label.startswith("High") { return "bg-red-500"; }
    if label.startswith("Some") { return "bg-amber-500"; }
    if label.startswith("Low") { return "bg-emerald-500"; }
    return "bg-gray-400";
}

"""The most serious of several labels, so a round trip shows its riskier leg."""
def:pub worst_risk(labels: list[str]) -> str {
    for rank in RANKS {
        for label in labels {
            if label.startswith(rank) { return label; }
        }
    }
    return labels[0] if len(labels) > 0 else "";
}

def:pub RiskBadge(label: str, detail: str = "") -> JsxElement {
    return <span className={"inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 " + risk_tone(label)} title={detail}>{label}</span>;
}
