# Detour weather integration reference

> **Historical trace — November 15, 2026:** The read-only findings below describe the previous weather flow before the new studio integration. Independent NWS forecasts/alerts are now implemented in the studio, including bounded stale data, official-warning retention during forecast outages and quiet long-range availability. See [current implementation and real-source evidence](trip-planner-implementation-status.md#current-detour-implementation). The original “pending” wording below is retained as historical provenance.

Read this when implementing the weather work package in [the agent handoff](DETOUR-AGENT-HANDOFF.md). A user-requested subagent completed this read-only review on November 15, 2026. The findings describe the previous app; integration into the new studio is pending. The review did not edit application files or claim new test execution.

## Reuse the existing real NWS source

The previous provider calls `https://api.weather.gov` without an API key, with an identifying User-Agent and optional `DETOUR_NWS_CONTACT`:

- `/points/{lat,lon}` resolves `properties.forecastHourly`.
- The returned hourly endpoint supplies time-bounded forecast periods.
- `/alerts/active?point={lat,lon}` supplies official active alerts.

The current [official API documentation](https://www.weather.gov/documentation/services-web-api) confirms free access and approximately seven-day forecast/hourly coverage. The old app deliberately uses a more conservative 150-hour cutoff. Keep that distinction: the application's cutoff is not the provider's maximum forecast horizon.

Relevant implementation:

| Source | What to read |
| --- | --- |
| `web/server/providers/weather.jac:25` | Headers, endpoint discovery and source configuration |
| `web/server/providers/weather.jac:53` | Route/time sampling |
| `web/server/providers/weather.jac:142` | Fetching and caches |
| `web/server/providers/weather.jac:194` | Horizon handling and forecast-availability date |
| `web/server/providers/weather.jac:213` | Top-level availability check |
| `web/server/providers/weather.jac:245` | Per-sample forecast/alert extraction |
| `web/server/weather_rules.jac:12` | Pure severity rules |
| `web/server/models.jac:226` | Existing WeatherEvidence model |
| `web/server/api.jac:98` | Saved-trip refresh endpoint and bounds |
| `web/components/RouteComparison.jac:60` | Compact risk/condition presentation |
| `web/components/comparison_view.jac:123` | Location/time wording |
| `web/pages/trips/[id].jac:49` | Refresh when reopening a trip |
| `web/tests/weather_tests.jac:60` | Existing recorded-fixture coverage |

## Actual previous behavior

The provider rounds coordinates to four decimals and samples each non-walking vehicle leg at departure, arrival and approximately hourly along the path. Intermediate samples currently select uniform path-vertex indices, inherit the origin's timezone, and may fall back to a straight line.

Caching: grid lookup 24 hours, hourly forecast 15 minutes, alerts 5 minutes. Fetching uses at most eight threads, four-second individual timeouts and an eight-second overall response budget. It has no explicit requests-per-second limiter or retry/backoff policy beyond concurrency/caching. Some threads may finish after the caller's overall budget expires.

The current rules are:

| Severity | Trigger |
| --- | --- |
| High | Severe/extreme alert or an event ending in Warning |
| Moderate | Moderate alert, Watch/Advisory, sustained wind at least 56 km/h, or at least 50% precipitation probability with snow/ice/freezing/thunderstorm terms |
| Low | Forecast and alerts were both read and no listed hazard was found |
| Unknown | Relevant forecast/alert evidence could not be read |

The route keeps its most significant known hazard. Missing data does not become Low. Known Moderate/High conditions still matter when another portion lies beyond forecast coverage. Ordinary rain alone does not trigger Moderate under the old commuter rules.

Old evidence includes conditions, precipitation probability, wind, alert names, location, valid time window and checked time. It lacks temperature and complete official alert headlines, instructions and source URLs. Extend the model before promising those details.

Old UI patterns worth retaining: a compact condition/risk indicator; an expanded explanation identifying place and local time; retained evidence when a saved trip reopens; fresh weather when available; and a quiet forecast-availability message for distant trips. Weather does not block route planning.

The old public refresh endpoint allows at most six legs, each no longer than 24 hours. Its TRAIN/BUS/WALK-oriented DTO is not a suitable direct contract for a complete multi-day vacation or flights.

## Defect that must not be copied

A successfully fetched official alert can be discarded when the hourly forecast fails. The top-level `read_any` check requires forecast periods (`weather.jac:213–217`), and `sample_evidence` returns unread when periods are absent (`245–247`).

Fetch and retain forecasts and alerts independently. An actual Winter Storm Warning must remain visible even if the hourly endpoint is unavailable. Add this regression before adapting the old provider.

## New-studio integration plan

1. Implement a worker-side adapter using the same real NWS sources, source-domain validation and bounded caches. Preserve official event times, geography and alert instructions. Fetching weather must not hold a graph-write transaction open or block the chat interface.
2. Construct samples from the new trip model:
   - Driving: use sourced OSRM geometry where available; sample by cumulative distance/time rather than vertex index. Resolve local times per location.
   - Flights: departure-airport weather at departure and arrival-airport weather at arrival. Do not invent airborne route weather or infer airline delays/cancellations from ground conditions alone.
   - Bases/activities: use the relevant local day or supplied activity time. When times are open, summarize the day rather than inventing precise event times.
3. Carry weather as auxiliary sourced state alongside routes/daylight. Current integration seams are `workers/atlas_runtime/planner.py` tool definitions/dispatch/final resources, `web/server/planning_api.py` request context/resource merge/import, and the studio's selected day/leg/detail views.
4. Refresh on trip opening and meaningful time/location changes. Bind results to weather-relevant trip inputs so delayed work cannot overwrite a newer itinerary's weather. Weather refresh alone should not count as an itinerary edit or require user confirmation.
5. Expose small day/leg weather summaries and expandable details: actual temperature if retrieved, precipitation/wind, official warning headline, affected place/time, source and checked time. Supply the same sourced facts to the agent for conversational recommendations. Keep the left pane restrained.
6. Use actual returned coverage to determine what is forecastable. For distant trips, show a calm normal state such as weather being checked closer to departure. Background failures should not dominate the UI or erase retained official warnings. Preserve the distinction between no data and benign conditions internally.

## Required tests

Reuse the existing recorded NWS fixture/rule tests where their contracts still apply. Add coverage for:

- Alert retained independently of forecast success.
- Expired/non-overlapping alerts excluded; present-day alerts not attached to an unrelated future trip.
- Arizona/Alaska, DST, cross-timezone driving and local-day boundaries.
- Multi-day plans beyond the old six-leg limit.
- Flight endpoint-only weather and absence of invented flight disruption claims.
- Partial coverage and future dates without fabricated conditions.
- Stale refresh rejection after dates/places change.
- Guest→account preservation of legitimate weather resources.
- TTL/budget behavior, source URL validation and background refresh/cancellation.
- Browser verification that concise warnings and full alert details fit the new laptop/phone inspector.

Record actual live NWS retrieval separately from fixture success. These tests must validate real-source handling; synthetic test fixtures are never a runtime weather fallback.
