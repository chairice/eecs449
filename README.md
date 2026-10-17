# Detour: an AI copilot for ground commuting

> **Working product name.** Detour is the current design direction for the
> EECS 449 team project; the name can change without changing the product
> contract below.

For a lot of cross-state commuters, there are a lot of tasks that go into making sure they reach their destinations: buying tickets, sorting through confirmation emails, scheduling around conflicts and delays, keeping track of tickets, checking the weather. None of them are hard. Together they take up a lot of time and attention.

This project builds a conversational AI agent that takes over some of that
work. A commuter describes the trip they need in plain language, compares a
small set of feasible routes, sees weather and disruption risks, and confirms
one plan. Detour keeps the confirmed plan in one place without booking or
changing anything behind the user's back.

## Product design

The first implementation target is one narrow, complete path:

**Describe a trip -> compare options -> understand the recommendation ->
confirm -> view the saved trip.**

The complete behavior, component boundaries, data contracts, external API
choices, ranking algorithm, failure states, and architectural decisions are in
the [design plan](docs/design/README.md). The interactive reference can be
opened locally from [`docs/design/prototype.html`](docs/design/prototype.html).

### Screen designs

All screens use the same responsive shell and visual system. These images are
design targets, not claims that the corresponding functionality is already
implemented.

#### 1. Landing page

![Detour marketing landing page](docs/design/screens/01-landing.jpg)

#### 2. Plan a trip

![Conversational trip planning form](docs/design/screens/02-plan.jpg)

#### 3. Compare routes and confirm

![Route comparison and recommendation view](docs/design/screens/03-results.jpg)

#### 4. Saved trips

![Upcoming and previous trips list](docs/design/screens/04-trips.jpg)

#### 5. Trip detail

![Confirmed trip detail and status view](docs/design/screens/05-trip-detail.jpg)

#### 6. Settings

![Routing preferences and data source settings](docs/design/screens/06-settings.jpg)

#### 7. Planning/loading state

![Route search loading state](docs/design/screens/07-loading.jpg)

#### 8. No feasible routes

![No routes recovery state](docs/design/screens/08-no-routes.jpg)

#### 9. Not found

![Detour 404 page](docs/design/screens/09-404.jpg)

## Product principles

1. **Conversation for intent, code for decisions.** The LLM converts plain
   language into a typed trip request. Deterministic code validates, scores,
   and ranks routes so recommendations are reproducible.
2. **Make tradeoffs legible.** Every recommendation identifies the concrete
   reasons it won: time, cost, transfers, reliability, and weather exposure.
3. **Keep the user in control.** Nothing is booked, messaged, or added to an
   external service without an explicit confirmation.
4. **Design for incomplete data.** Missing real-time data means “unknown,” not
   “on time.” The interface exposes freshness and confidence.
5. **Ship a complete vertical slice first.** The MVP uses deterministic route
   fixtures where necessary, then swaps in live providers behind stable
   interfaces.

## MVP use case

A student asks: “Get me from Ann Arbor to Chicago Friday after 4 PM. Keep it
under $50 and avoid tight transfers.” Detour returns up to three ground-transit
options, incorporates forecast and disruption information, explains its
recommendation, and saves the selected plan after confirmation.

The MVP does **not** purchase tickets, connect email or calendars, continuously
monitor trips, or promise nationwide coverage. Those are later capabilities
once the planning loop is reliable.

## Status

The repository implements a read-only, fixture-backed planning preview:
accessible structured input, a validated server endpoint, three synthetic
Ann Arbor–Chicago routes, deterministic feasibility/scoring, and selectable
route comparisons with explicit provenance and unknown conditions. See the
[preview contract and limitations](docs/planning-preview.md),
[domain contracts](docs/domain-model.md), [fixture adapter](docs/fixture-provider.md),
and [scoring rules](docs/scoring.md).

Authentication, expiring server drafts, confirmed saved trips, natural-language
parsing, and live weather/transit integrations remain planned work. The Trips
and Settings pages are honest placeholders; confirmation is disabled. See the
[architecture decisions](docs/design/ARCHITECTURE_DECISIONS.md) for the system
boundaries, algorithms, API choices, data lifecycle, and design tradeoffs.

## Development

Use **Jac 0.37.14** (standalone compiler); the JavaScript tooling baseline is
**Node 22.11.0** in `.nvmrc`. Follow [web setup](web/README.md) to install and
run the application. From the repository root, run the same checks as CI:

```bash
bash scripts/validate.sh
```

This checks every Jac source, runs all Jac regression suites, builds the full
application from current sources, and tests the emitted comparison adapter.

## Course

This project is being developed for EECS 449 (Conversational AI) at the University of Michigan.
