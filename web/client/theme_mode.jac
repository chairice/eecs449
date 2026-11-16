"""Light, dark or system colour theme, remembered in this browser.

The stored preference is "light", "dark" or "system" (stored as absent).
"system" follows `prefers-color-scheme`. The resolved theme is written to
`<html data-theme>`, which the stylesheets key their dark tokens on. A head
script in jac.toml applies the same rule before the bundle loads, so the first
paint already has the right palette; this module keeps it in step afterwards.

Storage and matchMedia can be missing or throw (private windows, blocked site
data, non-browser test runs), so every browser call tolerates failure.
"""

glob:pub THEME_KEY: str = "detour.theme.v1";
glob DARK_QUERY: str = "(prefers-color-scheme: dark)";

"""Any stored or passed value as a known preference; unknown values mean system."""
def:pub normal_preference(value: any) -> str {
    if value == "light" or value == "dark" { return str(value); }
    return "system";
}

"""The theme to paint for a preference, given whether the OS asks for dark."""
def:pub resolve_theme(preference: str, system_dark: bool) -> str {
    choice = normal_preference(preference);
    if choice == "system" { return "dark" if system_dark else "light"; }
    return choice;
}

def storage -> any {
    browser: any = window;
    return browser.localStorage;
}

def:pub load_preference -> str {
    try {
        return normal_preference(storage().getItem(THEME_KEY));
    } except Exception {
        return "system";
    }
}

"""Remember a preference; "system" clears the key. False when storage refused."""
def:pub save_preference(preference: str) -> bool {
    choice = normal_preference(preference);
    try {
        if choice == "system" {
            storage().removeItem(THEME_KEY);
        } else {
            storage().setItem(THEME_KEY, choice);
        }
        return True;
    } except Exception {
        return False;
    }
}

def:pub system_prefers_dark -> bool {
    try {
        browser: any = window;
        return bool(browser.matchMedia(DARK_QUERY).matches);
    } except Exception {
        return False;
    }
}

"""Paint a resolved theme onto <html>; the CSS tokens follow the attribute."""
def:pub apply_theme(theme: str) {
    try {
        page: any = document.documentElement;
        page.dataset.theme = "dark" if theme == "dark" else "light";
        page.style.colorScheme = "dark" if theme == "dark" else "light";
    } except Exception { }
}

glob current: str = "system";
glob watchers: list[Callable[[str], None]] = [];

def announce {
    for notify in list(watchers) { notify(current); }
}

def repaint {
    apply_theme(resolve_theme(current, system_prefers_dark()));
}

"""The preference in effect for this page."""
def:pub theme_preference -> str {
    return current;
}

"""Choose a preference: remember it, repaint, and tell the watchers."""
def:pub set_preference(preference: str) {
    current = normal_preference(preference);
    save_preference(current);
    repaint();
    announce();
}

"""Call `onChange` with the preference whenever it changes; returns a stop function."""
def:pub watch_theme(onChange: Callable[[str], None]) -> Callable[[], None] {
    watchers.append(onChange);
    return lambda { if onChange in watchers { watchers.remove(onChange); } };
}

"""Read the stored preference, paint it, and follow the OS and other tabs.

Safe to call on every render: the listeners are installed once per page.
"""
def:pub initialize_theme {
    try {
        browser: any = window;
        if browser.__detourTheme { return; }
        browser.__detourTheme = True;
        current = load_preference();
        repaint();
        mql: any = browser.matchMedia(DARK_QUERY);
        mql.addEventListener("change", lambda (event: any) {
            if current == "system" { repaint(); }
        });
        browser.addEventListener("storage", lambda (event: any) {
            if event.key == THEME_KEY or event.key == None {
                current = load_preference();
                repaint();
                announce();
            }
        });
    } except Exception { }
}
