"""Opening section: what the project is, in one breath."""

def:pub Hero -> JsxElement {
    return
        <section id="top" className="hero">
            <div className="hero-inner">
                <div className="hero-copy">
                    <p className="hero-eyebrow">
                        EECS 449 · Conversational AI · University of Michigan
                    </p>
                    <h1 className="hero-title">
                        Hand off the chores that fill your day.
                    </h1>
                    <p className="hero-lede">
                        Everyday Agent is a conversational AI that takes care of small, repetitive tasks like sorting email, scheduling, and tracking deadlines. Tell it what you want done; it plans the steps, uses your tools, and checks in before anything important.
                    </p>
                    <div className="hero-actions">
                        <a href="#goals" className="hero-primary">See our goals</a>
                        <a href="#how-it-works" className="hero-secondary">
                            How it works
                        </a>
                    </div>
                </div>
                <div className="hero-chat" aria-hidden="true">
                    <p className="hero-bubble hero-user">
                        Can you find a time for our project meeting this week?
                    </p>
                    <p className="hero-bubble hero-agent">
                        Everyone's free Thursday 4-5 PM. Want me to send the invite and a reminder the day before?
                    </p>
                </div>
            </div>
        </section>;
}
