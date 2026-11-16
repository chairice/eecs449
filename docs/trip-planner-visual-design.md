# Trip planner: visual and interaction design

Status: supporting visual studies for the adopted UI/UX baseline; subjective styling choices delegated to the designer. November 14, 2026. The [interaction blueprint](trip-planner-ux-blueprint.md) governs the adopted UX. Functionality is agreed in [the decision log](trip-planner-decisions.md); the [product and architecture proposal](trip-planner-design.md) remains the functional baseline. No application code was changed to create these studies.

## Agreed art direction

- A calm travel studio with a dark theme.
- Strong visual reference: [Olaf Dsouza's Food page](https://olafdsouza.com/food). Browser inspection showed near-black surfaces, clear sans-serif typography, quiet borders, generous spacing, and photography supplying much of the color.
- Selective photography: compact place/stay cards; larger images when inspecting an item. Map and itinerary remain the primary planning surfaces.
- Trip overview first, then drill into one day. Logistics-only trips have a simpler travel/stays overview.
- Compact persistent desktop chat, with a collapse control.
- Subdued dark default map. The route and selected stops receive emphasis; background roads, terrain, and labels should remain quiet.

## Layout studies under review

Both studies use the same interaction model, dark palette, typography, content, and compact chat. They differ in where the visual attention goes.

| Direction | Composition | Strength | Tradeoff |
| --- | --- | --- | --- |
| Quiet atlas | Compact linear list of overnight bases; more room for the map; day details occupy the same list column | Makes route construction and geographic reasoning central; compact photos support recognition | Less photographic atmosphere in the initial overview; narrow day details need careful progressive disclosure |
| Trip collection | More room for a two-column photographed base collection; smaller linked map | Closer to the reference's visual collection; easier to recognize and browse destinations | Gives the map less space; cards must remain concise as trips grow |

Designer decision: refine Quiet atlas because the user's process starts with locations, routes, driving, and overnight bases. The user delegated this aesthetic/layout judgment and emphasized an intuitive interface. Do not spend further interview rounds asking them to art-direct these variants; evaluate the interface through concrete planning tasks.

The study permits opening any of the ten supplied days, selecting a base, inspecting an activity, collapsing chat, and trying a sample review/approval transition. These interactions are local design demonstrations, not a connected model, persisted account, live provider search, or production map implementation.

## Proposed visual system

The values below are designer recommendations for review, not claims about the reference site's exact CSS.

| Role | Proposed treatment |
| --- | --- |
| App background | Near black, `#0b0c0c` |
| Persistent chat surface | Slightly lifted, `#101212` |
| Selected/raised surface | `#181b1a` |
| Quiet separators | `#272b29`, used sparingly |
| Main text | Soft white, `#eeefec` |
| Supporting text | `#a3aaa5`; essential information must remain readable |
| Route/selection accent | Restrained sage, `#a9c6b4`; provisional, not a settled brand color |
| Primary action | Soft white fill with dark text |
| Typography | Inter or a comparably clean sans-serif; regular and medium weights |
| Type scale | Approximately 27–28px trip title, 14px body/section text, 12px supporting information; 11px only for secondary metadata |
| Spacing | 4/8/12/16/24/32px rhythm; around 24px for principal content margins |
| Shape | Modest radii: roughly 7–8px for photos/controls, 10–12px for composer and contained surfaces |

Keep global navigation quiet and compact. Avoid a large permanent navigation sidebar that competes with the itinerary, map, and conversation. Surfaces separate through placement, whitespace, and small changes in tone. Use photos, the map route, and actual selection state for emphasis rather than coloring every section.

Recommended palette principle: the application stays neutral; the trip supplies personality. Warm Arizona imagery can coexist with colder Alaska imagery without changing the app's whole theme. Provider identity stays recognizable within consistent card geometry.

## Information hierarchy

The app guides one recommended next decision at a time, with the relevant panel in focus and concise conversational controls. The user can jump to any other part of the trip. This guidance policy is agreed; exact wording and controls are designer-owned implementation choices. Do not turn it into a rigid sequence of mandatory screens.

### Trip overview

1. Trip name and dates.
2. Small day strip, with one clear selected state and an obvious route back to overview.
3. Route, overnight bases, and a compact indication of night allocation.
4. Contextual planning conversation.

Show useful trip metadata, not a dashboard of decorative metrics. Missing accommodation, an infeasible constraint, or a pending proposal should appear where it affects a decision. Do not cover the overview in repeated warning badges.

### Day detail

Keep the day's name/date and overnight location immediately visible. Use aligned times and short activity labels. Separate travel, activities, meals, and free time through structure and text; do not assign a saturated color to every category. Open supporting details rather than printing them beneath every item.

A selected day highlights the corresponding map context. Preserve user orientation: avoid unsolicited camera jumps while a user reads or compares details. Exact fit/pan behavior remains to be refined with the chosen composition.

### Place and stay details

Use the larger image at this level. Show the information needed for the current decision with clear source attribution. Timings and operational facts retain their evidence state. Photo quality must not make an unverified quote or claim look authoritative.

Production photos should actually correspond to their place/property and have a usable source. Decorative mood images must not masquerade as researched property images.

### Comparisons

Use one consistent visual grammar for source-branded cards: image, provider identity, product name, exact dates/party, verified total, relevant tradeoffs, evidence time, and source action. Keep the total's unit explicit. Source logos/names support recognition, while card typography and geometry stay part of the app.

Comparison occupies the active detail surface, not a fourth permanent desktop column. The map can highlight candidates where location matters. A shortlist should be scannable at a glance, with deeper conditions available on inspection. Only qualifying verified offers can appear; the study contains no fabricated offer cards.

### Conversation

Compact user message surface, unframed assistant prose, deliberate whitespace, and a visible composer. The trip remains readable during a conversation. Context from a selected day/item can be shown quietly; full contextual annotation is still an optional idea.

The AI communicates findings and the next meaningful decision concisely. Tool details and long explanations expand when useful. Scrolling the transcript should not cause the map or itinerary to lose its selected context. Composer access and research cancellation remain easy to find.

Agreed selection behavior: use the main chat with a clear removable item-context chip. “Ask about this” attaches the selected place/day/route; removing the chip returns to unscoped trip conversation without deleting history. Free-form annotations remain optional. Do not open independent mini threads.

### Review and approval

Make proposed state visibly distinct from the approved itinerary. Use actual before/after fields and a short consequence summary; do not rely only on red/green color. Keep the approval action prominent and the current plan inspectable. Declining or refining the proposal should feel routine, not destructive.

The local sample removes an afternoon shopping stop and leaves free time while retaining the sunset plan. It demonstrates approval of an outline change; it does not claim that the detailed schedule has been externally checked.

## Motion and feedback proposals

- Use short, restrained transitions, around 160–220ms as an initial design target.
- Keep selection, focus, pending research, proposed changes, and saved/approved state visually distinguishable.
- Preserve context across overview/day/detail transitions. Avoid animating the whole screen for a small change.
- Research progress describes real activity, with a stop action. Show no invented completion percentages.
- Respect reduced-motion settings and retain keyboard-visible focus.
- Target at least 44px effective touch controls; audit contrast, focus order, zoom, and keyboard interactions in actual components.

## Responsive design

The studies check that content reflows without horizontal overflow at 320px and 360px. Their narrow view stacks the regions for exploration; this is not a final phone navigation design.

Production phone UX still needs one focused design decision: switching among itinerary/map/chat while preserving selected context and keeping the composer reachable. The desktop's three visible areas should not simply become three long pages stacked together. Comparison and review need focused phone views.

The same content and state model should support both layouts. Compact responsive presentation must preserve source/evidence details and the scope of an approval.

## Study assets and evidence

Preview-only assets are under the task-owned visualization directory:

- [Interactive study](</Users/bhavyemathur/.codex/visualizations/2026/11/14/01a1dab4-570c-7ce2-87a0-823c3cd939d5/dark-travel-studio.html>)
- [Illustrative photo sheet](</Users/bhavyemathur/.codex/visualizations/2026/11/14/01a1dab4-570c-7ce2-87a0-823c3cd939d5/illustrative-southwest.jpg>)

The photo sheet was generated with the built-in imagegen tool, then encoded as JPEG for the preview. It depicts invented Southwest scenery and a terrace. It is not source evidence of any destination, hotel, Airbnb, price, or available stay. The exact generation prompt is preserved beside the preview as `illustrative-southwest-prompt.md`.

The map study embeds the project's Natural Earth state boundaries and GeoNames city coordinates. Straight connections show intended stop order, not calculated road routes. The study does not yet evaluate a detailed road/terrain tile source.

Browser checks observed both composition variants, day drill-down, collapsing/reopening chat, and the sample outline before and after approval. The map rendered. The pre-approval timeline retained the shopping stop; approval replaced it with free afternoon. No horizontal overflow was measured at 320px or 360px. These checks validate the study's interactions only, not the application's implementation or full accessibility.

## Remaining visual frontier

- Make one next action understandable while retaining the freedom to change direction.
- Resolve styling and layout details through designer judgment; refine them when actual task walkthroughs expose friction.
- Design the focused mobile workspace.
- Detail first-entry/empty, research, comparison, conflict, and approval states using the chosen visual grammar.
- Confirm the complete visual and interaction specification before application implementation.

## Current interaction proposal

The user redirected emphasis toward intuitive interaction and delegated subjective styling choices. The current usability proposal is [the interaction blueprint](trip-planner-ux-blueprint.md). It proposes the phone Trip/Map/Chat convention and develops clarification inputs, coherent approval, and interruption recovery without further aesthetic voting.

The [updated interaction study](</Users/bhavyemathur/.codex/visualizations/2026/11/14/01a1dab4-570c-7ce2-87a0-823c3cd939d5/trip-planner-interaction-study.html>) removes variant selection and adds guided next actions, conversational shortcuts, explicit item context, context removal, and local message staging. It is the current review surface; the two-layout study above is historical exploration. Its narrow stacked rendering is still not a complete implementation of the proposed phone navigation.
