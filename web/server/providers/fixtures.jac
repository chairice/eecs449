"""Synthetic daily corridor schedules. Never a live fallback or booking source."""

import json;
import from datetime { date, datetime, timedelta, timezone }
import from pathlib { Path }
import from zoneinfo { ZoneInfo }
import from server.models {
    DomainError, ErrorCode, Place, ProviderMetadata, ProviderResult, ProviderWarning,
    RouteLeg, RouteOption, ServiceStatus, SourceStatus, TimeKind, TravelMode, TripRequest,
    check_keys, json_array, json_integer, json_object, json_optional_integer,
    json_text, metadata_from_object, place_from_object
}
import from server.providers.route_provider { RouteProvider }

glob DEFAULT_FIXTURE_PATH: str = str(Path(__file__).resolve().parents[2] / "fixtures" / "ann-arbor-chicago.json");

"""Resolve a local wall clock without silently choosing a DST fold or gap."""
def local_instant(local_date: str, local_time: str, zone_name: str, day_offset: int = 0) -> datetime {
    if day_offset < 0 or day_offset > 7 { raise ValueError("fixture day offset must be between zero and seven"); }
    day = date.fromisoformat(local_date) + timedelta(days=day_offset);
    if len(local_time) != 5 or local_time[2] != ":" { raise ValueError("time must be HH:MM"); }
    clock = datetime.strptime(local_time, "%H:%M").time();
    naive = datetime.combine(day, clock);
    zone = ZoneInfo(zone_name);
    first = naive.replace(tzinfo=zone, fold=0);
    second = naive.replace(tzinfo=zone, fold=1);
    if first.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) != naive {
        raise ValueError("local time does not exist due to daylight saving time");
    }
    if first.utcoffset() != second.utcoffset() {
        raise ValueError("local time is ambiguous due to daylight saving time");
    }
    return first;
}

def normalized_location(text: str) -> str {
    return " ".join(text.casefold().replace(",", " ").split());
}

def supports_corridor(request: TripRequest) -> bool {
    return normalized_location(request.origin_text) in ["ann arbor", "ann arbor mi", "ann arbor michigan"] and normalized_location(request.destination_text) in ["chicago", "chicago il", "chicago illinois"];
}

def fixture_failure(code: ErrorCode, message: str) -> ProviderResult[list[RouteOption]] {
    return ProviderResult(metadata=ProviderMetadata(provider="detour-synthetic-corridor-v1", status=SourceStatus.UNAVAILABLE), error=DomainError(code=code, message=message));
}

obj FixtureRouteProvider(RouteProvider) {
    has fixture_path: str = DEFAULT_FIXTURE_PATH;

    def search(request: TripRequest) -> ProviderResult[list[RouteOption]] {
        try {
            request.validate();
            if supports_corridor(request) {
                anchor_zone = "America/Detroit" if request.time_kind == TimeKind.DEPART_AFTER else "America/Chicago";
                _ = local_instant(request.local_date, request.local_time, anchor_zone);
            }
        } except (ValueError, TypeError, OverflowError) {
            return fixture_failure(ErrorCode.INVALID_REQUEST, "Choose valid trip fields and an unambiguous local departure or arrival time.");
        }
        try {
            return self.load_candidates(request);
        } except (OSError, ValueError, TypeError, KeyError, OverflowError) {
            return fixture_failure(ErrorCode.PROVIDER_UNAVAILABLE, "The synthetic route fixture could not be loaded or validated.");
        }
    }

    def load_candidates(request: TripRequest) -> ProviderResult[list[RouteOption]] {
        payload = json_object(json.loads(Path(self.fixture_path).read_text(encoding="utf-8")));
        check_keys(payload, ["schema_version", "synthetic", "description", "source", "places", "routes"]);
        if json_integer(payload.get("schema_version")) != 1 or payload.get("synthetic") is not True {
            raise ValueError("only synthetic fixture schema v1 is supported");
        }
        source = metadata_from_object(payload.get("source"));
        if source.status != SourceStatus.FIXTURE { raise ValueError("fixture must declare FIXTURE provenance"); }
        source.warnings.append(ProviderWarning(code="SYNTHETIC_DATA", message="Illustrative schedules and fares generated for the requested date. Not live service, availability, or booking information."));
        places: dict[str, Place] = {};
        for item in json_array(payload.get("places")) {
            place = place_from_object(item);
            if place.id in places { raise ValueError("duplicate fixture place id"); }
            places[place.id] = place;
        }
        routes: list[RouteOption] = [];
        seen: set[str] = set();
        for item in json_array(payload.get("routes")) {
            raw = json_object(item);
            check_keys(raw, ["id", "price_cents", "currency", "legs"]);
            route_id = json_text(raw.get("id"));
            if route_id in seen { raise ValueError("duplicate fixture route id"); }
            seen.add(route_id);
            legs: list[RouteLeg] = [];
            for leg_value in json_array(raw.get("legs")) {
                leg = json_object(leg_value);
                check_keys(leg, ["id", "mode", "origin_id", "destination_id", "departure_time", "arrival_time", "departure_day_offset", "arrival_day_offset", "operator", "service"]);
                origin = places[json_text(leg.get("origin_id"))];
                destination = places[json_text(leg.get("destination_id"))];
                departure = local_instant(request.local_date, json_text(leg.get("departure_time")), origin.timezone, json_integer(leg.get("departure_day_offset", 0)));
                arrival = local_instant(request.local_date, json_text(leg.get("arrival_time")), destination.timezone, json_integer(leg.get("arrival_day_offset", 0)));
                legs.append(RouteLeg(id=json_text(leg.get("id")), mode=TravelMode(json_text(leg.get("mode"))), origin=origin, destination=destination, departure_at=departure.isoformat(), arrival_at=arrival.isoformat(), operator=json_text(leg.get("operator")), service=json_text(leg.get("service")), status=ServiceStatus.SCHEDULED));
            }
            option = RouteOption(id=route_id, legs=legs, source=source, price_cents=json_optional_integer(raw.get("price_cents")), currency=json_text(raw.get("currency", "USD")));
            if option.legs[0].origin.id != "ann-arbor" or option.legs[-1].destination.id != "chicago" { raise ValueError("route is outside the fixture corridor"); }
            routes.append(option);
        }
        # Validation runs even for unsupported locations so broken fixture files
        # cannot masquerade as a successful empty provider response.
        return ProviderResult(metadata=source, data=routes if supports_corridor(request) else []);
    }
}
