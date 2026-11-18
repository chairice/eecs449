"""File-based router wrapper. Route discovery supplies the child tree."""

import from server.api { plan_trip, trip_weather }
import from server.interpret { interpret_trip }
import from server.atlas { atlas_catalog, atlas_status, atlas_interpret, atlas_route }
import from client.atlas_navigation { initialize_atlas_history }
import from server.planning {
    planner_status, planner_blank, planner_guest_start, planner_guest_poll, planner_guest_stage,
    planner_guest_cancel, planner_guest_upload, planner_guest_approve, planner_guest_reject,
    planner_list, planner_import, planner_get, planner_start, planner_poll, planner_stage,
    planner_approve, planner_reject, planner_cancel, planner_upload, planner_preferences, planner_forget_preference,
    planner_undo, planner_guest_undo, planner_rename, planner_guest_rename,
    planner_confirmations, planner_guest_confirmations, planner_delete, planner_restore, planner_deleted,
    planner_weather, planner_guest_weather, planner_media, planner_guest_media
}
import from client.theme_mode { initialize_theme }

def:pub app(children: any = None) -> JsxElement {
    initialize_atlas_history();
    initialize_theme();
    return <>{children}</>;
}
