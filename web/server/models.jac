"""Canonical server domain. Currency is integer USD cents; times carry offsets."""

import json;
import from datetime { datetime, date }
import from math { isfinite }
import from zoneinfo { ZoneInfo }

enum TravelMode: str { TRAIN = "TRAIN", BUS = "BUS", WALK = "WALK" }
enum TimeKind: str { DEPART_AFTER = "DEPART_AFTER", ARRIVE_BY = "ARRIVE_BY" }
enum SourceStatus: str {
    LIVE = "LIVE", CACHED = "CACHED", FIXTURE = "FIXTURE", UNAVAILABLE = "UNAVAILABLE"
}
enum ServiceStatus: str {
    SCHEDULED = "SCHEDULED", DELAYED = "DELAYED", CANCELED = "CANCELED", UNKNOWN = "UNKNOWN"
}
enum PriorityPreset: str {
    BALANCED = "BALANCED", FASTEST = "FASTEST", LOWEST_COST = "LOWEST_COST",
    MOST_RELIABLE = "MOST_RELIABLE", FEWEST_TRANSFERS = "FEWEST_TRANSFERS"
}
enum RiskLevel: str { LOW = "LOW", MODERATE = "MODERATE", HIGH = "HIGH", UNKNOWN = "UNKNOWN" }
enum ErrorCode: str {
    INVALID_REQUEST = "INVALID_REQUEST", CLARIFICATION_REQUIRED = "CLARIFICATION_REQUIRED",
    NO_ROUTES = "NO_ROUTES", PROVIDER_UNAVAILABLE = "PROVIDER_UNAVAILABLE",
    NOT_FOUND = "NOT_FOUND", SAVE_FAILED = "SAVE_FAILED", PARSER_UNAVAILABLE = "PARSER_UNAVAILABLE", DRAFT_EXPIRED = "DRAFT_EXPIRED"
}
enum ReasonCode: str {
    FASTEST = "FASTEST", LOWEST_COST = "LOWEST_COST", FEWEST_TRANSFERS = "FEWEST_TRANSFERS",
    WITHIN_BUDGET = "WITHIN_BUDGET", TIGHT_TRANSFER = "TIGHT_TRANSFER",
    DELAY_RISK_HIGH = "DELAY_RISK_HIGH", WEATHER_RISK_HIGH = "WEATHER_RISK_HIGH",
    WEATHER_ADVISORY = "WEATHER_ADVISORY", MISSING_DATA = "MISSING_DATA", STALE_DATA = "STALE_DATA"
}

def require_text(value: str, field_name: str) {
    if not isinstance(value, str) or not value.strip() { raise ValueError(field_name + " must be nonempty text"); }
}

def require_nonnegative(value: int, field_name: str) {
    if isinstance(value, bool) or not isinstance(value, int) or value < 0 {
        raise ValueError(field_name + " must be a nonnegative integer");
    }
}

def require_finite(value: float, field_name: str) {
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) { raise ValueError(field_name + " must be a finite number"); }
}

def require_unit(value: float, field_name: str) {
    require_finite(value, field_name);
    if value < 0.0 or value > 1.0 { raise ValueError(field_name + " must be in [0, 1]"); }
}

"""Accept ISO timestamps with seconds and an explicit UTC offset, never naive local time."""
def parse_timestamp(value: str) -> datetime {
    if not isinstance(value, str) or "T" not in value { raise ValueError("timestamp must use ISO 8601"); }
    result = datetime.fromisoformat(value.replace("Z", "+00:00"));
    if result.tzinfo is None or result.utcoffset() is None { raise ValueError("timestamp requires a UTC offset"); }
    return result;
}

obj DomainError {
    has code: ErrorCode, message: str;
    has retryable: bool = False, field_name: str | None = None;
    def postinit { self.validate(); }
    def validate {
        if not isinstance(self.code, ErrorCode) { raise ValueError("invalid error code"); }
        require_text(self.message, "message");
    }
}

obj ProviderWarning {
    has code: str, message: str;
    def postinit { self.validate(); }
    def validate { require_text(self.code, "warning code"); require_text(self.message, "warning message"); }
}

obj ProviderMetadata {
    has provider: str, status: SourceStatus;
    has fetched_at: str | None = None, expires_at: str | None = None;
    has warnings: list[ProviderWarning] = [];
    def postinit { self.validate(); }
    def validate {
        require_text(self.provider, "provider");
        if not isinstance(self.status, SourceStatus) { raise ValueError("invalid source status"); }
        if self.status != SourceStatus.UNAVAILABLE and self.fetched_at is None { raise ValueError("available source needs fetched_at"); }
        if self.fetched_at is not None { _ = parse_timestamp(self.fetched_at); }
        if self.expires_at is not None {
            if self.fetched_at is None { raise ValueError("expires_at requires fetched_at"); }
            if parse_timestamp(self.expires_at) < parse_timestamp(self.fetched_at) { raise ValueError("source expiry precedes fetch"); }
        }
    }
}

obj ProviderResult[T] {
    has metadata: ProviderMetadata;
    has data: T | None = None, error: DomainError | None = None;
    def postinit { self.validate(); }
    def validate {
        if self.metadata.status == SourceStatus.UNAVAILABLE {
            if self.data is not None or self.error is None { raise ValueError("unavailable source needs error and no data"); }
        } elif self.data is None or self.error is not None { raise ValueError("available source needs data and no error"); }
    }
}

obj Place {
    has id: str, name: str, latitude: float, longitude: float, timezone: str;
    def postinit { self.validate(); }
    def validate {
        require_text(self.id, "place id"); require_text(self.name, "place name");
        require_finite(self.latitude, "latitude"); require_finite(self.longitude, "longitude");
        if not isfinite(self.latitude) or not -90.0 <= self.latitude <= 90.0 { raise ValueError("invalid latitude"); }
        if not isfinite(self.longitude) or not -180.0 <= self.longitude <= 180.0 { raise ValueError("invalid longitude"); }
        _ = ZoneInfo(self.timezone);
    }
}

obj TripIntent {
    has origin_text: str | None = None, destination_text: str | None = None;
    has local_date: str | None = None, local_time: str | None = None, time_kind: TimeKind | None = None;
    has max_price_cents: int | None = None, min_transfer_minutes: int | None = None;
    has allowed_modes: list[TravelMode] | None = None;
    # Intent deliberately allows incomplete fields; conversion to TripRequest validates completeness.
    def postinit { self.validate(); }
    def validate {
        if self.origin_text is not None { require_text(self.origin_text, "origin"); }
        if self.destination_text is not None { require_text(self.destination_text, "destination"); }
        if self.local_date is not None and date.fromisoformat(self.local_date).isoformat() != self.local_date { raise ValueError("date must be YYYY-MM-DD"); }
        if self.local_time is not None {
            if len(self.local_time) != 5 or self.local_time[2] != ":" { raise ValueError("time must be HH:MM"); }
            _ = datetime.strptime(self.local_time, "%H:%M");
        }
        if self.time_kind is not None and not isinstance(self.time_kind, TimeKind) { raise ValueError("invalid intent time kind"); }
        if self.max_price_cents is not None { require_nonnegative(self.max_price_cents, "max price cents"); }
        if self.min_transfer_minutes is not None { require_nonnegative(self.min_transfer_minutes, "transfer minutes"); }
        if self.allowed_modes is not None {
            if not self.allowed_modes or len(set(self.allowed_modes)) != len(self.allowed_modes) { raise ValueError("modes must be nonempty and unique"); }
            for mode in self.allowed_modes {
                if not isinstance(mode, TravelMode) or mode == TravelMode.WALK { raise ValueError("allowed modes must be transit modes"); }
            }
        }
    }
}

obj TripRequest {
    has origin_text: str, destination_text: str, local_date: str, local_time: str, time_kind: TimeKind;
    has max_price_cents: int | None = None, min_transfer_minutes: int = 30;
    has allowed_modes: list[TravelMode] = [TravelMode.TRAIN, TravelMode.BUS];
    has priority: PriorityPreset = PriorityPreset.BALANCED;
    def postinit { self.validate(); }
    def validate {
        require_text(self.origin_text, "origin"); require_text(self.destination_text, "destination");
        if self.origin_text.strip().casefold() == self.destination_text.strip().casefold() { raise ValueError("origin and destination must differ"); }
        if date.fromisoformat(self.local_date).isoformat() != self.local_date { raise ValueError("date must be YYYY-MM-DD"); }
        if len(self.local_time) != 5 or self.local_time[2] != ":" { raise ValueError("time must be HH:MM"); }
        _ = datetime.strptime(self.local_time, "%H:%M");
        if not isinstance(self.time_kind, TimeKind) or not isinstance(self.priority, PriorityPreset) { raise ValueError("invalid request enum"); }
        if self.max_price_cents is not None { require_nonnegative(self.max_price_cents, "max price cents"); }
        require_nonnegative(self.min_transfer_minutes, "transfer minutes");
        if not self.allowed_modes or len(set(self.allowed_modes)) != len(self.allowed_modes) { raise ValueError("modes must be nonempty and unique"); }
        for mode in self.allowed_modes {
            if not isinstance(mode, TravelMode) or mode == TravelMode.WALK { raise ValueError("allowed modes must be transit modes"); }
        }
    }
}

obj RouteLeg {
    has id: str, mode: TravelMode, origin: Place, destination: Place, departure_at: str, arrival_at: str;
    has operator: str = "", service: str = "", status: ServiceStatus = ServiceStatus.UNKNOWN;
    has predicted_delay_minutes: int | None = None;
    def postinit { self.validate(); }
    def validate {
        require_text(self.id, "leg id");
        if not isinstance(self.mode, TravelMode) or not isinstance(self.status, ServiceStatus) { raise ValueError("invalid leg enum"); }
        if parse_timestamp(self.arrival_at) <= parse_timestamp(self.departure_at) { raise ValueError("arrival must follow departure"); }
        if self.predicted_delay_minutes is not None { require_nonnegative(self.predicted_delay_minutes, "delay minutes"); }
    }
}

obj RouteOption {
    has id: str, legs: list[RouteLeg], source: ProviderMetadata;
    has price_cents: int | None = None, currency: str = "USD";
    def postinit { self.validate(); }
    def validate {
        require_text(self.id, "route id");
        if not self.legs { raise ValueError("route needs at least one leg"); }
        if self.source.status == SourceStatus.UNAVAILABLE { raise ValueError("route source is unavailable"); }
        if self.currency != "USD" { raise ValueError("MVP supports USD only"); }
        if self.price_cents is not None { require_nonnegative(self.price_cents, "price cents"); }
        seen: set[str] = set();
        for i in range(len(self.legs)) {
            leg = self.legs[i];
            leg.validate();
            if leg.id in seen { raise ValueError("leg ids must be unique"); }
            seen.add(leg.id);
            if i > 0 {
                previous = self.legs[i - 1];
                if previous.destination.id != leg.origin.id { raise ValueError("route legs are disconnected"); }
                if parse_timestamp(previous.arrival_at) > parse_timestamp(leg.departure_at) { raise ValueError("route legs overlap"); }
            }
        }
    }
    def duration_minutes -> float {
        return (parse_timestamp(self.legs[-1].arrival_at) - parse_timestamp(self.legs[0].departure_at)).total_seconds() / 60.0;
    }
    def transfers -> int {
        transit_count = len([leg for leg in self.legs if leg.mode != TravelMode.WALK]);
        return max(0, transit_count - 1);
    }
}

obj WeatherEvidence {
    has place: Place, valid_from: str, valid_until: str, source: ProviderMetadata;
    has precipitation_probability: float | None = None, wind_kph: float | None = None;
    has alert_severity: RiskLevel = RiskLevel.UNKNOWN;
    def postinit { self.validate(); }
    def validate {
        if parse_timestamp(self.valid_until) <= parse_timestamp(self.valid_from) { raise ValueError("invalid weather window"); }
        if self.precipitation_probability is not None { require_unit(self.precipitation_probability, "precipitation probability"); }
        if self.wind_kph is not None {
            require_finite(self.wind_kph, "wind kph");
            if self.wind_kph < 0 { raise ValueError("invalid wind kph"); }
        }
        if not isinstance(self.alert_severity, RiskLevel) { raise ValueError("invalid weather severity"); }
        if self.source.status == SourceStatus.UNAVAILABLE and (self.precipitation_probability is not None or self.wind_kph is not None or self.alert_severity != RiskLevel.UNKNOWN) {
            raise ValueError("unavailable weather cannot contain known conditions");
        }
    }
}

obj RiskAssessment {
    has delay: RiskLevel = RiskLevel.UNKNOWN, transfer: RiskLevel = RiskLevel.UNKNOWN, weather: RiskLevel = RiskLevel.UNKNOWN;
    has uncertainty: float = 1.0, reason_codes: list[ReasonCode] = [];
    def postinit { self.validate(); }
    def validate {
        require_unit(self.uncertainty, "uncertainty");
        for risk in [self.delay, self.transfer, self.weather] {
            if not isinstance(risk, RiskLevel) { raise ValueError("invalid risk level"); }
        }
        for reason in self.reason_codes {
            if not isinstance(reason, ReasonCode) { raise ValueError("invalid reason code"); }
        }
    }
}

obj ScoreDimensions {
    has duration: float, reliability: float, price: float, transfers: float, weather: float;
    def postinit { self.validate(); }
    def validate {
        for value in [self.duration, self.reliability, self.price, self.transfers, self.weather] { require_unit(value, "score dimension"); }
    }
    def total -> float { return self.duration + self.reliability + self.price + self.transfers + self.weather; }
}

obj ScoredRoute {
    has option: RouteOption, risk: RiskAssessment, features: ScoreDimensions, score: float;
    has reason_codes: list[ReasonCode] = [], weather: list[WeatherEvidence] = [];
    def postinit { self.validate(); }
    def validate {
        require_finite(self.score, "score");
        if not isfinite(self.score) or not -10.0 <= self.score <= 100.0 { raise ValueError("score out of range"); }
        for reason in self.reason_codes {
            if not isinstance(reason, ReasonCode) { raise ValueError("invalid reason code"); }
        }
    }
}

obj TripPlanDraft {
    has id: str, request: TripRequest, routes: list[ScoredRoute], recommended_route_id: str;
    has weights: ScoreDimensions, created_at: str, expires_at: str;
    has sources: list[ProviderMetadata] = [];
    def postinit { self.validate(); }
    def validate {
        require_text(self.id, "draft id");
        route_ids = [route.option.id for route in self.routes];
        if not route_ids or len(set(route_ids)) != len(route_ids) { raise ValueError("draft routes must be nonempty and unique"); }
        if self.recommended_route_id not in route_ids { raise ValueError("recommendation must reference a draft route"); }
        if abs(self.weights.total() - 1.0) > 0.000001 { raise ValueError("weights must sum to one"); }
        if parse_timestamp(self.expires_at) <= parse_timestamp(self.created_at) { raise ValueError("draft expiry must follow creation"); }
    }
}

obj TripPlan {
    has id: str, owner_id: str, request: TripRequest, selected_route: ScoredRoute, created_at: str;
    has backup_route: ScoredRoute | None = None, refreshed_at: str | None = None;
    def postinit { self.validate(); }
    def validate {
        require_text(self.id, "plan id"); require_text(self.owner_id, "owner id");
        _ = parse_timestamp(self.created_at);
        if self.backup_route is not None and self.backup_route.option.id == self.selected_route.option.id { raise ValueError("backup must differ from selected route"); }
        if self.refreshed_at is not None and parse_timestamp(self.refreshed_at) < parse_timestamp(self.created_at) { raise ValueError("refresh precedes creation"); }
    }
}

obj UserPreferences {
    has priority: PriorityPreset = PriorityPreset.BALANCED, max_price_cents: int | None = None;
    has min_transfer_minutes: int = 30, avoided_modes: list[TravelMode] = [];
    def postinit { self.validate(); }
    def validate {
        if not isinstance(self.priority, PriorityPreset) { raise ValueError("invalid priority"); }
        if self.max_price_cents is not None { require_nonnegative(self.max_price_cents, "max price cents"); }
        require_nonnegative(self.min_transfer_minutes, "transfer minutes");
        if len(set(self.avoided_modes)) != len(self.avoided_modes) { raise ValueError("avoided modes must be unique"); }
        for mode in self.avoided_modes {
            if not isinstance(mode, TravelMode) { raise ValueError("invalid avoided mode"); }
        }
    }
}

"""JSON output preserves explicit nulls and integer cents; no raw provider payloads."""
def model_to_json(value: object) -> str {
    return json.dumps(model_to_object(value), allow_nan=False, sort_keys=True);
}

def provider_result_to_json[T](value: ProviderResult[T]) -> str {
    value.validate();
    return json.dumps({"metadata": model_to_object(value.metadata), "data": model_to_object(value.data), "error": model_to_object(value.error)}, allow_nan=False, sort_keys=True);
}

"""Explicit allowlist keeps runtime metadata and unrelated attributes off the wire."""
def model_to_object(value: object) -> object {
    if value is None or isinstance(value, (str, bool, int, float)) { return value; }
    if isinstance(value, list) { return [model_to_object(item) for item in value]; }
    fields: dict[str, object] = {};
    if isinstance(value, TripRequest) {
        value.validate();
        fields = {"origin_text": value.origin_text, "destination_text": value.destination_text, "local_date": value.local_date, "local_time": value.local_time, "time_kind": value.time_kind, "max_price_cents": value.max_price_cents, "min_transfer_minutes": value.min_transfer_minutes, "allowed_modes": value.allowed_modes, "priority": value.priority};
    } elif isinstance(value, TripIntent) {
        value.validate();
        fields = {"origin_text": value.origin_text, "destination_text": value.destination_text, "local_date": value.local_date, "local_time": value.local_time, "time_kind": value.time_kind, "max_price_cents": value.max_price_cents, "min_transfer_minutes": value.min_transfer_minutes, "allowed_modes": value.allowed_modes};
    } elif isinstance(value, Place) {
        value.validate();
        fields = {"id": value.id, "name": value.name, "latitude": value.latitude, "longitude": value.longitude, "timezone": value.timezone};
    } elif isinstance(value, ProviderMetadata) {
        value.validate();
        fields = {"provider": value.provider, "status": value.status, "fetched_at": value.fetched_at, "expires_at": value.expires_at, "warnings": value.warnings};
    } elif isinstance(value, ProviderWarning) {
        value.validate();
        fields = {"code": value.code, "message": value.message};
    } elif isinstance(value, DomainError) {
        value.validate();
        fields = {"code": value.code, "message": value.message, "retryable": value.retryable, "field_name": value.field_name};
    } elif isinstance(value, RouteLeg) {
        value.validate();
        fields = {"id": value.id, "mode": value.mode, "origin": value.origin, "destination": value.destination, "departure_at": value.departure_at, "arrival_at": value.arrival_at, "operator": value.operator, "service": value.service, "status": value.status, "predicted_delay_minutes": value.predicted_delay_minutes};
    } elif isinstance(value, RouteOption) {
        value.validate();
        fields = {"id": value.id, "legs": value.legs, "source": value.source, "price_cents": value.price_cents, "currency": value.currency};
    } elif isinstance(value, WeatherEvidence) {
        value.validate();
        fields = {"place": value.place, "valid_from": value.valid_from, "valid_until": value.valid_until, "source": value.source, "precipitation_probability": value.precipitation_probability, "wind_kph": value.wind_kph, "alert_severity": value.alert_severity};
    } elif isinstance(value, RiskAssessment) {
        value.validate();
        fields = {"delay": value.delay, "transfer": value.transfer, "weather": value.weather, "uncertainty": value.uncertainty, "reason_codes": value.reason_codes};
    } elif isinstance(value, ScoreDimensions) {
        value.validate();
        fields = {"duration": value.duration, "reliability": value.reliability, "price": value.price, "transfers": value.transfers, "weather": value.weather};
    } elif isinstance(value, ScoredRoute) {
        value.validate();
        fields = {"option": value.option, "risk": value.risk, "features": value.features, "score": value.score, "reason_codes": value.reason_codes, "weather": value.weather};
    } elif isinstance(value, TripPlanDraft) {
        value.validate();
        fields = {"id": value.id, "request": value.request, "routes": value.routes, "recommended_route_id": value.recommended_route_id, "weights": value.weights, "created_at": value.created_at, "expires_at": value.expires_at, "sources": value.sources};
    } elif isinstance(value, TripPlan) {
        value.validate();
        fields = {"id": value.id, "owner_id": value.owner_id, "request": value.request, "selected_route": value.selected_route, "backup_route": value.backup_route, "created_at": value.created_at, "refreshed_at": value.refreshed_at};
    } elif isinstance(value, UserPreferences) {
        value.validate();
        fields = {"priority": value.priority, "max_price_cents": value.max_price_cents, "min_transfer_minutes": value.min_transfer_minutes, "avoided_modes": value.avoided_modes};
    } else { raise ValueError("unsupported domain model"); }
    return {key: model_to_object(item) for (key, item) in fields.items()};
}

# Strict decoders are the trust boundary. Casts below follow runtime shape checks;
# unknown object fields fail rather than silently bypassing a misspelled constraint.
def json_object(value: object) -> dict[str, object] {
    if not isinstance(value, dict) { raise ValueError("expected a JSON object"); }
    result: dict[str, object] = {};
    for (key, item) in value.items() {
        if not isinstance(key, str) { raise ValueError("object keys must be strings"); }
        result[key] = item;
    }
    return result;
}
def json_text(value: object) -> str {
    if not isinstance(value, str) { raise ValueError("expected text"); }
    return value;
}
def json_integer(value: object) -> int {
    if isinstance(value, bool) or not isinstance(value, int) { raise ValueError("expected an integer"); }
    return value;
}
def json_optional_integer(value: object) -> int | None {
    return None if value is None else json_integer(value);
}
def json_number(value: object) -> float {
    if isinstance(value, bool) or not isinstance(value, (int, float)) { raise ValueError("expected a number"); }
    return float(value);
}
def json_array(value: object) -> list[object] {
    if not isinstance(value, list) { raise ValueError("expected an array"); }
    return [item for item in value];
}
def check_keys(value: dict[str, object], allowed: list[str]) {
    for key in value {
        if key not in allowed { raise ValueError("unknown field: " + key); }
    }
}
def trip_request_from_json(payload: str) -> TripRequest {
    raw = json_object(json.loads(payload));
    check_keys(raw, ["origin_text", "destination_text", "local_date", "local_time", "time_kind", "max_price_cents", "min_transfer_minutes", "allowed_modes", "priority"]);
    return TripRequest(
        origin_text=json_text(raw.get("origin_text")), destination_text=json_text(raw.get("destination_text")),
        local_date=json_text(raw.get("local_date")), local_time=json_text(raw.get("local_time")), time_kind=TimeKind(json_text(raw.get("time_kind"))),
        max_price_cents=json_optional_integer(raw.get("max_price_cents")), min_transfer_minutes=json_integer(raw.get("min_transfer_minutes", 30)),
        allowed_modes=[TravelMode(json_text(mode)) for mode in json_array(raw.get("allowed_modes", ["TRAIN", "BUS"]))],
        priority=PriorityPreset(json_text(raw.get("priority", "BALANCED")))
    );
}
def place_from_object(value: object) -> Place {
    raw = json_object(value);
    check_keys(raw, ["id", "name", "latitude", "longitude", "timezone"]);
    return Place(id=json_text(raw.get("id")), name=json_text(raw.get("name")), latitude=json_number(raw.get("latitude")), longitude=json_number(raw.get("longitude")), timezone=json_text(raw.get("timezone")));
}
def metadata_from_object(value: object) -> ProviderMetadata {
    raw = json_object(value);
    check_keys(raw, ["provider", "status", "fetched_at", "expires_at", "warnings"]);
    warnings: list[ProviderWarning] = [];
    for item in json_array(raw.get("warnings", [])) {
        warning = json_object(item);
        check_keys(warning, ["code", "message"]);
        warnings.append(ProviderWarning(code=json_text(warning.get("code")), message=json_text(warning.get("message"))));
    }
    fetched = raw.get("fetched_at"); expired = raw.get("expires_at");
    return ProviderMetadata(provider=json_text(raw.get("provider")), status=SourceStatus(json_text(raw.get("status"))), fetched_at=None if fetched is None else json_text(fetched), expires_at=None if expired is None else json_text(expired), warnings=warnings);
}
def route_option_from_json(payload: str) -> RouteOption {
    raw = json_object(json.loads(payload));
    check_keys(raw, ["id", "legs", "source", "price_cents", "currency"]);
    legs: list[RouteLeg] = [];
    for item in json_array(raw.get("legs")) {
        leg = json_object(item);
        check_keys(leg, ["id", "mode", "origin", "destination", "departure_at", "arrival_at", "operator", "service", "status", "predicted_delay_minutes"]);
        legs.append(RouteLeg(
            id=json_text(leg.get("id")), mode=TravelMode(json_text(leg.get("mode"))),
            origin=place_from_object(leg.get("origin")), destination=place_from_object(leg.get("destination")),
            departure_at=json_text(leg.get("departure_at")), arrival_at=json_text(leg.get("arrival_at")),
            operator=json_text(leg.get("operator", "")), service=json_text(leg.get("service", "")), status=ServiceStatus(json_text(leg.get("status", "UNKNOWN"))),
            predicted_delay_minutes=json_optional_integer(leg.get("predicted_delay_minutes"))
        ));
    }
    return RouteOption(id=json_text(raw.get("id")), legs=legs, source=metadata_from_object(raw.get("source")), price_cents=json_optional_integer(raw.get("price_cents")), currency=json_text(raw.get("currency", "USD")));
}
