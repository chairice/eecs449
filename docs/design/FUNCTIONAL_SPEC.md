# Functional specification

## Core user story

As a ground commuter, I can describe a trip in ordinary language, compare a
few feasible routes with their risks and tradeoffs, confirm one plan, and find
that plan later.

The user must always be able to see which facts came from providers, which
preferences affected the recommendation, and whether information is live,
cached, or fixture-backed.

## Navigation model

The public landing page has a single **Plan a trip** action. Inside the app,
the persistent navigation contains **Plan**, **Trips**, and **Settings**. The
brand returns to `/`; the profile control is display-only until authentication
is implemented.

Browser back and forward navigation must work. A direct visit to a valid route
renders the same state as in-app navigation. An unknown route renders the 404
page without discarding saved trips.

## `/` — landing

Purpose: explain the one-sentence hook and build trust before asking for input.

Required content:

- “Your commute, with the uncertainty handled.”
- Three benefits: compare routes, account for disruption, remain in control.
- A short example showing an Ann Arbor to Chicago request.
- A clear statement that Detour never books or changes a trip without
  confirmation.

Behavior:

- **Plan a trip** navigates to `/plan`.
- Marketing anchors scroll to content on the same page.
- No account or API data is fetched on page load.

## `/plan` — trip composer

Purpose: collect enough information for a route search without forcing the user
to learn a form language.

Inputs:

- Natural-language request, required.
- Optional structured controls for origin, destination, departure or arrival
  time, date, maximum price, and transfer preference.
- Example prompt: “Get me from Ann Arbor to Chicago Friday after 4 PM. Keep it
  under $50 and avoid tight transfers.”

Behavior:

1. The user submits the request.
2. The client trims input and rejects an empty request locally.
3. The server parses the request into a typed `TripRequest`.
4. If one required field is missing or ambiguous, the server returns one
   specific clarification question and preserves all known fields.
5. When the request is complete, navigation continues to `/plan/results` and
   the loading state is displayed.

Validation messages appear beside the relevant field and are summarized in an
ARIA live region. User input is never cleared after an error.

## `/plan/results` — comparison and recommendation

Purpose: make the decision small, legible, and reversible.

Each route card displays:

- Provider and route or service name.
- Departure and arrival times in the trip’s local time zones.
- Total duration and number of transfers.
- Estimated price with currency, or “fare unavailable.”
- Weather, delay, or transfer risk label.
- Data source and freshness in accessible details.

Behavior:

- Up to three feasible routes are shown, sorted by deterministic score.
- The highest-ranked route is selected initially and labeled **Recommended**.
- Selecting another card updates the recommendation panel and confirmation
  target without issuing a new provider request.
- The explanation lists concrete reason codes such as “fastest direct option,”
  “lowest cost,” or “tight transfer.” It never invents unavailable facts.
- **Edit request** returns to `/plan` with all input preserved.
- **Confirm this plan** persists the selected option, then navigates to
  `/trips/:id` with a “Plan saved” status message.
- Confirmation saves a plan only. It does not buy a ticket or contact another
  service.

## `/trips` — saved plans

Purpose: provide a durable home for decisions the user already made.

- Upcoming trips are ordered by departure time ascending.
- Past trips are ordered most recent first.
- Each row shows destination, departure, selected service, risk summary, and
  last refresh time.
- Opening a row navigates to `/trips/:id`.
- An empty list explains that confirmed plans will appear here and links to
  `/plan`.

## `/trips/:id` — trip detail

Purpose: turn the chosen route into a compact trip brief.

Required sections:

- Origin, destination, date, current status, and data freshness.
- Ordered itinerary legs with stations, times, modes, and transfers.
- Current weather or disruption advisories.
- The reason this route was selected and the closest backup option.

Behavior:

- **Refresh status** requests fresh provider data when supported. The existing
  plan remains visible while the refresh runs.
- A failed refresh retains the last successful data, labels it stale, and
  offers retry.
- If the trip ID does not exist or does not belong to the current user, render
  a not-found result without revealing whether another user owns it.
- Ticket purchase, cancellation, and automatic rebooking are absent from MVP.

## `/settings` — preferences and sources

Purpose: let users influence ranking without exposing raw algorithm internals.

Preferences:

- Priority: balanced, fastest, lowest cost, fewest transfers, or most reliable.
- Maximum price, optional.
- Minimum transfer buffer, default 30 minutes.
- Avoid modes, optional.

Source status:

- Route provider name and whether results are live or fixture-backed.
- Weather provider and last successful request.
- LLM parser status without exposing prompts or secrets.

**Save preferences** validates values and persists them. Updated preferences
affect the next search; they do not silently reorder an already-confirmed trip.

## Loading state

The planning state uses three plain-language phases:

1. Understanding the request.
2. Checking routes.
3. Comparing weather and disruption risk.

The phase label may advance as work completes, but fake percentages are not
shown. If planning exceeds 10 seconds, display a message that external data is
taking longer than expected. A cancellation returns to the preserved request.

## No-routes and provider-error states

No routes is distinct from a provider failure.

| State | Message | Recovery |
| --- | --- | --- |
| No feasible routes | Explain which constraints removed candidates | Edit request or relax one suggested constraint |
| Route provider unavailable | State that live routes could not be checked | Retry or use labeled demo data in development only |
| Weather unavailable | Continue ranking with weather marked unknown | Retry weather; never treat unknown as safe |
| LLM parse failure | Show structured fields with known values | Let the user correct them manually |
| Save failure | Keep selected route and unsaved draft | Retry save |

## 404

The 404 page says “This route went off the map,” reassures the user that saved
trips are unaffected, and links to `/plan`. It does not show the authenticated
application navigation for an invalid public URL.

## Component inventory

| Component | Responsibility | Proposed Jac module |
| --- | --- | --- |
| `PublicHeader` | Marketing navigation and CTA | `web/components/PublicHeader.cl.jac` |
| `AppShell` | Brand, app navigation, user control | `web/components/AppShell.cl.jac` |
| `TripComposer` | Conversational and structured inputs | `web/components/TripComposer.cl.jac` |
| `PlanningProgress` | Honest multi-phase loading state | `web/components/PlanningProgress.cl.jac` |
| `RouteCard` | Comparable option summary and selection | `web/components/RouteCard.cl.jac` |
| `RecommendationPanel` | Reasons, advisory, and confirmation | `web/components/RecommendationPanel.cl.jac` |
| `TripList` / `TripRow` | Upcoming and past plans | `web/components/TripList.cl.jac` |
| `ItineraryTimeline` | Ordered trip legs and transfer details | `web/components/ItineraryTimeline.cl.jac` |
| `SourceStatus` | Provider mode, freshness, and errors | `web/components/SourceStatus.cl.jac` |
| `EmptyState` | Empty, no-route, and recoverable errors | `web/components/EmptyState.cl.jac` |
| `NotFoundPage` | Unknown route recovery | `web/pages/NotFoundPage.cl.jac` |

## Responsive and accessibility rules

- Desktop comparison uses two columns: route list and selected-route details.
  Below 800 px, details follow the selected card in one column.
- Navigation collapses to text buttons that remain at least 44 px tall; no
  essential control is hover-only.
- Route selection uses a native button or radio pattern with visible focus,
  `aria-pressed` or `aria-checked`, and text labels in addition to color.
- Loading and save results use `aria-live="polite"`; validation and unrecoverable
  provider errors use `role="alert"`.
- Text maintains WCAG AA contrast, motion respects `prefers-reduced-motion`,
  and every icon has either a text label or an accessible name.
- Times always include a time-zone context when origin and destination differ.

## Analytics and success measures

Do not log full free-text requests by default. Record privacy-preserving events:

- planning started, clarification required, planning succeeded or failed;
- route selected, recommendation overridden, plan confirmed;
- provider latency, stale-data rate, and failure reason.

MVP targets:

- Golden-path completion in under two minutes for a first-time user.
- At least 90% deterministic parser success on the committed request fixture
  set, counting clarifications as successful recovery.
- Repeated scoring of the same normalized input produces the same ranking.
- Every failed provider request ends in a recoverable UI state.
