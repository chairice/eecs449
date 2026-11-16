import pytest
from atlas_runtime import geography


@pytest.mark.parametrize("query", ["Washington, DC", "Charleston, West Virginia", "Vancouver, Washington", "Tucson, Arizona"])
def test_state_normalization_does_not_rewrite_the_city_name(query, tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))
    def unexpected_network(*args, **kwargs):
        raise AssertionError("A catalog city should not need a network request")
    monkeypatch.setattr(geography, "urlopen", unexpected_network)
    value = geography.resolve(query, "CITY")
    assert value and value["lat"] is not None and value["timezone"]


def feature(name, lon=-111.1, lat=32.2, state="Arizona"):
    return {"properties": {"name": name, "countrycode": "US", "state": state, "osm_type": "N", "osm_id": 1},
            "geometry": {"coordinates": [lon, lat]}}


def test_landmark_selection_rejects_nearby_hotels_and_distant_namesakes():
    landmark = feature("Bell Rock")
    assert geography.select_feature([feature("Hilton Sedona Resort at Bell Rock"), feature("Bell Rock Trail"), landmark], "Bell Rock", "Arizona") is landmark
    assert geography.select_feature([feature("Bell Rock Trail")], "Bell Rock", "Arizona") is None
    assert geography.select_feature([landmark, feature("Bell Rock", lon=-112.5)], "Bell Rock", "Arizona") is None
    assert geography.select_feature([landmark], "Bell Rock", "Alaska") is None


def test_duplicate_osm_node_and_way_are_one_location():
    first = feature("Gates Pass", -111.1010354, 32.2226179)
    duplicate = feature("Gates Pass", -111.1011213, 32.2226522)
    assert geography.select_feature([first, duplicate, feature("Enclaves at Gates Pass")], "Gates Pass Scenic Overlook", "Arizona") is first


def test_geocoder_short_fallback_retains_source_coordinates(tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))
    calls = []
    def lookup(query):
        calls.append(query)
        return [] if len(calls) == 1 else [feature("Gates Pass", -111.101, 32.2226)]
    monkeypatch.setattr(geography, "photon", lookup)
    value = geography.resolve("Gates Pass Scenic Overlook, Tucson, AZ", "PLACE")
    assert calls == ["Gates Pass Scenic Overlook, Tucson, AZ", "gates pass Arizona"]
    assert value["lat"] == 32.2226 and value["sourceUrl"] == "https://www.openstreetmap.org/node/1"


@pytest.mark.parametrize("latitude,longitude,target,rises", [
    (64.8378, -147.7164, "2027-06-21", True),
    (71.2906, -156.7886, "2027-06-21", False),
    (71.2906, -156.7886, "2026-12-21", False),
])
def test_alaska_missing_twilight_does_not_erase_sunrise(monkeypatch, latitude, longitude, target, rises):
    from atlas_runtime import travel_tools
    monkeypatch.setattr(travel_tools, "resolve", lambda *_: {"lat": latitude, "lon": longitude, "timezone": "America/Anchorage"})
    result = travel_tools.daylight({"query": "Alaska test location", "date": target})
    assert bool(result["times"].get("sunrise")) is rises
    assert bool(result["times"].get("sunset")) is rises
    assert "astronomicalDusk" in result["unavailableEvents"] if target.endswith("06-21") else "sunrise" in result["unavailableEvents"]
    assert result["times"]["noon"].startswith(target)
