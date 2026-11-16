# Trip planner: interaction blueprint

Current work: read [DETOUR-AGENT-HANDOFF.md](DETOUR-AGENT-HANDOFF.md) for the November 15 revisions to branding, landing/studio navigation, pricing, approvals, trip management and weather. This document retains the earlier baseline for reference.

Status: adopted UI/UX baseline. November 14, 2026. The user has delegated routine visual choices and prioritized an intuitive, powerful interface. This document develops the agreed [functional decisions](trip-planner-decisions.md) into concrete interaction rules. Adoption confirms shared understanding and does not authorize application implementation.

## What the interface must make clear

At any moment, a user should be able to answer:

1. What does the app understand about my trip?
2. Which part am I looking at or asking about?
3. What is the most useful next decision?
4. What is already in my plan, and what is merely proposed?
5. What will happen if I choose this action?

Use the Quiet atlas layout as the designer-owned starting point: overview/itinerary, linked map, and compact collapsible chat. Preserve the chosen dark calm style. Evaluate the design through these questions and real planning tasks, rather than further palette/layout voting.

## New trip: reach a useful plan quickly

### Entry

Show one conversational starting point: “What are you planning?” Include a few example requests and paste/upload entry points. Examples demonstrate possibilities; they are not rigid trip modes. No sign-in or mandatory intake form blocks the first useful result.

A user can start with a vague idea, known dates and destination, a professional commitment, or a pasted itinerary. The AI infers the appropriate detail level and confirms it naturally. It asks only for information needed for the next meaningful step.

### First value

Make useful progress before collecting every preference. A vacation can start with a proposed route and overnight bases. A work trip can start with its known meeting/hotel commitments and unresolved transport. Missing information stays visible without turning the screen into an error report.

Show a concise explanation plus a visual proposal. The proposal belongs on the map and itinerary, not in a long chat paragraph. Label it “Proposed,” and make approval/refinement clear. If nothing has been approved yet, do not pretend an accepted itinerary already exists.

### Inputs and approvals

Clarification replies and uploads are inputs, not occasions for repeated approval dialogs. They can feed research and the next coherent proposal. Every proposed update to the accepted trip still needs preview and approval.

For example, “two adults” can supply the current stay search's party without a separate confirmation button. Selecting a result then produces a coherent proposal that includes any corresponding trip metadata changes. If the reply contradicts an accepted fact, keep the accepted plan intact and incorporate the new fact into the proposed revision. Do not silently rewrite the accepted trip.

This distinction preserves the agreed approval rule without making users approve every conversational answer twice.

## Guide one decision, allow any direction

The AI suggests one next decision and brings the relevant information into focus. The user can always choose another topic through chat or inspect another day/place.

Examples:

| Current situation | Concise guidance | Relevant surface |
| --- | --- | --- |
| Rough vacation route proposed | “Here is the route and where you would stay. What would you change?” | Proposed map and overnight bases |
| Route approved; no stays selected | “Let’s compare Tucson stays. Who’s traveling?” | Relevant location/nights and a focused clarification |
| One day is crowded | “We can keep all stops or leave a longer afternoon break.” | Selected day's outline and tradeoff |
| Hotel already booked for a work trip | “I’ll keep your hotel fixed and focus on transport.” | Commitments and transport needs |
| User interrupts stay search to discuss a hike | Answer the hike request and retain the search state | Selected hike context; research continues only within its authorized request |

Quick replies are concise conversational affordances alongside free-form input. They send an intent/answer into the same chat flow. They do not bypass interpretation, validation, or approval. Offer only relevant choices; do not make every turn a menu.

Keep a lightweight internal record of unfinished decisions so the assistant can resume after interruptions. The normal screen emphasizes the next useful step, not a large task-management dashboard.

## Overview, day, and item

A saved multi-day trip opens at overview: dates, route, overnight bases, and compact access to days. Selecting a day shows its outline/schedule and highlights its map context. Selecting an item opens supporting details; returning restores the day and scroll context.

The user is inspecting the same trip throughout. Do not create independent pages with disconnected selections or require them to re-explain the trip after opening details.

Detailed times, driving, openings, daylight, reservations, and buffers carry their evidence state. A provisional day is useful before checks finish, but it must stay visibly provisional. A work trip with no activity-planning intent does not get empty sightseeing sections.

## One conversation, explicit item context

Selecting a place/day/route for viewing is separate from asking about it. Provide an obvious “Ask about this” action in its details. That action attaches a removable context label to the main composer and focuses it.

Example sequence:

1. Open Day 5.
2. Select Bell Rock.
3. Choose “Ask about this place.”
4. Composer displays “About: Day 5 · Bell Rock.”
5. User types “replace this with something easier.”
6. AI interprets the request using explicit item references and current trip state.
7. It shows an alternative and any connected schedule changes in a proposal.
8. Approval updates the trip; refinement keeps the current plan intact.

Removing the label clears the request scope, not the conversation or selected view. Changing the inspected item must not silently change an already attached scope. A clear global request can override the contextual hint; ask for clarification only when the intended scope is genuinely ambiguous.

Use stable entity/revision references internally. If a referenced item has been removed or changed, resolve or clarify before editing. The study demonstrates one attached context at a time; a comparison can eventually attach a clear grouped reference such as two candidate stays, rather than spawning separate chats.

## Research and comparisons

Research runs without repeated provider-permission prompts once the necessary inputs are present. Show a truthful task label and Stop. Keep the itinerary and chat usable. Completed background work should not interrupt someone inspecting another item; notify quietly and let them return to results. If they are waiting on that task, focus its results normally.

Show a small curated comparison with consistent fields and recognizable provider identity. Include only offers meeting the agreed exact-date availability and total-price gate. Deeper terms expand on inspection. Make the difference between inspecting, choosing, and booking explicit.

The user can request “quieter,” “closer,” “less expensive,” “another source,” or “show more” through chat. Preserve prior results as context when useful, but do not mix different dates/parties into one current comparison.

Selecting an offer prepares its trip-change proposal. Opening a provider booking link is an external handoff. It does not mark the trip item booked. A user report or confirmation upload can support a reviewed booking-status update.

## Review changes in context

Prefer a focused review within the workspace rather than sending the user to a disconnected page. Keep the affected day/route recognizable. Show:

- The requested change and why the AI proposes it.
- Concrete additions, removals, moved dates/times, and connected effects.
- Fixed commitments that are preserved or conflicting.
- Relevant cost changes and any unresolved evidence.

Use one main approval action for the coherent proposal, with conversational refinement and an easy return to the current plan. A user can ask for a narrower proposal; do not force them to manually repair dependent fields.

After approval, acknowledge the actual change briefly and suggest the next useful step. Do not show an oversized success page. If the proposal is stale, explain that the trip changed and provide an updated preview before applying anything.

## Return, save, and research recovery

Recover the latest trip, conversation, selected context where still valid, and pending work. Show the current plan and a short continuation cue instead of requiring users to reread the whole transcript.

Guests get local recovery. After an initial useful plan, offer sign-in for durable cross-device saving without interrupting planning. Save indicators must distinguish local recovery, acknowledged account save, pending save, and failure. Keep a local recovery copy until account import succeeds.

When research cannot verify something, retain the rest of the trip and explain the specific missing result. Retries should not reset the workspace or discard collected context. Do not fill the gap with a fabricated offer or block all other planning.

## Phone convention: adopted default

Use three clear primary views: Trip, Map, and Chat, with bottom navigation. A saved trip opens on Trip overview. New-trip entry remains conversational. Context and pending work travel between views.

“Ask about this” takes the user to Chat with its context label attached. Returning to Trip restores the inspected day/item. Comparison and approval use focused full-width views with an obvious return path. Keep the composer above the keyboard and make the scope of an approval inspectable.

This convention was adopted with the UX baseline. The earlier prototype's narrow stacked layout is a rendering fallback, not the intended production phone navigation. The updated interaction study focuses on desktop context/guidance behavior; it does not claim to implement this complete phone convention.

Approved itinerary/booking details remain readable offline. Research, map retrieval, and new conversational planning require a connection. Offline status explains the capability that is unavailable while keeping the saved plan useful.

## What the updated study demonstrates

- A single designer-selected workspace, without aesthetic variant voting.
- A recommended next action and contextual conversational choices.
- Opening a day and a place without losing trip context.
- Explicit “Ask about this” actions and a removable main-composer context label.
- Editable message staging that shows attached context; it makes no AI request and proves no conversational semantics.
- A scripted outline-change proposal and approval interaction.

Illustrative photographs and sourced regional map geometry remain design assets, not travel research. There are no live offers or real booking actions in the study.

## Usability acceptance tasks

Once implemented, validate observed task completion rather than treating a visually polished screen as proof:

1. Start an Arizona-style vacation from a vague request and reach an understood first proposal without a full intake form.
2. Arrange transport for a work trip whose hotel is already booked, without entering a vacation workflow.
3. Point at one activity and request an easier alternative without retyping its name or accidentally changing another day.
4. Explain which state is current, what a pending proposal changes, and how to keep/refine the current plan.
5. Compare stays, understand total price/source/evidence, and distinguish selecting from booking.
6. Interrupt one planning task, return to it, and retain the relevant selections and inputs.
7. Resume on a phone, navigate Trip/Map/Chat, and read approved booking details offline.

For each task, record hesitation, misunderstood controls, unnecessary typing, repeated clarification, wrong-scope requests, and lost context. Do not invent user-test metrics. Prototype checks and actual-user/model/provider tests remain separate evidence.

## Observed study checks

Browser inspection verified the recommended Day 5 action, opening Bell Rock, attaching “About: Day 5 · Bell Rock,” and staging a typed request with that scope. Removing context preserved the inspected place and the unchanged original timeline. The “More relaxed” shortcut opened a pending proposal; “Keep current plan” retained Tlaquepaque and did not insert the proposed free afternoon. A widget-state restoration bug that initially closed place details was corrected and the path rechecked.

These are interface study observations. They do not establish live model interpretation, supplier research, account durability, phone navigation, or user-study success. No application implementation or real trip change was performed.
