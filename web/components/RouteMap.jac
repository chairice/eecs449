"""Light basemap showing a trip's stops and, once there is a route, the path
each leg runs: trains as solid lines, buses dashed, over a white casing so
they read against the grey tiles. Without segments it pins the stops only;
with fewer than two stops it frames the Ann Arbor to Chicago demo corridor.
"""

import "leaflet/dist/leaflet.css";
import from "react" { useEffect }
import from "leaflet" { map as leafletMap, tileLayer, circleMarker, polyline, layerGroup }
import from .comparison_view { ComparisonStop, ComparisonSegment }

glob CORRIDOR: list[list[float]] = [[42.2877, -83.743], [41.8786, -87.6405]];
# Matches --dt-accent; Leaflet paints SVG attributes, which cannot read CSS variables.
glob ROUTE_GREEN: str = "#1f7a3d";

def:pub RouteMap(stops: list[ComparisonStop], label: str, segments: list[ComparisonSegment] = []) -> JsxElement {
    has host: Ref[HTMLDivElement] = Ref();
    has view: Ref[any] = Ref(None);
    has pins: Ref[any] = Ref(None);
    key = "|".join([str(stop.latitude) + "," + str(stop.longitude) for stop in stops]) + "#" + "|".join([segment.mode + str(len(segment.points)) + str(segment.points[0]) for segment in segments]);
    modes = [segment.mode for segment in segments];

    def draw {
        m: any = view.current;
        group: any = pins.current;
        if not m or not group { return; }
        group.clearLayers();
        frame: list[list[float]] = [];
        for segment in segments {
            dashed = segment.mode == "Bus";
            polyline(segment.points, {"color": "#ffffff", "weight": 8, "opacity": 0.9, "lineCap": "round", "lineJoin": "round"}).addTo(group);
            polyline(segment.points, {"color": ROUTE_GREEN, "weight": 4, "opacity": 0.95, "lineCap": "round", "lineJoin": "round", "dashArray": "2 8" if dashed else None}).addTo(group);
            frame = frame + segment.points;
        }
        for (index, stop) in enumerate(stops) {
            endpoint = index == 0 or index == len(stops) - 1;
            circleMarker([stop.latitude, stop.longitude], {"radius": 8 if endpoint else 6, "color": "#ffffff", "weight": 3, "fillColor": ROUTE_GREEN, "fillOpacity": 1}).bindTooltip(stop.name).addTo(group);
            frame.append([stop.latitude, stop.longitude]);
        }
        # A lone stop sits inside the corridor's frame rather than filling the map.
        m.fitBounds(frame if len(frame) > 1 else CORRIDOR, {"padding": [56, 56]});
    }

    useEffect(lambda {
        if host.current {
            created: any = leafletMap(host.current, {"zoomControl": False, "scrollWheelZoom": False});
            # OpenStreetMap's standard tiles, greyed in CSS so the green route leads.
            tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
                "attribution": "&copy; <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap</a> contributors", "maxZoom": 19
            }).addTo(created);
            view.current = created;
            pins.current = layerGroup().addTo(created);
            draw();
        }
        return lambda {
            current: any = view.current;
            if current { current.remove(); }
            view.current = None;
        };
    }, []);
    useEffect(lambda { draw(); }, [key]);

    return <div className="dt-map-frame">
        <div className="dt-map" ref={host} role="img" aria-label={label}></div>
        {(<ul className="dt-map-legend" aria-hidden="true">
            {(<li><span className="dt-map-key is-train"></span>Train</li> if "Train" in modes else None)}
            {(<li><span className="dt-map-key is-bus"></span>Bus</li> if "Bus" in modes else None)}
        </ul> if len(segments) > 0 else None)}
    </div>;
}
