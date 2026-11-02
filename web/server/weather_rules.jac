"""
Weather evidence to a risk level. Pure and deterministic: no HTTP, no clock.

A point is HIGH under a warning-level alert; MODERATE under a lesser alert, a
likely wintry or stormy hour, or strong wind; LOW only when both its forecast
and its alerts were read and showed none of that. A route takes its worst
point, and any unread point keeps an otherwise calm route UNKNOWN: unknown is
never treated as safe."""

import from server.models { RiskLevel, SourceStatus, WeatherEvidence }

# About 35 mph sustained, where coaches and trains begin to slow.
glob WINDY_KPH: float = 56.0;
# A forecast hazard counts once the hour is at least this likely to see it.
glob LIKELY_CHANCE: float = 0.5;
glob HAZARD_WORDS: list[str] = ["snow", "sleet", "freezing", "ice", "blizzard", "wintry", "thunderstorm", "t-storm"];

def hazardous_forecast(item: WeatherEvidence) -> bool {
    if item.wind_kph is not None and item.wind_kph >= WINDY_KPH { return True; }
    chance = item.precipitation_probability;
    words = item.summary.casefold();
    return chance is not None and chance >= LIKELY_CHANCE and `any([word in words for word in HAZARD_WORDS]);
}

def:pub evidence_level(item: WeatherEvidence) -> RiskLevel {
    if item.source.status == SourceStatus.UNAVAILABLE { return RiskLevel.UNKNOWN; }
    if item.alert_severity == RiskLevel.HIGH { return RiskLevel.HIGH; }
    if item.alert_severity == RiskLevel.MODERATE or hazardous_forecast(item) { return RiskLevel.MODERATE; }
    if item.alert_severity == RiskLevel.UNKNOWN { return RiskLevel.UNKNOWN; }
    return RiskLevel.LOW;
}

def:pub route_weather_level(items: list[WeatherEvidence]) -> RiskLevel {
    levels = [evidence_level(item) for item in items];
    if RiskLevel.HIGH in levels { return RiskLevel.HIGH; }
    if RiskLevel.MODERATE in levels { return RiskLevel.MODERATE; }
    if not levels or RiskLevel.UNKNOWN in levels { return RiskLevel.UNKNOWN; }
    return RiskLevel.LOW;
}

"""A route's level while forecasts don't yet reach all of it (`opens` is when
they will): a hazard already forecast stands, anything else waits as unknown.
Returns the level and the `opens` still pending, or None once it no longer is."""
def:pub pending_weather(level: RiskLevel, opens: str | None) -> tuple[RiskLevel, str | None] {
    if opens is None or level in [RiskLevel.HIGH, RiskLevel.MODERATE] { return (level, None); }
    return (RiskLevel.UNKNOWN, opens);
}

glob SIGNIFICANCE: list[RiskLevel] = [RiskLevel.HIGH, RiskLevel.MODERATE, RiskLevel.LOW, RiskLevel.UNKNOWN];

def significance(item: WeatherEvidence) -> int {
    return SIGNIFICANCE.index(evidence_level(item));
}

"""Worst points first, journey order kept among equals, so an explanation can
lead with what set the route's level."""
def:pub by_significance(items: list[WeatherEvidence]) -> list[WeatherEvidence] {
    return sorted(items, key=significance);
}
