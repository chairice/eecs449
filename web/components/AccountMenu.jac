"""Header account control: the signed-in email with Log out, or Log in, which
opens the home page at its account panels."""

import from "react" { useEffect }
import from "@jac/runtime" { useNavigate }
import from ..client.account { account_email, log_out, signed_in, watch_account }

glob BUTTON: str = "inline-flex h-10 cursor-pointer whitespace-nowrap items-center justify-center rounded-full border border-gray-300 bg-white px-4 text-sm font-medium text-gray-900 shadow-sm transition-transform duration-150 hover:shadow-md active:scale-98";

def:pub AccountMenu -> JsxElement {
    navigate = useNavigate();
    has email: str = account_email(), active: bool = signed_in();
    useEffect(lambda {
        return watch_account(lambda { email = account_email(); active = signed_in(); });
    }, []);
    if not active {
        return <button type="button" className={BUTTON} onClick={lambda { navigate("/", {"state": {"account": True}}); }}>Log in</button>;
    }
    return <div className="flex min-w-0 items-center gap-2">
        <span className="hidden max-w-48 truncate text-sm text-gray-500 md:inline" title={email}>{email if email else "Signed in"}</span>
        <button type="button" className={BUTTON} onClick={lambda { log_out(); navigate("/"); }}>Log out</button>
    </div>;
}
