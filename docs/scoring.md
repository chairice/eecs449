# Deterministic route planning

`rank_routes(request, candidates, as_of, risk_by_route=None)` in
`web/server/planner.jac` is a pure planning function over canonical models. It
does not fetch routes or weather, call an LLM, access a clock, save a plan, or
modify its inputs. The caller supplies an offset-aware `as_of` timestamp for
reproducible freshness decisions and may supply validated risk assessments by
route ID. `RankingResult` exposes ordered scored routes, rejected route IDs and
constraint codes, effective weights, and an optional typed error.

## Hard constraints run first

A candidate is rejected if any leg is canceled, any transit mode is excluded,
its known fare exceeds a strict cap, its unknown fare cannot be certified within
that cap, its transfer slack is below the requested minimum, or its time falls
outside the requested window. All applicable rejection codes are retained.

The requested date and departure cutoff use the first origin's IANA time zone;
an arrival cutoff uses the final destination's zone. The constrained endpoint
must occur on the requested local date. Exact cutoff times are accepted.
Ambiguous/nonexistent DST times and date-conversion overflows are invalid
requests. Offset-aware timestamps determine elapsed duration, independent of
how the local clock is displayed.

Transfer slack is the time between consecutive transit vehicles **minus the
duration of intervening walking legs**. Walking neither adds a vehicle transfer
nor violates a train/bus mode selection. A 50-minute connection containing a
20-minute walk therefore provides 30 minutes of slack.

Only feasible candidates contribute duration and fare normalization. An
impossible cheap or fast route cannot change the scores of feasible routes.
An empty candidate set or an entirely rejected set returns `NO_ROUTES`.
Malformed canonical data, duplicate route IDs, invalid supplied risk, and
invalid time inputs return `INVALID_REQUEST`.

## Utilities and risk

Higher utilities are better; each lies in `[0, 1]`.

| Dimension | Utility |
| --- | --- |
| Duration | `(longest - duration) / (longest - shortest)` among feasible candidates |
| Known fare | `(highest - price) / (highest - lowest)` among feasible known fares |
| Unknown fare, without a strict cap | Neutral `0.5` plus uncertainty |
| Transfers | `risk_utility(transfer risk) / (1 + number of vehicle transfers)` |
| Reliability and weather | `LOW → 1`, `MODERATE → 0.5`, `HIGH → 0`, `UNKNOWN → 0.5` |

When every known duration or price is equal, that dimension has utility `1` for
all known candidates. With no known fares, every fare utility remains neutral.

Without supplied risk, the worst known transit-leg delay determines delay risk:
under 15 minutes is low, 15 through 29 is moderate, and 30 or more is high. This
coarse threshold model preserves the full delay minutes as evidence; delays
above the high-risk threshold receive no further reliability decrease. Missing
data on another leg never removes a known high-risk observation. Weather starts
unknown. Transfer risk is moderate when slack is less than 15 minutes above the
minimum; otherwise it is low. Hard-infeasible transfers were already removed.
This threshold changes utility as well as warnings: a single tight transfer has
utility `0.25`, while a single comfortable transfer has utility `0.5`. A direct
route with low transfer risk has utility `1`.

A route source is stale when its expiry is at or before `as_of`. Stale delay
evidence becomes unknown and receives neutral reliability utility. Data stays
visible with stale and missing-data reason codes.

## Score and presets

```text
base = duration_weight    * duration_utility
     + reliability_weight * reliability_utility
     + price_weight       * price_utility
     + transfer_weight    * transfer_utility
     + weather_weight     * weather_utility

score = 100 * base - 10 * uncertainty
```

| Preset | Duration | Reliability | Price | Transfers | Weather |
| --- | ---: | ---: | ---: | ---: | ---: |
| Balanced | 0.30 | 0.25 | 0.20 | 0.15 | 0.10 |
| Fastest | 0.55 | 0.15 | 0.10 | 0.10 | 0.10 |
| Lowest cost | 0.15 | 0.15 | 0.50 | 0.10 | 0.10 |
| Most reliable | 0.15 | 0.45 | 0.10 | 0.20 | 0.10 |
| Fewest transfers | 0.15 | 0.20 | 0.10 | 0.45 | 0.10 |

The baseline uncertainty is one quarter for each missing dimension: fare,
delay, weather, and freshness. Delay counts as missing if its assessment is
unknown or any transit leg lacks a predicted delay. Stale data adds the
freshness quarter and makes delay unknown. The final uncertainty is the maximum
of this baseline and the supplied assessment's uncertainty, so supplied
confidence cannot erase a known missing-data condition.

Scores are rounded to six decimal places before ordering. Equal scores break
ties by fewer transfers, earlier actual arrival, lower known price (unknown
last), then route ID. Reversing candidate input order does not alter ranking.
Feature values, effective weights, risk, and deduplicated reason codes remain
available for inspection and later draft persistence.

## Verification

Run `jac check tests/planner_tests.jac` and
`jac test tests/planner_tests.jac -v` from `web/`. The suite constructs canonical
objects directly and does not depend on the fixture provider. It verifies all
presets, speed/price tradeoffs, hard constraints, filtering before normalization,
walking slack, timezone and DST handling, date overflow, unknown/stale evidence,
partial high-risk observations, thresholds, every tie-break level, determinism,
input preservation, and typed failures.

These rules are an inspectable MVP heuristic, not a statistical probability of
delay or an assurance that a route is safe. Future weather/provider work must
supply normalized evidence and can replace risk thresholds through an explicit
design update without placing HTTP or LLM calls inside the ranker.
