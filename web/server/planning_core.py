"""Pure wire validation and proposal semantics for the Jac trip domain.

No model calls, database access, or natural-language parsing occurs here. Both
the worker and Jac's transactional endpoints use these structural invariants.
"""
from __future__ import annotations

import copy
import hashlib
import ipaddress
import json
import math
import re
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


class PlanningError(ValueError):
    """A recoverable domain conflict or invalid boundary payload."""


def uid(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex}"


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def dumps(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":"))


def loads(raw: str, maximum: int = 2_000_000) -> object:
    if not isinstance(raw, str) or len(raw.encode()) > maximum:
        raise PlanningError("This planning request is too large.")
    try:
        return json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Non-finite number")))
    except (ValueError, TypeError) as exc:
        raise PlanningError("The planning data is not valid JSON.") from exc


def text(value: object, field: str, maximum: int = 4000, *, empty: bool = True) -> str:
    if not isinstance(value, str) or len(value) > maximum or (not empty and not value.strip()):
        raise PlanningError(f"Invalid {field}.")
    return value.strip()


def identifier(value: object, field: str = "item ID") -> str:
    result = text(value, field, 160, empty=False)
    if any(ord(ch) < 32 for ch in result):
        raise PlanningError(f"Invalid {field}.")
    return result


def calendar(value: object, field: str) -> str:
    result = text(value, field, 10)
    if result:
        try:
            if date.fromisoformat(result).isoformat() != result:
                raise ValueError()
        except ValueError as exc:
            raise PlanningError(f"Use a real ISO calendar date for {field}.") from exc
    return result


def clock(value: object, field: str) -> str:
    result = text(value, field, 5)
    if result and not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", result):
        raise PlanningError(f"Use a local 24-hour time for {field}.")
    return result


def integer(value: object, field: str, low: int = 0, high: int = 10**12, *, nullable: bool = False) -> int | None:
    if nullable and value is None:
        return None
    if type(value) is not int or not low <= value <= high:
        raise PlanningError(f"Invalid {field}.")
    return value


def sequence(value: object, field: str, maximum: int = 1000) -> list:
    if not isinstance(value, list) or len(value) > maximum:
        raise PlanningError(f"Invalid {field}.")
    return value


def record(value: object, field: str) -> dict:
    if not isinstance(value, dict):
        raise PlanningError(f"Invalid {field}.")
    return value


def choice(value: object, allowed: set[str], field: str) -> str:
    if value not in allowed:
        raise PlanningError(f"Invalid {field}.")
    return str(value)


def public_url(value: object, *, empty: bool = True) -> str:
    result = text(value, "source link", 4096, empty=empty)
    if not result:
        return ""
    try:
        parsed = urlsplit(result)
        if parsed.scheme not in {"https", "http"} or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError()
        if parsed.hostname.lower() in {"localhost", "0.0.0.0", "127.0.0.1", "::1"}:
            raise ValueError()
        host = parsed.hostname.lower()
        if host.endswith((".localhost", ".local", ".internal", ".lan")):
            raise ValueError()
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            address = None
        if address is not None and not address.is_global:
            raise ValueError()
    except ValueError as exc:
        raise PlanningError("Use a public provider or source link.") from exc
    return result


def blank_trip(trip_id: str | None = None) -> dict:
    return {
        "schemaVersion": 1, "id": trip_id or uid("trip"), "title": "Untitled trip",
        "intent": "VACATION", "detail": "OUTLINE", "startDate": "", "endDate": "",
        "timezone": "America/Detroit", "party": {"adults": None, "childrenAges": [], "rooms": None, "driverAge": None},
        "budget": {"amountMinor": None, "currency": "USD", "hard": False},
        "places": [], "stays": [], "legs": [], "rentals": [], "days": [], "bookings": [],
        "constraints": [], "unresolved": [], "notes": "",
    }


def validate_trip(raw: object) -> dict:
    """Normalize partial plans while rejecting disconnected/invalid structures."""
    value = record(copy.deepcopy(raw), "trip")
    base = blank_trip(identifier(value.get("id"), "trip ID"))
    unknown = set(value) - set(base)
    if unknown:
        raise PlanningError("Unknown trip fields: " + ", ".join(sorted(unknown)))
    base.update(value)
    if base["schemaVersion"] != 1:
        raise PlanningError("Unsupported trip version.")
    base["title"] = text(base["title"], "trip title", 160, empty=False)
    base["intent"] = choice(base["intent"], {"VACATION", "BUSINESS", "MIXED"}, "trip intent")
    base["detail"] = choice(base["detail"], {"LOGISTICS", "OUTLINE", "DETAILED"}, "planning depth")
    base["startDate"] = calendar(base["startDate"], "trip start")
    base["endDate"] = calendar(base["endDate"], "trip end")
    if base["startDate"] and base["endDate"] and base["endDate"] < base["startDate"]:
        raise PlanningError("The trip ends before it starts.")
    base["timezone"] = text(base["timezone"], "trip time zone", 100, empty=False)
    base["notes"] = text(base["notes"], "trip notes", 40000)
    party = record(base["party"], "travelers")
    base["party"] = {
        "adults": integer(party.get("adults"), "adult count", 1, 99, nullable=True),
        "childrenAges": [integer(age, "child age", 0, 17) for age in sequence(party.get("childrenAges", []), "children", 20)],
        "rooms": integer(party.get("rooms"), "rooms", 1, 30, nullable=True),
        "driverAge": integer(party.get("driverAge"), "driver age", 18, 100, nullable=True),
    }
    budget = record(base["budget"], "budget")
    base["budget"] = {"amountMinor": integer(budget.get("amountMinor"), "budget amount", nullable=True),
                      "currency": text(budget.get("currency", "USD"), "budget currency", 3, empty=False).upper(),
                      "hard": bool(budget.get("hard", False))}
    ids: set[str] = set()

    def claim(item: dict, kind: str) -> None:
        item["id"] = identifier(item.get("id"), kind + " ID")
        if item["id"] in ids:
            raise PlanningError("Duplicate item ID: " + item["id"])
        ids.add(item["id"])

    places = sequence(base["places"], "places", 600)
    for place in places:
        record(place, "place"); claim(place, "place")
        place["query"] = text(place.get("query", place.get("label", "")), "place query", 400, empty=False)
        place["label"] = text(place.get("label", place["query"]), "place label", 400, empty=False)
        place["kind"] = choice(place.get("kind", "PLACE"), {"CITY", "AIRPORT", "PLACE", "PROPERTY", "PARK"}, "place kind")
        for field, maximum in [("lat", 90), ("lon", 180)]:
            number = place.get(field)
            if number is not None and (type(number) not in {int, float} or not math.isfinite(number) or abs(number) > maximum):
                raise PlanningError("Invalid place coordinates.")
            place[field] = number
        if (place["lat"] is None) != (place["lon"] is None):
            raise PlanningError("A place needs both coordinates or neither.")
        place["timezone"] = text(place.get("timezone", ""), "place time zone", 100)
        place["sourceUrl"] = public_url(place.get("sourceUrl", ""))
        place["photoUrl"] = public_url(place.get("photoUrl", ""))
        for key in ["photoSourceUrl"]:
            place[key] = public_url(place.get(key, ""))
        for key in ["photoAttribution", "photoLicense", "photoTitle", "address"]:
            place[key] = text(place.get(key, ""), key, 1000)
    place_ids = {p["id"] for p in places}

    def place_ref(item: dict, field: str, required: bool = False) -> None:
        ref = item.get(field, "") or ""
        if (required and not ref) or (ref and ref not in place_ids):
            raise PlanningError(f"{field} refers to a missing place.")
        item[field] = ref

    stays = sequence(base["stays"], "overnight stays", 400)
    for stay in stays:
        record(stay, "stay"); claim(stay, "stay"); place_ref(stay, "placeId", True)
        for field in ["checkIn", "checkOut"]:
            stay[field] = calendar(stay.get(field, ""), field)
        if stay["checkIn"] and stay["checkOut"] and stay["checkOut"] <= stay["checkIn"]:
            raise PlanningError("Check-out must be after check-in.")
        stay["propertyName"] = text(stay.get("propertyName", ""), "property name", 400)
        stay["status"] = choice(stay.get("status", "UNPLANNED"), {"UNPLANNED", "SELECTED", "BOOKED"}, "stay status")
        stay["locked"] = bool(stay.get("locked", False) or stay["status"] == "BOOKED" or stay.get("bookingId"))
        stay["offerId"] = text(stay.get("offerId", ""), "offer reference", 160)
        stay["bookingId"] = text(stay.get("bookingId", ""), "booking reference", 160)
        stay["notes"] = text(stay.get("notes", ""), "stay notes", 4000)

    legs = sequence(base["legs"], "travel legs", 600)
    for leg in legs:
        record(leg, "travel leg"); claim(leg, "travel leg")
        place_ref(leg, "fromId", True); place_ref(leg, "toId", True)
        if leg["fromId"] == leg["toId"]:
            raise PlanningError("A travel leg must connect different places.")
        leg["mode"] = choice(leg.get("mode", "UNKNOWN"), {"FLIGHT", "DRIVE", "TRANSIT", "WALK", "UNKNOWN"}, "travel mode")
        for field in ["departDate", "arriveDate"]:
            leg[field] = calendar(leg.get(field, ""), field)
        for field in ["departTime", "arriveTime"]:
            leg[field] = clock(leg.get(field, ""), field)
        if leg["departDate"] and leg["arriveDate"] and leg["arriveDate"] < leg["departDate"]:
            raise PlanningError("Travel arrival precedes departure.")
        leg["durationMinutes"] = integer(leg.get("durationMinutes"), "travel duration", 0, 100000, nullable=True)
        leg["notes"] = text(leg.get("notes", ""), "travel notes", 4000)
        leg["locked"] = bool(leg.get("locked", False))
        leg["offerId"] = text(leg.get("offerId", ""), "offer reference", 160)
        leg["bookingId"] = text(leg.get("bookingId", ""), "booking reference", 160)
        leg["locked"] = leg["locked"] or bool(leg["bookingId"])

    rentals = sequence(base["rentals"], "car rentals", 50)
    for rental in rentals:
        record(rental, "car rental"); claim(rental, "car rental")
        place_ref(rental, "pickupPlaceId", True); place_ref(rental, "dropoffPlaceId", True)
        for field in ["pickupDate", "dropoffDate"]:
            rental[field] = calendar(rental.get(field, ""), field)
        for field in ["pickupTime", "dropoffTime"]:
            rental[field] = clock(rental.get(field, ""), field)
        if all(rental[field] for field in ["pickupDate", "dropoffDate", "pickupTime", "dropoffTime"]):
            first = next(place for place in places if place["id"] == rental["pickupPlaceId"])
            last = next(place for place in places if place["id"] == rental["dropoffPlaceId"])
            if first["timezone"] and last["timezone"]:
                try:
                    pickup = datetime.fromisoformat(rental["pickupDate"] + "T" + rental["pickupTime"]).replace(tzinfo=ZoneInfo(first["timezone"])).astimezone(timezone.utc)
                    dropoff = datetime.fromisoformat(rental["dropoffDate"] + "T" + rental["dropoffTime"]).replace(tzinfo=ZoneInfo(last["timezone"])).astimezone(timezone.utc)
                    if dropoff <= pickup: raise PlanningError("Car drop-off must be after pickup.")
                except ZoneInfoNotFoundError as exc:
                    raise PlanningError("A car-rental location has an unknown time zone.") from exc
            elif rental["pickupPlaceId"] == rental["dropoffPlaceId"] and (rental["dropoffDate"], rental["dropoffTime"]) <= (rental["pickupDate"], rental["pickupTime"]):
                raise PlanningError("Car drop-off must be after pickup.")
        for field in ["provider", "vehicle"]:
            rental[field] = text(rental.get(field, ""), field, 400)
        rental["status"] = choice(rental.get("status", "UNPLANNED"), {"UNPLANNED", "SELECTED", "BOOKED"}, "car rental status")
        rental["bookingId"] = text(rental.get("bookingId", ""), "booking reference", 160)
        rental["offerId"] = text(rental.get("offerId", ""), "offer reference", 160)
        rental["locked"] = bool(rental.get("locked", False) or rental["status"] == "BOOKED" or rental["bookingId"])
        rental["notes"] = text(rental.get("notes", ""), "rental notes", 4000)

    days = sequence(base["days"], "days", 400)
    seen_dates: set[str] = set()
    for day in days:
        record(day, "day"); claim(day, "day")
        day["date"] = calendar(day.get("date", ""), "day date")
        if day["date"]:
            if day["date"] in seen_dates:
                raise PlanningError("Two day records have the same date.")
            seen_dates.add(day["date"])
            if base["startDate"] and day["date"] < base["startDate"] or base["endDate"] and day["date"] > base["endDate"]:
                raise PlanningError("A day falls outside the trip dates.")
        day["title"] = text(day.get("title", "Open day"), "day title", 240, empty=False)
        place_ref(day, "overnightPlaceId")
        day["notes"] = text(day.get("notes", ""), "day notes", 6000)
        for item in sequence(day.setdefault("items", []), "day items", 100):
            record(item, "day item"); claim(item, "day item")
            item["title"] = text(item.get("title"), "activity title", 400, empty=False)
            item["kind"] = choice(item.get("kind", "ACTIVITY"), {"ACTIVITY", "TRAVEL", "MEAL", "REST", "FREE", "LODGING"}, "activity kind")
            place_ref(item, "placeId")
            for field in ["startTime", "endTime"]:
                item[field] = clock(item.get(field, ""), field)
            if item["startTime"] and item["endTime"] and item["endTime"] < item["startTime"]:
                raise PlanningError("An activity ends before it starts; split cross-midnight activities into days.")
            item["durationMinutes"] = integer(item.get("durationMinutes"), "activity duration", 0, 1440, nullable=True)
            item["bufferMinutes"] = integer(item.get("bufferMinutes", 0), "buffer", 0, 1440)
            item["notes"] = text(item.get("notes", ""), "activity notes", 6000)
            item["optional"] = bool(item.get("optional", False))
            item["locked"] = bool(item.get("locked", False))
            item["timingState"] = choice(item.get("timingState", "PROVISIONAL"), {"PROVISIONAL", "CHECKED", "CONFLICT", "UNRESOLVED"}, "timing evidence state")
            item["sourceRefs"] = [identifier(ref, "evidence reference") for ref in sequence(item.get("sourceRefs", []), "evidence references", 30)]
            item["actions"] = [{"label": text(record(action, "activity action").get("label"), "action label", 100, empty=False),
                                "url": public_url(action.get("url", ""), empty=False)}
                               for action in sequence(item.get("actions", []), "activity actions", 6)]
    days.sort(key=lambda d: d["date"] or "9999-12-31")
    for booking in sequence(base["bookings"], "bookings", 200):
        record(booking, "booking"); claim(booking, "booking")
        booking["title"] = text(booking.get("title"), "booking title", 400, empty=False)
        booking["status"] = choice(booking.get("status", "BOOKED"), {"BOOKED", "USER_REPORTED", "CANCELLED"}, "booking state")
        booking["source"] = choice(booking.get("source", "USER"), {"USER", "DOCUMENT"}, "booking evidence source")
        booking["amountMinor"] = integer(booking.get("amountMinor"), "paid amount", nullable=True)
        booking["currency"] = text(booking.get("currency", "USD"), "booking currency", 3, empty=False).upper()
        booking["details"] = text(booking.get("details", ""), "booking details", 12000)
        booking["sourceRef"] = text(booking.get("sourceRef", ""), "booking source", 160)
    booking_ids = {b["id"] for b in base["bookings"]}
    for item in stays + legs + rentals:
        if item.get("bookingId") and item["bookingId"] not in booking_ids:
            raise PlanningError("Missing booking referenced by a stay or leg.")
    for field in ["constraints", "unresolved"]:
        base[field] = [text(v, field, 4000, empty=False) for v in sequence(base[field], field, 200)]
    return base


def _fixed(snapshot: dict) -> dict[str, dict]:
    result = {}
    for collection in [snapshot["stays"], snapshot["legs"], snapshot.get("rentals", [])]:
        for item in collection:
            if item.get("locked"):
                result[item["id"]] = copy.deepcopy(item)
    for day in snapshot["days"]:
        for item in day["items"]:
            if item.get("locked"):
                result[item["id"]] = {"item": copy.deepcopy(item), "date": day["date"], "baseId": day["overnightPlaceId"] if not item.get("placeId") else ""}
    for booking in snapshot["bookings"]:
        if booking["status"] != "CANCELLED":
            result[booking["id"]] = copy.deepcopy(booking)
    return result


def _insert_item(day: dict, item: dict, before_id: object = "") -> None:
    items = day.setdefault("items", [])
    if before_id in (None, ""):
        items.append(item)
        return
    anchor = identifier(before_id, "activity position")
    if anchor == item["id"]:
        raise PlanningError("An activity cannot be placed before itself.")
    position = next((index for index, value in enumerate(items) if value["id"] == anchor), None)
    if position is None:
        raise PlanningError("The activity used to position this change is missing from the destination day.")
    items.insert(position, item)


def apply_operations(current: dict, operations: object) -> dict:
    """Apply explicitly typed operations to a copy, preserving untouched data."""
    result = validate_trip(current)
    fixed = _fixed(result)
    original_places = {p["id"]: copy.deepcopy(p) for p in result["places"]}
    for operation in sequence(operations, "proposed changes", 1500):
        op = record(operation, "proposed change")
        action = op.get("action")
        value = copy.deepcopy(op.get("value", {}))
        if action == "replace_trip":
            if current["places"] or current["days"] or current["bookings"]:
                raise PlanningError("An existing plan must be revised with targeted changes, not replaced.")
            result = blank_trip(current["id"])
            result.update(record(value, "new plan")); result["id"] = current["id"]
        elif action == "set_trip":
            allowed = {"title", "intent", "detail", "startDate", "endDate", "timezone", "party", "budget", "constraints", "unresolved", "notes"}
            if not isinstance(value, dict) or set(value) - allowed:
                raise PlanningError("Invalid trip-level update.")
            result.update(value)
        elif action in {"upsert_place", "upsert_stay", "upsert_leg", "upsert_day", "upsert_booking", "upsert_rental"}:
            kind = action[7:]
            field = {"place": "places", "stay": "stays", "leg": "legs", "day": "days", "booking": "bookings", "rental": "rentals"}[kind]
            incoming = record(value, kind)
            item_id = identifier(incoming.get("id"))
            existing = next((x for x in result[field] if x["id"] == item_id), None)
            if existing:
                if kind == "day" and "items" in incoming:
                    raise PlanningError("Use targeted item changes to preserve the rest of a day.")
                existing.update(incoming)
            else:
                result[field].append(incoming)
        elif action in {"remove_place", "remove_stay", "remove_leg", "remove_day", "remove_booking", "remove_rental"}:
            field = {"place": "places", "stay": "stays", "leg": "legs", "day": "days", "booking": "bookings", "rental": "rentals"}[action[7:]]
            item_id = identifier(op.get("targetId"))
            if not any(x["id"] == item_id for x in result[field]):
                raise PlanningError("The item to remove is no longer in this plan.")
            result[field] = [x for x in result[field] if x["id"] != item_id]
        elif action in {"upsert_item", "remove_item", "move_item"}:
            day_id = identifier(op.get("dayId"), "day reference")
            day = next((x for x in result["days"] if x["id"] == day_id), None)
            if day is None:
                raise PlanningError("The selected day is no longer in this plan.")
            if action == "upsert_item":
                incoming = record(value, "day item"); item_id = identifier(incoming.get("id"))
                existing = next((x for x in day.setdefault("items", []) if x["id"] == item_id), None)
                if existing:
                    existing.update(incoming)
                    if op.get("beforeId") not in (None, ""):
                        day["items"] = [x for x in day["items"] if x["id"] != item_id]
                        _insert_item(day, existing, op["beforeId"])
                else:
                    _insert_item(day, incoming, op.get("beforeId", ""))
            else:
                item_id = identifier(op.get("targetId"))
                existing = next((x for x in day["items"] if x["id"] == item_id), None)
                if existing is None:
                    raise PlanningError("The selected activity is no longer in this plan.")
                day["items"] = [x for x in day["items"] if x["id"] != item_id]
                if action == "move_item":
                    destination = next((x for x in result["days"] if x["id"] == op.get("toDayId")), None)
                    if destination is None:
                        raise PlanningError("The destination day is missing.")
                    _insert_item(destination, existing, op.get("beforeId", ""))
        else:
            raise PlanningError("Unsupported planning operation.")
    result = validate_trip(result)
    all_new = {x["id"]: x for field in ["stays", "legs", "bookings", "rentals"] for x in result[field]}
    all_new.update({x["id"]: {"item": x, "date": d["date"], "baseId": d["overnightPlaceId"] if not x.get("placeId") else ""} for d in result["days"] for x in d["items"]})
    for item_id, before in fixed.items():
        after = all_new.get(item_id)
        if after is None or after != before:
            raise PlanningError("This proposal changes a fixed or booked commitment. Keep it intact and explain the conflict.")
    # A stable place ID must not disguise a different location for a fixed item.
    protected_places = set()
    for value in fixed.values():
        item = value.get("item", value)
        protected_places.update(item.get(k) for k in ["placeId", "fromId", "toId", "pickupPlaceId", "dropoffPlaceId"] if item.get(k))
        if value.get("baseId"): protected_places.add(value["baseId"])
    old_places = original_places
    new_places = {p["id"]: p for p in result["places"]}
    for place_id in protected_places:
        old, new = old_places[place_id], new_places.get(place_id, {})
        if any(old.get(k) != new.get(k) for k in ["query", "kind"]):
            raise PlanningError("This change relocates a fixed or booked commitment. Keep its location intact and explain the conflict.")
    return result


def change_summary(before: dict, after: dict) -> list[dict]:
    """A readable diff with source IDs, rather than model-invented summaries."""
    changes = []
    for field in ["title", "startDate", "endDate", "party", "budget", "detail", "constraints", "unresolved"]:
        if before.get(field) != after.get(field):
            changes.append({"kind": "UPDATE", "section": "trip", "label": field, "before": before.get(field), "after": after.get(field)})
    for field in ["places", "stays", "legs", "days", "bookings", "rentals"]:
        left = {x["id"]: x for x in before.get(field, [])}; right = {x["id"]: x for x in after.get(field, [])}
        for item_id in left.keys() | right.keys():
            old, new = left.get(item_id), right.get(item_id)
            if old != new:
                changes.append({"kind": "ADD" if old is None else "REMOVE" if new is None else "UPDATE", "section": field,
                                "id": item_id, "label": (new or old).get("title", (new or old).get("label", (new or old).get("propertyName", field))),
                                "before": old, "after": new})
    return changes


def fingerprint(value: object) -> str:
    return hashlib.sha256(dumps(value).encode()).hexdigest()


def money_minor(value: str) -> int:
    """Parse a source monetary number, never a model estimate."""
    try:
        number = Decimal(value.replace(",", "").replace("$", "").strip())
        if not number.is_finite() or number < 0 or number != number.quantize(Decimal("0.01")):
            raise InvalidOperation()
        return int(number * 100)
    except (InvalidOperation, ValueError) as exc:
        raise PlanningError("Invalid monetary amount.") from exc


def budget_summary(snapshot: dict, offers: list[dict]) -> dict:
    """Sum distinct selected observations, separately from paid bookings."""
    selected = {x.get("offerId") for field in ["stays", "legs", "rentals"] for x in snapshot.get(field, []) if x.get("offerId") and not x.get("bookingId")}
    subtotals: dict[str, int] = {}
    estimates: dict[str, int] = {}
    for offer in offers:
        if offer.get("id") in selected:
            price = offer.get("price") or {}
            currency = price.get("currency", offer.get("currency", "USD"))
            if price:
                amount = price.get("estimatedTotalMinor")
                if price.get("basis") == "TOTAL": amount = price.get("amountMinor")
                target = subtotals if price.get("basis") == "TOTAL" and price.get("feesIncluded") is True and not price.get("from") else estimates
            else:
                amount, target = offer.get("totalMinor"), subtotals
            if type(amount) is int and amount >= 0:
                target[currency] = target.get(currency, 0) + amount
                selected.discard(offer["id"])
    paid: dict[str, int] = {}
    for booking in snapshot["bookings"]:
        if booking.get("amountMinor") is not None and booking["status"] != "CANCELLED":
            currency = booking["currency"]; paid[currency] = paid.get(currency, 0) + booking["amountMinor"]
    return {"selectedQuoteSubtotals": subtotals, "selectedEstimateSubtotals": estimates, "bookedSubtotals": paid,
            "unpricedStays": sum(1 for x in snapshot["stays"] if not x.get("offerId") and not x.get("bookingId")),
            "unpricedLegs": sum(1 for x in snapshot["legs"] if x["mode"] in {"FLIGHT", "TRANSIT", "UNKNOWN"} and not x.get("offerId") and not x.get("bookingId")),
            "unpricedRentals": sum(1 for x in snapshot.get("rentals", []) if not x.get("offerId") and not x.get("bookingId")),
            "missingOfferIds": sorted(selected)}


def validate_trip_json(raw: str) -> str:
    return dumps(validate_trip(loads(raw)))


def apply_operations_json(snapshot: str, operations: str) -> str:
    return dumps(apply_operations(validate_trip(loads(snapshot)), loads(operations)))


def change_summary_json(before: str, after: str) -> str:
    return dumps(change_summary(validate_trip(loads(before)), validate_trip(loads(after))))


def journey_signature(snapshot: dict, leg: dict) -> dict:
    """Bind auxiliary flight details to the exact saved leg and airport identity."""
    places = {p['id']: p for p in snapshot['places']}
    keys = ['fromId', 'toId', 'mode', 'departDate', 'arriveDate', 'departTime', 'arriveTime', 'durationMinutes', 'offerId', 'bookingId']
    value = {key: leg.get(key) for key in keys}
    for side, place_id in [('from', leg['fromId']), ('to', leg['toId'])]:
        place = places.get(place_id, {})
        for key in ['query', 'label']:
            value[side + key.title()] = place.get(key, '')
    return value
