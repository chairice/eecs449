#!/usr/bin/env python3
"""Refresh the offline Atlas catalog from primary, openly licensed datasets.

Raw downloads live in a temporary cache, never in the repository. Output order,
rounding and JSON encoding are deterministic for identical source bytes.
"""
import argparse
import csv
import gzip
import hashlib
import io
import json
import pathlib
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone

STATES = set("AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY".split())
SOURCES = {
    "geonames": ("https://download.geonames.org/export/dump/US.zip", "CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
    "counties": ("https://download.geonames.org/export/dump/admin2Codes.txt", "CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
    "airports": ("https://davidmegginson.github.io/ourairports-data/airports.csv", "Public domain", "https://ourairports.com/data/"),
    "states": ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_1_states_provinces.geojson", "Public domain", "https://www.naturalearthdata.com/about/terms-of-use/"),
    "countries": ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson", "Public domain", "https://www.naturalearthdata.com/about/terms-of-use/"),
}


def encode(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=pathlib.Path, help="Reuse downloaded source bytes in this directory")
    args = parser.parse_args()
    cache = args.cache or pathlib.Path(tempfile.mkdtemp(prefix="detour-atlas-data-"))
    cache.mkdir(parents=True, exist_ok=True)
    output = pathlib.Path(__file__).resolve().parents[1] / "web/fixtures/atlas"
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"schemaVersion": 1, "retrievedAt": datetime.now(timezone.utc).date().isoformat(), "sources": {}, "outputs": {}}
    raw = {}
    for key, (url, license_name, license_url) in SOURCES.items():
        target = cache / key
        headers = cache / (key + ".headers")
        if not target.exists():
            partial = cache / (key + ".part")
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error", "--dump-header", str(headers), "--output", str(partial), url], check=True)
            partial.replace(target)
        raw[key] = target.read_bytes()
        modified = ""
        if headers.exists():
            for line in headers.read_text().splitlines():
                if line.lower().startswith("last-modified:"):
                    modified = line.split(":", 1)[1].strip()
        manifest["sources"][key] = {"url": url, "license": license_name, "licenseUrl": license_url, "sha256": hashlib.sha256(raw[key]).hexdigest(), "bytes": len(raw[key]), "lastModified": modified}
    counties = {}
    for row in csv.reader(io.StringIO(raw["counties"].decode()), delimiter="\t"):
        if row and row[0].startswith("US."):
            counties[row[0]] = row[1]
    places = []
    latest = ""
    with zipfile.ZipFile(io.BytesIO(raw["geonames"])) as archive:
        rows = csv.reader(io.TextIOWrapper(archive.open("US.txt"), encoding="utf-8"), delimiter="\t")
        for row in rows:
            # PPLX (neighborhood), PPLH (historic), PPLQ (abandoned), PPLW
            # (destroyed), PPLCH (historic capital) are intentionally excluded.
            if row[8] != "US" or row[10] not in STATES or row[7] not in {"PPL", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLC", "PPLG", "PPLL", "PPLR"}:
                continue
            if int(row[14]) <= 0 and not row[7].startswith("PPLA") and row[7] != "PPLC":
                continue
            aliases = []
            if row[2] and row[2].casefold() != row[1].casefold():
                aliases.append(row[2])
            # Only ASCII variants are bundled; avoid thousands of multilingual
            # aliases and historic forms whose validity is not tagged here.
            for alias in row[3].split(","):
                if alias and alias.isascii() and len(alias) <= 80 and alias.casefold() != row[1].casefold() and alias not in aliases:
                    aliases.append(alias)
                if len(aliases) >= 3:
                    break
            places.append({"id": "geo:" + row[0], "name": row[1], "state": row[10], "county": counties.get("US." + row[10] + "." + row[11], ""), "kind": "CITY", "lat": round(float(row[4]), 5), "lon": round(float(row[5]), 5), "code": "", "aliases": aliases})
            latest = max(latest, row[18])
    for row in csv.DictReader(io.StringIO(raw["airports"].decode())):
        state = row["iso_region"].removeprefix("US-")
        if row["iso_country"] != "US" or state not in STATES or row["type"] not in {"large_airport", "medium_airport", "small_airport", "seaplane_base"}:
            continue
        if not row["iata_code"] and row["type"] not in {"large_airport", "medium_airport"}:
            continue
        aliases = list(dict.fromkeys(item for item in (row["iata_code"], row["icao_code"] if "icao_code" in row else "", row["gps_code"], row["local_code"], row["ident"]) if item))
        places.append({"id": "airport:" + row["id"], "name": row["name"], "state": state, "county": "", "kind": "AIRPORT", "lat": round(float(row["latitude_deg"]), 5), "lon": round(float(row["longitude_deg"]), 5), "code": row["iata_code"] or row["local_code"] or row["ident"], "aliases": aliases})
    places.sort(key=lambda item: (item["name"].casefold(), item["state"], item["county"], item["id"]))
    states = []
    for feature in json.loads(raw["states"])["features"]:
        properties = feature["properties"]
        code = properties.get("postal")
        if properties.get("admin") == "United States of America" and code in STATES:
            states.append({"type": "Feature", "properties": {"name": properties["name"], "code": code}, "geometry": feature["geometry"]})
    assert {item["properties"]["code"] for item in states} == STATES, "State boundaries must cover exactly 50 states + DC"
    countries = [feature for feature in json.loads(raw["countries"])["features"] if feature["properties"].get("ADM0_A3") == "USA"]
    assert len(countries) == 1
    countries[0]["properties"] = {"name": "United States of America", "code": "US"}
    assert {item["state"] for item in places} == STATES
    assert len({item["id"] for item in places}) == len(places)
    objects = {"places.json.gz": places, "states.geojson": {"type": "FeatureCollection", "features": sorted(states, key=lambda item: item["properties"]["code"])}, "country.geojson": {"type": "FeatureCollection", "features": countries}}
    for name, value in objects.items():
        data = encode(value)
        if name.endswith(".gz"):
            data = gzip.compress(data, compresslevel=9, mtime=0)
        (output / name).write_bytes(data)
        manifest["outputs"][name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    manifest["catalog"] = {"places": len(places), "cities": sum(item["kind"] == "CITY" for item in places), "airports": sum(item["kind"] == "AIRPORT" for item in places), "states": 51, "latestGeoNamesRecordModification": latest}
    (output / "manifest.json").write_bytes(encode(manifest))
    print(json.dumps(manifest["catalog"], indent=2))
    print(json.dumps(manifest["outputs"], indent=2))


if __name__ == "__main__":
    main()
