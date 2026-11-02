"""The signed-in Detour account.

Jac's built-in user store checks the email and password and issues the session
token; this module only remembers which email that token belongs to, so the
header can name it and saved trips can be kept apart per account. Every change
is announced to the watchers below, so the header and landing panels stay in step.
"""

import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, jacLogout, jacIsLoggedIn }

glob ACCOUNT_KEY: str = "detour.account.v1";
glob:pub MIN_PASSWORD: int = 8;

def storage -> any {
    browser: any = window;
    return browser.localStorage;
}

glob watchers: list[Callable[[], None]] = [];

def announce {
    for notify in list(watchers) { notify(); }
}

def remember(email: str) {
    try { storage().setItem(ACCOUNT_KEY, email); } except Exception { }
}

def forget {
    try { storage().removeItem(ACCOUNT_KEY); } except Exception { }
}

def:pub signed_in -> bool {
    try { return bool(jacIsLoggedIn()); } except Exception { return False; }
}

"""The account's email, or "" when signed out or the browser forgot it."""
def:pub account_email -> str {
    if not signed_in() { return ""; }
    try {
        value: any = storage().getItem(ACCOUNT_KEY);
        return str(value) if value else "";
    } except Exception {
        return "";
    }
}

"""Emails compare case-insensitively; spaces around them are dropped."""
def:pub normal_email(email: str) -> str {
    return email.strip().lower();
}

"""One plain reason the form can't be sent yet, or "" when it can."""
def:pub credential_problem(email: str, password: str) -> str {
    address = normal_email(email);
    at = address.find("@");
    if address == "" { return "Enter your email."; }
    if at < 1 or address.find(".", at) < at + 2 or address.endswith(".") or " " in address {
        return "Enter an email like name@example.com.";
    }
    if password == "" { return "Enter your password."; }
    return "";
}

"""Returns "" on success, else a message to show beside the form."""
async def:pub log_in(email: str, password: str) -> str {
    ok: bool = False;
    address = normal_email(email);
    try {
        ok = await jacLogin(address, password);
    } except Exception {
        return "Detour couldn't reach the server. Try again in a moment.";
    }
    if not ok { return "That email and password don't match an account."; }
    remember(address);
    announce();
    return "";
}

"""Creates the account, then signs in with it: signup alone opens no session."""
async def:pub create_account(email: str, password: str) -> str {
    created: SignupResult | None = None;
    ok: bool = False;
    address = normal_email(email);
    if len(password) < MIN_PASSWORD {
        return "Use at least " + str(MIN_PASSWORD) + " characters for your password.";
    }
    try {
        created = await jacSignup(address, password);
    } except Exception {
        return "Detour couldn't reach the server. Try again in a moment.";
    }
    if created is None or not created.success {
        return "An account with that email may already exist. Try logging in instead.";
    }
    try {
        ok = await jacLogin(address, password);
    } except Exception {
        ok = False;
    }
    if not ok { return "Your account was created, but signing in failed. Try logging in."; }
    remember(address);
    announce();
    return "";
}

def:pub log_out {
    jacLogout();
    forget();
    announce();
}

"""Calls `onChange` after every sign-in or sign-out; returns the unsubscribe."""
def:pub watch_account(onChange: Callable[[], None]) -> Callable[[], None] {
    watchers.append(onChange);
    return lambda { watchers.remove(onChange); };
}
