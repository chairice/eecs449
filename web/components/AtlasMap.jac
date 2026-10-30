"""Persistent, tile-free atlas. Route edits redraw overlays without moving the camera.

Flight arcs are illustrative great-circle paths, never actual flight tracks.
Driving paths are rendered only after the routing service supplies geometry.
"""

import "leaflet/dist/leaflet.css";
import from "react" { useEffect }
import from "leaflet" { map as leafletMap, circleMarker, polyline, layerGroup, geoJSON }

glob ATLAS_HOME: list[list[float]] = [[24.4, -125.2], [49.6, -66.5]];

"""Sample a great-circle connection, unwrapping longitude across the dateline."""
def atlas_flight_points(start: any, end: any) -> list[list[float]] {
    radians = Math.PI / 180;
    lat1 = float(start["lat"]) * radians;
    lat2 = float(end["lat"]) * radians;
    lon1 = float(start["lon"]) * radians;
    lon2 = float(end["lon"]) * radians;
    cosine = Math.sin(lat1) * Math.sin(lat2) + Math.cos(lat1) * Math.cos(lat2) * Math.cos(lon2 - lon1);
    clamped = Math.max(-1, Math.min(1, cosine));
    angle = Math.atan2(Math.sqrt(Math.max(0, 1 - clamped * clamped)), clamped);
    result: list[list[float]] = [];
    previous = float(start["lon"]);
    for index in range(49) {
        fraction = index / 48;
        if angle < 0.00001 {
            result.append([float(start["lat"]), float(start["lon"])]);
        } else {
            first = Math.sin((1 - fraction) * angle) / Math.sin(angle);
            second = Math.sin(fraction * angle) / Math.sin(angle);
            x = first * Math.cos(lat1) * Math.cos(lon1) + second * Math.cos(lat2) * Math.cos(lon2);
            y = first * Math.cos(lat1) * Math.sin(lon1) + second * Math.cos(lat2) * Math.sin(lon2);
            z = first * Math.sin(lat1) + second * Math.sin(lat2);
            latitude = Math.atan2(z, Math.sqrt(x * x + y * y)) / radians;
            longitude = Math.atan2(y, x) / radians;
            while longitude - previous > 180 { longitude = longitude - 360; }
            while longitude - previous < -180 { longitude = longitude + 360; }
            result.append([latitude as float, longitude as float]);
            previous = longitude as float;
        }
    }
    return result;
}

def:pub AtlasMap(journeys: any, states: any, selectedId: str = "", modeFilter: str = "ALL", fitVersion: int = 0, resetVersion: int = 0, onSelect: Callable[[str], None] = lambda (_id: str) {}, presentation: bool = False) -> JsxElement {
    has host: Ref[HTMLDivElement] = Ref();
    has view: Ref[any] = Ref(None);
    has boundaries: Ref[any] = Ref(None);
    has routes: Ref[any] = Ref(None);

    def reset_view {
        if view.current { view.current.fitBounds(ATLAS_HOME, {"padding": [35, 35], "animate": False}); }
    }

    def focus_region(region: str) {
        if not view.current { return; }
        if region == "AK" { view.current.fitBounds([[51, -171], [72, -129]], {"padding": [35, 35], "animate": False}); }
        elif region == "HI" { view.current.fitBounds([[18.7, -160.7], [22.5, -154.5]], {"padding": [45, 45], "animate": False}); }
        else { reset_view(); }
    }

    def fit_journey {
        if not view.current { return; }
        frame: list[list[float]] = [];
        for journey in journeys {
            if selectedId and journey["id"] != selectedId { continue; }
            for stop in journey["stops"] {
                place = stop["place"];
                if place { frame.append([float(place["lat"]), float(place["lon"])]); }
            }
            stops = journey["stops"] as list[any];
            for (index, leg) in enumerate(journey["legs"]) {
                route = leg["route"];
                if leg["mode"] == "DRIVE" and route and route["status"] == "READY" {
                    frame = frame + (route["points"] as list[list[float]]);
                } elif leg["mode"] == "FLIGHT" and index + 1 < len(stops) and stops[index]["place"] and stops[index + 1]["place"] {
                    frame = frame + atlas_flight_points(stops[index]["place"], stops[index + 1]["place"]);
                }
            }
        }
        if len(frame) > 0 { view.current.fitBounds(frame, {"padding": [65, 65], "maxZoom": 8, "animate": False}); }
    }

    def add_path(points: list[list[float]], journey: any, flight: bool, active: bool) {
        group = routes.current;
        planned = journey["status"] == "PLANNED";
        opacity = 0.9 if active else 0.18;
        color = str(journey["color"] or "#b86645");
        polyline(points, {"color": "#faf9f5", "weight": 6.5 if active else 4, "opacity": 0.75 if active else 0.15, "interactive": False, "lineCap": "round"}).addTo(group);
        path = polyline(points, {"color": color, "weight": 2.4 if flight else 3.2, "opacity": opacity, "dashArray": "3 7" if planned else None, "lineCap": "round", "lineJoin": "round", "className": "atlas-flight-path" if flight else "atlas-drive-path"}).addTo(group);
        # The compiler's DOM stub returns object; Leaflet accepts this live DOM node.
        label: any = document.createElement("span");
        label.textContent = str(journey["title"]) + (" · illustrative flight" if flight else " · road route");
        path.bindTooltip(label, {"sticky": True, "className": "atlas-route-tooltip"});
        journey_id = str(journey["id"]);
        path.on("click", lambda { if not presentation and journey_id != selectedId { onSelect(journey_id); } });
    }

    def draw_routes {
        if not routes.current { return; }
        routes.current.clearLayers();
        for journey in journeys {
            active = not selectedId or journey["id"] == selectedId;
            stops = journey["stops"] as list[any];
            legs = journey["legs"] as list[any];
            for (index, leg) in enumerate(legs) {
                if index + 1 >= len(stops) { continue; }
                if modeFilter != "ALL" and leg["mode"] != modeFilter { continue; }
                first = stops[index]["place"];
                last = stops[index + 1]["place"];
                if not first or not last { continue; }
                route = leg["route"];
                if leg["mode"] == "FLIGHT" {
                    add_path(atlas_flight_points(first, last), journey, True, active);
                } elif leg["mode"] == "DRIVE" and route and route["status"] == "READY" {
                    points = route["points"] as list[list[float]];
                    if len(points) > 1 { add_path(points, journey, False, active); }
                }
            }
            for (index, stop) in enumerate(stops) {
                place = stop["place"];
                if not place { continue; }
                if modeFilter != "ALL" {
                    before = index > 0 and index - 1 < len(legs) and legs[index - 1]["mode"] == modeFilter;
                    after = index < len(legs) and legs[index]["mode"] == modeFilter;
                    if not before and not after { continue; }
                }
                pin = circleMarker([float(place["lat"]), float(place["lon"])], {"radius": 5 if active else 3, "color": "#faf9f5", "weight": 2, "fillColor": str(journey["color"] or "#b86645"), "fillOpacity": 1 if active else 0.25, "opacity": 1 if active else 0.3}).addTo(routes.current);
                label: any = document.createElement("span");
                label.textContent = str(index + 1) + "  " + str(place["name"]);
                pin.bindTooltip(label, {"permanent": bool(selectedId) and active, "direction": "top", "offset": [0, -8], "className": "atlas-stop-label"});
            }
        }
    }

    useEffect(lambda {
        created: any = leafletMap(host.current, {"zoomControl": False, "attributionControl": False, "scrollWheelZoom": True, "keyboard": True, "minZoom": 2, "maxZoom": 12, "zoomSnap": 0.25, "zoomDelta": 0.5, "preferCanvas": False});
        view.current = created;
        boundaries.current = layerGroup().addTo(created);
        routes.current = layerGroup().addTo(created);
        reset_view();
        observer = ResizeObserver(lambda (_entries: any, _observer: any) { created.invalidateSize({"pan": False}); });
        observer.observe(host.current);
        return lambda {
            observer.disconnect();
            created.remove();
            view.current = None;
            boundaries.current = None;
            routes.current = None;
        };
    }, []);

    can with [states] entry {
        if boundaries.current {
            boundaries.current.clearLayers();
            if states {
                geoJSON(states, {"style": {"color": "#c6c8bb", "weight": 0.8, "opacity": 0.85, "fillColor": "#eeeee5", "fillOpacity": 1}, "interactive": False}).addTo(boundaries.current);
                boundaries.current.eachLayer(lambda (layer: any) { layer.bringToBack(); });
            }
        }
    }
    can with [journeys, selectedId, modeFilter, presentation] entry { draw_routes(); }
    can with [fitVersion] entry { if fitVersion > 0 { fit_journey(); } }
    can with [resetVersion] entry { if resetVersion > 0 { reset_view(); } }
    can with [presentation] entry { if view.current { view.current.invalidateSize({"pan": False}); } }

    return <div className="atlas-map-stage">
        <div className="atlas-map" ref={host} role="region" aria-label="Interactive United States journey atlas. Use arrow keys to pan and plus or minus to zoom." tabIndex={0}></div>
        <div className="atlas-map-caption" aria-hidden="true"><span>UNITED STATES</span><span>A personal atlas</span></div>
        <div className="atlas-map-controls" aria-label="Map controls">
            <button type="button" aria-label="Zoom in" title="Zoom in" onClick={lambda { if view.current { view.current.zoomIn(); } }}>+</button>
            <button type="button" aria-label="Zoom out" title="Zoom out" onClick={lambda { if view.current { view.current.zoomOut(); } }}>−</button>
            <span></span>
            <button type="button" aria-label="Show contiguous United States" title="Contiguous United States" onClick={lambda { focus_region("US"); }}>US</button>
            <button type="button" aria-label="Show Alaska" title="Alaska" onClick={lambda { focus_region("AK"); }}>AK</button>
            <button type="button" aria-label="Show Hawaii" title="Hawaii" onClick={lambda { focus_region("HI"); }}>HI</button>
        </div>
        <div className="atlas-map-footnote">Flight arcs are illustrative · Roads: OSRM / <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">© OpenStreetMap</a>{" · Map: Natural Earth · Places: "}<a href="https://www.geonames.org/" target="_blank" rel="noreferrer">GeoNames</a>{" / "}<a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noreferrer">CC BY 4.0</a>{" · OurAirports"}</div>
    </div>;
}
