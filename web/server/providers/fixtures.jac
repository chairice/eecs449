"""
Synthetic daily corridor schedules. Never a live fallback or booking source."""

import json;
import from datetime { date, datetime, timedelta, timezone }
import from pathlib { Path }
import from zoneinfo { ZoneInfo }
import from server.models {
    DomainError, ErrorCode, Place, ProviderMetadata, ProviderResult, ProviderWarning,
    RouteLeg, RouteOption, ServiceStatus, SourceStatus, TimeKind, TravelMode, TripRequest,
    check_keys, json_array, json_integer, json_object, json_optional_integer,
    json_text, metadata_from_object, parse_timestamp, path_from_array, place_from_object
}
import from server.providers.route_provider { RouteProvider }

glob FIXTURE_DIR: Path = Path(__file__).resolve().parents[2] / "fixtures";
glob DEFAULT_FIXTURE_PATH: str = str(FIXTURE_DIR / "ann-arbor-chicago.json");
# More corridors, read alongside the primary file and merged into one network.
glob EXTRA_FIXTURE_PATHS: list[str] = [str(FIXTURE_DIR / "michigan-ohio-corridors.json")];

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

"""Every fixture file merged: places by id, city names to place ids, drawn
paths by mode and direction, and the raw route templates still to expand."""
obj FixtureNetwork {
    has source: object;
    has places: dict[str, Place];
    has cities: dict[str, str];
    has paths: dict[str, list[list[float]]];
    has routes: list[dict[str, object]];
}

"""Fixture place ids at each end of the request, or None when either end is not a demo city."""
def corridor_ends(request: TripRequest, network: FixtureNetwork) -> tuple[str, str] | None {
    origin = network.cities.get(normalized_location(request.origin_text));
    destination = network.cities.get(normalized_location(request.destination_text));
    if origin is None or destination is None or origin == destination { return None; }
    return (origin, destination);
}

# An arrive-by search reaches back at most this many days before its deadline.
glob MAX_WINDOW_DAYS: int = 7;

"""Days before an arrive-by deadline still ahead of `as_of`, in the deadline's
zone, oldest first; the deadline's file_ids day is searched separately."""
def earlier_days(request: TripRequest, as_of: str, network: FixtureNetwork) -> list[str] {
    ends = corridor_ends(request, network);
    if request.time_kind != TimeKind.ARRIVE_BY or ends is None { return []; }
    zone = ZoneInfo(network.places[ends[1]].timezone);
    today = parse_timestamp(as_of).astimezone(zone).date();
    deadline = date.fromisoformat(request.local_date);
    first = max(today, deadline - timedelta(days=MAX_WINDOW_DAYS));
    return [(first + timedelta(days=offset)).isoformat() for offset in range((deadline - first).days)];
}

def on_day(request: TripRequest, day: str) -> TripRequest {
    return TripRequest(origin_text=request.origin_text, destination_text=request.destination_text, local_date=day,
        local_time=request.local_time, time_kind=request.time_kind, max_price_cents=request.max_price_cents,
        min_transfer_minutes=request.min_transfer_minutes, allowed_modes=list(request.allowed_modes), priority=request.priority);
}

def fixture_failure(code: ErrorCode, message: str) -> ProviderResult[list[RouteOption]] {
    return ProviderResult(metadata=ProviderMetadata(provider="detour-synthetic-corridor-v1", status=SourceStatus.UNAVAILABLE), error=DomainError(code=code, message=message));
}

"""One fixture file, checked for schema and provenance before anything is read from it."""
def read_fixture(path: str) -> dict[str, object] {
    payload = json_object(json.loads(Path(path).read_text(encoding="utf-8")));
    check_keys(payload, ["schema_version", "synthetic", "description", "source", "cities", "places", "routes", "paths"]);
    if json_integer(payload.get("schema_version")) != 1 or payload.get("synthetic") is not True {
        raise ValueError("only synthetic fixture schema v1 is supported");
    }
    return payload;
}

obj FixtureRouteProvider(RouteProvider) {
    has fixture_path: str = DEFAULT_FIXTURE_PATH;
    has extra_paths: list[str] = EXTRA_FIXTURE_PATHS;

    def search(request: TripRequest, as_of: str | None = None) -> ProviderResult[list[RouteOption]] {
        try {
            request.validate();
        } except (ValueError, TypeError, OverflowError) {
            return fixture_failure(ErrorCode.INVALID_REQUEST, "Choose valid trip fields and an unambiguous local departure or arrival time.");
        }
        try {
            network = self.load_network();
        } except (OSError, ValueError, TypeError, KeyError, OverflowError) {
            return fixture_failure(ErrorCode.PROVIDER_UNAVAILABLE, "The synthetic route fixture could not be loaded or validated.");
        }
        try {
            ends = corridor_ends(request, network);
            if ends is not None {
                # Departures are read in the origin's zone, arrivals in the destination's.
                anchor = ends[0] if request.time_kind == TimeKind.DEPART_AFTER else ends[1];
                _ = local_instant(request.local_date, request.local_time, network.places[anchor].timezone);
            }
        } except (ValueError, TypeError, OverflowError) {
            return fixture_failure(ErrorCode.INVALID_REQUEST, "Choose valid trip fields and an unambiguous local departure or arrival time.");
        }
        try {
            found = self.load_candidates(request, network);
            if found.data is None or as_of is None { return found; }
            # Earlier days' copies of a route keep their template id plus the day.
            routes = list(found.data);
            for day in earlier_days(request, as_of, network) {
                for route in self.load_candidates(on_day(request, day), network).data or [] {
                    route.id = route.id + "@" + day;
                    routes.append(route);
                }
            }
            return ProviderResult(metadata=found.metadata, data=routes);
        } except (OSError, ValueError, TypeError, KeyError, OverflowError) {
            return fixture_failure(ErrorCode.PROVIDER_UNAVAILABLE, "The synthetic route fixture could not be loaded or validated.");
        }
    }

    """Read the primary fixture and every extra corridor file into one network.
    A place shared between files must match exactly; a city name may name only one place."""
    def load_network -> FixtureNetwork {
        payloads = [read_fixture(self.fixture_path)] + [read_fixture(path) for path in self.extra_paths];
        raw_source = payloads[0].get("source");
        source = metadata_from_object(raw_source);
        if source.status != SourceStatus.FIXTURE { raise ValueError("fixture must declare FIXTURE provenance"); }
        places: dict[str, Place] = {};
        cities: dict[str, str] = {};
        paths: dict[str, list[list[float]]] = {};
        templates: list[dict[str, object]] = [];
        for payload in payloads {
            extra_source = metadata_from_object(payload.get("source"));
            if extra_source.status != SourceStatus.FIXTURE { raise ValueError("every fixture file must declare FIXTURE provenance"); }
            file_ids: set[str] = set();
            for item in json_array(payload.get("places")) {
                place = place_from_object(item);
                if place.id in file_ids { raise ValueError("duplicate fixture place id"); }
                file_ids.add(place.id);
                known = places.get(place.id);
                if known is not None and (known.name != place.name or known.latitude != place.latitude or known.longitude != place.longitude or known.timezone != place.timezone) {
                    raise ValueError("fixture files disagree about a shared place");
                }
                places[place.id] = place;
            }
            for item in json_array(payload.get("cities", [])) {
                raw_city = json_object(item);
                check_keys(raw_city, ["place_id", "names"]);
                place_id = json_text(raw_city.get("place_id"));
                if place_id not in file_ids { raise ValueError("fixture city must name a place in its file_ids file"); }
                for name in json_array(raw_city.get("names")) {
                    key = normalized_location(json_text(name));
                    if key == "" or cities.get(key, place_id) != place_id { raise ValueError("fixture city name is empty or ambiguous"); }
                    cities[key] = place_id;
                }
            }
            # Drawn alignments, stored once per mode and pair of places; a leg
            # running the other way gets the same points reversed.
            for item in json_array(payload.get("paths", [])) {
                raw_path = json_object(item);
                check_keys(raw_path, ["mode", "between", "points"]);
                joined = [json_text(end) for end in json_array(raw_path.get("between"))];
                if len(joined) != 2 or joined[0] not in file_ids or joined[1] not in file_ids { raise ValueError("fixture path must join two known places"); }
                mode = TravelMode(json_text(raw_path.get("mode"))).value;
                points = path_from_array(raw_path.get("points"));
                paths[mode + ":" + joined[0] + ":" + joined[1]] = points;
                paths[mode + ":" + joined[1] + ":" + joined[0]] = list(reversed(points));
            }
            for item in json_array(payload.get("routes")) {
                raw = json_object(item);
                for leg_value in json_array(raw.get("legs")) {
                    leg = json_object(leg_value);
                    if json_text(leg.get("origin_id")) not in file_ids or json_text(leg.get("destination_id")) not in file_ids {
                        raise KeyError("fixture leg names a place outside its file");
                    }
                }
                templates.append(raw);
            }
        }
        return FixtureNetwork(source=raw_source, places=places, cities=cities, paths=paths, routes=templates);
    }

    def load_candidates(request: TripRequest, network: FixtureNetwork) -> ProviderResult[list[RouteOption]] {
        # Fresh metadata per call, so the synthetic warning is added once per result.
        source = metadata_from_object(network.source);
        source.warnings.append(ProviderWarning(code="SYNTHETIC_DATA", message="Illustrative schedules and fares generated for the requested date. Not live service, availability, or booking information."));
        places = network.places;
        endpoints = set(network.cities.values());
        routes: list[RouteOption] = [];
        seen: set[str] = set();
        for raw in network.routes {
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
                mode = TravelMode(json_text(leg.get("mode")));
                path = network.paths.get(mode.value + ":" + origin.id + ":" + destination.id, []);
                legs.append(RouteLeg(id=json_text(leg.get("id")), mode=mode, origin=origin, destination=destination, departure_at=departure.isoformat(), arrival_at=arrival.isoformat(), operator=json_text(leg.get("operator")), service=json_text(leg.get("service")), status=ServiceStatus.SCHEDULED, path=path));
            }
            option = RouteOption(id=route_id, legs=legs, source=source, price_cents=json_optional_integer(raw.get("price_cents")), currency=json_text(raw.get("currency", "USD")));
            if option.legs[0].origin.id not in endpoints or option.legs[-1].destination.id not in endpoints { raise ValueError("route must run between two demo cities"); }
            routes.append(option);
        }

        # Validation runs even for unsupported locations so broken fixture files
        # cannot masquerade as a successful empty provider response.
        ends = corridor_ends(request, network);
        if ends is None { return ProviderResult(metadata=source, data=[]); }
        return ProviderResult(metadata=source, data=[route for route in routes if route.legs[0].origin.id == ends[0] and route.legs[-1].destination.id == ends[1]]);
    }
}
