"""Copy for the landing page, kept in one place so it is easy to edit."""

obj:pub TextCard {
    has title: str,
        body: str;
}

glob:pub GOALS: list[TextCard] = [
         TextCard(
             title="Automate routine tasks",
             body="Find the chores that are repetitive and rule-based, and let the agent handle them from start to finish."
         ),
         TextCard(
             title="Keep it conversational",
             body="Talk to it in plain language, ask follow-up questions, and correct it without learning special commands."
         ),
         TextCard(
             title="Use real tools",
             body="Connect to the calendar, email, and to-do apps you already use, so the agent acts instead of just suggesting."
         ),
         TextCard(
             title="Keep you in control",
             body="It asks before anything important or hard to undo, explains what it did, and respects your privacy."
         ),
         TextCard(
             title="Measure the benefit",
             body="Check whether the agent really saves time and effort compared with doing the same tasks by hand."
         )
     ];

glob:pub USE_CASES: list[TextCard] = [
         TextCard(
             title="Inbox triage",
             body="Summarize an overflowing inbox and surface what needs a reply today."
         ),
         TextCard(
             title="Scheduling",
             body="Find meeting times that work and sort out calendar conflicts."
         ),
         TextCard(
             title="Deadlines",
             body="Track assignments, bills, and renewals, and remind you before they are due."
         ),
         TextCard(
             title="Errands and meals",
             body="Plan grocery runs, errands, and the week's meals around your schedule."
         ),
         TextCard(
             title="Routine replies",
             body="Draft the quick, predictable messages you send over and over."
         )
     ];

glob:pub STEPS: list[TextCard] = [
         TextCard(
             title="Say what you need",
             body="\"Find a time for our project meeting this week and remind everyone the day before.\""
         ),
         TextCard(
             title="The agent plans it",
             body="It breaks the request into steps and picks the right tools, such as your calendar and email."
         ),
         TextCard(
             title="You approve, it finishes",
             body="It checks with you before sending anything, then does the work and reports back."
         )
     ];
