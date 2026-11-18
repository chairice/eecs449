"""Dark, inspectable map. Unsourced road paths are never drawn as road routes."""
import "leaflet/dist/leaflet.css";
import from react { useEffect, useRef }
import from leaflet { map as createMap, tileLayer, circleMarker, polyline, layerGroup }

def:pub matching_journey(snapshot: any, leg: any, journey: any) -> bool {
    signature = journey["legSignature"];
    if not signature or journey["legId"] != leg["id"] { return False; }
    for field in ["fromId", "toId", "mode", "departDate", "arriveDate", "departTime", "arriveTime", "durationMinutes", "offerId", "bookingId"] {
        if signature[field] != leg[field] { return False; }
    }
    for place in snapshot["places"] {
        if place["id"] == leg["fromId"] and (place["query"] != signature["fromQuery"] or place["label"] != signature["fromLabel"]) { return False; }
        if place["id"] == leg["toId"] and (place["query"] != signature["toQuery"] or place["label"] != signature["toLabel"]) { return False; }
    }
    return True;
}

def:pub matching_flight_schedule(leg: any, flight: any) -> bool {
    for field in ["departDate", "arriveDate", "departTime", "arriveTime", "durationMinutes"] {
        if leg[field] is not None and leg[field] != "" and flight[field] is not None and flight[field] != "" and leg[field] != flight[field] { return False; }
    }
    return True;
}

def:pub journey_map_snapshot(snapshot: any, resources: any = None) -> any {
    result = JSON.parse(JSON.stringify(snapshot));
    if not resources { return result; }
    mapped: any = [];
    for leg in result["legs"] {
        selected: any = None;
        for offer in resources["offers"] or [] { if offer["id"] == leg["offerId"] { selected = offer; } }
        segments = selected["flight"]["segments"] if selected and selected["flight"] and matching_flight_schedule(leg, selected["flight"]) else [];
        if not segments or len(segments) == 0 {
            for journey in resources["flightJourneys"] or [] { if matching_journey(snapshot, leg, journey) and journey["flight"] { segments = journey["flight"]["segments"] or []; } }
        }
        if leg["mode"] != "FLIGHT" or not segments or len(segments) < 2 { mapped.append(leg); continue; }
        previous = str(leg["fromId"]);
        complete = True;
        for segment in segments { if not segment["fromAirport"] or not segment["toAirport"] or segment["toAirport"]["lat"] is None or segment["toAirport"]["lon"] is None { complete = False; } }
        if not complete { mapped.append(leg); continue; }
        for (index, segment) in enumerate(segments) {
            destination = str(leg["toId"]);
            if index < len(segments) - 1 {
                destination = str(leg["id"]) + "-connection-" + str(index);
                airport = segment["toAirport"];
                result["places"].append({"id": destination, "label": str(airport["label"]) + " (" + str(airport["code"]) + ")", "lat": airport["lat"], "lon": airport["lon"], "kind": "AIRPORT", "mapSelectId": leg["id"], "mapFromId": leg["fromId"], "mapToId": leg["toId"]});
            }
            mapped.append({"id": str(leg["id"]) + "-segment-" + str(index), "fromId": previous, "toId": destination, "mode": "FLIGHT", "routeSourceRef": ""});
            previous = destination;
        }
    }
    result["legs"] = mapped;
    return result;
}

def:pub PlannerMap(snapshot: any, focusIds: any, selectedId: str, onSelect: Callable[[str], None], roads: any = None, resources: any = None, onLocate: Callable[[], None] = lambda {}) -> JsxElement {
    display = journey_map_snapshot(snapshot, resources);
    mapFocus = focusIds + [place["id"] for place in display["places"] if place["mapFromId"] in focusIds or place["mapToId"] in focusIds];
    host = useRef(None);
    view = useRef(None);
    overlay = useRef(None);
    frame = useRef([]);
    has missingFocus: bool = False;
    useEffect(lambda {
        instance: any = createMap(host.current, {"zoomControl": False, "scrollWheelZoom": True, "maxZoom": 18, "minZoom": 2});
        view.current = instance;
        tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {"maxZoom": 19, "attribution": "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors", "className": "studio-map-tiles", "referrerPolicy": "strict-origin-when-cross-origin"}).addTo(instance);
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
        for place in display["places"] { places[place["id"]] = place; }
        for leg in display["legs"] {
            first = places[leg["fromId"]]; last = places[leg["toId"]];
            if not first or not last or first["lat"] is None or last["lat"] is None { continue; }
            routed: bool = False;
            for road in roads or [] {
                if road["id"] == leg["routeSourceRef"] and Math.abs(road["from"]["lat"] - first["lat"]) < 0.002 and Math.abs(road["to"]["lat"] - last["lat"]) < 0.002 and Math.abs(road["from"]["lon"] - first["lon"]) < 0.002 and Math.abs(road["to"]["lon"] - last["lon"]) < 0.002 {
                    polyline(road["points"], {"color": "var(--dt-accent)", "weight": 3, "opacity": 0.95, "interactive": False}).addTo(overlay.current);
                    routed = True;
                }
            }
            # Dashed connections show trip structure, not calculated driving geometry.
            if not routed { polyline([[first["lat"], first["lon"]], [last["lat"], last["lon"]]], {"color": "var(--dt-accent)", "weight": 2, "opacity": 0.9, "dashArray": "4 8", "interactive": False}).addTo(overlay.current); }
        }
        for (index, place) in enumerate(display["places"]) {
            if place["lat"] is None { continue; }
            active = len(mapFocus) == 0 or place["id"] in mapFocus;
            if active { points.append([place["lat"], place["lon"]]); }
            pin: any = circleMarker([place["lat"], place["lon"]], {"radius": 8 if place["id"] == selectedId else 5, "color": "var(--dt-surface)", "weight": 2, "fillColor": "var(--dt-accent)" if active else "var(--dt-muted)", "fillOpacity": 1, "opacity": 1 if active else 0.4}).addTo(overlay.current);
            label: any = document.createElement("span");
            label.textContent = str(place["label"]);
            pin.bindTooltip(label, {"direction": "top", "permanent": active and len(display["places"]) < 12, "className": "studio-map-label"});
            place_id = str(place["mapSelectId"] or place["id"]);
            pin.on("click", lambda { onSelect(place_id); });
        }
        frame.current = points;
        missingFocus = len(focusIds) > 0 and len(points) == 0;
    }, [JSON.stringify(display), JSON.stringify(mapFocus), selectedId, roads]);
    useEffect(lambda { if view.current and len(frame.current) > 0 { view.current.fitBounds(frame.current, {"padding": [55, 55], "maxZoom": 12, "animate": False}); } }, [snapshot["id"], JSON.stringify([[place["id"], place["lat"], place["lon"]] for place in display["places"]]), JSON.stringify(focusIds)]);
    return <section className="studio-map" aria-label="Trip map">
        <div ref={host} className="studio-map-canvas"/>
        <div className="studio-map-caption"><span className="studio-map-dot"/> Dashed lines show connections · not flight paths</div>
        {if missingFocus { <div className="studio-map-unresolved"><strong>These stops need a location check.</strong><p>The itinerary is here; their map positions are not verified yet.</p><button type="button" onClick={onLocate}>Ask Detour to locate them ↗</button></div> }}
        <div className="studio-map-zoom"><button type="button" aria-label="Zoom in" onClick={lambda { if view.current { view.current.zoomIn(); } }}>+</button><button type="button" aria-label="Zoom out" onClick={lambda { if view.current { view.current.zoomOut(); } }}>−</button></div>
    </section>;
}
