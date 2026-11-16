#!/usr/bin/env python3
"""Opt-in live PDF + image import test using clearly synthetic travel material."""
import base64
import copy
import json
import os
from pathlib import Path
import tempfile

from dotenv import load_dotenv
from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfWriter
from pypdf.generic import DictionaryObject, NameObject, DecodedStreamObject
from atlas_runtime.planner import plan
from server import planning_jobs as jobs
from server.planning_core import blank_trip

load_dotenv(Path(__file__).resolve().parents[1] / "workers/.env")

LINES = ["SYNTHETIC QA ITINERARY - NOT A BOOKING", "Sample trip only. No reservation or payment.",
         "Two adults, no children", "Trip: December 26-28, 2026", "Flight: DTW to PHX, December 26, 2026",
         "Departure: 10:00 AM Detroit local time", "Arrival: 12:30 PM Arizona local time", "Stay area: Tucson, December 26-28"]


def main():
    with tempfile.TemporaryDirectory(prefix="atlas-import-live-") as folder:
        root = Path(folder); os.environ["PLANNER_DATA_DIR"] = str(root / "private")
        image = Image.new("RGB", (1400, 900), "white"); draw = ImageDraw.Draw(image)
        font_path = Path("/System/Library/Fonts/Supplemental/Arial.ttf")
        font = ImageFont.truetype(str(font_path), 34) if font_path.exists() else ImageFont.load_default(size=34)
        for index, line in enumerate(LINES): draw.text((55, 50 + index * 90), line, font=font, fill="black")
        image_path = root / "sample-itinerary.png"; image.save(image_path)
        writer = PdfWriter(); page = writer.add_blank_page(width=612, height=792)
        font_obj = DictionaryObject({NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"), NameObject("/BaseFont"): NameObject("/Helvetica")})
        page[NameObject("/Resources")] = DictionaryObject({NameObject("/Font"): DictionaryObject({NameObject("/F1"): writer._add_object(font_obj)})})
        stream = DecodedStreamObject()
        stream.set_data(("BT /F1 12 Tf 40 750 Td " + " 0 -28 Td ".join("(" + line.replace("(", "\\(").replace(")", "\\)") + ") Tj" for line in LINES) + " ET").encode())
        page[NameObject("/Contents")] = writer._add_object(stream)
        pdf_path = root / "sample-itinerary.pdf"
        with pdf_path.open("wb") as handle: writer.write(handle)
        owner = "local-live-import-test"
        ids = [jobs.attachment(owner, path.name, media, base64.b64encode(path.read_bytes()).decode())["id"]
               for path, media in [(image_path, "image/png"), (pdf_path, "application/pdf")]]
        snapshot = blank_trip("trip_import_live"); before = copy.deepcopy(snapshot)
        request = {"tripId": snapshot["id"], "snapshot": snapshot, "baseRevision": 0, "today": "2026-11-14", "timeZone": "America/Detroit",
                   "conversation": [], "workingContext": {}, "preferences": {}, "summary": "", "attachments": ids,
                   "message": "Import the travel facts from these two synthetic QA documents into one logistics-only proposal. Preserve the dates and local flight times. They are explicitly NOT bookings; do not mark anything booked. Don't research inventory or opening hours."}
        result = plan(request, owner, update=lambda message: print(message, flush=True))
        proposed = result["proposed"]
        Path("/tmp/atlas-live-import-results.json").write_text(json.dumps(result, indent=2))
        assert snapshot == before
        assert proposed["startDate"] == "2026-12-26" and proposed["endDate"] == "2026-12-28"
        assert proposed["party"]["adults"] == 2
        assert any(leg["departTime"] == "10:00" and leg["arriveTime"] == "12:30" for leg in proposed["legs"])
        assert all(booking["status"] != "BOOKED" for booking in proposed["bookings"])
        assert result["sourceCount"] == 0
        print("PASS: multimodal PDF/image import, dates, local times, party, preview-only changes, and no invented booking")


if __name__ == "__main__": main()
