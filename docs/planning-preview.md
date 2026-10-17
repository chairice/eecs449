# Fixture planning preview

The implemented preview is intentionally read-only: explicit trip fields go
through the server fixture provider and deterministic ranker, then the browser
renders the returned comparison. It does not create a server draft, save a
plan, buy a ticket, or call a language model or external travel service.

## Application boundary

`server.api.plan_trip(request_json: str) -> str` is an anonymous Jac RPC.
The input is the canonical `TripRequest` JSON contract, capped at 16 KiB UTF-8.
The natural-language description is not sent: until the parser is implemented,
only structured fields determine the result. Explicit JSON serialization keeps
Jac object metadata and arbitrary client fields out of the application boundary.

The returned JSON contains:

- `schema_version: 1` and `mode: "FIXTURE"`;
- the validated `request` and server-clock `as_of` timestamp;
- ordered `routes`, each with canonical evidence, risk, score, and reason codes;
- `rejected` route IDs with hard-constraint reasons;
- effective `weights` and provider `sources`;
- `error`, either null or a typed domain error.

A successful Jac transport response can contain a domain error. The client must
check `error`, not assume that HTTP 200 means feasible routes exist. Malformed
requests return `INVALID_REQUEST`; a valid unsupported corridor or infeasible
request returns `NO_ROUTES`; a missing or broken fixture returns
`PROVIDER_UNAVAILABLE`. Error messages do not reveal local fixture paths.

The provider is fixed server-side. A client cannot select a filesystem path,
override the server clock, inject route candidates, or supply risk assessments
through this endpoint. Internal dependency-injection helpers are not exposed as
RPC functions. There are no writes requiring user ownership in this preview.

## Client behavior

The composer validates before submission and preserves fields on validation or
transport failure. During a request it displays a loading status and prevents
duplicate submission. Results use server ordering; changing the selected card
only changes the inspected itinerary, not ranking or stored state. Native radio
controls provide keyboard selection. Confirmation remains disabled with an
explicit explanation that saving is not implemented.

The comparison is carried in browser navigation state, not in a shareable draft
URL or server-side store. Direct links without a preview recover to the planning
form. Editing a returned request restores its structured fields and the locally
retained description. Browser history is not a durable trip repository.

## Demo and limitations

Use the dated October 23, 2026 example to fill empty fields, then search the
Ann Arbor to Chicago corridor. All three schedules and fares are synthetic;
delay and weather remain explicitly unknown. Arbitrary fixture dates are allowed
for repeatable tests and demonstrations, including past dates. Neither the
date nor the dataset's authored timestamp implies real service availability.

The MVP still needs authenticated ownership, expiring server-side drafts,
confirmation and durable saved trips, typed natural-language parsing, and live
weather/provider adapters. See issues #13–#18 and #20–#23. This preview is a
testable step toward that workflow, not an implementation of those contracts.

## Tests

`scripts/validate.sh` runs domain, provider, scoring, composer, and API suites.
API tests exercise the actual `main.jac` registration through `JacTestClient`,
including anonymous success, malformed payloads, and inaccessible internal
helpers. Browser QA should additionally cover form errors, request loading,
three selectable results, edit-and-resubmit, unsupported corridors, direct-link
recovery, and keyboard navigation. No external credentials are needed.
