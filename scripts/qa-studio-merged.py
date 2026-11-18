#!/usr/bin/env python3
"""Merged studio acceptance with isolated guest/account data and mocked tiles.

No model, real inbox, existing account or public tile-server access. Optional
--account creates a new local QA account and exercises real protected endpoints.
"""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "web"), str(ROOT / "scripts")]
from server.planning_api import fresh
from qa_map_tiles import mock_map_tiles
from playwright.sync_api import sync_playwright

os.environ["PLAYWRIGHT_BROWSERS_PATH"] = str(ROOT / "workers/.browsers")
spec = importlib.util.spec_from_file_location("agenda_qa", ROOT / "scripts/qa-studio-agenda.py")
agenda = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agenda)
STATE = """(()=>{let keys=Object.keys(localStorage).filter(k=>k.startsWith('atlas.studio.v1.')&&k!=='atlas.studio.v1.guest');let key=localStorage.getItem('jac_token')?keys[0]:'atlas.studio.v1.guest';return JSON.parse(localStorage.getItem(key)||'null')})()"""
GMAIL = "https://mail.google.com/mail/u/0/#inbox/QA-message-only"
OUTLOOK = "https://outlook.office.com/mail/inbox/id/QA-message-only#conversation"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    parser.add_argument("--output", type=Path, default=Path("/tmp/detour-merged-browser"))
    parser.add_argument("--account", action="store_true")
    args = parser.parse_args()
    address = urlparse(args.base)
    if address.scheme != "http" or address.hostname not in {"localhost", "127.0.0.1"}:
        parser.error("Use a local HTTP app; this check creates isolated QA records.")
    args.output.mkdir(parents=True, exist_ok=True)
    checks, errors, origins, rename_requests = {}, [], {}, []

    def check(name, value):
        assert value, name
        checks[name] = True
        print("PASS", name, flush=True)

    def envelope(value):
        return {"ok": True, "type": "response", "data": {"result": json.dumps(value), "reports": []}, "error": None}

    def prepare(page):
        page.on("pageerror", lambda error: errors.append(str(error)))
        def requested(request):
            if "/function/" in request.url:
                origins[id(page)] = request.url.split("/function/")[0]
            if request.method == "POST" and request.url.endswith("/planner_guest_rename"):
                rename_requests.append(request.post_data_json)
        page.on("request", requested)
        mock_map_tiles(page)
        def auxiliary(route):
            name = route.request.url.rsplit("/", 1)[-1]
            if name.endswith("weather"):
                value = {"status": "UNAVAILABLE", "samples": []}
            else:
                body = route.request.post_data_json
                trip_id = body.get("trip_id") or json.loads(body.get("state_json", "{}")).get("id", "")
                value = {"tripId": trip_id, "locations": [], "pending": False}
            route.fulfill(status=200, content_type="application/json", body=json.dumps(envelope(value)))
        for name in ["planner_guest_weather", "planner_weather", "planner_guest_media", "planner_media"]:
            page.route("**/function/" + name, auxiliary)

    def read(page):
        return page.evaluate(STATE)

    def wait_state(page, condition, value=None):
        page.wait_for_function("arg=>{let s=" + STATE + ";return s && (" + condition + ")}", arg=value, timeout=30000)

    def seed(page, state):
        page.goto(args.base + "/studio", wait_until="networkidle")
        page.wait_for_selector("#studio-prompt")
        page.evaluate("([s,cap])=>{localStorage.setItem('atlas.studio.v1.guest',JSON.stringify(s));localStorage.setItem('atlas.guest.capability.v1',cap);localStorage.setItem('atlas.studio.view.v1.'+s.id,JSON.stringify({pane:'overview',phoneTab:'trip'}))}", [state, "guest_" + secrets.token_hex(32)])
        page.reload(wait_until="networkidle")
        page.wait_for_selector("#studio-prompt")

    def confirmations(page):
        page.get_by_role("button", name=re.compile(r"^Confirmations")).first.click()
        page.get_by_role("heading", name="Confirmations", exact=True).wait_for()

    def rename(page, title):
        page.locator('button[title="Rename this trip"]:visible').first.click()
        page.get_by_label("Trip name", exact=True).fill(title)
        page.get_by_label("Trip name", exact=True).press("Enter")
        wait_state(page, "s.snapshot.title===arg", title)

    def library(page, deleted=False):
        button = page.get_by_role("button", name="Your trips", exact=True)
        if button.get_attribute("aria-expanded") != "true":
            button.click()
        if deleted:
            control = page.get_by_role("button", name="Recently Deleted", exact=True)
            if control.count(): control.click()
        else:
            back = page.get_by_role("button", name="← Your trips", exact=True)
            if back.count(): back.click()

    def rpc(page, name, payload):
        return page.evaluate("""async ([origin,name,payload])=>{
          const token=localStorage.getItem('jac_token');
          const response=await fetch(origin+'/function/'+name,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(payload)});
          const envelope=await response.json();if(!response.ok||!envelope.ok)throw new Error('QA RPC rejected: '+name);
          const result=envelope.data.result;return typeof result==='string'?JSON.parse(result):result;
        }""", [origins.get(id(page), args.base), name, payload])

    def manual(title):
        state = agenda.fixture(manual=True, title=title)
        for place in state["snapshot"]["places"]:
            place["photoUrl"] = ""
        return state

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            context = browser.new_context(viewport={"width": 1440, "height": 1000}, reduced_motion="reduce", color_scheme="dark", accept_downloads=True)
            page = context.new_page(); prepare(page)
            page.add_init_script("localStorage.setItem('detour.theme.v1','dark')")
            page.goto(args.base + "/", wait_until="networkidle")
            check("landing_palette_stays_light", page.locator("html").get_attribute("data-theme") == "light")
            state = manual("QA merged guide")
            seed(page, state)
            check("studio_matches_landing_even_with_old_dark_preference", page.locator("html").get_attribute("data-theme") == "light")
            page.screenshot(path=str(args.output / "merged-studio-overview.png"))
            initial = copy.deepcopy(read(page)["snapshot"])
            page.locator('button[title="Rename this trip"]:visible').first.click()
            page.get_by_label("Trip name", exact=True).fill("This rename was cancelled")
            page.get_by_label("Trip name", exact=True).press("Escape")
            page.wait_for_timeout(150)
            check("escape_rename_does_not_save_or_change_title", not rename_requests and read(page)["snapshot"] == initial)
            before = read(page)
            rename(page, "QA renamed guide")
            renamed = read(page)
            check("enter_rename_saves_once", len(rename_requests) == 1 and renamed["revision"] == before["revision"] + 1)
            check("rename_keeps_all_agenda_records", all(renamed["snapshot"][key] == initial[key] for key in initial if key != "title"))
            page.get_by_role("button", name="Undo last trip change", exact=True).click()
            wait_state(page, "s.snapshot.title===arg", initial["title"])
            check("guest_rename_undo_restores_exact_snapshot", read(page)["snapshot"] == initial)
            confirmations(page)
            before = read(page)
            page.get_by_label("Nickname", exact=True).fill("Hotel confirmation")
            page.get_by_label("Email link", exact=True).fill(GMAIL)
            page.get_by_role("button", name="Add confirmation", exact=True).click()
            wait_state(page, "s.confirmations?.length===1")
            saved = read(page)
            check("email_bookmark_keeps_gmail_message_fragment", saved["confirmations"][0]["link"] == GMAIL)
            check("email_save_does_not_change_plan_revision_or_undo", all(saved[key] == before[key] for key in ["snapshot", "revision", "undo", "undoHistory"]))
            check("email_link_is_real_navigation_not_booking", page.get_by_role("link", name="Open Hotel confirmation email in a new tab").get_attribute("href") == GMAIL and not saved["snapshot"]["bookings"])
            page.locator("#studio-prompt").fill("QA unsent message must remain private to the composer.")
            with page.expect_download(timeout=30000) as pending_download:
                page.get_by_role("button", name="Export PDF", exact=True).click()
            exported = args.output / "merged-guide-with-email.pdf"
            pending_download.value.save_as(str(exported))
            from pypdf import PdfReader
            pdf = PdfReader(exported)
            contents = "\n".join(pdf_page.extract_text() or "" for pdf_page in pdf.pages)
            destinations = [str(annotation.get_object().get("/A", {}).get("/URI", "")) for pdf_page in pdf.pages for annotation in pdf_page.get("/Annots", [])]
            check("actual_pdf_from_email_view_contains_whole_plan_and_bookmark", all(text in contents for text in ["Important emails", "Hotel confirmation", "Team bike day", "Group bike pickup"]))
            check("actual_pdf_preserves_email_message_destination", GMAIL in destinations)
            check("export_keeps_draft_and_does_not_export_chat", page.locator("#studio-prompt").input_value() == "QA unsent message must remain private to the composer." and "QA unsent message" not in contents)
            page.reload(wait_until="networkidle"); confirmations(page)
            check("guest_email_survives_reload", page.get_by_role("link", name="Open Hotel confirmation email in a new tab").count() == 1)
            page.get_by_role("button", name="Edit Hotel confirmation", exact=True).click()
            page.get_by_label("Nickname", exact=True).fill("Work invitation")
            page.get_by_label("Email link", exact=True).fill(OUTLOOK)
            page.get_by_role("button", name="Save changes", exact=True).click()
            wait_state(page, "s.confirmations?.[0]?.nickname==='Work invitation'")
            check("bookmark_edit_preserves_outlook_anchor", read(page)["confirmations"][0]["link"] == OUTLOOK)
            page.get_by_role("button", name="Remove Work invitation", exact=True).click()
            wait_state(page, "s.confirmations?.length===0")
            check("bookmark_removal_persisted", not read(page)["confirmations"])
            page.route("**/function/planner_guest_confirmations", lambda route: route.fulfill(status=200, content_type="application/json", body=json.dumps(envelope({"error": "Controlled QA save failure"}))), times=1)
            page.get_by_label("Nickname", exact=True).fill("Unsent bookmark")
            page.get_by_label("Email link", exact=True).fill(GMAIL)
            page.get_by_role("button", name="Add confirmation", exact=True).click()
            page.get_by_role("alert").wait_for()
            check("failed_bookmark_save_keeps_draft", page.get_by_label("Nickname", exact=True).input_value() == "Unsent bookmark" and page.get_by_label("Email link", exact=True).input_value() == GMAIL and not read(page)["confirmations"])
            page.get_by_role("button", name="Dismiss error", exact=True).click()
            page.set_viewport_size({"width": 390, "height": 844})
            check("phone_bookmark_form_has_no_horizontal_overflow", page.evaluate("document.documentElement.scrollWidth<=innerWidth"))
            page.screenshot(path=str(args.output / "merged-confirmations-phone.png"))
            page.set_viewport_size({"width": 1440, "height": 1000})
            page.goto(args.base + "/plan", wait_until="networkidle")
            check("legacy_pages_keep_dark_preference", page.locator("html").get_attribute("data-theme") == "dark")
            context.close()

            if args.account:
                context = browser.new_context(viewport={"width": 1440, "height": 1000}, reduced_motion="reduce", accept_downloads=True)
                page = context.new_page(); prepare(page)
                empty = fresh(); seed(page, empty); confirmations(page)
                page.get_by_label("Nickname", exact=True).fill("Only saved email")
                page.get_by_label("Email link", exact=True).fill(GMAIL)
                page.get_by_role("button", name="Add confirmation", exact=True).click()
                wait_state(page, "s.confirmations?.length===1")
                check("bookmark_only_guest_has_export_available", page.get_by_role("button", name="Export PDF", exact=True).is_enabled())
                rename(page, "QA bookmarked trip A")
                page.locator(".studio-account-button").click()
                page.get_by_role("button", name="New here? Create an account", exact=True).click()
                email = "detour-merge-qa-" + secrets.token_hex(8) + "@example.invalid"
                page.get_by_label("Email", exact=True).fill(email)
                page.get_by_label("Password", exact=True).fill(secrets.token_urlsafe(24))
                page.get_by_role("button", name="Create account & save trip", exact=True).click()
                page.get_by_role("button", name="Sign out", exact=True).wait_for(timeout=30000)
                wait_state(page, "s.confirmations?.length===1")
                first = read(page)
                check("bookmark_only_guest_import_keeps_email", first["id"] == empty["id"] and first["confirmations"][0]["link"] == GMAIL)
                second = manual("QA planned trip B")
                imported = rpc(page, "planner_import", {"state_json": json.dumps(second), "token": ""})
                check("owned_second_trip_imported", imported["id"] == second["id"])
                library(page);page.get_by_role("button", name=second["snapshot"]["title"] + " →", exact=True).click()
                wait_state(page, "s.id===arg", second["id"])
                page.locator('[data-plan-item="bike-day"]').click();page.wait_for_selector(".studio-day-detail")
                library(page);page.get_by_role("button", name=first["snapshot"]["title"] + " →", exact=True).click()
                wait_state(page, "s.id===arg", first["id"]); confirmations(page)
                page.get_by_role("button", name="Edit Only saved email", exact=True).click()
                page.get_by_label("Nickname", exact=True).fill("Delayed trip A response")
                pending = []
                def delay(route):
                    response = route.fetch()
                    pending.append((route, response))
                page.route("**/function/planner_confirmations", delay, times=1)
                page.get_by_role("button", name="Save changes", exact=True).click()
                page.wait_for_timeout(300)
                assert pending, "Expected one controlled delayed save"
                library(page);page.get_by_role("button", name=second["snapshot"]["title"] + " →", exact=True).click()
                wait_state(page, "s.id===arg", second["id"])
                check("trip_switch_restores_planned_day", page.locator(".studio-day-detail").count() == 1)
                pending[0][0].fulfill(response=pending[0][1]);page.wait_for_timeout(250)
                check("late_bookmark_response_does_not_change_other_trip", read(page)["id"] == second["id"] and not read(page).get("confirmations"))
                confirmations(page)
                check("bookmark_draft_does_not_leak_between_trips", page.get_by_label("Nickname", exact=True).input_value() == "" and page.get_by_label("Email link", exact=True).input_value() == "")
                confirmed = rpc(page, "planner_get", {"trip_id": first["id"]})
                check("delayed_save_still_persists_to_original_trip", confirmed["confirmations"][0]["nickname"] == "Delayed trip A response")
                library(page);page.get_by_role("button", name="Delete " + first["snapshot"]["title"], exact=True).click()
                page.wait_for_timeout(350)
                check("deleting_inactive_trip_keeps_current_trip", read(page)["id"] == second["id"])
                library(page, deleted=True)
                row = page.locator(".studio-library-row").filter(has_text=first["snapshot"]["title"])
                row.get_by_role("button", name="Restore", exact=True).click();page.wait_for_timeout(350)
                restored = rpc(page, "planner_get", {"trip_id": first["id"]})
                check("recently_deleted_restore_keeps_email_and_current_trip", restored["confirmations"][0]["nickname"] == "Delayed trip A response" and read(page)["id"] == second["id"])
                library(page)
                page.get_by_role("button", name="Close your trips", exact=True).click()
                page.get_by_role("button", name="Your trip", exact=True).click()
                page.locator('[data-plan-item="bike-day"]').click() if page.locator(".studio-day-detail").count() == 0 else None
                library(page);page.get_by_role("button", name="Delete " + second["snapshot"]["title"], exact=True).click()
                wait_state(page, "s.id!==arg", second["id"])
                check("deleting_active_trip_opens_new_draft", read(page)["id"] not in {first["id"], second["id"]})
                page.get_by_role("button", name="Undo", exact=True).click()
                wait_state(page, "s.id===arg", second["id"])
                check("deletion_undo_restores_exact_trip_and_day", read(page)["snapshot"] == imported["snapshot"] and page.locator(".studio-day-detail").count() == 1)
                page.reload(wait_until="networkidle");page.wait_for_selector(".studio-day-detail")
                check("restored_day_survives_account_reload", read(page)["id"] == second["id"])
                page.screenshot(path=str(args.output / "merged-account-restored-day.png"))
                context.close()
            check("no_uncaught_browser_errors", not errors)
        finally:
            (args.output / "results.json").write_text(json.dumps({"checks": checks, "errors": errors, "mapTiles": "Labelled local SVG fixture; no OSM network access.", "modelOrInboxAccess": False}, indent=2))
            browser.close()
    print(json.dumps({"passed": len(checks), "errors": errors, "output": str(args.output)}))


if __name__ == "__main__":
    main()
