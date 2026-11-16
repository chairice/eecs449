# Trip planner: design interview decision log

Current work: read [DETOUR-AGENT-HANDOFF.md](DETOUR-AGENT-HANDOFF.md) for the November 15 revisions to branding, landing/studio navigation, pricing, approvals, trip management and weather. This document retains the earlier baseline for reference.

Status: functional understanding confirmed and UI/UX baseline adopted. These are product decisions, not implemented or validated capabilities. No application changes are authorized by this log. Updated November 14, 2026.

## Settled decisions

### Purpose and scope

- Build an AI-native conversational trip planner in Jac.
- Plan the complete experience first. There is no deadline constraint or additional course requirement beyond Jac; decide implementation scope and sequencing afterward.
- Intended geographic scope is U.S.-only. The user's examples include Arizona and Alaska.
- Support both short professional trips needing only travel/stays and detailed multi-day vacations. Do not require an activity itinerary for every trip.
- Planning depth and pacing are separate. Infer initial planning depth, confirm it conversationally, and manage it through chat. Do not add a dedicated depth selector. The user's Arizona itinerary is a reference for detailed planning, not a mandatory level for all users.

### Collaboration and visual experience

- The AI collaboratively builds complex trips, first proposing a rough route and overnight bases, then developing details with the user.
- Main vacation workspace: linked map and itinerary, with chat alongside. Simpler logistics-only trips need an appropriately simpler presentation; exact layout remains open.
- Use the map and itinerary for viewing and selection. Changes go through chat; do not introduce direct drag/reorder/time-edit controls.
- Researched flights, stays, and cars appear in a dedicated visual comparison panel linked to the map, guided by a short summary in chat. Use curated, source-branded cards with consistent verified fields and tradeoffs; users can request more options or a different comparison through chat.
- Actively guide the user through one recommended next decision while keeping the trip visible and allowing them to jump to any topic through chat. Focus the relevant workspace panel and use contextual quick replies where helpful; do not impose a rigid wizard or require the user to discover every next step themselves.
- Discuss selected places, days, and routes through the main trip chat with a clear removable context chip, such as “About: Day 5 · Bell Rock.” Do not create separate mini chat threads. The selected item is context for interpretation; any resulting edit still requires preview and approval.
- Every proposed trip edit needs preview and user approval before changing the trip, including explicitly requested edits.
- Propose connected downstream adjustments together. Preserve booked or explicitly fixed commitments and expose conflicts in the preview.
- For detailed days, show a clearly provisional schedule early with estimated/unchecked timings marked. Research opening hours, road travel times, daylight, and reservation constraints before presenting the checked version for final approval. This does not relax the stricter evidence gate for priced travel offer cards.
- One planner owns a trip and makes decisions for the whole traveling party. Multi-user collaborative planning is excluded from the agreed ownership model.

### Research and booking

- Compare real date-specific travel options inside the app; booking happens on provider sites.
- Travel-data integrations must be free or use browser/search research. Commercial partner approval is not an acceptable prerequisite. This supersedes the earlier suggestion of partner-backed inventory APIs.
- The free constraint applies to travel data. The user has Anthropic credits available for AI inference. Hosting/deployment choices and the research cost budget remain open; do not assume all infrastructure must run free or that all infrastructure spend is approved.
- Results should visibly identify their source provider, such as Airbnb, Hertz, or AAA, and link to the source.
- An offer card may appear only when exact-date availability and total price are verified. Unverified properties, generic nightly prices, and search snippets do not qualify as offer cards.
- Browser research is the normal intended flow. Try and retry meaningful research before reporting a verification problem; leave unverified items unresolved and do not invent a result. A prominent fallback interface is not a current priority. A separate external-search handoff after failure has not been explicitly settled.
- No specific provider or browser integration has been selected. Successful end-to-end free browser research remains a validation dependency.
- Once enough search inputs are available, the AI can autonomously perform read-only research within the user's request, with visible progress and a stop control. It does not need permission for each task or provider. Adding results or making other proposed trip changes still requires user approval.

### Accounts and persistence

- Users can start without signing in.
- Signing in enables saving and resuming trips across devices, preserving the work already done as a guest.
- Exact autosave, guest recovery, authentication, and persistence contracts remain to be designed.
- Approved itineraries, addresses, and imported booking details must be available for offline reading. Maps, routing, new research, and live offer checks remain online; fully offline maps/routing are outside the agreed offline scope.
- Keep approved itineraries inside the app. Read-only itinerary sharing, printable/PDF export, and calendar export are not part of the selected product scope.

### Personalization

- Ask about trip budget when it first affects a meaningful decision, allow “no fixed budget,” and distinguish hard limits from flexible targets through conversation. Do not block early exploration on an intake budget question.
- The AI learns and remembers reusable travel preferences automatically across trips, with controls to review and forget them. Saving each learned preference does not require a separate approval.
- Exact distinction between durable preferences and trip-specific observations, and how remembered preferences are applied to a new trip, remain to be designed.

### Bringing in existing plans

- Support pasted text and uploaded documents/images, including booking confirmations and existing itineraries.
- AI extraction produces a proposed trip update for review and approval, preserving supplied details and commitments.
- Email account connections are not part of the selected input scope.

## Candidate ideas, not requirements

- Free-form visual annotations beyond selecting structured places, days, and routes remain optional. Structured item context in the main chat is now an agreed requirement.

## Research findings and evidence boundaries

- Current Atlas uses browser-local journey storage, direct model HTTP calls, geographic catalog lookup, and road calculations. Its current conversation flow updates a draft before final review; this does not meet the newly agreed per-edit approval workflow.
- No connected hotel/car inventory was found. The existing flight research helper returns web-search leads and is not connected to the Atlas UI; it does not establish verified offers.
- The project pins Jac 0.37.14. A cached runtime can execute the bundled guides using the project-managed Python, although the ordinary `jac` command is not working on PATH. Framework capabilities must be distinguished from what this app currently implements.
- A synthetic lodging test for Tucson, December 26–28, 2026, two adults, did not verify exact-date availability or a total price through the available web-search tools. Full browser automation was unavailable in that experiment, so this is not evidence that a properly equipped browser agent cannot succeed.
- Partner API research revealed access gates, but those APIs are no longer the chosen integration strategy. No signup, live paid query, booking, or reservation was performed.

## Design proposal under review

The user confirmed shared understanding of the functionality and requested a dedicated pass on simple, elegant, intuitive, powerful UI/UX and visual/aesthetic requirements. The existing sketch is conceptual, not an approved visual design. Technical feasibility and deployment remain experiments or implementation decisions, not validated capabilities.

The user adopted [the interaction blueprint](trip-planner-ux-blueprint.md) as the UI/UX baseline. This includes its entry flow, clarification/approval distinction, contextual chat, research/comparison behavior, resuming work, and context-preserving Trip/Map/Chat phone navigation. Adoption confirms the design; implementation was explicitly not authorized by that confirmation.

The subsequent [implementation plan](trip-planner-implementation-plan.md) translates this baseline into dependency-ordered work packages and acceptance checks. It is a delivery plan, not evidence of completed implementation.

## Visual/UX design frontier

### Chosen direction

- The user prioritizes an intuitive interface over choosing between aesthetic/layout variants and delegates subjective styling choices to the designer. Continue the interview on consequential interaction decisions, not palette, spacing, or composition preferences. Use Quiet atlas as the designer's starting layout; this is delegated judgment, not an explicit user vote for that variant.
- Calm travel studio, with a dark theme.
- Selective photography: compact photo-led place/stay cards and larger imagery in item details. The map and itinerary remain primary.
- Multi-day trips open on a compact overview of the route, overnight bases, and days. Selecting a day opens its details and focuses the linked map; do not default to ten fully expanded daily schedules. Logistics-only trips retain a simpler travel/stays overview.
- Desktop chat is a compact persistent side pane, with a collapse control to give the trip more room when desired.
- Default map treatment is subdued and dark, with restrained background detail and emphasis on the planned route and selected stops. Satellite and strongly topographic treatments are not the chosen default.
- The user particularly likes [Olaf Dsouza's Food page](https://olafdsouza.com/food) as a visual reference.
- Live browser inspection of that page showed near-black surfaces, clean sans-serif typography, quiet dividers/borders, generous spacing, and photo-led cards. These are reference observations; the exact trip-planner typography, tokens, and imagery treatment still need design approval.
- This supersedes the earlier sketch's tentative light/warm/serif treatment. That sketch established functionality and is not the approved aesthetic.

### Designer-owned implementation refinements

These are refinements within the adopted baseline, not unresolved interview questions.

- Usability: guidance through decisions, conversational controls, first-trip clarity, visible context, and understandable proposal effects.
- Workspace hierarchy, density, focus, navigation, and progressive disclosure.
- Map, itinerary, comparison, and proposal-review composition.
- Typography, palette, spacing, surfaces, imagery, and provider identity.
- Motion, interaction feedback, responsive behavior, and accessibility.
- Concrete visual directions and detailed interaction walkthroughs before final design confirmation.

## Implementation coverage

Shared understanding of functionality and UI/UX has been confirmed. The implementation plan covers the areas below; do not restart the product interview for routine engineering or styling choices.

- Starting a trip: conversational entry for vague requests and known routes; extraction and reconciliation of existing plans/bookings through the agreed paste/upload channels.
- Preference gathering, pacing, budget constraints, and destination discovery.
- Activity discovery and schedule feasibility: travel times, operating hours, daylight, buffers, fixed reservations, and evidence.
- How candidate selections, bookings made elsewhere, and fixed commitments are represented.
- Visual states and interactions: day selection, contextual references, alternative comparisons, and approval previews.
- Research mechanics and evidence: free browser capabilities, fields required for a verified quote, freshness, failures, and cancellation.
- Guest recovery, durable account storage, and cross-device continuity within the app.
- Typed trip state, proposed changes, dependency handling, conversation context, orchestration, and Jac architecture.
- Migration of the existing application and saved journeys; acceptance criteria and implementation increments.

Application implementation remains a separate step from the adopted baseline and written implementation plan. Material changes to agreed constraints need evidence and a focused user decision; routine implementation details are designer/engineering responsibilities.
