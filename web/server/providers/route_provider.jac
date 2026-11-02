"""
Route providers return normalized candidates; the planner applies constraints."""

import from server.models { ProviderResult, RouteOption, TripRequest }

obj RouteProvider {
    """`as_of` is when the search is made; an arrive-by search may then return
    candidates on every day from it to the deadline."""
    def search(request: TripRequest, as_of: str | None = None) -> ProviderResult[list[RouteOption]] {
        _ = (request, as_of);
        raise NotImplementedError("RouteProvider.search requires an adapter");
    }
}
