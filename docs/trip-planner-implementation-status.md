# Trip planner implementation status

## Current Detour implementation

Updated November 15, 2026 (America/Detroit). This section describes the implemented [Detour handoff](DETOUR-AGENT-HANDOFF.md). The November 14 and early November 15 evidence retained below is historical: Atlas branding, universal approval, studio-at-home, strict all-in-only offer presentation and missing new-studio weather have been superseded. The feature snapshot has been committed and merged to remote `main`; production packaging and public hosting are being verified as described below. Existing working changes, saved trips and private configuration were preserved.

### Implemented behavior

- The recognizable Detour landing is restored at `/`; planning actions open `/studio`. Studio, assistant and PWA copy use Detour. Guest/account handoff and compatibility routes remain.
- Overview → day → item navigation uses a focused pane with Back and restored scroll/focus instead of nested capped inspectors. Phone Trip/Map/Chat navigation and detail views keep content and actions reachable. Your Trips and overlays support consistent dismissal.
- Routine requested edits apply immediately with a short acknowledgment and Undo. Consequential changes proposed by the assistant ask a plain-language question in the main chat, with confirmation bound to the correct pending decision/current revision. Fixed locations and imported/booked commitments are guarded; unrelated days remain intact. Atomic account writes, stale-result rejection and revision checks remain internal.
- Trip deletion supports Undo and Recently Deleted recovery for 30 days. Abandoned near-empty drafts are eligible after 24 hours based on meaningful planning content, rather than title/chat count. Active work, actual plans, imported/booked content and explicitly retained drafts are protected.
- Real source-branded research cards appear in chat with a larger comparison view. Requested flight legs, stays and cars are tracked independently. Browser tools support active controls, page structure, screenshots and stable references. A persistent line near the composer reports actual current activity separately from worker lease renewal.
- Canonical offer prices contain `amountMinor`, `currency`, `basis` (`TOTAL`, `PER_PERSON`, `PER_NIGHT`, `PER_DAY`), `from`, `quantity`, `estimatedTotalMinor` and `feesIncluded`. Observed starting/unit prices and provider results/property handoffs are supported. Wrong-date/wrong-party evidence is rejected; derived estimates remain separate from booked/paid costs. Selecting an offer never marks it booked.
- Independent NWS hourly forecasts and official alerts cover itinerary ground locations, including flight departure/arrival airports, overnight bases and activities. Date/location changes invalidate prior evidence, refresh is separate from itinerary edits, and stale data is bounded. A forecast outage retains valid official warnings. Long-range trips show quiet forecast availability rather than invented conditions. Details expose source/update information.
- Chat renders CommonMark/GFM, including bold, lists, links and tables, through sanitized Markdown. Raw HTML, unsafe URL protocols and arbitrary Markdown images are excluded.
- Native Jac ownership, account save/resume, mixed flight/drive planning, imports, preference review/forget and offline saved-itinerary reading remain. The isolated worker and private source captures remain separate from native graph writes.

### Current browser, semantic and real-source evidence

These checks used isolated/synthetic test trips and real model/public-source calls where stated. No user trip was replaced and no travel was booked.

| Check | Observed result | Local evidence |
| --- | --- | --- |
| Desktop/phone browser QA | **28/28 passed; zero page errors**, including landing/studio navigation, focused details, Markdown, lifecycle and research presentation | `/tmp/detour-ui-browser-results.json`, `/tmp/detour-ui-journeys-final.log` |
| Actual conversational edit | A requested rest break applied and Undo restored state; fixed commitments and unrelated days were preserved | `/tmp/detour-ui-journeys.log` |
| Live model decision semantics | Routine rest-break edit/Undo and consequential question followed by bound confirmation | `/tmp/detour-edits-live.log` |
| Real NWS adapter | Returned real forecast data and one official warning | `/tmp/detour-weather-adapter-live.json` |
| Exact combined research acceptance | **Six real offers** covering DTW → SFO November 22, SFO → XNA November 25, and San Francisco hotel November 22–25, 2026; one adult/one room; revalidated with the final frozen validator | `/tmp/detour-live-combined-research.json` |
| Full fresh-guest research pipeline | Actual chat → queue → worker → staging → **nine inline cards** in 145 seconds; three per exact flight/hotel component, three real captures, unchanged itinerary and zero page/public errors | `/tmp/detour-final-guest-research-result.json`, `/tmp/detour-final-guest-research.log` |
| Real Chromium browser regression | Local date-picker controls → selection → stale-reference rejection passed; includes generic focusable controls | `scripts/test-research-browser.py`, included in `scripts/validate.sh` |
| Additional Airbnb research | **Three real dated home/room offers** for San Francisco November 22–25, 2026, one adult; final strict validation passed | `/tmp/detour-live-airbnb-final-research.json` |
| Car-rental source/validator proof | One genuine dated Toyota Corolla Intermediate quote accepted by the strict validator; DiscoverCars source total $269.94 USD for three days, fee inclusion unknown; SFO November 22–25, 2026, noon pickup/return, driver 30 within observed 30–65 category; reached through the actual public search form | `/tmp/detour-car-probe-options.json` |
| Full fresh-guest car pipeline | Actual chat → queue → worker → staging → **three genuine car cards** in 104 seconds; three actual captures, SFO November 22–25, 2026, noon pickup/return, driver 30 within observed 30–65 bracket, USD; unchanged itinerary and zero page/public errors | `/tmp/detour-final-guest-car-result.json`, `/tmp/detour-final-guest-car.log` |

The browser screenshots were inspected: [landing](screenshots/17-detour-home.jpg), [desktop flight detail](screenshots/18-detour-flight-desktop.jpg), [desktop studio](screenshots/19-detour-studio-desktop.jpg), [phone chat](screenshots/20-detour-phone-chat.jpg), [phone flight detail](screenshots/21-detour-phone-flight.jpg), [real research cards](screenshots/22-detour-real-research.jpg), [actual live research pipeline](screenshots/23-detour-live-research-pipeline.jpg), and [actual live car pipeline](screenshots/24-detour-live-car-pipeline.jpg). Research results are observations from those runs, not a guarantee of future prices, availability or provider access.

### Final validation and runtime status

**The refreshed complete release validation passed: 68 Jac source checks, 124 Jac tests, 59 Node tests and 152 Python tests**, plus the real local Chromium date-picker/selection/stale-reference regression, production client/JAB build, offline-worker finalization and bundle secret scan. Evidence: `/tmp/detour-final-validation.log`. The final browser fixes capture generic focusable date-picker controls and strictly distinguish 12-hour/24-hour evidence so noon cannot validate a midnight query. The browser regression is part of `scripts/validate.sh`, with Chromium installed in CI.

The development supervisor was stopped for the build because Jac shares prepared-module caches, then restarted successfully against the final source using `bash scripts/dev-studio.sh`. Intended URLs are `http://localhost:8000/`, `/studio`, and API port 8001; runtime output is `/tmp/detour-implementation-running.log`.

**Expanded native API validation passed again against the final rebuilt/restarted server.** `scripts/test-studio-api.py` verified authentication, two-account isolation, hidden helper rejection, atomic concurrent revisions, stale writes, payload-bound guest import, revision-bound/idempotent Undo, deletion/recovery and weather ownership. Evidence: `/tmp/detour-final-native-api.log`. The site returned HTTP 200 and the worker reported ready after the final restart.

**The full fresh-guest flight/hotel research journey passed**, as recorded in the evidence table above and [actual live pipeline screenshot](screenshots/23-detour-live-research-pipeline.jpg). **The full fresh-guest car pipeline also passed** in 104 seconds with three genuine cards, three actual source captures, unchanged itinerary and zero page/public errors. It used a genuine observed provider-results URL as a research lead, not seeded offers. The cheapest observed option was FOX Toyota Corolla Intermediate at a source-quoted $269.94 USD total for three days, with fee inclusion unknown. The accepted query matched SFO November 22–25, 2026, noon pickup/return and driver age 30 within the source's actual 30–65 bracket. Evidence: `/tmp/detour-final-guest-car-result.json`, `/tmp/detour-final-guest-car.log`, and [actual car pipeline](screenshots/24-detour-live-car-pipeline.jpg).

### Release and deployment status

<!-- RELEASE_AND_DEPLOYMENT_STATUS -->
Remote `main` now contains the Detour feature and integrated teammate updates at [`78baaf7`](https://github.com/chairice/eecs449/commit/78baaf7063be403f9f8f4ed0f36a2ec8ffd34767), including feature commit `c82eb6e`. This was a verified fast-forward publication; no pull request was created. Commit/merge was completed before deployment work resumed.

The combined-main validation passed **74 Jac source checks, 134 Jac tests, 81 Node tests and 162 Python tests**, real local Chromium regression, sealed client/JAB build, offline-worker finalization and secret scan (`/tmp/detour-merge-validation.log`). The later production supervisor/materializer package adds targeted tests; its final test count, native production/restart proof and public URL remain to be recorded after verification.

The selected free deployment runs the sealed Jac app, Chromium worker and persistent private database/queue on the existing Mac, with a temporary public Cloudflare Quick Tunnel. The Mac, supervisor, network and tunnel must remain available; this is not permanent managed cloud hosting. Anthropic requests consume the host's configured model credits. JacHammer was investigated first, but permanent hosting requires a paid plan and the app's additional worker/storage topology was not verified on its free sandbox. See [the deployment guide](../deploy/README.md) for actual commands, private state, backup/upgrade behavior and hosting limits.

Public deployment verification is in progress. No public URL or successful production/restart result is claimed until those checks finish. The root Render auto-provision blueprint has been removed; the retained Render examples are non-default historical or explicitly paid configurations and are not used for this free deployment.

### Remaining limits

- The exact flight/stay, Airbnb and car examples passed. General provider coverage remains best effort; the car app acceptance used an observed provider-results URL as a lead and does not prove unaided coverage across rental sites.
- Public sites can block access, change controls, drop dates or omit charges. Genuine observed options, price bases and source handoffs are required; missing coverage must remain unresolved rather than invented.
- Weather and geographic data are bounded best effort. Official alerts/forecast horizons depend on source availability; flight weather describes ground endpoints rather than airborne risk.
- The runtime remains one host, one elected worker, private persistent worker storage and Jac PostgreSQL. Production/deployment verification is recorded above; public-load, penetration and multi-host validation have not been performed. Offline access covers the last online-loaded saved itinerary, not live maps/research or new edits.

## Historical implementation evidence: November 14–15

The following record is preserved for provenance. It describes earlier behavior and test results; current product behavior and final-validation status are above.

Implementation and local verification, November 14, 2026. No deployment, commit, PR or public publication has been performed. The pre-existing working changes were preserved; the pre-implementation backup is `/tmp/trip-planner-preimplementation`.

## Implemented

- Native Jac account-owned trip, profile and revision nodes; protected account endpoints; atomic approval, stale-revision protection and payload-bound idempotency. Foreign Python helpers use private bindings, with actual GET/POST rejection verified. The explicit runtime RPC bridge preserves authentication despite Jac 0.37.14's automatic protected-bridge limitation.
- Structured trip state covering places, flights/drives, overnight stays, separate car rentals, days/activities, imported bookings, party, budget and unresolved details. Targeted changes preserve booked/fixed commitments and produce derived before/after summaries. Activity insertion/reordering uses an explicit beforeId anchor, including moves within a day, without replacing other activities. Accepted state changes only through approval.
- One elected isolated planning worker with a private SQLite WAL queue, prepared jobs, leases, admission limits, heartbeat, cross-device active-job recovery, cancellation and late-result rejection. Anthropic interprets language; local code validates structure, references, dates, money and provenance rather than parsing user intent.
- Streaming model responses, bounded staged proposals for large imports, complete-response validation and repair. An unapproved working preview can appear while a long itinerary is being constructed.
- Public read-only Chromium research with observed page/control references, private source captures, source-branded cards, exact search-parameter and fee-inclusive total evidence checks, and separate search links when no offer qualifies. No login, reservation or payment tools.
- Cached GeoNames/OurAirports city and airport locations; throttled Photon landmark resolution with source URLs and duplicate/name disambiguation. Ambiguous locations remain unmapped. Free cached OSRM road estimates and Astral sunrise/sunset/twilight calculations, including independent missing-event handling for Alaska.
- Dark map-led studio at `/` and `/studio`, overview → day → item navigation, collapsible chat, selected-item context, coherent preview/approval, dedicated comparison panel, uploads, guest device cache, account migration, saved trips and automatic preference review/forget. Mobile uses Trip/Map/Chat navigation. The previous commuter and Atlas journal flows remain at their compatibility routes.
- Production PWA caches the shell and static assets, with a studio navigation fallback; it excludes account APIs, uploads and external map tiles. Jac's generic worker is replaced in both emitted client and JAB by `scripts/finalize-studio-build.py`. Signing out clears the account's device trip cache.
- Pinned compiler wrapper, supervised local startup, pinned worker dependencies and CI installation, production preview utility and bundle secret scan. Credentials live in ignored, private `workers/.env`, outside Jac's `web/` packaging root. Both processes receive configuration through the supervisor.

## Deterministic and integration evidence

- Final complete `scripts/validate.sh` passed: **64 Jac source checks, 124 Jac tests, production client/JAB build, bundle secret scan, 47 Node client/service-worker tests and 76 Python worker/domain/API/evidence tests**. Log: `/tmp/atlas-release-validation.log`. The emitted-Jac regression reproduces the historical-research panel bug and verifies the requested day takes priority. Structural tests cover positioned insertion, same-day reordering, missing/self anchors and preservation of existing times.
- Tests include targeted edits, fixed commitments, mixed time zones, rental pickup/dropoff instants, money, owner isolation, concurrent queue claim, expired leases, cancellation, guest ownership transfer, stale/duplicate approval, evidence rejection, traveler counts, batched proposal aggregation and incomplete model-response repair.
- Real running Jac API integration passed authentication, two-account isolation, hidden helper GET/POST rejection, guest migration with retained proposal, duplicate concurrent approvals, competing approvals with exactly one winner, stale revisions and conflicting import payloads. Command: `workers/.venv/bin/python scripts/test-studio-api.py`.
- Emitted-Jac handler tests prove preview and day/item selection leave accepted state unchanged, chat carries explicit selected context, and approval sends the proposal/base revision before displaying acknowledged state.
- Production worker policy tests verify root/studio navigation fallback, content-hash stylesheet caching, exclusion of account endpoints and external tiles, and preservation of unrelated application caches.

## Live model and source evidence

All live tests use synthetic test trips or the supplied Arizona itinerary and a fixed date anchor of November 14, 2026. They do not change user trips or book anything.

- Mixed multi-turn request: DTW → SFO flight, SFO → XNA flight, XNA → Ann Arbor drive preserved; next Friday → November 20, following Monday → November 23, drive November 24. Logistics-only refinement and explicit lasting parking preference passed. `/tmp/atlas-live-semantic-results.json`.
- Professional DTW → Seattle November 30–December 2: BUSINESS/LOGISTICS, one adult, no sightseeing; passed. `/tmp/atlas-business-semantic-results.json`.
- Complete Arizona import: all **10 days, 138 entries and 121 supplied timed entries**, cross-year dates, drive/buffer notes, rest breaks, optional alternatives and missing-out notes retained. The supplied Meteor Crater closing-time contradiction was surfaced. No inventory was invented. `/tmp/atlas-arizona-batched-final.json`.
- Live activity-order regression: the model moved the existing 14:00–16:00 rest break before the untimed sunset stop with every activity and time unchanged, no research and no trip-specific preference saved. `/tmp/atlas-day-order-live-results.json`.
- PDF and image import: December 26–28, DTW → PHX with 10:00 departure/12:30 arrival local, two adults and no fictional booked status; passed. `/tmp/atlas-live-import-results.json`.
- Actual Photon checks located Gates Pass, Bell Rock and Red Hills Visitor Center using real OSM features. A misleading Bell Rock residential street was rejected after matching was tightened. Actual OSRM Tucson → Sedona returned approximately 260 minutes/373 km, excluding stops and live conditions; Tucson December 27 daylight calculation returned approximately 07:23/17:26 local. These are source checks, not a validation of the whole Arizona schedule.
- Actual hotel, flight and car research reached real public pages. Hotel providers dropped dates or blocked access; Google Flights loaded the correct route/date/party but did not establish all required evidence or a usable booking handoff; Hertz/Enterprise forms did not complete reliably. **No qualifying live offer was verified in these tests.** No unverified cards were shown. The final flight regression also verifies no unverified reference fares appear in chat. Results: `/tmp/atlas-live-flight-research.json`, `/tmp/atlas-live-car-research.json`.

## Browser verification

- Guest conversation → real proposal → explicit approval → day drilldown → reload recovery succeeded.
- Guest → local account migration retained the accepted trip and pending proposal. Sign-out removed account contents from the workspace; sign-in restored the saved trip without a spurious blank trip.
- Preferences review/forget, Escape dismissal, selected-place inspection, removable main-chat context, desktop chat collapse, active research cancellation without accepted changes, and 390×844 mobile Trip/Map/Chat behavior were exercised in the real browser.
- The production client was loaded on localhost:8002, signed in and then its preview server was stopped. Reloading `/studio` still rendered the cached application, styling and saved trip. The saved day, including the corrected rest-before-sunset order, remained available without an API connection. The final reconnection message uses plain language instead of exposing transport errors. A final native-account edit added only the requested 14:00–16:00 rest break, retained all original stops and other days, and saved no trip-specific global preference. External maps were not put into the service-worker cache. A fully disconnected operating-system network was not simulated.

## Material limitations

- Free public-browser research is implemented, but **reliable live flight/stay/car inventory is not established**. Anti-bot pages, inaccessible search controls, missing taxes and absent booking links can leave a search unresolved. Search handoffs remain available. This must be validated further before promising broad coverage.
- Geographic lookup and public routing are best effort, cached and bounded. Dashed connections are explicitly not calculated road routes. Seasonal closures, terrain, traffic, opening hours and reservation constraints may still need research. Unsupported timings remain provisional; the detailed Arizona plan has not been fully checked against current park/provider sources.
- The current runtime supports one host, one elected worker, a persistent private worker volume and Jac PostgreSQL. No public-load, penetration, multi-host or deployment validation has been performed. Existing Render scripts predate this architecture.
- Offline access covers the last loaded trip on that device after an online production load. Maps/research, new approvals and account sync require a connection. Source providers and model availability remain external dependencies.

## Run and verify

See [the repository README](../README.md) and [runtime setup](../workers/README.md). Start both processes with `bash scripts/dev-studio.sh`. Stop the development server before running production builds, then restart it because Jac shares prepared-module caches. Never put credentials under `web/`: Jac's artifact builder includes environment files regardless of Git ignore rules; the build secret scan enforces this boundary.

## Captured interface evidence

These are synthetic local QA trips, captured from the running app:

- [Approval preview](screenshots/12-studio-proposal.jpg)
- [Phone itinerary](screenshots/13-studio-mobile.jpg)
- [Cached itinerary with the preview server stopped](screenshots/14-studio-offline.jpg)
- [Finished desktop workspace](screenshots/15-studio-desktop.jpg)

The main app and worker are left running at `http://localhost:8000/studio`, with output in `/tmp/atlas-running.log`. The temporary production preview was stopped after offline QA. The final native API integration result is `/tmp/atlas-final-api-tests.log`.

## November 15: work-trip startup failure

The reported “Plan a work trip” failure was traced to an Anthropic HTTP 401 for the configured credential. The replacement credential was configured privately and accepted by the Models API. No credential values were logged or added to source control.

A second defect kept the interface busy: the shared response decoder raised on a valid FAILED task's error field before the polling handler could process its terminal status. Polling now uses a dedicated task decoder, allowing FAILED/CANCELLED responses to clear the active task and busy state, preserve accepted/proposed trip data, and permit a retry. Ordinary RPC failures still raise. The worker now maps authentication, permission, rate-limit, connection and service errors to useful messages without leaking provider exception bodies.

Complete validation passed: 64 Jac source checks, 124 Jac tests, 49 client tests, 82 worker tests, the production build and bundle secret scan. Regression tests exercise terminal failure → no further polling → successful retry, cancellation decoding, and safe provider error messages. Log: `/tmp/atlas-work-trip-validation.log`.

Live browser verification succeeded in a separate guest session: clicking “Plan a work trip” returned the route/date clarification, and the next message produced a December 1–3 Seattle proposal with outbound/return flights, a two-night hotel placeholder and no activity itinerary. No trip edits were approved. [Successful work-trip flow](screenshots/16-work-trip-fixed.jpg). The website and API both returned HTTP 200 after restart, and the app/worker remain running at `http://localhost:8000/studio`.
