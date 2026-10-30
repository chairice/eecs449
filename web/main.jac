"""File-based router wrapper. Route discovery supplies the child tree."""

import from server.api { plan_trip }
import from server.interpret { interpret_trip }
import from server.atlas { atlas_catalog, atlas_status, atlas_interpret, atlas_route }

def:pub app(children: any = None) -> JsxElement {
    return <>{children}</>;
}
