# Atlas: travel history as the foundation for trip planning

## Agreed product boundary

Atlas is a separate, conversation-first workspace for visualizing past and
planned US journeys. It does not book, research tickets/hotels, or forward
unsupported flight/driving itineraries to the existing fixture transit planner.
Its versioned, structured journeys are the future planning agent's input—not
merely painted map lines.

## Design tree

- **Canvas:** warm minimalist atlas, bundled US geographic outlines, Leaflet
  pan/zoom, lower-48 initial view, Alaska/Hawaii available, explicit Reset and
  Fit journey. Selecting or editing does not move the camera.
- **Journey:** title, note, explicit Past/Planned status, ordered resolved or
  unresolved stops, per-leg Flight/Driving mode, optional local dates/times,
  preserved vague timing. Dates never automatically complete journeys.
- **Creation:** conversation-first when the server LLM is configured; editable
  proposal and explicit save. Manual lookup and honestly labeled limited
  rules remain usable without credentials. Never silently drop unknown places,
  modes, dates, or legs. Geographic coordinates come from the catalog, not AI.
- **Geography:** local GeoNames populated places and OurAirports US airports.
  Cities remain cities, not arbitrarily assigned airports. Flights use
  illustrative arcs; driving uses calculated OSRM geometry, not an asserted
  historical trace. US-only road routing; no cross-border support.
- **Storage:** separate versioned browser-local journal records and recovery
  drafts, explicit save, idempotent updates, recoverable Trash. Report storage
  failures and retain in-memory edits. No account or cross-device guarantees.
- **Presentation:** cumulative journeys, Past/Planned and Flight/Driving
  filters, muted unselected journeys, solid past/dashed planned lines. Desktop
  panel/mobile sheet; presentation hides controls but retains attribution,
  legend, pan/zoom, and an exit control. No export or public sharing.

## Architecture and decisions

The Jac page and components own interaction state. Pure client helpers own
validation, local lookup, draft editing and versioned serialization. Read-only
Jac RPC endpoints serve bundled geographic data, interpret one explicit
request, and calculate a driving leg. Provider payloads are normalized at the
server boundary. No atlas request mutates existing transit-trip records.

The server holds the optional LLM credential. An explicit AI request can
include the current proposed itinerary to support follow-up edits; unrelated
saved journeys and their notes are never included. The model proposes fields,
not routes or coordinates. Model errors must be visible rather than silently
masquerading as successful AI interpretation.

Public OSRM is a small-demo dependency, not an unlimited production backend.
The adapter limits request frequency, caches results, bounds requests and
responses, and allows an operator-configured endpoint for later self-hosting.
Only catalog-resolved coordinates are sent; client URLs are not accepted.
There is no commercial fallback. Attribution and the public service's route
request logging are disclosed in the workspace and data documentation.

Routing failure leaves stops and successful legs intact. Unrouted driving legs
have no invented line, can be saved with an explicit warning, and can be retried.
Coordinate data and calculated geometry remain separate from a user's intended
dates, modes and status, so later planning can refresh evidence without changing
the intended itinerary.

## Acceptance checks

1. Create and refine a mixed-mode multi-leg journey, then explicitly save it.
2. Resolve ambiguous locations; preserve unknown details and the original text.
3. Edit/reorder stops and modes without reusing stale driving geometry.
4. Reload a saved journey and recover an unsaved draft; trash and restore safely.
5. Filter journeys and enter/exit presentation without moving the camera.
6. Handle missing AI, routing outages, malformed storage and storage quota errors.
7. Complete the basic flow on desktop and phone with keyboard-accessible controls.
8. Preserve existing Plan/Trips behavior and run the full Jac/client test suite.

The earlier travel editor is visual/interaction reference only: its original
source checkout was not available during this implementation.
