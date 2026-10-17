"""Small DOM boundary used after the accessible error summary has rendered."""

def:pub focus_composer_errors {
    element: any = document.getElementById("composer-errors");
    if element { element.focus(); }
}
