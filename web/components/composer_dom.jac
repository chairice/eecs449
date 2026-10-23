"""Small DOM boundary for moving focus to a field after a failed search."""

def:pub focus_field(id: str) {
    element: any = document.getElementById(id);
    if element { element.focus(); }
}
