"""Marketing header: the brand, the account control, and the entry into planning."""

import from .Brand { Brand }
import from .Icon { Icon }
import from .AccountMenu { AccountMenu }
import from .ThemeToggle { ThemeToggle }
import from "@jac/runtime" { Link }

# Sticky bar over the green backdrop: translucent sky tint, blurred, hairline below.
glob:pub HEADER: str = "dt-header border-b border-sky-200/70 bg-linear-to-r from-sky-100/90 via-sky-50/90 to-cyan-100/90 backdrop-blur-md";

def:pub PublicHeader -> JsxElement {
    return <header className={HEADER}>
        <div className="dt-header-inner">
            <Brand/>
            <div className="flex flex-wrap items-center gap-3">
                <ThemeToggle/>
                <AccountMenu/>
                <Link className="dt-primary bg-linear-to-r from-emerald-600 to-green-700 font-semibold text-white shadow-sm active:scale-98" to="/plan">Plan a trip<Icon name="arrow.up.right"/></Link>
            </div>
        </div>
    </header>;
}
