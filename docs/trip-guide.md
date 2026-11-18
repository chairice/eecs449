# Saved trip guide and PDF

November 16, 2026 (America/Detroit). This is the follow-up to the [compact workspace refresh](studio-ux-refresh.md) on local branch `codex/detour-clearer-workspace`. The local implementation and required validation are complete. This iteration has not been committed, pushed or deployed; the earlier production instance remains unchanged.

## A useful saved trip

The main workspace is a guide to the saved plan, beside the conversation. **Your trip** and **Map** are persistent views; comparisons open from the relevant flight, stay or rental through **Compare** or **Find options**. This gives a comparison an explicit trip item and search group instead of exposing an empty global Options view.

All saved days remain navigable, including logistics-only trips. Day views join the day's activities, travel connections and stays, with check-in, overnight and check-out context. Selecting or reopening a day does not rewrite the itinerary; the browser remembers the valid day/view per trip. The map and detail Back paths return to that context.

Saved flight, stay and rental cards resolve their selected source offer and any actual booking record. They show the practical details available: local dates/times, carrier or property, stops, address, observed price basis and booking amount where supplied. Selected, fixed, booked, user-reported and cancelled states stay distinct. A booking identifier alone does not establish a booked state, and choosing an option does not buy it. Missing prices remain unpriced; estimates and actual booking amounts retain their separate meanings.

Visual day cards combine readable times/notes with available place imagery. Longer notes use a two-line preview and a keyboard-accessible full-details disclosure; practical supplier/action links stay directly reachable in a compact row. New place photos are retrieved from real Wikimedia sources with free-license metadata, attribution and source links. A quiet auxiliary media request can fill existing trips after opening; it is independent of itinerary edits and uses verified place identity. Missing imagery leaves useful text intact. These photos are sourced assets, not generated destination pictures or fallback inventory.

## Sourced flight journeys

A verified segment observation can enrich the same selected offer, preserving its price and schedule, or attach an unpriced leg-keyed `flightJourneys` resource when no priced offer is available. Both paths retain the saved travel identity and original price provenance. Resource signatures bind the leg schedule and airport query/labels; stale resources are discarded on staging/import. No new fare or booking is inferred.

Details and the map can display the sourced airport itinerary, including connection airports, rather than only the outer endpoints. The guide uses those same segment facts for its timeline and PDF. Unavailable segment details remain absent.

An independent browser check verified the selected American example: **AA2211 SFO 07:00 → LAX 08:35**, an **86-minute layover**, then **AA6348 LAX 10:01 → XNA 15:28**, for **388 minutes total**. These are observed journey facts; they do not establish a new price, availability or booked status. Separate real-photo checks retrieved Golden Gate Bridge and Sausalito imagery.

## Download the entire saved trip

**Export PDF** downloads the full saved trip from the browser, regardless of which day is currently open. It includes the overall route and diagram, every saved day and activity, travel/stay/rental details, available sourced flight segments, booking details and the applicable cost/status summaries. It preserves missing/unknown information instead of filling gaps with sample data.

The PDF is generated locally from saved state with embedded licensed fonts and vector diagrams. Once the application/export assets and trip are available offline, the export does not require a new model request or source lookup. Exporting leaves the saved trip unchanged. This explicit PDF download is an approved addition to the earlier handoff's no-export boundary.

The local PDF QA fixture is `output/pdf/detour-offsite-qa.pdf` (three pages). It is a layout test artifact, not a user's booking or evidence of fresh inventory; fixture content does not invent fare prices or booked commitments. An actual browser download from the saved-guide QA trip produced eight pages, with the full itinerary present and chat excluded. The final cold first-export regression passed 18/18 checks from the latest built chunks after fixing module/asset base resolution. All eight pages of the larger QA export and all three pages of the sample were visually reviewed; final PDF polish keeps observed dates readable and activity titles, notes and source links together.

## Implementation

| Source | Responsibility |
| --- | --- |
| [StudioTripPlan.jac](../web/components/StudioTripPlan.jac) | Saved travel/stay cards, visual day guide and sourced segment timeline |
| [TripStudio.jac](../web/components/TripStudio.jac), [StudioDetails.jac](../web/components/StudioDetails.jac) | All-day navigation, contextual comparisons, practical details and full-state PDF action |
| [Planning state helpers](../web/client/planning_state.jac) | Pure joins for selected offers, bookings, photos, day context and per-trip view cache |
| [Planning media](../web/server/planning_media.py), [place photo adapter](../web/server/place_photos.py) | Quiet cached/background imagery for existing trips |
| [Worker photos](../workers/atlas_runtime/place_photos.py), [flight journeys](../workers/atlas_runtime/flight_journey.py) | Sourced enrichment and matching to saved travel identity |
| [PDF model](../web/client/trip_pdf.ts), [renderer](../web/client/trip_pdf_render.ts), [font licence](../web/client/pdf_assets/LICENSE_LIBERATION) | Whole-trip offline document, safe public links, embedded fonts and vector diagrams |
| [Full browser journey](../scripts/qa-studio-agenda.py), [cold-offline PDF check](../scripts/test-studio-pdf-offline.py), [live offsite test](../scripts/test-trip-guide-live.py) | Isolated guide/account navigation, actual local PDF download/cold export and opt-in real model/source workflow |
| [Agenda tests](../scripts/test-studio-agenda.mjs), [PDF tests](../scripts/test-trip-pdf.mjs), [resource tests](../workers/tests/test_trip_resources.py) | Saved-guide joins, export content and sourced-resource regressions |

## Completed evidence and validation

All required work and validation are complete for this local iteration. The full baseline suite covered unchanged Jac/Python code; after the final PDF-only formatter/pagination polish, all Node checks and the targeted sealed build/manifest/secret checks were rerun. Focused counts below overlap the wider suites.

| Check | Observed result |
| --- | --- |
| Jac/Python full-suite baseline | **75 Jac source checks, 134 Jac tests and 203 Python tests passed**; those sources were unchanged by the final PDF-only polish |
| Latest complete Node run | **110 client + 31 PDF checks passed (141 total)** against the final source |
| Final sealed release | Jac build, offline finalizer, sealed payload integrity and secret scan passed; post-finalizer JAB size **6,685,684 bytes** |
| Hardened native browser controls | Passed native widgets, stale references, delayed rerender, changed/ambiguous controls, explicit no-change outcomes and transaction guards |
| Workspace/guide/options handlers | 45 focused Node checks passed; workspace Jac checks passed |
| Final saved-guide browser journey | **31/31 passed, zero browser errors**: LOGISTICS days, leave/reload/Back, account trip switch/reopen, selected prices independent of shortlist, sourced photos/segments, PDF download and offline export |
| Map/layout refinement | 13 affected checks passed, including loaded OSM tiles and day scoping that excludes unrelated Detroit/future LAX connections from the November 23 bike day |
| Actual researched guide polish | 12 desktop/phone/keyboard checks passed for supplier links, two-line notes/full details, accessible credits and 44 px phone actions |
| Real model UI | Seven desktop/phone/reload checks passed |
| Native account/media | Baseline API and nine native media checks passed, including real Golden Gate Bridge imagery, ownership and unchanged snapshot/revision/Undo |
| Final PDF content/layout | 13 focused PDF checks passed; Unix seconds, milliseconds and ISO observation times render as readable dates; short activity titles/notes/links stay together; all eight large-export and three sample pages were visually reviewed |
| Final cold first PDF export | **18/18 passed** from a fresh context using the latest chunks: first-ever export offline after Map reload, all four fixture PDF pages, fonts, every day, real LAX segments and provenance labels; no errors and byte-identical source/view state |
| Public-only model flight enrichment | **7/7 passed** in 19.09 seconds; two real captures, one native disclosure click with observed expansion, model update/staging and unchanged snapshot/revision/Undo/price |
| Live offsite research/follow-up | **14 checks passed** across initial, manual and follow-up checks; 43 captures and three actual photos |

The public-only flight fixture contains public airport/schedule facts for the exact American example, not a user's existing saved-trip context. It verified the actual browser → disclosure click → observation → model update → staging path. The original full-context diagnostic replay was not executed. Evidence: `/tmp/detour-public-flight-model-qa.log` and the isolated `detour-public-flight-qa-8ekwicic/result.json` artifact.

The live offsite run obtained named rental rates/hours and venue facts from actual sources, including Poggio, Scoma's and the aquarium. Exact November 23 ferry timing, bike rules/availability and the docking/return plan remain explicit travel-planning tasks rather than confirmed reservations. The follow-up produced five actionable tasks while all other trip content remained byte-for-byte identical, performed no additional browser research and supported exact Undo. Evidence: `/tmp/detour-trip-guide-live.log`, its follow-up log, and the isolated `detour-trip-guide-live-xzqurq65` evidence/follow-up/summary artifacts.

Reviewed screenshots: [complete saved guide](screenshots/32-detour-useful-trip-desktop.jpg), [day itinerary](screenshots/33-detour-bike-day-desktop.jpg), [day-scoped map](screenshots/34-detour-bike-map-desktop.jpg), [sourced flight connection](screenshots/35-detour-sourced-connection-desktop.jpg), [phone day](screenshots/36-detour-bike-day-phone.jpg), [account trip reopen](screenshots/38-detour-account-trip-reopen.jpg), [actual researched overview](screenshots/39-detour-researched-offsite-overview.jpg), [practical researched day](screenshots/40-detour-researched-offsite-day.jpg) and [phone researched guide](screenshots/41-detour-researched-offsite-phone.jpg).

Full-suite evidence: `/tmp/detour-trip-guide-final-validation.log`. Final browser evidence: `/tmp/detour-agenda-browser/results.json` and `/tmp/detour-real-agenda-qa-results.json`. The latest cold-export result is `/private/tmp/detour-pdf-final-offline/results.json` (four-page fixture PDF, 49,671 bytes). The local preview returned HTTP 200 and its planning worker reported ready after restoration.

The prior compact-workspace pass remains separate: it validated its layout and a model-backed selection/Undo replay of unchanged genuine historical quotes. Its fresh SFO → XNA search returned no qualifying offers and is not a fresh-inventory success for this follow-up. The new segment/offsite tests do not confirm a new fare, bike availability or a booking. This completed iteration remains local-only: no commit, push or deployment was performed, and the earlier production instance is unchanged.
