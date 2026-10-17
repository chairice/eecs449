# Synthetic corridor route provider

`FixtureRouteProvider.search(TripRequest)` implements `RouteProvider` and returns
`ProviderResult[list[RouteOption]]`. It loads
`web/fixtures/ann-arbor-chicago.json` relative to its own module, independent of
the process's working directory. It makes no network calls.

The committed data is **entirely synthetic**. Operator names, timetables and
fares are illustrative. Every success, including an empty search, carries
`FIXTURE` provenance and a `SYNTHETIC_DATA` warning. The source's `fetched_at`
records dataset authorship, not a live observation. No real-time delays,
cancellations, weather, seats, bookings or operational guarantees are implied.

| Option | Departure / arrival (local terminal time) | Elapsed time | Price | Transfers |
| --- | --- | --- | --- | --- |
| Direct train | 17:20 Eastern / 21:40 Central | 5h 20m | $45 | 0 |
| Direct bus | 18:00 Eastern / 22:30 Central | 5h 30m | $38 | 0 |
| Train + bus | 16:30 Eastern / 21:30 Central | 6h | $42 | 1, with a 50m buffer |

## Date and request semantics

Templates repeat on the request's local calendar date, including future dates.
Each leg resolves its local clock using its terminal's IANA time zone; day
offsets support overnight legs. Summer and winter offsets are computed from
the requested date rather than copied from the authored dataset.

A departure constraint refers to Ann Arbor local time; an arrival constraint
refers to Chicago local time. Ambiguous or nonexistent request times around DST
return `INVALID_REQUEST` and require correction. The current request model has
no fold/offset selection field, so the provider never guesses one.

The provider returns **all candidates on that date**. It does not apply the
request's departure/arrival cutoff, price cap, modes, transfer buffer, ranking or
recommendation. Those belong to the planner. Thus a late-night request can
return candidates that the planner subsequently eliminates.

Supported locations are Ann Arbor (optionally MI/Michigan) to Chicago
(optionally IL/Illinois), ignoring case, commas and extra whitespace. Other
corridors and the reverse direction return a successful empty list. There is no
geocoder or automatic live-provider fallback.

## Validation and tests

The adapter validates the complete file before returning any routes. Unknown
schema fields, duplicate IDs, invalid prices/modes/times, disconnected legs,
unknown places and non-fixture provenance produce `PROVIDER_UNAVAILABLE` with
no data and a sanitized message. Invalid JSON and missing files use the same
typed failure. A valid fixture with an empty route list is a successful empty
response. Every search reloads independent objects; caller mutation cannot
change the next result.

Run `jac test tests/fixture_tests.jac -v` from `web/`. Tests cover all three
options, empty/error distinction, determinism, mutation isolation, aliases,
constraint preservation, future dates, DST, malformed data and working-directory
independence. No API keys or external services are required.
