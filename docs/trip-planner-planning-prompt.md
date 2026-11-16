# Planning prompt: conversational trip planner in Jac

Copy the prompt below into a planning conversation with access to this repository.

---

Help me thoroughly design an AI-native, conversational trip-planning application in Jac. Work with me as a product designer and technical architect. We are planning first: do not implement the application yet.

## Vision and constraints

The app should help someone turn an incomplete travel idea into a coherent, actionable multi-day trip. Through conversation, it should understand their needs, help them explore destinations and tradeoffs, find and compare accommodation such as hotels and vacation rentals, consider flights and car rentals, organize activities, and maintain a useful itinerary as decisions change.

The experience must be intuitive. Our current chat often presents a huge block of text. Simply shortening replies will not solve the product design: decide which information belongs in conversation, which belongs in a persistent trip workspace, and which needs an interactive comparison or decision interface.

Jac is required. There is no deadline or imposed feature quota. Design the right product first; choose implementation scope and sequencing after we understand it. Distinguish the complete vision from the first coherent release, but do not shrink the vision in advance because of an assumed time limit.

## Start with the actual project

Inspect repository instructions, the current application, existing design documents, and relevant tests before drawing conclusions. Identify what is implemented, what is documented only, what is unverified, and what is missing. Cite concrete files for important findings. Inspect the running interface if available; do not claim browser observations from source inspection alone.

Useful starting points in `eecs449-team/`:

- `web/components/AtlasStudio.jac`
- `web/client/atlas_state.jac` and `web/client/atlas_flow.jac`
- `web/server/atlas.jac`, `web/server/atlas_service.py`, and `web/server/atlas_flights.py`
- `docs/atlas-design.md` and `docs/design/`
- `scripts/test-atlas-conversation.py` and `scripts/test-atlas-live-conversation.py`
- `web/jac.toml` and applicable `AGENTS.md` files

Initial source inspection suggests that Atlas primarily supports conversational route construction, maps, and browser-local journey storage. Its chat renders assistant content as a text message, and its review flow says travel search is not connected. An existing flight research module describes its output as public-web search leads rather than live inventory. Verify these observations and whether each path is actually wired into the application.

Older documents describe narrower commute-planning and travel-journal products. Treat those as historical context, not mandatory boundaries for this new vision. Preserve existing uncommitted work. Explain reuse, refactoring, or replacement based on evidence rather than assuming either a rewrite or incremental changes are best.

For Jac technical decisions, consult the installed compiler's guides, beginning with `jac guide jac-essentials`, and the relevant task guides. Check the pinned compiler and project environment. Do not assume Python or JSX syntax, or propose framework features without verifying their availability. There is no need to edit application code during planning.

## Collaborate before producing a specification

Begin with a concise understanding of the vision, the most consequential gaps in the current app, and at most three high-impact questions. Focus on unresolved product choices such as the primary traveler and trip types, geographic coverage, and how far the app should take someone from exploration to a booking handoff.

Do not ask me to repeat facts supplied above. Recommend defaults and explain the practical tradeoffs. Discuss decisions in small batches; avoid sending a giant questionnaire or a full specification before we align on the experience. Track assumptions and open questions explicitly. Challenge ideas when there is a concrete usability or feasibility problem.

As we converge, develop the following plan.

## 1. Product definition and complete user journey

Define the primary user, the job they need done, the final artifact they leave with, and what makes the experience valuable beyond an ordinary chat conversation.

Walk through a realistic trip from a vague initial request to a saved, usable plan: discovering preferences, resolving important constraints, considering travel and stays, composing days, comparing alternatives, selecting options, and revising the result. Include a user who already knows their destination and one who needs help choosing. Support multi-city and mixed flight/driving journeys where they fit the agreed product.

Separate exploration, suggestions, user selections, and confirmed bookings. The initial vision requests planning and finding options; do not silently expand that into purchasing tickets or making reservations.

## 2. Conversation and interface design

Recommend an interaction model and explain the major alternatives. Specify how conversation, the itinerary, option comparisons, and any map work together on desktop and mobile. Give each surface a clear purpose; do not let the existing map dictate the product.

Show what users actually see and do: concise assistant messages, focused clarification controls, comparable option cards, day views, editable constraints, and clear actions. Use only the components the flow needs. Describe how much is visible at once, how details expand, and how users return to earlier choices. Keep chat and direct edits synchronized, and explain how changes are communicated.

Write a realistic multi-turn example. At every important turn, show the user message, the visible assistant response, the structured interface presented, and what changes in the trip. Include a short answer to a clarification, a comparison request, and a revision such as “stay one night longer, but keep the hotel and avoid early flights.” Show a useful response if preserving all those preferences is impossible. Avoid paragraphs that merely describe the proposed UI.

Cover loading, partial results, empty results, errors, and recovery as part of the journey. The assistant should make useful progress with incomplete information and ask questions when the answer materially changes the plan, rather than requiring a complete intake form first.

## 3. AI behavior and reliable trip state

Define what the model decides and what application code guarantees. Keep natural-language interpretation and conversational reasoning model-led; use deterministic code for schemas, permissions, arithmetic, date validity, and structural consistency rather than brittle keyword parsing.

Propose a typed contract for assistant messages, proposed trip changes, clarification questions, tool requests, and supported UI components. Explain how the UI renders that contract without trusting arbitrary model-generated executable code. Choose the simplest orchestration that serves the product; justify additional agents or services only if needed.

Model the trip as persistent structured state, not just a transcript. Cover preferences, constraints, destinations, local dates and time zones, travelers, transport, accommodation nights, daily activities, alternatives, selections, budgets, and unresolved decisions as needed. Distinguish user facts, explicit assumptions, model suggestions, and externally sourced evidence.

Explain revisions, stable item references, undo, and dependency handling. If dates or travelers change, what becomes invalid, what is retained, what needs refreshing, and what does the user see? Prevent stale asynchronous results from overwriting a newer trip. Define relative-date interpretation with an explicit current-date/time-zone anchor and clarify ambiguous wording rather than guessing silently.

## 4. Travel data and integrations

For flights, hotels/vacation rentals, car rentals, places/activities, and maps/routing, identify the capabilities required and investigate realistic sources before recommending providers. Verify current documentation, access requirements, supported coverage, pricing, usage restrictions, and whether an integration can actually be obtained. Link primary sources and label anything unverified.

Distinguish destination advice, property or activity discovery, generic search links, date-specific availability, priced offers, and booking handoffs. A generic link or search snippet must not appear as a selectable verified offer. Do not invent prices, availability, opening hours, travel durations, or booking status. Clearly label estimates and explain their basis.

Define result provenance, freshness, price units, currency, taxes/fees where known, cancellation details where available, and behavior when data is missing or stale. Show how costs are aggregated without double-counting alternatives or confusing per-night, per-person, and whole-trip prices. Identify an honest fallback when a desired integration is unavailable, and explain the reduced experience.

## 5. Jac architecture and evolution of this codebase

Describe the client, Jac server, AI orchestration, provider adapters, persistence, and data flow. Specify key typed entities and internal API/tool contracts with representative payloads. Address conversation context, storage across sessions, failure recovery, and credentials staying on the server at the depth needed to make implementation decisions.

Use Jac capabilities deliberately. Investigate where its graph, walkers, and supported AI tooling help; do not force them into the design purely for appearance. Explain the role of any existing Python helpers or proposed non-Jac components.

Map the design onto this repository: what we can reuse, what needs to change, and how existing saved journeys and overlapping app flows will be handled. Record enduring architecture decisions, alternatives, and tradeoffs separately from the implementation backlog.

## 6. Validation and implementation sequence

Define observable acceptance criteria for the complete planning journey and its most important failure paths. Include genuine multi-turn semantic tests, exact relative-date expectations with an explicit anchor, preservation of constraints after edits, consistency between chat and UI, provider grounding, cost calculations, and reload/resume behavior. Separate fixture tests from live-provider validation; passing one does not prove the other.

Once the product decisions are agreed, recommend a first coherent release and subsequent increments, each delivering an end-to-end user benefit with clear dependencies and completion criteria. Base the order on user value and technical uncertainty, not an artificial deadline. Identify integration experiments that should precede commitments.

## Planning outputs and working style

Keep our discussion concise and concrete, using examples and small wireframes where helpful. Maintain a decision log. Explain what you recommend, why, what we give up, and what evidence could change the choice.

After we align, produce a cohesive product/UX specification, architecture and data contracts, integration feasibility assessment, acceptance scenarios, and implementation sequence. Keep enduring design decisions separate from delivery tasks. Clearly label agreed decisions, recommendations, assumptions, and unresolved blockers. Do not start implementation until I explicitly ask.
