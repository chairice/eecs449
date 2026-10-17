"""File-based router wrapper. Route discovery supplies the child tree."""

import from server.api { plan_trip }

def:pub app(children: any = None) -> JsxElement {
    return <>{children}</>;
}
