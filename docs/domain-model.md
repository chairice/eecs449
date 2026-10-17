# Canonical domain contract

`web/server/models.jac` implements the types in ADR-001 and the typed failure
boundary in ADR-009. It contains no HTTP calls, planner, persistence, or public
endpoints. Models validate at construction. The explicit JSON encoder validates
again, including nested objects, because Jac objects remain mutable.

## Units and time

- Prices are nonnegative integer **USD cents**. `None` means unknown; `0` means
  free. The first MVP rejects other currencies. Booleans are not valid numbers.
- Delays and transfer buffers are nonnegative integer minutes. Route duration
  is derived from the first departure and last arrival and may include fractional
  minutes. Transfers count changes between transit legs, excluding walk legs.
- Provider, itinerary, draft and plan timestamps use ISO 8601 with an explicit
  UTC offset or `Z`. Elapsed durations compare actual instants across time zones
  and DST changes. Place time zones are valid IANA identifiers.
- A request retains `YYYY-MM-DD`, `HH:MM` and `DEPART_AFTER`/`ARRIVE_BY` as local
  user intent. The future resolver must use the origin zone for departure and
  destination zone for arrival, and clarify nonexistent or ambiguous local times.
  The model itself does not guess a zone from a place phrase.
- Precipitation probability, utilities, weights and uncertainty are finite values
  in `[0, 1]`. Wind speed is nonnegative kilometers per hour. The defined ranking
  formula permits scores from `-10` through `100`; this module does not rank.

## Data and error boundaries

`TripIntent` permits incomplete fields while validating fields that are present.
`TripRequest` requires complete locations and time semantics. Allowed request
modes are train and bus; walking is an itinerary connector.

`RouteOption` has ordered, chronologically connected `RouteLeg` objects with
unique leg IDs, optional price, and required `ProviderMetadata`. Duration and
transfer count are derived methods, not duplicated fields that can drift.
`ServiceStatus.UNKNOWN` is the default; missing real-time data is not on-time
evidence. A known schedule can explicitly use `SCHEDULED`.

`ProviderResult[T]` contains `metadata`, `data`, and `error`. Available sources
must include a fetch timestamp and data (an empty list is a successful empty
search). `UNAVAILABLE` requires a typed error and no data. Expiration is optional
but cannot precede fetch. Warnings preserve partial/stale-data context. Weather
with an unavailable source cannot assert known conditions.

Drafts retain typed requests, scored routes, effective weights, recommendation,
source metadata and lifetime. Weights sum to one, IDs are unique and the
recommendation references an existing option. Plans require a nonempty owner
and a distinct optional backup. Ownership authorization belongs to the future
repository service; a nonempty owner ID alone does not authorize access.

## Serialization

`model_to_json` exports the named domain objects through an explicit field
allowlist. It emits enum strings, JSON nulls and nested ordinary objects, without
Jac runtime metadata. `provider_result_to_json` handles generic envelopes.
`trip_request_from_json` and `route_option_from_json` validate incoming plain JSON
and reconstruct typed nested objects. They reject unknown keys, missing required
fields, wrong types, invalid enums and inconsistent values. This JSON format is
for fixtures and explicit API boundaries; Jac's generated typed bridge may add
its own transport metadata and must be exercised when endpoints are introduced.

Run `jac check server/models.jac`, `jac check tests/domain_tests.jac`, and
`jac test tests/domain_tests.jac -v` from `web/`. Tests cover JSON roundtrips,
timezone and DST elapsed time, malformed requests, unknown versus free fares,
route continuity, provider failure, impossible/nonfinite values and draft/plan
invariants. No credentials or network services are required.
