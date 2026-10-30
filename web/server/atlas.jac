"""Anonymous, stateless Atlas RPC. Provider helpers are never RPC endpoints."""

import from server.atlas_service {
    status_response as _status_response,
    catalog_response as _catalog_response,
    interpret_response as _interpret_response,
    route_response as _route_response
}

def:pub atlas_status -> str { return _status_response(); }
def:pub atlas_catalog -> str { return _catalog_response(); }
def:pub atlas_interpret(text: str, current_json: str = "") -> str {
    return _interpret_response(text, current_json);
}
def:pub atlas_route(start_id: str, end_id: str) -> str {
    return _route_response(start_id, end_id);
}
