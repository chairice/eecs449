"""Dark, inspectable map. Unsourced road paths are never drawn as road routes."""
import "leaflet/dist/leaflet.css";
import from react { useEffect, useRef }
import from leaflet { map as createMap, tileLayer, circleMarker, polyline, layerGroup }

def:pub PlannerMap(snapshot: any, focusIds: any, selectedId: str, onSelect: Callable[[str], None], roads: any = None, onLocate: Callable[[], None] = lambda {}) -> JsxElement {
    host = useRef(None);
    view = useRef(None);
    overlay = useRef(None);
    frame = useRef([]);
    has missingFocus: bool = False;
    useEffect(lambda {
        instance: any = createMap(host.current, {"zoomControl": False, "scrollWheelZoom": True, "maxZoom": 18, "minZoom": 2});
        view.current = instance;
        tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {"maxZoom": 19, "attribution": "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors", "className": "studio-map-tiles"}).addTo(instance);
        overlay.current = layerGroup().addTo(instance);
        instance.setView([38.8, -105], 4);
        observer = ResizeObserver(lambda (_entries: any, _observer: any) { instance.invalidateSize(); });
        observer.observe(host.current);
        return lambda { observer.disconnect(); instance.remove(); view.current = None; };
    }, []);
    useEffect(lambda {
        if not view.current or not overlay.current { return; }
        overlay.current.clearLayers();
        points: any = [];
        places: any = {};
        for place in snapshot["places"] { places[place["id"]] = place; }
        for leg in snapshot["legs"] {
            first = places[leg["fromId"]]; last = places[leg["toId"]];
            if not first or not last or first["lat"] is None or last["lat"] is None { continue; }
            routed: bool = False;
            for road in roads or [] {
                if road["id"] == leg["routeSourceRef"] and Math.abs(road["from"]["lat"] - first["lat"]) < 0.002 and Math.abs(road["to"]["lat"] - last["lat"]) < 0.002 and Math.abs(road["from"]["lon"] - first["lon"]) < 0.002 and Math.abs(road["to"]["lon"] - last["lon"]) < 0.002 {
                    polyline(road["points"], {"color": "#d8c291", "weight": 3, "opacity": 0.85, "interactive": False}).addTo(overlay.current);
                    routed = True;
                }
            }
            # Dashed connections show trip structure, not calculated driving geometry.
            if not routed { polyline([[first["lat"], first["lon"]], [last["lat"], last["lon"]]], {"color": "#a5bda9", "weight": 2, "opacity": 0.55, "dashArray": "4 8", "interactive": False}).addTo(overlay.current); }
        }
        for (index, place) in enumerate(snapshot["places"]) {
            if place["lat"] is None { continue; }
            active = len(focusIds) == 0 or place["id"] in focusIds;
            if active { points.append([place["lat"], place["lon"]]); }
            pin: any = circleMarker([place["lat"], place["lon"]], {"radius": 8 if place["id"] == selectedId else 5, "color": "#f0eee6", "weight": 2, "fillColor": "#d8c291" if active else "#737a77", "fillOpacity": 1, "opacity": 1 if active else 0.4}).addTo(overlay.current);
            label: any = document.createElement("span");
            label.textContent = str(place["label"]);
            pin.bindTooltip(label, {"direction": "top", "permanent": active and len(snapshot["places"]) < 12, "className": "studio-map-label"});
            place_id = str(place["id"]);
            pin.on("click", lambda { onSelect(place_id); });
        }
        frame.current = points;
        missingFocus = len(focusIds) > 0 and len(points) == 0;
    }, [snapshot, JSON.stringify(focusIds), selectedId, roads]);
    useEffect(lambda { if view.current and len(frame.current) > 0 { view.current.fitBounds(frame.current, {"padding": [55, 55], "maxZoom": 12, "animate": False}); } }, [snapshot["id"], JSON.stringify([[place["id"], place["lat"], place["lon"]] for place in snapshot["places"]]), JSON.stringify(focusIds)]);
    return <section className="studio-map" aria-label="Trip map">
        <div ref={host} className="studio-map-canvas"/>
        <div className="studio-map-caption"><span className="studio-map-dot"/> Trip connections · routes to check</div>
        {if missingFocus { <div className="studio-map-unresolved"><strong>These stops need a location check.</strong><p>The itinerary is here; their map positions are not verified yet.</p><button type="button" onClick={onLocate}>Ask Detour to locate them ↗</button></div> }}
        <div className="studio-map-zoom"><button type="button" aria-label="Zoom in" onClick={lambda { if view.current { view.current.zoomIn(); } }}>+</button><button type="button" aria-label="Zoom out" onClick={lambda { if view.current { view.current.zoomOut(); } }}>−</button></div>
    </section>;
}
