"""Chat with Detour, after Airbnb's AI assistant: starter prompts, a running
conversation, and one rounded composer with a round send button."""

import from react { useEffect }
import from .Icon { Icon }

# action names the manual search panel a reply can open: "where", "when" or "".
obj:pub ChatMessage { has id: int, sender: str, text: str, action: str = ""; }

glob ACTION_LABELS: dict[str, str] = {"where": "Choose a destination", "when": "Pick dates"};

glob STARTERS: list[str] = ["Chicago this Friday after 4pm", "Chicago tomorrow, under $40", "Ann Arbor Nov 3, back Nov 5"];

"""Your messages sit on the right; Detour's on the left beside its mark."""
def:pub ChatBubble(message: ChatMessage, onAction: Callable[[str], None]) -> JsxElement {
    if message.sender == "user" { return <p className="dt-msg dt-msg-user">{message.text}</p>; }
    return <div className="dt-msg dt-msg-detour">
        <span className="dt-msg-avatar" aria-hidden="true"><Icon name="route" size={16}/></span>
        <div className="dt-msg-body">
            <p><span className="dt-sr-only">Detour: </span>{message.text}</p>
            {(<button type="button" className="dt-msg-action" onClick={lambda { onAction(message.action); }}>{ACTION_LABELS[message.action]}</button> if message.action in ACTION_LABELS else None)}
        </div>
    </div>;
}

def:pub AskDetour(
    onSend: Callable[[str], None],
    messages: list[ChatMessage] = [],
    busy: bool = False,
    readBy: str = "",
    # Opens the manual search: "" for a plain reveal, or the panel to open.
    onManual: Callable[[str], None] | None = None,
    manualOpen: bool = False
) -> JsxElement {
    has draft: str = "";
    has thread: Ref[HTMLDivElement] = Ref();
    talking = len(messages) > 0;

    def send(text: str) {
        if busy or text.strip() == "" { return; }
        draft = "";
        onSend(text.strip());
    }
    # Keep the newest message in view as the conversation grows.
    useEffect(lambda {
        box: any = thread.current;
        if box { box.scrollTop = box.scrollHeight; }
    }, [len(messages), busy]);

    return <section className={"dt-chat" + (" is-talking" if talking else "")} aria-label="Chat with Detour">
        {(<div className="dt-chat-thread" ref={thread} role="log" aria-live="polite" aria-label="Conversation">
            {for message in messages { <ChatBubble key={message.id} message={message} onAction={lambda (action: str) { if onManual is not None { onManual(action); } }}/> }}
            {(<div className="dt-msg dt-msg-detour"><span className="dt-msg-avatar" aria-hidden="true"><Icon name="route" size={16}/></span><p className="dt-typing" aria-label="Detour is reading"><span></span><span></span><span></span></p></div> if busy else None)}
        </div> if talking else None)}
        <form className="dt-chat-compose" onSubmit={lambda (e: FormEvent) { e.preventDefault(); send(draft); }}>
            <label className="dt-sr-only" htmlFor="ask-request">Message Detour</label>
            <input id="ask-request" type="text" maxLength={500} autoComplete="off" value={draft}
                placeholder={"Reply to Detour" if talking else "Where do you need to be, and when?"}
                onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}/>
            <button className="dt-chat-send" type="submit" aria-label="Send" disabled={busy or draft.strip() == ""}><Icon name="arrow.up" size={18}/></button>
        </form>
        {(<div className="dt-chat-starters" aria-label="Try asking">
            {for starter in STARTERS { <button key={starter} type="button" className="dt-chat-starter" disabled={busy} onClick={lambda { send(starter); }}>{starter}</button> }}
        </div> if not talking else None)}
        {(<button type="button" className="dt-chat-manual" onClick={lambda { onManual(""); }}>Or choose a destination and dates yourself</button> if onManual is not None and not manualOpen else None)}
        {(<p className="dt-chat-credit">{"Answers by Claude" if readBy == "claude" else "Answers by Detour's built-in parser"}</p> if talking and readBy != "" else None)}
    </section>;
}
