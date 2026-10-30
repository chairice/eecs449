# Atlas offline geographic data

The checked-in catalog has 32,992 records covering the 50 US states and the
District of Columbia, including Alaska and Hawaii. It contains 30,929 populated
places and administrative seats plus 2,063 airports. US territories and foreign
locations are excluded. This is a nationwide catalog, **not every settlement or
every airstrip**. A place missing from it remains unresolved in the editor; the
application does not guess coordinates.

## Sources and licenses

| Source | Selection | License |
| --- | --- | --- |
| [GeoNames US extract](https://download.geonames.org/export/dump/US.zip) and [county names](https://download.geonames.org/export/dump/admin2Codes.txt) | US populated-place records with positive reported population, plus administrative seats/capital regardless of population; only 50 states + DC | [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/) |
| [OurAirports](https://ourairports.com/data/) | Open large/medium airports and IATA-coded small airports/seaplane bases in those states | Public domain |
| [Natural Earth vector data](https://github.com/nvkelso/natural-earth-vector) | 1:50m state boundaries and 1:10m US country boundary | [Public domain](https://www.naturalearthdata.com/about/terms-of-use/) |

Attribution: geographical place names and coordinates from **GeoNames**, licensed
under CC BY 4.0, modified by filtering, alias selection, coordinate rounding and
format conversion. Airport data from **OurAirports**. Made with **Natural Earth**.
All sources provide their data without guarantees of accuracy or completeness.

The data was retrieved on 2026-10-30. The latest GeoNames modification date among
included records is 2026-10-28; this is a record modification date, not a claim
that every record was surveyed recently. The manifest records source URLs,
response Last-Modified values when supplied, licenses, source byte counts and
SHA-256 checksums, and output byte counts/checksums. Natural Earth URLs point to
its upstream repository; the recorded checksum identifies the precise snapshot.

## Reproducible refresh

Run from the repository root with Python 3.10+ and curl:

```sh
python3 scripts/build-atlas-data.py
```

Raw downloads go to a new temporary directory and are not committed. To rebuild
from the same downloaded bytes, retain that directory and pass
`--cache /absolute/path/to/cache`. For a fresh upstream snapshot, use a new cache
directory. Output ordering, encoding, coordinate precision, and gzip timestamps
are deterministic; the manifest retrieval date reflects the run date. Review the
updated manifest and counts before committing a refresh.

The roughly 1.25 MB `web/fixtures/atlas/places.json.gz` decompresses to a JSON
array. Each record has `id`, `name`, `state`, `county`, `kind`, `lat`, `lon`,
`code`, and `aliases`. GeoNames IDs use `geo:` and OurAirports IDs use `airport:`.
Coordinates are WGS84 decimal degrees, rounded to five decimal places. Airports
have IATA codes when available, otherwise local identifiers. County names are
retained for city disambiguation. Up to three ASCII/transliterated GeoNames
aliases are included; airport aliases include available ICAO/GPS/local codes.
The source alias convenience field does not label historical aliases, so an
alias is a search aid, not evidence of a current official name.

GeoNames neighborhoods, historic, abandoned and destroyed place feature codes
are excluded. OurAirports closed airports, heliports and balloonports are
excluded. Positive population is a practical coverage filter, not a minimum
city-size requirement or a current census guarantee. Airport inclusion does not
promise scheduled passenger service.

`states.geojson` has exactly 51 features with `properties.name` and
`properties.code`. `country.geojson` contains the US MultiPolygon. These are
simplified cartographic boundaries; they are useful for drawing and conservative
cross-border route rejection, not legal boundary determination or navigation.
Coastal roads, bridges, islands and borderline routes may remain unverified
because of simplification. A failed road calculation is shown as unavailable;
the UI must not substitute a straight line as a road route.

## Browser persistence and validation

The client saves one JSON envelope under `detour.atlas.v1`, containing schema
version 1, the saved journeys, and the current draft. This makes each successful
localStorage write atomic. Saved journeys require at least two resolved stops,
a title, a known mode for each leg, valid optional calendar dates/times, and no
unreviewed details. A route can still be unavailable; route availability is not a
condition of saving. Drafts may retain unknown modes, unresolved places and
unreviewed details. Journey statuses are `PLANNED` and `PAST`.

Malformed or future-version existing storage is preserved and produces an error;
it is not silently overwritten. Quota/blocked-storage failures are reported.
Notes, message counts, stop counts and geometry sizes are bounded. Data is local
to this browser and is not shared or synchronized between devices. Clearing site
data removes saved journeys.

Dates are compared in itinerary order. Times are explicitly local wall-clock
values without an attached timezone, so the validator does not compare clocks
across stops: that could incorrectly reject westbound flights. It does not infer
durations or fabricate missing dates/times.

After a production client build, run
`node --test scripts/test-client-atlas.mjs` to check the emitted JavaScript,
storage failure behavior, itinerary mutations, exact-name ambiguity, and bundled
dataset checksums and state coverage.
