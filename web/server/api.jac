"""
Stateless fixture planning RPC. This endpoint never creates or saves a draft.

Input is the explicit TripRequest JSON contract, limited to 16 KiB UTF-8.
Output is JSON with schema_version, mode, request, as_of, routes, rejected,
weights, sources, and error. All provider candidates survive until ranking;
the response returns every feasible ranked option. Fixture dates may be past
or future because these are synthetic examples, never bookable schedules.
"""

import json;
import from datetime { datetime, timezone }
import from server.models {
    DomainError, ErrorCode,
    model_to_object as _model_to_object,
    trip_request_from_json as _trip_request_from_json
}
import from server.planner { rank_routes as _rank_routes }
import from server.providers.fixtures { FixtureRouteProvider }
import from server.providers.route_provider { RouteProvider }

glob MAX_REQUEST_BYTES: int = 16384;

"""The single anonymous endpoint only reads committed synthetic fixture data."""
def:pub plan_trip(request_json: str) -> str {
    return _plan_response(request_json, FixtureRouteProvider(), datetime.now(timezone.utc).isoformat());
}

"""Injected dependencies keep boundary tests deterministic without exposing knobs over RPC."""
def _plan_response(request_json: str, provider: RouteProvider, as_of: str) -> str {
    body: dict[str, object] = {
        "schema_version": 1, "mode": "FIXTURE", "request": None,
        "as_of": as_of, "routes": [], "rejected": [], "weights": None,
        "sources": [], "error": None
    };
    try {
        if not isinstance(request_json, str) or len(request_json.encode("utf-8")) > MAX_REQUEST_BYTES {
            raise ValueError("invalid request payload");
        }
        request = _trip_request_from_json(request_json);
    } except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError) {
        return _failed_response(body, DomainError(ErrorCode.INVALID_REQUEST, "Provide a valid structured trip request of at most 16 KiB."));
    }
    body["request"] = _model_to_object(request);
    provided = provider.search(request);
    body["sources"] = [_model_to_object(provided.metadata)];
    if provided.error is not None {
        return _failed_response(body, provided.error);
    }
    if provided.data is None {
        return _failed_response(body, DomainError(ErrorCode.PROVIDER_UNAVAILABLE, "The synthetic route provider did not return candidates."));
    }
    ranked = _rank_routes(request, provided.data, as_of);
    body["weights"] = _model_to_object(ranked.weights);
    body["rejected"] = [{"route_id": item.route_id, "reasons": list(item.reasons)} for item in ranked.rejected];
    if ranked.error is not None {
        error = ranked.error;
        if error.code == ErrorCode.INVALID_REQUEST {
            error = DomainError(ErrorCode.INVALID_REQUEST, "Choose valid trip fields and an unambiguous local departure or arrival time.");
        }
        return _failed_response(body, error);
    }
    body["routes"] = _model_to_object(ranked.routes);
    return json.dumps(body, allow_nan=False, sort_keys=True);
}

def _failed_response(body: dict[str, object], error: DomainError) -> str {
    body["error"] = _model_to_object(error);
    return json.dumps(body, allow_nan=False, sort_keys=True);
}