# Atlas validation record

Validated locally on 2026-10-30 with Jac 0.37.14 and Node 22.11.0.
Final full run: 100 Jac tests, production build, and 30 emitted-JavaScript tests
passed (20 Atlas/navigation, 10 existing planner-client tests).

## Automated coverage

`bash scripts/validate.sh` checks all Jac sources, runs all Jac tests, builds
the production application, and runs Node tests against the actual emitted
JavaScript. Atlas adds mocked backend tests (no paid model/network dependency),
client data/storage/mutation tests, catalog checksum/coverage checks, and
early navigation-dispatcher tests. Existing planner suites run unchanged.

Review regressions cover empty initial contexts; repeated return legs;
malformed/truncated model output; no silent loss of modes/dates; provider size,
coordinate and rate limits; stale-tab writes; quota failures; optional unsent
prompts; metadata-preserving reorder; atomic proposal application; manual place
disambiguation retention; unchanged-route reuse; and navigation registration
before React Router.

## Browser evidence

- Empty Atlas; explicit `DTW -> JFK -> BOS` request resolves all three airports.
- The original complex New York/Ann Arbor/SF request stays wholly visible and
  unresolved without AI, rather than claiming a successful interpretation.
- Mixed flight/driving editor, explicit save, status/mode filters, presentation,
  fit/reset, unsaved changes prompt, recovery of note and unsent description,
  recoverable Trash and restore.
- Desktop 1280×900 and phone 390×844 layouts inspected; screenshots in README
  are labeled synthetic QA journeys, not user history.
- A real public OSRM Ann Arbor–Chicago road request succeeded. JFK–Boston was
  rejected by conservative shoreline checks; the UI left that leg undrawn and
  kept its stops, explaining that it can be saved and retried.
- Same-document Back prompts on a dirty editor; Keep editing remains in Atlas,
  and Discard replays the requested history navigation.
- Two-tab browser reproduction: the stale tab's autosave is rejected, its text
  remains visible, and Back is intercepted even though persistence failed. A
  fresh reload confirms the newer saved note and road geometry are intact.
- Mobile edits to departure date/time and explicit Past status save correctly.
- Existing natural-language commuter search still returns three synthetic
  Ann Arbor–Chicago options for November 6 after 4 PM.

## What this does not establish

No live paid-model request was made. Configured-AI behavior is tested with mocked
responses, not evidence of model quality, available credit, or account access.
There is no production-scale provider/load test, distributed rate limiter,
atomic cross-tab database, cross-device synchronization, offline service worker,
ticket purchase or recommendation integration. Catalog coverage is not exhaustive.
The public road service and conservative coastal-boundary limitations are real.
