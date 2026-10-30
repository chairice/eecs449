"""Install before BrowserRouter subscribes; a dirty editor supplies the handler.

The one early listener survives route unmounts and hot reload. It delegates to
the current editor only, so other Detour pages keep ordinary browser history.
"""

def:pub initialize_atlas_history {
    browser: any = window;
    if not browser.__detourAtlasHistory {
        browser.__detourAtlasHistory = {"handler": None};
        window.addEventListener("popstate", lambda (event: any) {
            handler: any = browser.__detourAtlasHistory["handler"];
            if handler { handler(event); }
        }, True);
    }
}

def:pub set_atlas_history_handler(handler: any) {
    browser: any = window;
    initialize_atlas_history();
    browser.__detourAtlasHistory["handler"] = handler;
}
