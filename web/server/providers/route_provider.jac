"""
Route providers return normalized candidates; the planner applies constraints."""

import from server.models { ProviderResult, RouteOption, TripRequest }

obj RouteProvider {
    def search(request: TripRequest) -> ProviderResult[list[RouteOption]] {
        _ = request;
        raise NotImplementedError("RouteProvider.search requires an adapter");
    }
}
