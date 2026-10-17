"""Render the search preview carried by navigation; direct links recover safely."""

import from "@jac/runtime" { useLocation }
import from ...components.RouteComparison { RouteComparison }

def:pub ResultsPage -> JsxPage {
    location = useLocation();
    state: any = location.state;
    preview: any = state["preview"] if state else None;
    submittedRequest: any = state["draft"] if state else None;
    requestText = str(state["requestText"]) if state and state["requestText"] else "";
    return <RouteComparison preview={preview} requestText={requestText} submittedRequest={submittedRequest}/>;
}
