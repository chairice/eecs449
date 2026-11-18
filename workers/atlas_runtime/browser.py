"""A clean, bounded research browser. Only observed public pages become evidence."""
from __future__ import annotations

import ipaddress
import json
import os
import re
import socket
import time
from pathlib import Path
from urllib.parse import urlsplit, quote

from server.planning_core import PlanningError, public_url, uid


def allowed_url(url: str) -> bool:
    try:
        host = urlsplit(public_url(url, empty=False)).hostname
        for item in socket.getaddrinfo(host, None):
            if not ipaddress.ip_address(item[4][0]).is_global:
                return False
        return True
    except (ValueError, OSError):
        return False


class ResearchBrowser:
    def __init__(self):
        self.engine = self.browser = self.context = self.page = None
        self.captures: dict[str, dict] = {}
        self.refs = {}
        self.ref_specs = {}

    def start(self):
        if self.page:
            return
        from playwright.sync_api import sync_playwright
        os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(Path(__file__).resolve().parents[1] / ".browsers"))
        self.engine = sync_playwright().start()
        self.browser = self.engine.chromium.launch(headless=True, args=["--disable-dev-shm-usage"])
        self.context = self.browser.new_context(viewport={"width": 1280, "height": 900}, locale="en-US")
        self.context.route("**/*", self._route)
        self.page = self.context.new_page()
        self.page.set_default_timeout(12000)

    @staticmethod
    def _route(route):
        url = route.request.url
        if url.startswith("https://") or url.startswith("http://"):
            if allowed_url(url):
                route.continue_()
                return
        route.abort()

    def capture(self):
        # References are unique for this browser lifetime and bind real elements.
        # A stale reference can fail, but can never silently select a new element.
        for handle in self.refs.values():
            try: handle.dispose()
            except Exception: pass
        self.refs = {}
        self.ref_specs = {}
        self.ref_page_url = self.page.url
        self.ref_generation = getattr(self, "ref_generation", 0) + 1
        prefix = "p" + str(self.ref_generation) + "-"
        controls = self.page.locator("a,button,input,select,textarea,[role=button],[role=gridcell],[role=option],[role=combobox],[role=checkbox],[tabindex='0']").evaluate_all("""(es,prefix)=>es.map((e,i)=>({e,i})).filter(({e})=>{if(getComputedStyle(e).visibility==='hidden')return false;const r=e.getBoundingClientRect();return (r.width>0&&r.height>0)||[...e.querySelectorAll('*')].some(c=>{const r=c.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(c).visibility!=='hidden'})}).sort((a,b)=>{const score=e=>{const r=e.getBoundingClientRect();return (e.closest('[role=dialog],[aria-modal=true],[id*=onetrust],[id*=cookie],[class*=cookie],[class*=consent]')?100:0)+(r.bottom>0&&r.top<innerHeight?10:0)};return score(b.e)-score(a.e)}).slice(0,350).map(({e,i})=>{const ref=prefix+i;e.setAttribute('data-detour-ref',ref);return {ref,tag:e.tagName,text:(e.innerText||e.getAttribute('aria-label')||e.getAttribute('placeholder')||'').slice(0,300),label:e.getAttribute('aria-label')||'',title:e.getAttribute('title')||'',role:e.getAttribute('role')||'',disabled:!!e.disabled||e.getAttribute('aria-disabled')==='true',value:e.value||'',href:e.href||'',type:e.type||'',checked:e.checked,expanded:e.getAttribute('aria-expanded')}})""", prefix)
        for element in self.page.query_selector_all("[data-detour-ref^='" + prefix + "']"):
            ref = element.get_attribute("data-detour-ref")
            self.refs[ref] = element
        self.ref_specs = {control["ref"]: control for control in controls}
        body = self.page.locator("body").inner_text(timeout=15000)[:90000]
        try: structure = self.page.locator("body").aria_snapshot(timeout=4000)[:30000]
        except Exception: structure = ""
        images = self.page.locator("img").evaluate_all("es=>es.filter(e=>e.getBoundingClientRect().width>90 && e.getBoundingClientRect().height>60 && e.naturalWidth>0).slice(0,24).map(e=>({url:e.currentSrc||e.src,alt:e.alt||''}))")
        images = [item for item in images if item["url"].startswith("https://")]
        result = {"captureId": uid("source"), "url": self.page.url, "title": self.page.title(),
                  "observedAt": time.time(), "text": body, "structure": structure, "controls": controls, "images": images}
        self.captures[result["captureId"]] = result
        from server.planning_jobs import data_dir
        folder = data_dir() / "evidence"; folder.mkdir(exist_ok=True, mode=0o700)
        path = folder / (result["captureId"] + ".json")
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            json.dump(result, handle, ensure_ascii=False)
        return {**result, "text": body[:24000], "structure": structure[:16000]}

    def element(self, ref):
        if ref not in self.refs:
            raise PlanningError("That page reference expired. Read the page again.")
        element = self.refs[ref]
        if not element.evaluate("e=>e.isConnected"):
            raise PlanningError("That page control changed. Read the page again.")
        return element

    @staticmethod
    def _same_control(element, spec):
        current = element.evaluate("e=>({tag:e.tagName,role:e.getAttribute('role')||'',label:e.getAttribute('aria-label')||'',text:(e.innerText||e.getAttribute('aria-label')||e.getAttribute('placeholder')||'').slice(0,300),href:e.href||''})")
        clean = lambda value: " ".join(str(value or "").split())
        return all(clean(current.get(key)) == clean(spec.get(key)) for key in ['tag', 'role', 'label', 'text', 'href'])

    def click_target(self, ref):
        """Resolve the observed control again after scroll/layout changes.

        A connected ElementHandle may represent a retired client-rendered widget.
        The exact captured role/name and page scope must still identify one target.
        No fuzzy matching or silent retargeting is allowed.
        """
        element = self.element(ref)
        spec = self.ref_specs.get(ref)
        if not spec or self.page.url != self.ref_page_url or not self._same_control(element, spec):
            raise PlanningError("That page control changed. Read the page again.")
        scroll_target = element if element.is_visible() else next((child for child in element.query_selector_all('*') if child.is_visible()), None)
        if scroll_target is None: raise PlanningError("That control is not visible. Read the page again.")
        scroll_target.scroll_into_view_if_needed()
        self.page.wait_for_timeout(500)
        role = spec.get('role') or {'BUTTON': 'button', 'A': 'link'}.get(spec['tag'], '')
        name = spec.get('label') or spec.get('text') or ''
        if role and name:
            target = self.page.get_by_role(role, name=name, exact=True)
        else:
            target = self.page.locator('[data-detour-ref="' + ref + '"]')
        if target.count() != 1 or not self._same_control(target, spec):
            raise PlanningError("That control changed or is ambiguous. Read the page again.")
        if not target.is_visible():
            children = target.locator('*').all()
            target = next((child for child in children if child.is_visible()), None)
            if target is None: raise PlanningError("That control is not visible. Read the page again.")
        return target, spec

    def call(self, name: str, args: dict):
        try:
            result = self._call(name, args)
            self.trace(name, args, capture_id=result.get("captureId", ""))
            return result
        except Exception as exc:
            self.trace(name, args, error=type(exc).__name__ + ": " + str(exc)[:300])
            raise

    def trace(self, name, args, capture_id="", error=""):
        if os.getenv("PLANNER_CAPTURE_REJECTIONS") != "1": return
        from server.planning_jobs import data_dir
        folder = data_dir() / "evidence"; folder.mkdir(exist_ok=True, mode=0o700)
        if not hasattr(self, "trace_path"): self.trace_path = folder / (uid("actions") + ".jsonl")
        descriptor = os.open(self.trace_path, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
        # Search text may be private; trace only action identifiers and outcomes.
        with os.fdopen(descriptor, "a") as handle:
            handle.write(json.dumps({"at": time.time(), "action": name, "ref": args.get("ref"), "captureId": capture_id, "error": error}) + "\n")

    def _call(self, name: str, args: dict):
        self.start()
        action = None
        if name == "browser_capture":
            source = self.captures.get(args["captureId"])
            if not source: raise PlanningError("That source capture is unavailable.")
            # Old controls are evidence only; current refs must come from read.
            return {**source, "text": source["text"][:30000], "controls": [{k: v for k, v in c.items() if k != "ref"} for c in source["controls"]], "readOnlyCapture": True}
        if name in {"browser_search", "browser_open"}:
            engines = {"google": "https://www.google.com/search?q=", "bing": "https://www.bing.com/search?q=", "duckduckgo": "https://html.duckduckgo.com/html/?q="}
            url = engines.get(args.get("engine", "google"), engines["google"]) + quote(args["query"]) if name == "browser_search" else args["url"]
            if not allowed_url(url):
                raise PlanningError("This source is not an accessible public web address.")
            self.page.goto(url, wait_until="domcontentloaded", timeout=30000)
        elif name == "browser_click":
            element, spec = self.click_target(args["ref"])
            label = ((spec.get("text") or "") + " " + (spec.get("label") or "")).strip().lower()
            # Date-picker confirmation is safe; transaction confirmation is not.
            if re.search(r"\b(pay|purchase|book now|reserve now|confirm booking|confirm reservation|sign in|log in|captcha|robot|verify you are human)\b", label):
                raise PlanningError("Research stops before login, reservation, or payment.")
            before = len(self.context.pages)
            element.click()
            action = {"type": "click", "label": spec.get("label") or spec.get("text"), "tag": spec["tag"],
                      "role": spec.get("role", ""), "expandedBefore": spec.get("expanded"), "urlBefore": self.ref_page_url}
            if len(self.context.pages) > before:
                self.page = self.context.pages[-1]
                self.page.wait_for_load_state("domcontentloaded", timeout=15000)
        elif name == "browser_fill":
            element = self.element(args["ref"])
            field_name = (element.get_attribute("name") or "") + " " + (element.get_attribute("autocomplete") or "")
            if element.get_attribute("type") in {"password", "file", "email", "tel"} or re.search(r"\b(cc-number|cc-csc|cc-exp|given-name|family-name|cardnumber|cvv)\b", field_name.lower()):
                raise PlanningError("Research cannot enter credentials or upload files.")
            if element.evaluate("e=>e.tagName") == "SELECT":
                element.select_option(label=args["value"])
            else:
                value = str(args["value"])[:1000]
                if args.get("sequential") or element.get_attribute("role") == "combobox":
                    element.fill("")
                    element.press_sequentially(value, delay=40)
                else:
                    element.fill(value)
                if args.get("submit"): element.press("Enter")
        elif name == "browser_press":
            key = args["key"]
            if key not in {"Enter", "Escape", "Tab", "ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight", "Home", "End", "Space"}:
                raise PlanningError("Use a supported search-control key.")
            if not args.get("ref") and key == "Escape": self.page.keyboard.press(key)
            else: self.element(args["ref"]).press(key)
        elif name == "browser_scroll":
            self.page.mouse.wheel(0, max(-1600, min(1600, int(args.get("pixels", 700)))))
        elif name == "browser_wait":
            self.page.wait_for_timeout(max(100, min(5000, int(args.get("milliseconds", 1500)))))
        elif name == "browser_screenshot":
            import base64
            result = self.capture()
            data = self.page.screenshot(type="png", full_page=False)
            from server.planning_jobs import data_dir
            path = data_dir() / "evidence" / (result["captureId"] + ".png")
            descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, "wb") as handle: handle.write(data)
            return {**result, "_image": base64.b64encode(data).decode()}
        elif name != "browser_read":
            raise PlanningError("Unknown research action.")
        self.page.wait_for_timeout(800)
        result = self.capture()
        if action:
            matching = [control for control in result["controls"] if control["tag"] == action["tag"] and (control.get("label") or control.get("text")) == action["label"]]
            after = matching[0].get("expanded") if len(matching) == 1 else None
            action["expandedAfter"] = after
            if action["urlBefore"] != self.page.url: action["outcome"] = "NAVIGATED"
            elif action["expandedBefore"] is not None and after is not None:
                action["outcome"] = "CHANGED" if action["expandedBefore"] != after else "NO_CHANGE"
            else: action["outcome"] = "OBSERVE_RESULT"
            result["action"] = action
        return result

    def close(self):
        if self.context:
            self.context.close()
        if self.browser:
            self.browser.close()
        if self.engine:
            self.engine.stop()


def _query(query, location_required=False):
    from server.planning_core import calendar, integer, clock, text
    required = {
        "FLIGHT": ["origin", "destination", "departDate", "adults", "childrenAges"],
        "HOTEL": ["checkIn", "checkOut", "adults", "childrenAges", "rooms"],
        "STAY": ["checkIn", "checkOut", "adults", "childrenAges"],
        "CAR": ["pickupLocation", "dropoffLocation", "pickupDate", "dropoffDate", "pickupTime", "dropoffTime", "driverAge"],
    }.get(query.get("category"))
    if not required or any(key not in query or query[key] in (None, "") for key in required):
        raise PlanningError("The search needs its dates, travelers and required pricing parameters.")
    for key in ["checkIn", "checkOut", "departDate", "returnDate", "pickupDate", "dropoffDate"]:
        if query.get(key): calendar(query[key], key)
    for key in ["adults", "rooms"]:
        if key in query: integer(query[key], key, 1, 99)
    if "childrenAges" in query:
        if not isinstance(query["childrenAges"], list): raise PlanningError("Child ages must be established.")
        for age in query["childrenAges"]: integer(age, "child age", 0, 17)
    if query["category"] == "FLIGHT" and any(not re.fullmatch(r"[A-Z]{3}", str(query[key])) for key in ["origin", "destination"]):
        raise PlanningError("Flight searches need specific IATA airport codes.")
    if query["category"] == "CAR":
        integer(query["driverAge"], "driver age", 18, 100)
        for key in ["pickupTime", "dropoffTime"]: clock(query[key], key)
        for key in ["pickupLocation", "dropoffLocation"]: text(query[key], key, 400, empty=False)
    if query.get("returnDate"): required = [*required, "returnDate"]
    if query["category"] in {"HOTEL", "STAY"} and (location_required or query.get("location")):
        text(query.get("location"), "stay search location", 400, empty=False)
        required = [*required, "location"]
    return required


def _observed(excerpt, corpus):
    return bool(excerpt) and " ".join(excerpt.split()) in " ".join(corpus.split())


def _fact_matches(value, excerpt, key=""):
    """Check literal numeric/search facts, without interpreting provider prose."""
    excerpt = " ".join(excerpt.split())
    if key in {"pickupTime", "dropoffTime"} and isinstance(value, str):
        target = tuple(map(int, value.split(":")))
        tokens = re.findall(r"(?<![\w:])(\d{1,2}):(\d{2})(?::00)?\s*([ap]\.?m\.?)?(?![\w:])", excerpt, re.I)
        for hour, minute, meridian in tokens:
            hour, minute = int(hour), int(minute)
            if minute > 59: continue
            if meridian:
                if not 1 <= hour <= 12: continue
                hour = hour % 12 + (12 if meridian.lower().startswith("p") else 0)
            elif hour > 23: continue
            if (hour, minute) == target: return True
        if target == (12, 0) and re.search(r"\bnoon\b", excerpt, re.I): return True
        if target == (0, 0) and re.search(r"\bmidnight\b", excerpt, re.I): return True
        return False
    if isinstance(value, int):
        if key == "driverAge":
            age_range = re.search(r"(?<!\d)(\d{2})\s*[–—-]\s*(\d{2})(?!\d)", excerpt)
            if age_range and int(age_range[1]) <= value <= int(age_range[2]): return True
            minimum_age = re.search(r"(?<!\d)(\d{2})\s*\+", excerpt)
            if minimum_age and value >= int(minimum_age[1]): return True
        return bool(re.search(r"(?<!\d)" + str(value) + r"(?!\d)", excerpt))
    if isinstance(value, list):
        return all(re.search(r"(?<!\d)" + str(age) + r"(?!\d)", excerpt) for age in value)
    variants = [str(value).lower()]
    if isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        from datetime import date
        target = date.fromisoformat(value)
        years = re.findall(r"(?<!\d)(?:19|20)\d{2}(?!\d)", excerpt)
        if years and str(target.year) not in years: return False
        # Providers compact same-month ranges as “Nov 22–25”. Match the actual
        # day token and month, retaining the model's typed observed-query check.
        month_present = any(re.search(r"\b" + re.escape(target.strftime(fmt).lower()) + r"\b", excerpt.lower()) for fmt in ["%b", "%B"])
        month_tokens = {token[:3].lower() for token in re.findall(r"\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\b", excerpt, re.I)}
        if month_present and len(month_tokens) == 1 and re.search(r"(?<!\d)" + str(target.day) + r"(?!\d)", excerpt): return True
        variants += [target.strftime(pattern).lower() for pattern in ["%b %d, %Y", "%B %d, %Y", "%m/%d/%Y", "%m/%d/%y", "%a, %b %d", "%b %d", "%B %d"]]
        variants += [v.replace(" 0", " ").replace("/0", "/").lstrip("0") for v in variants]
    return any(v in excerpt.lower() for v in variants)


def verified_offers(candidates: list, captures: dict, query: dict | None, components: dict | None = None) -> tuple[list, list]:
    """Retain observed options with honest unit/starting prices and exact searches.

    Every quote has a provider capture, literal price and matching search facts.
    Fee inclusion and a direct booking deep-link are optional, never invented.
    Derived estimates use integer arithmetic over the actual requested quantity.
    """
    from server.planning_core import money_minor, text, integer
    from datetime import date
    accepted, rejected = [], []
    for index, candidate in enumerate(candidates[:12]):
        try:
            search = candidate.get("query") or query
            if not isinstance(search, dict): raise PlanningError("This option needs its search context.")
            new_price = candidate.get("price")
            required = _query(search, location_required=bool(new_price))
            if components:
                component = components.get(candidate.get("componentId"))
                if not component or not isinstance(component.get("query"), dict):
                    raise PlanningError("This option needs its declared search component.")
                for key, requested in component["query"].items():
                    if key in {"notes", "query"}: continue
                    actual = search.get(key)
                    if isinstance(requested, str) and isinstance(actual, str):
                        matched = " ".join(requested.lower().split()) == " ".join(actual.lower().split())
                    else: matched = requested == actual
                    if not matched: raise PlanningError("This option differs from the declared search " + key + ".")
            source = captures.get(candidate.get("captureId"))
            if not source or any(domain in source["url"] for domain in ["google.com/search", "bing.com/search"]):
                raise PlanningError("A real provider result page was not observed.")
            corpus = source["text"] + "\n" + source.get("structure", "") + "\n" + "\n".join(str(c.get("value", "")) + " " + str(c.get("label", "")) for c in source["controls"])
            if new_price is not None and not isinstance(new_price, dict): raise PlanningError("The option needs a structured price basis.")
            price = new_price or {"amount": candidate.get("total"), "basis": "TOTAL", "from": False, "feesIncluded": True}
            amount = money_minor(str(price.get("amount", candidate.get("total", ""))))
            excerpt = text(candidate.get("priceExcerpt", candidate.get("totalExcerpt")), "price excerpt", 2000, empty=False)
            if not _observed(excerpt, corpus): raise PlanningError("The price excerpt was not observed.")
            tokens = re.findall(r"(?:US\$|CA\$|AU\$|[$€£])\s*(\d[\d,]*(?:\.\d{1,2})?)|(\d[\d,]*(?:\.\d{1,2})?)\s*(?:USD|CAD|AUD|EUR|GBP|U\.?S\.?\s*dollars?)\b", excerpt, re.I)
            displayed = [left or right for left, right in tokens]
            if amount not in [money_minor(n.replace(",", "")) for n in displayed]:
                raise PlanningError("The amount does not match the displayed price.")
            availability = candidate.get("availabilityExcerpt", "")
            if availability and not _observed(availability, corpus): raise PlanningError("The availability excerpt was not observed.")
            if re.search(r"\b(not available|unavailable|sold out|no availability)\b", availability, re.I):
                raise PlanningError("The provider says this option is unavailable.")
            if new_price:
                name = text(candidate.get("nameExcerpt"), "option name excerpt", 2000, empty=False)
                if not _observed(name, corpus): raise PlanningError("The option name was not observed.")
            source_host = urlsplit(source["url"]).hostname.lower()
            facts = candidate.get("queryEvidence", {})
            if not isinstance(facts, dict): raise PlanningError("Search evidence must map fields to observed excerpts.")
            observed = candidate.get("observedQuery", search if not new_price else {})
            if not isinstance(observed, dict): raise PlanningError("The observed search needs structured fields.")
            for key in required:
                value = search[key]
                if observed.get(key) != value: raise PlanningError("The observed dates or travelers differ from the request.")
                if value == []: continue  # A one-adult setting need not separately print zero children.
                fact = facts.get(key, "")
                single_unit = key == "rooms" and value == 1 and (source_host == "airbnb.com" or source_host.endswith(".airbnb.com")) and candidate.get("roomBasis") == "SINGLE_LISTING"
                if not isinstance(fact, str) or not fact or not _observed(fact, corpus) or not (_fact_matches(value, fact, key) or single_unit):
                    raise PlanningError("The provider did not establish the requested " + key + ".")
            basis = price.get("basis", "TOTAL")
            if basis not in {"TOTAL", "PER_PERSON", "PER_NIGHT", "PER_DAY"}: raise PlanningError("Unknown price basis.")
            if not isinstance(price.get("from", False), bool): raise PlanningError("Starting-price flag must be true or false.")
            fees = price.get("feesIncluded")
            if fees is not None and not isinstance(fees, bool): raise PlanningError("Fee inclusion must be true, false or null.")
            fee_excerpt = candidate.get("feesExcerpt", "")
            if fees is True:
                if not fee_excerpt or not _observed(fee_excerpt, corpus) or re.search(r"\b(excludes?|excluding|not included|pay at property|due at property)\b", fee_excerpt, re.I) or not re.search(r"\b(includes?|including|included|inclusive|all-in)\b", fee_excerpt, re.I):
                    raise PlanningError("Fee inclusion needs an observed statement; use feesIncluded null when unknown.")
            elif fees not in (None, False): raise PlanningError("Invalid fee inclusion.")
            currency = text(price.get("currency", candidate.get("currency", "USD")), "currency", 3, empty=False).upper()
            if not re.fullmatch(r"[A-Z]{3}", currency): raise PlanningError("Use an ISO currency code.")
            price_codes = set(re.findall(r"(?<![A-Z])(?:USD|CAD|AUD|NZD|EUR|GBP)(?![A-Z])", excerpt.upper()))
            if price_codes and currency not in price_codes: raise PlanningError("The quoted currency differs from the displayed price currency.")
            currency_excerpt = candidate.get("currencyExcerpt", "")
            if not _observed(currency_excerpt, corpus): raise PlanningError("The currency excerpt was not observed.")
            explicit_currency = bool(re.search(r"(?<![A-Z])" + re.escape(currency) + r"(?![A-Z])", currency_excerpt, re.I))
            if currency == "USD":
                explicit_currency = explicit_currency or bool(re.search(r"US\$|\bU\.?S\.?\s*DOLLARS?\b", currency_excerpt, re.I))
            if not explicit_currency:
                codes = set(re.findall(r"(?<![A-Z])(?:USD|CAD|AUD|NZD|EUR|GBP)(?![A-Z])", corpus.upper()))
                selected_currency = any(re.search(r"(?:CURRENCY|SELECTED CURRENCY)[\s\u200b:–-]*" + re.escape(currency) + r"\b", str(control.get("text", "")) + " " + str(control.get("label", "")) + " " + str(control.get("value", "")), re.I) for control in source["controls"])
                symbol = {"USD": "$", "CAD": "$", "AUD": "$", "NZD": "$", "EUR": "€", "GBP": "£"}.get(currency)
                if not symbol or symbol not in currency_excerpt or not (selected_currency or codes == {currency}):
                    raise PlanningError("The displayed currency needs its actual source currency code or selected currency control.")
            if basis == "PER_NIGHT":
                quantity = (date.fromisoformat(search["checkOut"]) - date.fromisoformat(search["checkIn"])).days * search.get("rooms", 1)
            elif basis == "PER_PERSON": quantity = search.get("adults", 1) + len(search.get("childrenAges", []))
            elif basis == "PER_DAY":
                from datetime import datetime
                duration = datetime.fromisoformat(search["dropoffDate"] + "T" + search["dropoffTime"]) - datetime.fromisoformat(search["pickupDate"] + "T" + search["pickupTime"])
                quantity = max(1, (int(duration.total_seconds()) + 86399) // 86400)
            else: quantity = 1
            integer(quantity, "price quantity", 1, 10000)
            if "quantity" in price and price["quantity"] != quantity: raise PlanningError("The price calculation uses the wrong quantity.")
            try: link = public_url(candidate.get("bookingUrl") or source["url"], empty=False)
            except PlanningError: link = public_url(source["url"], empty=False)
            if link != source["url"] and not any(c.get("href") == link for c in source["controls"]):
                # Keep the genuine option; a guessed/deep link never replaces
                # the already observed, usable provider results/property page.
                link = public_url(source["url"], empty=False)
            host = urlsplit(source["url"]).hostname.lower().removeprefix("www.")
            brands = {"airbnb.com": "Airbnb", "booking.com": "Booking.com", "expedia.com": "Expedia", "hertz.com": "Hertz", "avis.com": "Avis", "enterprise.com": "Enterprise", "kayak.com": "KAYAK", "southwest.com": "Southwest", "delta.com": "Delta", "united.com": "United", "aa.com": "American Airlines", "google.com": "Google Travel", "hilton.com": "Hilton", "marriott.com": "Marriott"}
            brand = next((name for domain, name in brands.items() if host == domain or host.endswith("." + domain)), host)
            photo = candidate.get("photoUrl", "")
            if not any(image.get("url") == photo for image in source.get("images", [])): photo = ""
            canonical = {"amountMinor": amount, "currency": currency, "basis": basis, "from": bool(price.get("from", False)), "quantity": quantity,
                         "estimatedTotalMinor": amount * quantity if basis != "TOTAL" else None, "feesIncluded": fees}
            offer = {"id": uid("offer"), "componentId": candidate.get("componentId", ""), "category": search["category"], "title": text(candidate.get("title"), "offer title", 400, empty=False),
                "provider": brand, "providerHost": host, "photoUrl": photo, "price": canonical, "currency": currency, "bookingUrl": link,
                "observedAt": source["observedAt"], "query": search, "evidence": candidate, "sourceUrl": source["url"],
                "details": text(candidate.get("details", ""), "offer details", 3000), "location": text(candidate.get("location", ""), "offer location", 400)}
            if basis == "TOTAL" and fees is True and not canonical["from"]: offer["totalMinor"] = amount
            if isinstance(candidate.get("flight"), dict):
                flight_excerpt = candidate.get("flightExcerpt", "")
                if not flight_excerpt or not _observed(flight_excerpt, corpus):
                    raise PlanningError("Flight times/stops need an observed flight excerpt.")
                flight = candidate["flight"]
                for key in ["departDate", "arriveDate"]:
                    if flight.get(key):
                        from server.planning_core import calendar
                        calendar(flight[key], key)
                if flight.get("airline"): text(flight["airline"], "airline", 200)
                for key in ["departTime", "arriveTime"]:
                    if flight.get(key):
                        from server.planning_core import clock
                        clock(flight[key], key)
                if flight.get("stops") is not None: integer(flight["stops"], "flight stops", 0, 6)
                if flight.get("durationMinutes") is not None: integer(flight["durationMinutes"], "flight duration", 1, 3000)
                flight = dict(flight)
                if flight.get("segments"):
                    from .flight_journey import normalized_segments, complete_flight
                    segments = normalized_segments(flight["segments"], flight, search, corpus, source["url"])
                    flight = complete_flight(flight, segments)
                offer["flight"] = flight
            accepted.append(offer)
        except (PlanningError, KeyError, TypeError, ValueError) as exc:
            rejected.append("Option " + str(index + 1) + ": " + str(exc))
            if os.getenv("PLANNER_CAPTURE_REJECTIONS") == "1":
                from server.planning_jobs import data_dir
                folder = data_dir() / "evidence"; folder.mkdir(exist_ok=True, mode=0o700)
                path = folder / (uid("candidate") + ".json")
                descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                with os.fdopen(descriptor, "w") as handle: json.dump({"candidate": candidate, "reason": str(exc)}, handle)
    return accepted, rejected
