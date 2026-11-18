# Detour: implementation handoff

> **Local trip-guide follow-up — November 16:** The current local work adds a useful all-days saved guide, durable navigation/reopening, selected flight/stay cost/status summaries, contextual comparisons, sourced photos and same-offer flight segments, and whole-trip offline-capable PDF download. This explicitly extends the older no-export boundary. It is not committed, pushed or deployed; the earlier production instance is unchanged. [The trip-guide note](trip-guide.md) records the design and evidence. The work is complete locally: 75 Jac source checks, 134 Jac tests, 110 client + 31 PDF Node checks (141 total), 203 Python tests and the final sealed build passed. Final browser checks passed 31/31, cold-offline PDF 18/18 and focused PDF quality 13 checks. Native media, public-only model flight enrichment and real offsite research passed; unconfirmed ferry/bike/return details remain explicit travel tasks. The local preview is restored with HTTP 200 and worker ready.

> **Prior local UI revision — November 16:** The current local branch replaces the permanent three-column/full-cards-in-chat layout with a Trip/Options/Map canvas beside compact conversation, grouped canonical comparisons and visual weather. This iteration is not committed, pushed or deployed; the earlier production instance remains unchanged. [The workspace refresh note](studio-ux-refresh.md) records the new hierarchy, accessibility and validation status. It supersedes the older layout descriptions below without changing real-source, ownership, fixed-booking or Undo safeguards. Reviewed desktop/phone checks passed (27/27 layout plus 6/6 handoff/mobile). Final validation passed 74 Jac source checks, 134 Jac tests, 106 Node tests and 181 Python tests with the sealed build. Actual historical-quote Choose → model/staging → exact Undo passed 15/15 checks; the separate fresh search returned no qualifying offers and is not claimed as fresh inventory acceptance.

> **Current status — November 15, 2026:** The handoff's application changes are implemented: familiar `/` landing and `/studio` split, Detour branding, focused desktop/phone navigation, in-chat research cards/comparison, immediate routine edits with Undo, bound plain-chat consequential decisions, fixed/booked guards, recoverable deletion/meaningful-draft cleanup, persistent actual activity, independent NWS weather and safe Markdown. Exact two-flight/San Francisco stay research produced six real offers; the actual fresh-guest chat → queue → worker → cards journey then produced nine cards with unchanged itinerary and zero errors. Airbnb produced three real home/room offers. Browser QA passed 28/28. The full car-chat pipeline passed with three genuine dated cards using an observed provider-results URL as a lead, with unchanged itinerary and zero errors. Feature validation passed (68 source checks, 124 Jac, 59 client and 152 Python tests); the integrated main/production results are recorded in the release update below. Expanded native API verification passed against the final restarted server, with HTTP 200 and worker ready. See [current implementation, artifacts and remaining checks](trip-planner-implementation-status.md#current-detour-implementation).
>
> **Release update:** Feature/main integration is published at `78baaf7`; the production package is published at `9abd340`. The free temporary public app is verified at [https://activity-fed-fame-sense.trycloudflare.com/](https://activity-fed-fame-sense.trycloudflare.com/), including real same-origin chat → queue → Anthropic → staged reply. Merged-main checks passed 74 Jac source checks, 134 Jac tests and 81 client tests; the final Python suite passed 167 tests. Native production API, stable signing/session/account/trip state across artifact upgrades/restoration, sealed-manifest integrity and worker health passed. Hosting is on the existing Mac through a temporary Cloudflare Quick Tunnel; the Mac/app/tunnel must remain running. See [deployment instructions](../deploy/README.md) and [release/deployment evidence](trip-planner-implementation-status.md#release-and-deployment-status).
>
> The detailed sections below preserve the original requirements and pre-implementation observations. Statements such as “currently,” “pending,” “not integrated yet,” the old runtime log, implementation-order instructions and the receiving-agent prompt describe that earlier handoff snapshot; they are not current completion status. Earlier Atlas/universal-approval/strict-all-in/no-studio-weather behavior is superseded. Use the linked status for the current runtime and final evidence.

Updated November 15, 2026 (America/Detroit). Start here when continuing the current application. This handoff incorporates the user's latest feedback; it supersedes conflicting approval, pricing, branding and home-page rules in the November 14 design documents.

## Objective and first actions

Deliver a polished, agent-led U.S. trip planner in Jac: the familiar Detour landing page opens a focused conversational studio, the agent researches and presents real travel options, and meaningful weather information follows the itinerary.

1. Inspect `git status`, applicable `AGENTS.md`, and the current running app before changing anything. Preserve the large existing working tree and users' saved trips. Many essential implementation files are untracked; a clean checkout does not represent the current app.
2. Read the requirements below. They are the current product contract. Read [the weather review](detour-weather-review.md) when implementing weather. Consult older documents only for details consistent with this handoff.
3. Finish browser verification of the Markdown change already in the working tree, then implement the remaining work packages. Keep the site available while the user tests; coordinate necessary service restarts and avoid building against a running Jac process's shared prepared caches.
4. Complete the live research acceptance scenario. Test counts and successful search-link handoffs alone do not establish useful travel research.

## Baseline to preserve

- Support both short professional logistics-only trips and detailed multi-day vacations, with mixed flight/driving routes and pacing/detail managed conversationally.
- Keep the linked map/day/item workspace, explicit removable chat context, one trip owner planning for a party, guest-first use, account save/resume, pasted plans and PDF/image imports, and preference learning with review/forget controls.
- Preserve offline reading of the saved itinerary, addresses and booking details; maps and research require a connection. Trips remain inside the app; inbox integration, sharing/export and calendar connections were not requested.
- Travel data access must be free or browser/search based. Anthropic credits are available. Paid travel-provider partnerships are not an acceptable prerequisite. There is no implementation deadline constraint.

## Current workspace and runtime

- Repository: `/Users/bhavyemathur/Desktop/College/UMich/EECS/EECS 449/eecs449-team`.
- Jac 0.37.14 is pinned. Follow the compiler's bundled guides before editing Jac; `scripts/jac` is the portable wrapper. Start with `jac-essentials`, `jac-core-cheatsheet`, `jac-types`, and the relevant client/server guide.
- Website was left running at `http://localhost:8000/studio`; development API is port 8001. Verify availability before starting another instance. The supervisor is `scripts/dev-studio.py`, launched by `bash scripts/dev-studio.sh`. Runtime output is `/tmp/atlas-running.log`.
- Anthropic configuration is already in private, ignored `workers/.env`. Use the existing configuration; do not print credential values. The credential was replaced after a confirmed HTTP 401 and accepted in live requests on November 15.
- Worker Python is `workers/.venv/bin/python`; Chromium is under `workers/.browsers`; dependencies are in `workers/requirements.lock`.
- Jac PostgreSQL and `web/.jac/data/planner` contain persistent state. Preserve them. Worker jobs, captures and uploads are private data, not disposable fixtures.
- No deployment, commit, PR or publication has been requested/performed for this iteration. An earlier pre-implementation backup was recorded at `/tmp/trip-planner-preimplementation`; verify it exists before relying on it.

### Architecture worth preserving

The new UI is `web/components/TripStudio.jac`, with `PlannerMap.jac`, `web/client/planning_state.jac`, and `web/studio.css`. Native Jac account-owned trip/profile/revision nodes and protected endpoints live in `web/server/planning.jac`. `planning_core.py` validates structured trip operations; `planning_api.py` stages/commits state and resources; `planning_jobs.py` owns a private SQLite queue. `workers/atlas_runtime` runs Anthropic and an isolated research browser outside graph write transactions.

The LLM interprets language. Local checks validate structure, ownership, references, dates, money and fixed commitments. Preserve this division; avoid replacing interpretation with keyword/regex intent rules. Internal revisions and atomic writes remain useful after approval controls disappear from the product.

Account endpoints require the explicit authenticated bridge in `web/client/planning_rpc.jac` because the pinned compiler's automatic bridge does not handle protected endpoints. Keep foreign Python helper imports private (`_` aliases); endpoint isolation has been tested against the real Jac server.

## Current product contract

### 1. Restore the familiar landing page

`/` should look and feel extremely similar to the previous Detour home, while its copy describes the broader current planner. Retain the recognizable header, typography, soft green/sky palette, destination photo carousel and overall composition. The main Plan a trip action and other planning entry points open `/studio`.

The previous landing is preserved in `web/pages/commuter.jac`, `DestinationCarousel.jac`, `PublicHeader.jac`, `AuthPanels.jac`, `AppShell.jac`, `home.css` and `styles.css`. Currently `/` directly renders the studio. `pages/layout.jac` also treats both `/` and `/studio` as dark shell-free pages; update that distinction.

Audit all CTAs, carousel interactions and post-login/signup destinations: many still point at the old `/plan` commuter flow. Preserve guest work when signing in from the landing page. Reuse the existing identity system rather than creating another account flow. Keep legacy compatibility routes usable. The intended planning geography remains U.S.-only.

**Done when:** a fresh visit shows the recognizable Detour landing, Plan opens the new studio, returning home restores the landing's correct theme, and guest/sign-in/resume paths preserve work.

### 2. Simplify the studio's left pane

Opening a flight currently inserts an inspector above the overview, capped at 42% height with its own scrolling. Proposal panels add another capped scroll area. Replace this with focused overview → day → item navigation: detail views occupy the pane, have an obvious Back action, and restore prior selection/scroll context.

Use type-specific, compact layouts. A flight should prioritize route, local departure/arrival dates/times, airline/stops where researched, price basis, and useful actions. Put long notes/source details behind disclosure controls. Use a single primary scroll area and keep actions reachable. On phones, use a full-width detail view/sheet. Reduce repeated banners, metadata, unresolved-detail lists and always-visible source explanations. Weather must fit this restrained design.

**Done when:** clicking a flight/place/day feels like navigating a focused workspace, details/actions are reachable on laptop and phone, and closing restores the expected previous view without nested-scroll awkwardness.

### 3. Fix interaction state and trip management

Your Trips must close on outside click, Escape, repeated activation, or selecting a trip. Its active appearance follows its open state. Apply consistent dismissal, focus restoration and selection cleanup to other overlays and details.

Add trip deletion with Undo and a recoverable Recently Deleted area. A retention period such as 30 days is a suggested implementation default, not an explicit user decision.

Automatically remove abandoned generic/near-empty trip shells from the saved-trip list. Determine this from meaningful planning content, not whether there are chat messages, prompts, or a changed title. A chat-filled default shell can still be unplanned. Protect actual routes, overnight bases, day plans, imports/bookings, active work and explicitly retained drafts. Do not remove the current draft while the person is working. Preserve recovery when classifying borderline drafts.

**Done when:** all dismissal paths clear menu state, intentional trips can be removed/restored, empty shells stop accumulating, and meaningful plans survive cleanup regardless of title or chat count.

### 4. Brand the current app as Detour

Replace user-visible Atlas branding with Detour: studio wordmark, conversation labels, assistant prompt/name, page/PWA metadata, remembered-preference copy and public failure messages. Remove wordmark underlining on hover; keep keyboard focus visible. Internal module/storage names may remain for compatibility. The older Atlas journal at `/atlas` is a retained legacy feature, not the new product's name.

**Done when:** the home→studio journey consistently says Detour and the logo's hover/focus states work as intended.

### 5. Research real options and present them in chat

The user explicitly rejected demo inventory, fabricated offers, presentation-mode mock data, and synthetic fallbacks. Everything presented as a travel option must come from real research. They want best-effort results, confident presentation, real observed starting prices and reasonable model-derived calculations grounded in researched prices. They do not want repeated verification disclaimers, confidence badges or raw errors in the user flow. Use honest price bases such as From, per person, per night or stay total; retain provenance and calculations internally.

The old rule requiring complete all-in-price/availability/booking-link verification before displaying any card is superseded. A missing direct booking link should not erase a real option: an observed provider results/property page can be the handoff. Never turn a known wrong-date/wrong-party result into a matching offer, or represent a starting rate as a verified all-in booking total. Actual booking remains external, and choosing an option does not mark it booked.

The implementation must research all requested components. Track flight legs, stays and cars independently; optional hotel budget/area questions should not silently stop an already-specified flight search. Retry meaningful interactions, fix date/traveler controls, and try another real source when appropriate. Browser-agent capabilities need improvement: live page structure/accessibility, forms/date pickers, screenshots, scrolling, result selection, and stable action references. Anthropic's browser-use toolset is a candidate implementation, not integrated yet.

Show a curated shortlist as compact source-branded cards directly in chat, with a larger comparison surface available when useful. Capture enough structure for real flight times/stops, accommodation location and price basis. Keep a single coherent current search context while allowing comparison with prior results.

Changing this policy requires coordinated offer schema, evidence, selection and budget updates—not just changing the prompt. Current `totalMinor`/mandatory-fees-included assumptions cannot represent all starting/per-night/derived prices correctly. Preserve private source captures and validate calculations structurally while allowing the agent to interpret sources.

**Exact observed failure:** job `job-0a507665ade646af8e3fd13f644c00cc` inspected only two pages. Google Flights displayed fares for DTW→SFO on November 22 with one passenger; the agent withheld cards because it could not confirm a booking link. Google Hotels actually showed November 30–December 1 and two travelers despite November 22–25/one-adult parameters in the URL. SFO→XNA was never searched. This is evidence of both agent shortcomings and over-restrictive presentation policy; do not attribute it solely to provider blocking.

Relevant captures, if retained, are in `web/.jac/data/planner/evidence/source-bba4bda31f254e708329c12f589e3d0c.json` and `source-e03a426c0edb471b8e2e99dd89447518.json`. These are real captures; never fabricate a missing capture.

**Done when:** live DTW→SFO, SFO→XNA and San Francisco stay research produces real relevant option cards in the app, using the requested November 22/25, 2026 dates and one adult/one room; hotel controls match the search; every requested leg is addressed; price bases and provider handoffs are correct. Extend this with a real Airbnb and car-rental example. A test yielding only generic search links is not evidence that option presentation works. Availability of external sources limits absolute guarantees: the requirement to seek options is not permission to invent them.

### 6. Show one visible current-step line

A progress row already exists inside the scrolling chat log, but the user cannot reliably see meaningful activity. Place a single persistent, updating line near the composer: Searching DTW → SFO, Setting your hotel dates, Comparing stays, etc. Drive it from actual work/tool events, with concise model-generated public summaries where useful. It is activity context, not raw chain-of-thought. Keep Stop available and ensure mobile users see progress when starting from Trip view. Heartbeat renewal currently overwrites task text with a generic message; separate lease renewal from activity updates.

**Done when:** the line is visible throughout slow model/browser calls, changes with the actual step, does not accumulate a transcript of status messages, and stops cleanly on completion/cancellation/failure.

### 7. Replace the approval workflow with agent-led edits

The user rejected the Git-like proposal/Approve update experience. Routine requested changes should apply immediately, with a short acknowledgment and Undo. An explicit instruction generally supplies permission for that edit.

When the agent independently proposes a consequential change—travel dates, route, overnight bases, removing destinations, or disturbing fixed commitments—it should ask a plain-language question in the main chat before applying it. Connect the answer to the correct pending decision and current state. Keep booked/fixed commitments protected and explain connected consequences. Booking purchases/cancellations remain outside the app.

Remove proposal banners, change counts, separate approval screens/buttons and redundant confirmation of clarification answers. Keep structural validation, atomic account writes, stale-result protection and internal revision/undo support. Teach the model when to act versus ask; use structural safeguards around consequential changes. Existing tests tied to universal approval must be rewritten to assert the new behavior, while preserving data integrity tests.

**Done when:** add a rest break applies naturally and can be undone; an agent-initiated date/base change asks in chat; answering confirms the intended current change; no technical review workflow appears; fixed bookings and unrelated days remain intact.

### 8. Integrate real weather similarly to the previous app

A requested subagent completed a read-only trace of the previous NWS integration. Its findings and implementation pointers are in [detour-weather-review.md](detour-weather-review.md). No new-studio weather integration has been implemented.

Reuse real NWS hourly forecasts and alerts with compact, location/time-relevant warnings and expandable details. Support travel legs, overnight bases and activities. Fetch/refresh weather as auxiliary sourced data, independently from itinerary edits. Flights need ground weather at departure/arrival airports, not straight-line airborne-risk claims. Long-range trips get a quiet normal forecast-availability state rather than invented conditions.

Preserve official alerts even if forecast retrieval fails. Distinguish missing data from benign conditions internally, and preserve real safety warnings even though technical failures should not dominate the user interface.

**Done when:** the trip and selected day/leg expose relevant real weather, source/updated time and official warnings; changing dates/locations invalidates old results; opening a trip refreshes without blocking chat; a forecast outage does not erase an actual warning; no future forecast is invented.

### 9. Finish Markdown support already implemented

Current new changes: `ChatMarkdown.jac` renders CommonMark/GFM via `react-markdown` 10.1.0 and `remark-gfm` 4.0.1; TripStudio uses it for conversation bodies; compact chat CSS styles headings, lists, code, tables and links. Raw HTML is skipped, unsafe link protocols are sanitized, and arbitrary Markdown images are excluded. Packages are declared and installed. `test-client-studio.mjs` includes a renderer stub; `test-chat-markdown.mjs` exercises the real emitted wrapper and renderer. `scripts/validate.sh` now includes these tests.

Verified: two Jac component checks, ten focused Node tests (seven studio + three Markdown), and a standalone Vite client bundle build. Logs: `/tmp/detour-markdown-check.log`, `/tmp/detour-markdown-install.log`, `/tmp/detour-markdown-client-build.log`. Live browser rendering of the user's exact message is still pending.

Important build state: the standalone Vite smoke build clears dist without generating Jac's HTML/PWA files. The last complete `.jac/client/dist` was restored from the sealed JAB afterward. Thus the live development/emitted source contains the Markdown fix, while the current sealed production artifact/dist is the previous full release. Run a complete release build before distributing it.

**Done when:** `**Indoor and hands-on:**` renders bold in the actual chat, lists/links/tables fit the pane, untrusted HTML/URLs stay inert, old stored messages render without migration, and the full release includes the change.

## Implementation order

1. Verify the working state and finish Markdown browser QA; preserve current work.
2. Restore landing→studio navigation and Detour branding. Audit account/guest handoff.
3. Improve real browser research, per-component completion tracking, offer schema/pricing and in-chat result cards. Establish the live research acceptance scenario early.
4. Replace universal approval with conversational decisions, automatic routine edits and Undo. Preserve native ownership/stale-result safeguards.
5. Rework pane/detail navigation, trip-switcher dismissal, deletion/empty-draft lifecycle, and visible activity status using consistent interaction components.
6. Add NWS weather as an independent auxiliary service and incorporate its compact warnings into the new detail views and agent context.
7. Run combined desktop/phone journeys, full validation, native API tests and live semantic/research checks. Update docs/screenshots to describe implemented behavior; keep this handoff's status distinctions accurate.

This order is a delivery recommendation. User requirements above are authoritative; avoid asking the user to re-decide routine styling or implementation details.

## Validation and release

Before Markdown, full validation passed 64 Jac source checks, 124 Jac tests, 49 client tests and 82 worker tests, including build/secret scan: `/tmp/atlas-work-trip-validation.log`. Live work-trip startup and a two-flight/two-night-hotel proposal succeeded after the credential/failure fixes. The exact guest failure/retry regression now stops polling and preserves the trip.

From the repository root:

```sh
JAC_BIN="$PWD/scripts/jac" bash scripts/validate.sh
workers/.venv/bin/python scripts/test-studio-api.py  # running local Jac server
```

Live model tests require the existing local configuration and deliberately consume credits:

```sh
export PYTHONPATH="$PWD/workers:$PWD/web"
export PLAYWRIGHT_BROWSERS_PATH="$PWD/workers/.browsers"
workers/.venv/bin/python scripts/test-studio-live.py --scenario mixed
workers/.venv/bin/python scripts/test-studio-live.py --scenario business
workers/.venv/bin/python scripts/test-studio-live.py --scenario arizona
workers/.venv/bin/python scripts/test-studio-live.py --scenario day_order
workers/.venv/bin/python scripts/test-studio-research-live.py flight
workers/.venv/bin/python scripts/test-studio-research-live.py car
```

Revise research tests to require real usable cards for the supported presentation scenario; current tests allow honest empty-card/search-link outcomes. Preserve real-data-only production behavior. Recorded/synthetic fixtures belong in clearly identified tests, not in runtime inventory.

For builds, stop the known local supervisor cleanly rather than killing unrelated processes, then rebuild and restart using `bash scripts/dev-studio.sh`. Jac shares prepared-module caches across dev/build; concurrent sealing previously caused runtime endpoint-registration errors until restart. `validate.sh` finalizes the custom offline worker and scans the actual tar-format JAB for secrets. Credentials must remain outside `web/` because the compiler can package .env files despite Git ignore rules.

Completion requires actual browser task success, not only unit tests: landing entry; professional and vacation planning; both researched flight legs plus stay; small edit/Undo; consequential chat confirmation; selected-item context; deletion/cleanup; weather warning details; Markdown; phone navigation; save/resume; cancellation and recovery; offline saved itinerary. Keep raw errors and implementation jargon out of product copy. Report remaining external limitations accurately.

## Receiving-agent prompt

Continue Detour using `docs/DETOUR-AGENT-HANDOFF.md` as the current requirements and execution plan. Preserve the existing working tree, saved trips and configured local credentials. The latest decisions supersede older universal-approval, all-in-total-only and studio-as-home requirements. First finish live Markdown verification, then implement the work packages and their acceptance criteria. Reuse the preserved Detour landing style, make the studio agent-led, research and present real options only, and integrate the NWS behavior described in `docs/detour-weather-review.md`. Keep the user's development site available where possible, run the appropriate real and automated checks, and distinguish implemented, tested and pending work in your report.
