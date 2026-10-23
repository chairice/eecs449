"""Light basemap showing a trip's stops and the line between them.

It pins only the stops it is given. With none, it frames the Ann Arbor to
Chicago demo corridor without marking anything.
"""

import "leaflet/dist/leaflet.css";
import from "react" { useEffect }
import from "leaflet" { map as leafletMap, tileLayer, circleMarker, polyline, layerGroup }
import from .comparison_view { ComparisonStop }

glob CORRIDOR: list[list[float]] = [[42.2877, -83.743], [41.8786, -87.6405]];
# Matches --dt-accent; Leaflet paints SVG attributes, which cannot read CSS variables.
glob ROUTE_GREEN: str = "#1f7a3d";

def:pub RouteMap(stops: list[ComparisonStop], label: str) -> JsxElement {
    has host: Ref[HTMLDivElement] = Ref();
    has view: Ref[any] = Ref(None);
    has pins: Ref[any] = Ref(None);
    key = "|".join([str(stop.latitude) + "," + str(stop.longitude) for stop in stops]);

    def draw {
        m: any = view.current;
        group: any = pins.current;
        if not m or not group { return; }
        group.clearLayers();
        points = [[stop.latitude, stop.longitude] for stop in stops];
        if len(points) > 1 {
            polyline(points, {"color": ROUTE_GREEN, "weight": 4, "opacity": 0.85, "lineCap": "round"}).addTo(group);
        }
        for (index, stop) in enumerate(stops) {
            endpoint = index == 0 or index == len(stops) - 1;
            circleMarker([stop.latitude, stop.longitude], {"radius": 8 if endpoint else 5, "color": "#ffffff", "weight": 3, "fillColor": ROUTE_GREEN, "fillOpacity": 1}).bindTooltip(stop.name).addTo(group);
        }
        if len(points) == 1 {
            m.setView(points[0], 9);
        } else {
            m.fitBounds(points if len(points) > 0 else CORRIDOR, {"padding": [56, 56]});
        }
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

    return <div className="dt-map" ref={host} role="img" aria-label={label}></div>;
}
