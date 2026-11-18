# Studio workspace refresh

November 16, 2026 (America/Detroit). This describes the local `codex/detour-clearer-workspace` UI iteration. It has not been committed, pushed or deployed for this iteration. The earlier production instance on port 8080 remains unchanged; the refreshed development app is on `http://localhost:8000/studio` with API port 8001.

## One place for each kind of information

The desktop workspace uses a main canvas with **Trip**, **Options** and **Map** views beside a compact conversation, rather than three permanent columns. A trip without meaningful planning content starts with a centered conversation. The canvas becomes useful as the plan or research takes shape. The trip overview balances its title/weather header, paired Stays and Travel sections, and day grid so the summary does not become a long sidebar.

Full option rows appear only in **Options**. Chat contains concise route/date/count references that open the relevant comparison. Flights are grouped by leg, travel date and party, with one active leg shown at a time, so outbound and onward/return alternatives do not become one mixed list. Stays and cars retain their own search context. A user can still discuss any option in the main conversation. When a search yields no qualifying option, that particular message can show compact provider search links. Links are validated and attached to their research turn, so unrelated edits do not inherit an earlier search handoff.

Flight rows prioritize carrier identity, local departure/arrival times, stops and the observed price basis. Thirteen vendored airline images provide compact carrier recognition; provider and route text is not repeated as a second heading. Long notes and source detail use a native **Details** disclosure. Starting, per-person/unit and source-total labels retain their existing meaning; display changes do not invent prices or imply a booking.

**Choose** sends an explicit offer reference through the existing agent pipeline. It preserves the user's unsent text, attachments and selected context. Selection remains distinct from booking. Requested updates retain Undo and booked/fixed commitment safeguards. Selection matching uses explicit IATA codes or exact catalog airport names; conflicting airport identities are rejected instead of being inferred from a city-name prefix.

## Compact conversation and weather

The conversation keeps the transcript as its primary area. Its header and default composer are compact; suggested replies occupy one horizontal row instead of wrapping into a wall of chips. Current-step activity and Stop remain visible while work runs. Routine edits no longer insert a large global “Trip updated” banner: Undo belongs in the toolbar and must remain reachable from mobile chat, while essential notices use a small floating surface.

Weather uses condition icons, temperature and concise precipitation/wind tiles. Airport captions use IATA codes while full place names remain available to assistive technology and title text. Routine NWS/update metadata is removed from the workspace. Official warning summaries remain available with details on demand; a forecast failure does not erase a valid warning. Future or missing forecasts use a quiet availability state rather than invented conditions.

## Navigation and accessibility

Trip/day/item views keep a focused Back path and restore relevant selection, focus and scroll position. The main canvas and conversation have their own deliberate scroll areas; option lists, details and the composer should not create accidental horizontal overflow or large empty regions. Mobile keeps chat and primary actions reachable without reproducing a desktop column arrangement.

Carrier images are supplementary to readable carrier names. Weather icons have readable conditions/metric labels, abbreviated airports retain full accessible names, and native disclosures keep longer details keyboard-accessible. Visible focus, explicit option/leg selection and reachable Undo remain part of the interaction contract.

## Sources and implementation

| Source | Responsibility |
| --- | --- |
| [TripStudio.jac](../web/components/TripStudio.jac), [studio.css](../web/studio.css) | Main-canvas modes, compact conversation, context-preserving Choose, notices and responsive layout |
| [StudioOffers.jac](../web/components/StudioOffers.jac) | Canonical grouped options, leg/date/party grouping, compact chat references and flight rows |
| [StudioDetails.jac](../web/components/StudioDetails.jac) | Focused item details and disclosure hierarchy |
| [StudioWeather.jac](../web/components/StudioWeather.jac), [studio-weather.css](../web/studio-weather.css) | Visual forecasts, airport captions, warnings and quiet unavailable states |
| [Airline source manifest](../web/assets/airlines/sources.json) | Provenance for the vendored carrier images |
| [Planning API](../web/server/planning_api.py), [API regressions](../workers/tests/test_api.py) | Per-turn validated research links, source/selection matching and airport identity safeguards |
| [Attachment/state helpers](../web/client/planning_state.jac) | Real file encoding and preservation of unrelated composer work |
| [Offline finalizer](../scripts/finalize-studio-build.py) | Copies public assets into the client/JAB and preserves sealed manifest integrity |
| [Workspace tests](../scripts/test-client-studio.mjs), [option tests](../scripts/test-studio-options.mjs), [weather tests](../scripts/test-studio-weather.mjs) | Emitted handler and real-renderer regression coverage |

## Reviewed interface evidence

The reviewed screenshots show the actual local interface using previously captured real quotes and the user-provided weather layout fixture:

- [Balanced trip overview](screenshots/25-detour-visual-trip-desktop.jpg): title/weather hierarchy, paired Stays/Travel and day grid.
- [Desktop flight comparison](screenshots/26-detour-visual-flight-desktop.jpg): one canonical active-leg comparison with compact rows.
- [Phone conversation](screenshots/28-detour-visual-chat-phone.jpg): compact chat and reachable Undo.
- [Phone flight options](screenshots/29-detour-visual-flight-phone.jpg): compact rows and primary actions.
- [Selected phone flight](screenshots/30-detour-visual-weather-phone.jpg): IATA captions, weather and actions above the fold; the fixture's actual next-day SFO arrival is November 23.

At the inspected test viewports, the transcript occupies about **82% of desktop** and **81% of phone** chat height. The chat header is 34 px, default composer 56 px and suggestions stay in one 30 px horizontal row. Desktop flight rows are approximately 81 px, desktop stay/car rows 93 px, phone flight rows 184.5 px and phone stay/car rows 157 px. Choose and flight Details retain 44 px tap targets; three desktop flight options fit together.

## Validation status

| Check | Current observed result |
| --- | --- |
| Real-browser layout journey | **27/27 passed**, zero page errors |
| Source handoff/mobile Undo | **6/6 passed**, zero page errors |
| Emitted workspace handlers | **18 passed**, including actual UTF-8/base64 file encoding, preservation of unsent draft/files/context during Choose and friendly upload failures |
| Weather renderer | **8 SSR checks passed** |
| Flight/options renderer | **12 SSR checks passed** |
| Offline/sealed assets | **4 offline and 4 sealed-asset checks passed**; all 13 logos returned successfully from native/production preview, rendered with nonzero natural dimensions, retained hashes and survived offline reload |
| Airport selection/API | **20 API regression checks passed**, including explicit/exact airport matching and conflicting-airport rejection |
| Final full suite/build | **Passed:** 74 Jac source checks, 134 Jac tests, 106 Node tests and 181 Python tests; complete sealed release build succeeded |
| Actual model Choose → Undo replay | **15/15 passed** through actual UI → queue → Anthropic → staging using unchanged genuine historical quotes; exact Undo restored the snapshot |

The layout and renderer checks use unchanged previously captured real offer data and a user-supplied weather layout fixture. They are test inputs, not runtime fallback inventory or evidence of newly retrieved weather. Earlier published live-source results remain documented separately in [implementation status](trip-planner-implementation-status.md).

The fresh SFO → XNA research attempt inspected **13 captures and returned no qualifying offers**. That run is an honest no-result/provider-link fallback, **not a fresh research acceptance pass**.

The actual Choose → Undo integration passed **15/15 checks** using uniquely test-owned historical cache entries containing unchanged genuine earlier quotes and their original timestamps. The model selected the correct second flight leg, kept it selected rather than booked, preserved the fixed outbound leg and all unrelated days byte-for-byte, and kept the option picker open. Unrelated draft attachments were excluded from the selection request; unsent text, files and selected context survived both success and Undo. Undo restored the exact prior snapshot. This proves historical-result selection through the real model/staging pipeline; it does not claim fresh fare discovery. [Selected historical quote in the refreshed UI](screenshots/31-detour-chosen-real-flight.jpg). Results: `/tmp/detour-ux-choose-results.json`.

Final full validation and the complete sealed build finished successfully after the frozen source, mobile refinements and singular-label polish. Evidence: `/tmp/detour-ux-final-validation.log`. This remains a local branch iteration: no commit, push or deployment was requested or performed for the refresh, and the earlier production instance remains unchanged.
