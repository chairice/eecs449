# Landing-theme and trip-management integration

November 18, 2026 (America/Detroit). This integrates remote `main` at `4b640a9` with the saved-guide/PDF work checkpointed at `c3ea8aa`. The combined source, clean build and required verification are complete. Git publication is recorded in repository history; hosting status remains in the deployment guide.

## Combined behavior

- The landing page and studio use the incoming light palette. Compatibility pages keep their remembered Light/Dark/System preference.
- Trip renaming is a validated, undoable revision. Escape cancels; Enter and blur must not save twice.
- Removing another trip keeps the current trip open. Removing the current trip opens a new draft; Undo and Recently Deleted can restore it.
- Confirmation emails are manually bookmarked nickname/link records beside the plan. Saving a bookmark does not read the inbox, change booking status or consume a planning revision. A bookmark-only draft is meaningful saved content and survives sign-in and abandoned-draft cleanup.
- All saved days, chosen travel/stays, known prices, sourced flight connections, licensed place photos, day-map context, compact conversation and whole-trip PDF export remain available.
- PDF exports include a separate Important emails section. Legitimate Gmail/Outlook message fragments remain clickable; source URL filtering still excludes credentials and capability links.

The editor is keyed to its trip. A delayed bookmark-save response cannot replace the currently selected trip's bookmarks or leak an unsent editor draft into another trip. Trip-view caches remain isolated by trip ID.

## Reviewed interface

The final light-palette screenshots were reviewed at desktop and phone sizes:

- [Overview with chosen travel, stay and saved days](screenshots/42-detour-light-overview.png)
- [Phone confirmation-email bookmarks](screenshots/43-detour-confirmations-phone.png)
- [Phone saved-day itinerary](screenshots/44-detour-day-phone.png)
- [Phone inline trip renaming](screenshots/45-detour-rename-phone.png)

These are labelled QA trips using unchanged genuine historical quotes, actual earlier sourced place photos/journey details, and a weather layout fixture. They do not show newly available fares, confirmed activity arrangements or a user's bookings. Map imagery is mocked only in automated tests, never in the runtime app; no mocked-map screenshot is included here.

## Runtime and map boundaries

`web/atlas_runtime/` is the canonical packaged runtime. The development and production supervisors set `DETOUR_EMBEDDED_WORKER=off` and run their own worker. Direct Jac hosting enables the embedded worker by default, with private host/project configuration. Chromium must be installed in the host's applicable Playwright cache; installing only the Python package does not install the browser. See [web setup](../web/README.md) and [worker setup](../workers/README.md).

The incoming map referrer setting is retained. Headless browser QA uses explicit synthetic SVG map tiles from `scripts/qa_map_tiles.py`, labelled as fixtures. Automated checks never fetch the public OpenStreetMap tile service. They verify planned overlays and map controls, not a live provider's imagery or availability. These fixtures are never imported by the application.

## Verification

The final clean sealed build passed: **76 Jac source checks, 134 Jac tests, 150 Node tests (116 + 34) and 213 Python tests**. Native widget/stale-reference/delayed-rerender/transaction guards, canonical packaged-runtime/catalog integrity and the packaged-secret scan passed. The final post-finalizer artifact is **6,757,192 bytes**. Palette-only contrast fixes were visually verified, and the first cold-offline export was repeated against this exact final artifact.

| Check | Observed result |
| --- | --- |
| New merged guest/account browser journey | **31/31 passed**, zero uncaught errors: fixed light studio, legacy dark preference, rename Escape/single Enter/actual Undo, bookmark CRUD and failed-save draft recovery, bookmarked-email PDF links, guest import, delayed response isolation, active/inactive deletion and restoration |
| Existing saved-guide browser journey | **31/31 passed**, zero errors: every LOGISTICS day, source-backed choice presentation, per-day map context, trip switching, actual full-trip and cached-offline PDF download |
| First-ever cold offline PDF | **18/18 passed** in a fresh context after offline Map reload; entire trip, connection details, embedded fonts and unchanged source/view state |
| Native API/media | Existing native ownership/revision/Undo/deletion checks and **9 media checks passed** |
| Isolated sealed web-only runtime | **14/14 passed** using separate test state; packaged worker startup and one claimed/staged task |
| Focused PDF | **15/15 passed**, including real PDF URI read-back for Gmail fragments and fake credential rejection |
| Final palette review | **19/19 passed** in a real browser; Rename text contrast **4.84:1** and route contrast **3.82:1** after the focused fixes |
| Visual document review | All four pages of the focused email sample and all **nine pages** of the actual merged-UI export were rendered and reviewed without clipping or orphaned actions |

Evidence is retained in `/tmp/detour-merge-final-validation.log`, `/tmp/detour-merged-browser/results.json`, `/tmp/detour-merged-agenda/results.json`, `/tmp/detour-merge-theme/results.json` and `/tmp/detour-merged-final-cold-pdf/results.json`. These are isolated QA scenarios, not another person's saved trip, a mailbox connection or proof of new inventory/booking availability. The UI export `/tmp/detour-merged-browser/merged-guide-with-email.pdf` contains the complete manual QA agenda plus its bookmarked test message.

Run the full check with development stopped, then restart the app for native/browser checks:

```sh
JAC_BIN="$PWD/scripts/jac" bash scripts/validate.sh
bash scripts/dev-studio.sh
# Separate terminal after the app is ready:
workers/.venv/bin/python scripts/qa-studio-merged.py --base http://127.0.0.1:8000 --account
workers/.venv/bin/python scripts/qa-studio-agenda.py --base http://127.0.0.1:8000 --account
workers/.venv/bin/python scripts/test-studio-api.py
```

For cold production-client export, run `scripts/preview-studio.py` after a complete build, then `scripts/test-studio-pdf-offline.py --base http://127.0.0.1:8002` in a separate terminal. Its first PDF export occurs after an offline reload; no model, inbox or existing account is accessed.

The new merge journey creates isolated guest/test-account records. It exercises the light palette, rename cancellation/single-save/Undo, bookmark CRUD and failed-save draft recovery, bookmark-only account import, delayed-save trip isolation, active/inactive deletion and recovery, and saved-day reopening. It never reads a person's existing trip or mailbox.
