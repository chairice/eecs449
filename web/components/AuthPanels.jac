"""Account entry points under the home page hero: log in beside create an
account, or, once signed in, who is signed in and the way into planning.
Jac's user store checks the password; nothing is emailed."""

import from "react" { useEffect }
import from "@jac/runtime" { Link, useNavigate }
import from .FloatingField { FloatingField }
import from .Icon { Icon }
import from ..browser { scrollToTop }
import from ..client.account { MIN_PASSWORD, account_email, create_account, credential_problem, log_in, log_out, signed_in, watch_account }

glob CARD: str = "rounded-2xl border border-gray-200 bg-white p-6 text-left shadow-sm transition-shadow duration-200 hover:shadow-md sm:p-8";
glob PRIMARY: str = "inline-flex h-12 w-full cursor-pointer border-0 items-center justify-center gap-2 rounded-xl bg-linear-to-r from-emerald-600 to-green-700 px-6 text-base font-semibold text-white shadow-sm transition-transform duration-150 hover:from-emerald-700 hover:to-green-800 active:scale-98 disabled:cursor-not-allowed disabled:opacity-60";
glob ERROR: str = "rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700";

def:pub LoginPanel -> JsxElement {
    navigate = useNavigate();
    has email: str = "", password: str = "", problem: str = "", busy: bool = False;
    async def submit {
        if busy { return; }
        problem = credential_problem(email, password);
        if problem { return; }
        busy = True;
        failure = await log_in(email, password);
        busy = False;
        if failure {
            problem = failure;
            password = "";
            return;
        }
        navigate("/plan");
        scrollToTop();
    }
    return <section className={CARD} aria-labelledby="login-title">
        <p className="text-sm font-medium text-emerald-700">Returning traveler</p>
        <h2 id="login-title" className="mt-1 text-2xl font-semibold tracking-tight text-gray-900">Welcome back</h2>
        <p className="mt-1 text-sm text-gray-500">Log in to see the trips saved to your account.</p>
        <form className="mt-6" noValidate={True} onSubmit={lambda (e: FormEvent) { e.preventDefault(); submit(); }}><fieldset className="m-0 grid min-w-0 gap-3 border-0 p-0" disabled={busy}>
            <FloatingField id="login-email" label="Email" kind="email" autoComplete="email" value={email}
                onChange={lambda (v: str) { email = v; }} invalid={bool(problem)}/>
            <FloatingField id="login-password" label="Password" kind="password" autoComplete="current-password" value={password}
                onChange={lambda (v: str) { password = v; }} invalid={bool(problem)}/>
            {if problem { <p className={ERROR} role="alert">{problem}</p> }}
            <button type="submit" className={PRIMARY + " mt-2"} disabled={busy}>{"Logging in…" if busy else "Log in"}</button>
        </fieldset></form>
    </section>;
}

def:pub SignupPanel -> JsxElement {
    navigate = useNavigate();
    has email: str = "", password: str = "", confirm: str = "", problem: str = "", busy: bool = False;
    async def submit {
        if busy { return; }
        problem = credential_problem(email, password);
        if not problem and len(password) < MIN_PASSWORD {
            problem = "Use at least " + str(MIN_PASSWORD) + " characters for your password.";
        }
        if not problem and confirm != password { problem = "The two passwords don't match."; }
        if problem { return; }
        busy = True;
        failure = await create_account(email, password);
        busy = False;
        if failure {
            problem = failure;
            return;
        }
        navigate("/plan");
        scrollToTop();
    }
    steps = [
        ("Your email", "It's how you log in. No confirmation email is sent."),
        ("A password", "At least " + str(MIN_PASSWORD) + " characters."),
        ("Start planning", "Trips you save stay with this account.")
    ];
    return <section className={CARD} aria-labelledby="signup-title">
        <p className="text-sm font-medium text-emerald-700">New to Detour</p>
        <h2 id="signup-title" className="mt-1 text-2xl font-semibold tracking-tight text-gray-900">Create a new account</h2>
        <ol className="m-0 mt-5 grid list-none gap-3 p-0 sm:grid-cols-3">
            {for (index, step) in enumerate(steps) {
                <li key={step[0]} className="flex gap-3 sm:block">
                    <span className="inline-grid size-7 shrink-0 place-items-center rounded-full bg-emerald-50 text-sm font-semibold text-emerald-700 ring-1 ring-emerald-200">{index + 1}</span>
                    <span className="grid sm:mt-2"><span className="text-sm font-medium text-gray-900">{step[0]}</span><span className="text-sm text-gray-500">{step[1]}</span></span>
                </li>
            }}
        </ol>
        <form className="mt-6" noValidate={True} onSubmit={lambda (e: FormEvent) { e.preventDefault(); submit(); }}><fieldset className="m-0 grid min-w-0 gap-3 border-0 p-0" disabled={busy}>
            <FloatingField id="signup-email" label="Email" kind="email" autoComplete="email" value={email}
                onChange={lambda (v: str) { email = v; }} invalid={bool(problem)}/>
            <div className="grid gap-3 sm:grid-cols-2">
                <FloatingField id="signup-password" label="Password" kind="password" autoComplete="new-password" value={password}
                    onChange={lambda (v: str) { password = v; }} invalid={bool(problem)}/>
                <FloatingField id="signup-confirm" label="Confirm password" kind="password" autoComplete="new-password" value={confirm}
                    onChange={lambda (v: str) { confirm = v; }} invalid={bool(problem)}/>
            </div>
            {if problem { <p className={ERROR} role="alert">{problem}</p> }}
            <button type="submit" className={PRIMARY + " mt-2"} disabled={busy}>{"Creating your account…" if busy else "Create account"}</button>
        </fieldset></form>
    </section>;
}

def:pub AuthPanels -> JsxElement {
    has email: str = account_email(), active: bool = signed_in();
    useEffect(lambda {
        return watch_account(lambda { email = account_email(); active = signed_in(); });
    }, []);
    return <section id="account" className="w-full scroll-mt-28 text-left" aria-label="Your Detour account">
        {(
            <div className={CARD + " mx-auto flex max-w-2xl flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between"}>
                <div>
                    <p className="text-sm font-medium text-emerald-700">Signed in</p>
                    <h2 className="mt-1 text-2xl font-semibold tracking-tight text-gray-900">Welcome back</h2>
                    <p className="mt-1 text-sm text-gray-500">{email if email else "Your account"}</p>
                </div>
                <div className="flex w-full gap-3 sm:w-auto">
                    <button type="button" onClick={lambda { log_out(); }}
                        className="inline-flex h-12 flex-1 cursor-pointer items-center justify-center rounded-xl border border-gray-300 bg-white px-5 text-base font-medium text-gray-900 transition-transform duration-150 hover:border-gray-900 active:scale-98 sm:flex-none">Log out</button>
                    <Link to="/plan" className="inline-flex h-12 flex-1 items-center justify-center gap-2 rounded-xl bg-linear-to-r from-emerald-600 to-green-700 px-5 text-base font-semibold text-white no-underline shadow-sm transition-transform duration-150 hover:from-emerald-700 hover:to-green-800 active:scale-98 sm:flex-none">Plan a trip<Icon name="arrow.right"/></Link>
                </div>
            </div>
        ) if active else (
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
                <LoginPanel/>
                <SignupPanel/>
            </div>
        )}
    </section>;
}
