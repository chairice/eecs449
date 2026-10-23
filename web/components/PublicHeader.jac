"""Marketing header: the brand and the one entry into trip planning."""

import from .Brand { Brand }
import from .Icon { Icon }
import from "@jac/runtime" { Link }

def:pub PublicHeader -> JsxElement {
    return <header className="dt-header">
        <div className="dt-header-inner">
            <Brand/>
            <Link className="dt-primary" to="/plan">Plan a trip<Icon name="arrow.up.right"/></Link>
        </div>
    </header>;
}
