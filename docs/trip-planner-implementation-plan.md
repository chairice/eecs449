# Trip planner: implementation plan

Current work: read [DETOUR-AGENT-HANDOFF.md](DETOUR-AGENT-HANDOFF.md) for the November 15 revisions to branding, landing/studio navigation, pricing, approvals, trip management and weather. This document retains the earlier baseline for reference.

Prepared November 14, 2026. Status: implementation plan only; application implementation has not started under this request.

The [decision log](trip-planner-decisions.md), [product/architecture design](trip-planner-design.md), and adopted [UX blueprint](trip-planner-ux-blueprint.md) define the product. [Visual design notes](trip-planner-visual-design.md) support those requirements. This document defines delivery order, code ownership, dependencies, and completion evidence rather than reopening the design.

## Delivery strategy

Build working user flows in small, reviewable increments. Validate free browser research immediately, while building the state/approval foundation independently. Do not spend the whole first phase reskinning the route journal or build every backend subsystem before any real interaction works.

The first usable checkpoint is a real conversation that creates a route/overnight proposal, shows it on the target workspace, applies it only after approval, and supports a contextual revision. The first complete travel-research checkpoint adds one genuinely verified source → comparison → selection → approval → external booking handoff. Then extend the same pipeline across flights, hotels, vacation rentals, and cars.

There is no imposed deadline. The stages below express dependencies and completion criteria, not a time budget. Every agreed capability stays in the full plan; early checkpoints are not a reduction of the product vision.

### Non-negotiable implementation boundaries

- Jac owns the application, account/trip state, domain operations, and UI. A narrow Python worker/adapter can run the Anthropic SDK and browser libraries.
- Natural-language interpretation stays model-led. Deterministic checks handle schemas, identity, dates, arithmetic, references, and structural constraints.
- Accepted trip state, user-supplied working context, pending proposals, and research evidence remain separate.
- A clarification reply can supply search/proposal context without an approval dialog. Changes to the accepted trip still need coherent preview and approval.
- Search/research is autonomous within the request. Results cannot silently modify the accepted itinerary.
- An offer card requires exact-date/party availability and a verified total, with evidence and a usable source link. No invented offers or generic search leads presented as inventory.
- Travel-data access is free. Anthropic credits can fund model/tool use; browser execution, storage, and hosting require their own operational decision.
- Trip changes go through chat, including contextual quick replies. Viewing, selecting, collapsing panels, and clearing request context do not mutate the trip.
- No ticket purchases, email integrations, multi-user coediting, itinerary sharing/export, or fully offline maps are introduced.

## Current code: reuse and gaps

| Current artifact | Reuse | Required change |
| --- | --- | --- |
| [AtlasStudio.jac](../web/components/AtlasStudio.jac) | Existing integration points and journey interaction lessons | Its response currently changes the editable draft immediately, and its chat renders text blocks. Replace this flow with typed proposals, a compact conversation, and focused workspace components |
| [atlas_state.jac](../web/client/atlas_state.jac) | Catalog lookup, recovery/error handling patterns, legacy serialization knowledge | Replace the flat browser-local journal as the canonical new model; preserve legacy records and add explicit reviewed import |
| [AtlasMap.jac](../web/components/AtlasMap.jac) | Leaflet integration, regions, bounds, overlays, selection behavior | It is tile-free and renders state outlines. Add a validated free path to detailed dark basemap/places and day-level route overlays |
| [atlas_service.py](../web/server/atlas_service.py) | Catalog resolution and bounded road-provider utilities | Its 4,000-character input, 24-stop route schema, and last-12-turn context are not a multi-day planning model. Long itinerary import and activity/day hierarchy need new contracts |
| [atlas_flights.py](../web/server/atlas_flights.py) | Prior source-link research lessons | It returns unverified search leads and is not connected to the Atlas UI. It does not satisfy the offer gate |
| [account.jac](../web/client/account.jac) | Runtime signup/login/logout | Add real owner-authorized trip persistence and guest-to-account transfer; email-keyed local storage is not server ownership |
| [main.jac](../web/main.jac) | Entry-point and routing conventions | Explicitly expose new RPCs and route the new workspace; verify live registration rather than defining unused functions |
| [render.yaml](../render.yaml), [render-start.sh](../scripts/render-start.sh) | Existing build/serve entry points | The current deployment assumes browser-local trip data and disposable embedded storage. Persistent accounts/trips/uploads and browser execution need a validated deployment topology |
| [validate.sh](../scripts/validate.sh), [CI](../.github/workflows/validate.yml) | Pinned compiler checks, Jac suites, build, emitted-client tests | Register all new client/worker/contract tests. The explicit Node test list currently omits the newer Atlas flow test |

The checkout already contains tracked and untracked Atlas work. Preserve it. Classify the current diff before editing, and avoid a wholesale reset, blind migration, or commit of unrelated work. Historical prototype/test results are not a current baseline.

## Work packages and dependency order

Each package should be one focused PR or a small sequence of reviewable PRs. These are proposed work items, not published GitHub issues.

| ID | Deliverable | Depends on | Completion checkpoint |
| --- | --- | --- | --- |
| T00 | Reproducible toolchain and measured baseline | — | Clean installation can check, test, build, and serve the current app; pre-existing failures are recorded |
| T01 | Free research, location, and dark-map capability experiments | T00 | Captured evidence establishes which sources/tools work and the resources they need |
| T02 | Trip contracts and atomic proposal application | T00 | Preview/reject/apply/stale/duplicate/cross-owner cases work against the actual state boundary |
| T03 | Durable jobs and model/browser tool runtime | T01, T02 | Jobs survive interruption and return typed proposals/evidence without editing accepted trips |
| T04 | First real conversational planning flow | T02, T03 | New request → useful proposal → approval → contextual revision works end to end |
| T05 | Complete desktop workspace and contextual chat | T04 | Overview/day/place/map/review stay synchronized and guide one next decision |
| T06 | Account continuity, trip list, guest import, save recovery | T02, T04 | Guest work moves once into an account and resumes on another device |
| T07 | First live offer-comparison flow | T01, T03, T05 | One proven category/source completes research → verified card → selected proposal → external handoff |
| T08 | Complete transport/accommodation coverage | T07 | Flights, hotels, vacation rentals, and cars each pass the same quote and handoff gate |
| T09 | Uploaded plans/confirmations and legacy import | T03, T05, T06 | Pasted/uploaded/legacy information becomes a reviewed, traceable proposal without losing supplied details |
| T10 | Detailed daily planning and feasibility checks | T03, T05 | Timed days are checked, fixed commitments retained, and connected revisions explained |
| T11 | Automatic preference learning with review/forget | T03, T06 | Personalization transfers appropriately between trips and can be removed |
| T12 | Phone workspace and offline approved plans | T05, T06 | Trip/Map/Chat preserve context; saved details work offline without live-data claims |
| T13 | Durable deployment, full-flow validation, and navigation cutover | T05–T12 | All agreed flows work on the actual deployed topology, with explicit coverage and evidence |

T01 and T02 can progress independently after T00. After T05, account continuity, live comparisons, and schedule composition can proceed independently where their dependencies permit. This is dependency planning, not a requirement to use multiple implementation agents.

## T00 — Establish a reproducible baseline

1. Inspect the current diff and identify reusable work without discarding it.
2. Repair the portable Jac launch/install path and confirm **0.37.14**, as pinned in [web/jac.toml](../web/jac.toml). The working cached-runtime command found during planning is a local diagnostic, not a path to hardcode in project scripts.
3. Consult `jac guide jac-essentials`, `jac-core-cheatsheet`, `jac-types`, and the task-specific endpoint/auth/persistence/concurrency guides before editing Jac.
4. Run the existing validation script and browser smoke flow. Record baseline failures separately from new regressions.
5. Confirm configuration presence without printing credential values. Keep the existing app runnable while the new flow is developed behind an isolated route or feature switch.

**Exit:** another checkout can reproduce the toolchain and baseline. A type check, HTTP 200, or old passing test count is not reported as proof of the new planning experience.

## T01 — Prove the uncertain external capabilities

### Browser and quote experiment

Create a small standalone, non-booking experiment using an application-owned Chromium browser and an Anthropic-compatible tool loop. Check account/model/tool compatibility and pin the working SDK/browser dependencies. Do not assume the existing route interpreter's model supports every browser feature.

Primary path: the documented Anthropic browser toolset plus a minimal application-owned driver. Its SDK support is beta and the supplied example driver is not production code. Keep the integration behind an adapter; if necessary, implement a small standard tool interface over the same browser operations. Do not depend on a fictional provider from a documentation example or a paid hosted-browser service. [Browser tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-tool), [SDK and drivers](https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-sdk)

Use explicit synthetic test party/age inputs and future travel dates, not assumptions about the user's actual party. Test one source per category, then alternatives where necessary:

- Flight: exact segments, dates, passengers, fare inputs, available itinerary, all-in selected price, handoff.
- Hotel: dates, room/party composition, available room/rate, compulsory-charge total, handoff.
- Vacation rental: dates, guests, available unit, total stay cost, handoff. A hotel result does not prove rental coverage.
- Car: pickup/drop-off place and local time, driver/rate eligibility, available product/class, compulsory-charge total, handoff.

For each run capture the query, visible applied search state, product/quote state, URL, observation time, field evidence, handoff behavior, tool steps, latency, and model/resource consumption. Repeat from a clean session, then alter dates/party to expose stale state. Include Alaska/Hawaii in the supported-coverage tests rather than extrapolating from mainland success.

A source passes only after a real successful quote and handoff are observed. A snippet, date-bearing URL, inaccessible page, or empty result does not establish that capability. Also test a genuine no-availability/error case so the gate fails honestly. Public browsing is the initial source-access scope; adding consumer-account linking is not implicit.

### Places, map, and routing experiment

- Resolve actual activity/attraction/airport/hotel locations through data. The populated-place catalog cannot locate every trail or hotel, and the model must not supply invented coordinates.
- Prove a free detailed dark-map source at overview and local/day zoom, including attribution and usable deployment access. Retain Leaflet unless the successful map source justifies another renderer.
- Exercise calculated road geometry and duration with the existing adapter's limits. Keep estimated routing distinct from traffic-aware travel time.
- Check Alaska/Hawaii regions and unsupported water/cross-border road cases explicitly. Do not draw a straight connection and label it a verified road route.
- Establish how genuine provider/place photos can be displayed with provenance. Missing optional photos may have a neutral fallback; illustrative study images must not appear as actual researched properties.

**Exit:** a written capability matrix identifies successful sources, unsupported fields/routes, selected runtime approach, measurable costs/latencies, and the next concrete experiment for unresolved categories. Choose job resource ceilings and deployment recommendations from measurements.

**Gate:** only proven category/source paths can publish live cards. Unresolved supplier experiments do not prevent building the domain/UI, but they prevent claiming complete live-offer coverage. If experiments require a change to the agreed evidence standard or free-data requirement, bring the observed result back to the user rather than silently changing scope.

## T02 — Build the trip and proposal foundation

Implement typed contracts for accepted snapshots, days/items, legs/stays, bookings, working context, offers, evidence, proposals, conversation, jobs, and preference records. Use stable IDs and explicit versions. A flat list of 24 stops is not the new trip representation.

Start with immutable accepted snapshots plus an audit of proposals and applied commands; a general-purpose event-sourcing platform is unnecessary. Specify operations such as adding/removing/moving an item, changing an overnight allocation, selecting an offer, and recording a user-supported booking.

Implement the authenticated repository and `apply_proposal` domain operation using the caller-owned trip:

1. Resolve owner, trip, and proposal.
2. Check command identity and payload consistency; a repeated successful command returns its existing result.
3. Check the base revision and fixed commitments.
4. Create one new accepted revision and mark the proposal applied in the same transaction.
5. Return a typed view model; stale or conflicting proposals produce a new-review requirement.

Use Jac's documented request transaction/retry behavior. Keep external model/browser effects outside the writing unit. For guests, use the same operation semantics in the local draft reducer; do not store isolated guest trips under Jac's shared anonymous root.

**Tests:** rejection and preview do not change accepted state; duplicate commands do not double-apply; reused command keys with different payloads fail; concurrent approvals cannot both overwrite a revision; wrong-owner IDs fail; fixed bookings survive unrelated edits; serialization preserves source/evidence states.

## T03 — Build recoverable planning/research jobs

Implement submit/claim/heartbeat/finish/cancel operations and a committed job ledger. One worker service is sufficient initially; isolated browser contexts serve research jobs. Avoid introducing a queue cluster before a measured need.

Submitting a planning turn records its input and job. The worker performs the model/tool loop outside the database transaction, then submits a typed result/proposal. The browser/model worker cannot apply accepted-trip changes. Claim leases, attempt ceilings, cancellation, and idempotent result submission are application logic.

Use account ownership for signed-in requests and narrowly scoped temporary job capabilities for guest work. Browser sessions and upload/evidence records must be isolated across users/jobs. A browser context must not have application secrets or arbitrary database access.

Build the evidence ledger and offer gate here. Every displayed mandatory field must point to observed source evidence. Keep cited acquisition separate from strict normalization: native citations conflict with strict JSON output configurations; valid JSON alone is not factual verification. [Structured output constraints](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)

Carry a query fingerprint and originating revision through every job. Changes to search-relevant inputs invalidate current eligibility; an unrelated title edit need not invalidate an otherwise fresh quote. Cancellation or late completion must never overwrite a newer plan. Polling is an acceptable first transport; do not make streaming infrastructure a prerequisite for correctness.

**Tests:** restart/reclaim, cancellation during execution, duplicate result submission, expired guest capability, cross-user result access, late/out-of-order result, invalid evidence, and transaction replay without a duplicated external model call.

## T04 — Ship the first real conversational slice

Build the thin target UI needed for: conversational entry → focused clarification if necessary → route/overnight proposal → map/list preview → approval → follow-up revision. Use the adopted dark style from the beginning without waiting for every secondary panel.

The response contract should include concise prose, an optional clarification with contextual replies, one recommended next action, typed focus/context references, jobs, and an optional proposal reference. Render app-owned components; do not accept executable model-generated UI.

Persist user inputs separately from accepted trip data. Explicit clarification answers feed the working query/proposal without an extra confirmation click. A request that changes accepted facts still yields a reviewable proposal. Short answers must work across multiple turns.

Build model context from accepted state, working facts, the pending proposal, selected references, relevant preferences, a bounded conversation summary, and needed source excerpts. Do not rely only on the last 12 messages. Handle the full pasted Arizona itinerary without the current 4,000-character silent failure/truncation pattern.

**Exit:** a genuine live conversation can create and revise a route, including the mixed DTW → SFO → XNA → Ann Arbor case, without losing endpoints, modes, or stated commitments. Relative dates are tested with an explicit current-date/time-zone anchor. A logistics-only request does not produce an activity-planning intake.

## T05 — Complete the desktop workspace

Extract focused Jac components for entry, trip overview, day view, item detail, map, conversation/composer, comparison, and proposal review. Add a client state layer separating server plan data from transient presentation state.

Implement:

- Overview → day → item with selection and return context retained.
- One guided next decision and optional quick replies, while free-form chat remains available.
- Explicit “Ask about this” actions attaching removable composer context. Inspecting an item alone does not rewrite a drafted request's scope.
- Stable entity/revision references for contextual requests; removing context clears scope, not history.
- Compact collapsible chat; active research and text drafts survive collapse.
- In-context differences and coherent approval/refinement. All affected fields are inspectable.
- Real progress/stop and quiet completion notifications that do not steal focus from another task.
- Loading, empty, conflict, incomplete-check, and save-status states using the same UI hierarchy.

Keep the existing map engine where useful, add the proven free basemap/location path, and distinguish planned links from calculated roads. UI selections and panel changes never require trip approval.

**Exit:** a user can locate an activity, ask for an easier alternative without retyping its name, inspect the proposed consequences, and keep or approve the plan. Verify actual controls and keyboard behavior, not class names or screenshots alone.

## T06 — Make trips durable across sessions/devices

Extend existing runtime accounts with owner-root trip/revision/proposal/conversation storage, trip listing, loading, and truthful save state. Use the configured durable database; the documented external setting is `JAC_DB_URL`.

Guest drafts use versioned IndexedDB recovery. Account import has a stable import ID and acknowledgement: retrying creates one account trip, retains the local copy until success, and does not overwrite another trip with the same title. Reconcile any guest proposal references against the imported revision.

Store recovery metadata and UI context appropriately; do not use a client-supplied email as authorization. Signing out clears account-specific device caches. A failed save preserves recoverable work and allows retry.

**Exit:** start as guest, approve a route, sign in, reload, resume on a second device, and survive server restart. Test quota failure, interrupted import, duplicate import, stale-tab edits, and account isolation.

## T07–T08 — Deliver verified comparisons, then all agreed categories

Start with the category/source that T01 actually proves most reliable. Complete one vertical flow before generalizing multiple supplier integrations:

1. Model gathers the quote inputs contextually and creates a research job.
2. Worker obtains observed quote evidence and publishes only qualifying offers.
3. The comparison panel shows source identity, dates/party, total/unit/currency, important supported terms, observation time, and source action.
4. Inspecting a candidate highlights relevant map context without choosing it.
5. Choosing creates a proposal; approval records the selection and related trip facts.
6. Refresh checks and the external handoff preserve the relevant query/product context.
7. A later user report/upload can support a reviewed booking-status update; clickout alone never means booked.

Extend the shared evidence/card contract to flights, hotels, vacation rentals, and cars, with category-specific fields and source-specific adapters only where needed. Airline segments, hotel nights/rooms, and rental driver/pickup inputs cannot be flattened into a generic price string.

Implement exact-money arithmetic and separate booked/paid amounts, selected quote snapshots, and unpriced sections. Alternatives do not accumulate into totals. Old quotes may appear as historical observations, never as fresh current offers.

**Exit:** each claimed category has a successful audited query and handoff plus failure/staleness tests. Include missing mandatory fees, mismatched dates/party, session-bound links, and query changes after research. A source that has not passed remains unclaimed; no demo offers substitute for it.

## T09 — Complete imports and attachments

Pasted itinerary extraction begins in T04; extend it to uploaded text/PDF/images and booking confirmations. Add scoped binary storage, metadata, bounded extraction jobs, source anchors, and a preview of facts/commitments/conflicts. Use synthetic or redacted fixtures, not private confirmation details.

Long inputs need explicit chunking/reassembly and completeness checks. Preserve user text, cross-year dates, optional alternatives, breaks, and unresolved details. Do not flatten a ten-day itinerary into a handful of route stops or silently cut the end off.

Add reviewed legacy import for Atlas journeys and, where applicable, previous saved trips. Old route/history information is not automatically a fully checked vacation plan. Retain the old data until the new account/local record is acknowledged.

**Exit:** the Arizona paste and equivalent document/image import produce a source-linked proposal; approval preserves the supplied structure. Booked items become fixed only with the correct documented/user-reported status. Upload limits, unsupported formats, storage retention, and recovery are explicit and tested against the actual deployment resources.

## T10 — Build daily composition and feasibility checks

Extend the planner to compose days around confirmed transport, stays, must-do activities, pacing, breaks, optional alternatives, and daylight/access constraints. Show provisional day outlines promptly, then research/check before final detailed-schedule approval.

Use free observed place/operating information, calculated road routes, and a verified local time-zone/daylight implementation. Separate structural feasibility from estimates and live-changing conditions. A future holiday schedule cannot be declared verified from generic hours.

Code checks date/night consistency, interval overlap, drive/buffer arithmetic, and fixed anchors. The model reasons over preferences and tradeoffs and proposes connected changes. It must not silently optimize away a booked hotel or a must-do activity.

**Exit:** catch the imported Meteor Crater arrival/closing-note conflict without claiming an independently checked closure; then validate actual relevant constraints. Handle “another night in Sedona, keep the booked Page hotel” with a connected proposal or explicit infeasibility. Preserve a loosely planned day beside a detailed one.

## T11 — Add reviewable automatic personalization

Extract reusable preferences separately from trip facts, bookings, and accepted state. Store provenance/context, apply explicit current instructions first, and keep professional/vacation context from leaking blindly.

Provide review/forget controls. Forgetting must prevent immediate re-learning from the same old source turns; use source exclusion/tombstone logic or equivalent explicit suppression. Keep account memory isolated, with local guest memory handled under the same recovery/import boundaries.

**Exit:** learned preferences influence a new relevant trip, can be inspected/removed, and do not override a contradictory current request. Forget remains effective after reload and another conversation turn.

## T12 — Build the actual phone and offline experience

Implement Trip/Map/Chat primary navigation over the same client state, not separate planning sessions. Preserve selected day/item, draft text, attached context, pending proposal, and research state across switches. “Ask about this” opens Chat with its label attached; returning restores the inspected item.

Give comparisons and review focused full-width views with an obvious return path. Account for the keyboard, touch targets, focus, and approval content. A stacked desktop preview is not the finished phone design.

Cache the approved itinerary, addresses, and imported booking details in an account-scoped local snapshot plus an offline app shell. Show saved version/time. Maps, research, and conversational changes stay online. Do not prefetch map tiles or preserve current-price claims under the offline requirement.

**Exit:** on a phone, inspect a day, ask about one stop, review the resulting proposal, return without losing context, then read the approved plan offline. Test sign-out cache clearing and a second account on the same device.

## T13 — Validate deployment and cut over navigation

Choose deployment topology using T01's measured browser/worker requirements. Logical services are Jac web/API, worker execution, durable Postgres, and private attachment/evidence storage. They may share local infrastructure during development; do not assume the current free single-web-service configuration can host the whole system.

Replace the existing disposable-storage startup assumptions. Verify `JAC_DB_URL`, durable file/object storage, stable account secrets, recoverable worker claiming, and user-owned trip persistence after real restart/redeploy. Provisioning costs remain an operational decision; this plan purchases no services.

Make the new planner the primary entry flow only after the professional-trip and Arizona-style vacation journeys pass. Update the old commute-specific product copy and navigation. Retain reviewed legacy import without exposing synthetic commuter results as live travel offers.

**Exit:** complete the agreed flow on the intended deployed network, where supplier access can differ from local browsing; pass fresh Jac/client/worker/build checks, live multi-turn semantic tests, source audits, account recovery, phone/offline tests, and observed usability walkthroughs. No unsupported provider/region is advertised as working.

## Proposed code ownership

Paths below are planned additions; exact Jac imports/types must follow the pinned guides and an early cross-boundary compile check. Keep the old commuter domain separate rather than adding another unrelated meaning to its existing `server/models.jac`.

```text
web/planning/contracts.jac              Pure typed DTOs and enums
web/planning/validation.jac             Structural/date/money/reference invariants
web/server/trips/models.jac             Persistent account-owned graph entities
web/server/trips/repository.jac         Owner-authorized reads and revision writes
web/server/trips/proposals.jac          Diff, validation, and atomic application
web/server/trips/rpc.jac                Thin exposed operations
web/server/planning/turns.jac           Turn submission and view-model results
web/server/planning/jobs.jac            Claim/lease/cancel/result ledger
web/server/planning/evidence.jac        Query/evidence matching and quote gate
web/server/planning/imports.jac         Guest, attachment, and legacy import
web/server/planning/preferences.jac     Learning lifecycle and review/forget
web/client/planning/store.jac           Accepted/proposed/presentation state
web/client/planning/guest_store.jac     IndexedDB recovery and import tracking
web/client/planning/offline.jac         Approved offline snapshot management
web/components/planning/               Entry, overview, day/item, chat/context,
                                       compare, review, phone navigation
web/planning.css                       Scoped dark design and responsive rules
workers/pyproject.toml                  Pinned worker/browser SDK dependencies
workers/planner_worker.py               Model/tool loop outside write requests
workers/browser_driver.py               Isolated interactive browser adapter
workers/evidence_capture.py             Source state and field provenance
workers/tests/                         Worker, source fixture, cancellation tests
web/tests/planning/                    Domain/RPC/ownership/revision tests
scripts/test-client-planning-*.mjs      Emitted-client interaction state tests
scripts/test-planning-live.py           Opt-in multi-turn model regressions
scripts/test-research-live.py           Opt-in supplier quote/handoff audits
```

Prefer a small cohesive module over empty files created merely to match this tree. Shared DTO placement must be validated in client and server compilation before spreading imports throughout the project.

## Verification and release evidence

| Evidence class | What it proves | Required examples |
| --- | --- | --- |
| Pure/domain tests | Invariants and proposal semantics | Money, nights, IDs, fixed commitments, rejection, idempotency |
| Real Jac integration | Persistence, authorization, transaction behavior | Two owners, concurrent approval, restart, guest import |
| Client/browser interaction | User control and retained context | Next step, day/place, context chip, reject/approve, keyboard, phone |
| Live model conversations | Natural-language and multi-turn behavior | Short answers, mixed modes, relative dates, topic switching, contextual edits |
| Live supplier audits | Observed availability/total and working handoff | Each supported category/source, changed party/dates, stale and unavailable cases |
| Deployment tests | Real operating topology | Durable data/files, worker restart, cancellation, source access from deployed network |

Register new suites in [validate.sh](../scripts/validate.sh) and CI instead of relying on manual discovery. Ordinary CI stays deterministic and does not consume provider credits. Live suites are explicit, bounded, record date/time-zone anchors and evidence, and report actual failures; they are not silently skipped and counted as passed.

Final task-based acceptance is the adopted UX set: create a vacation without a mandatory intake form; arrange a work trip with a booked hotel; replace one selected activity; understand/approve a connected change; compare and externally book a researched option; resume after interruption; continue on another device; read approved details offline. Record observed usability problems rather than inventing success rates.

## First implementation checkpoint

Begin with **T00**, then **T01 and T02**. The first feature PR should establish the typed accepted/working/proposal distinction and a tested approval operation. The browser experiment runs independently and informs the worker/provider adapter before integration. Next deliver **T03 → T04**, giving us a real route-planning conversation and approval flow on which the adopted interface can grow.

No new product questionnaire is needed to start those packages. The outstanding source/deployment details are concrete experiments and engineering decisions; any material change to the agreed product constraints should return to the user with evidence.
