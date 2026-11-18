"""Explicit local map imagery for browser QA; never contact public tile servers.

The synthetic grid is visibly labelled. It tests map controls/overlays, not a
provider's availability, geography or imagery. Production never imports it.
"""
import re

TILE_URL = re.compile(r"^https?://(?:[^/.]+\.)?tile\.openstreetmap\.org/")
TILE_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<rect width="256" height="256" fill="#e8eee8"/>
<path d="M0 64H256M0 128H256M0 192H256M64 0V256M128 0V256M192 0V256" stroke="#c5d3c9"/>
<text x="128" y="125" text-anchor="middle" font-family="sans-serif" font-size="12" fill="#587164">QA map tile</text>
<text x="128" y="143" text-anchor="middle" font-family="sans-serif" font-size="9" fill="#587164">mocked - not geographic imagery</text>
</svg>"""


def mock_map_tiles(surface):
    """Return requested tile URLs, fulfilled locally before any network access."""
    requested = []

    def tile(route):
        requested.append(route.request.url)
        route.fulfill(status=200, content_type="image/svg+xml", body=TILE_SVG,
                      headers={"Cache-Control": "public, max-age=604800",
                               "X-Detour-QA-Fixture": "mocked-map-tile"})

    surface.route(TILE_URL, tile)
    return requested
