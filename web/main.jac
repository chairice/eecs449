"""File-based router wrapper. Route discovery supplies the child tree."""

import from server.api { plan_trip, trip_weather }
import from server.interpret { interpret_trip }
import from server.atlas { atlas_catalog, atlas_status, atlas_interpret, atlas_route }
import from client.atlas_navigation { initialize_atlas_history }
import from client.theme_mode { initialize_theme }

def:pub app(children: any = None) -> JsxElement {
    initialize_atlas_history();
    initialize_theme();
    return <>{children}</>;
}
