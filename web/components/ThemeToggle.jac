"""Header colour-theme control: Light, Dark or System, as three pressed-state
buttons in one pill. The choice is remembered in this browser (see
client/theme_mode.jac); System follows the operating system's setting."""

import from "react" { useEffect }
import from .Icon { Icon }
import from ..client.theme_mode { set_preference, theme_preference, watch_theme }

glob OPTION: str = "dt-theme-option inline-grid h-8 w-8 cursor-pointer place-items-center rounded-full border-0 p-0 transition-colors duration-150";
glob CHOICES: list[list[str]] = [["light", "Light", "sun"], ["dark", "Dark", "moon"], ["system", "System", "display"]];

def:pub ThemeToggle -> JsxElement {
    has choice: str = theme_preference();
    useEffect(lambda {
        choice = theme_preference();
        return watch_theme(lambda (next: str) { choice = next; });
    }, []);
    return <div className="dt-theme-toggle inline-flex shrink-0 items-center gap-0.5 rounded-full border border-gray-300 bg-white p-0.5 shadow-sm" role="group" aria-label="Color theme">
        {[
            <button key={item[0]} type="button" className={OPTION + (" bg-emerald-50 text-emerald-800" if choice == item[0] else " bg-transparent text-gray-500 hover:text-gray-900")}
                aria-pressed={"true" if choice == item[0] else "false"} title={item[1] + " theme"}
                onClick={lambda { set_preference(item[0]); }}>
                <Icon name={item[2]} size={16}/><span className="dt-sr-only">{item[1]}</span>
            </button>
            for item in CHOICES
        ]}
    </div>;
}
