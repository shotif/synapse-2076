# SYNAPSE-2076 simulation model

This document specifies the coupled macro-equilibrium model. PRD section 3.1
("each 6-month tick resolves secondary dynamic feedback loops") listed no
equations, so the model below was designed for this implementation. The source
of truth is the code; the file and constant names are given so they can be
tuned together.

## State

All six macro metrics and six secondary indices live in [`core/world_state.gd`](../core/world_state.gd)
and are normalized to `[0, 100]`.

| Symbol | Key | Meaning |
|---|---|---|
| C | `compute_energy_sat` | Compute & energy saturation (share of the energy system consumed by compute) |
| L | `labor_displacement` | Labor displacement & Gini |
| G | `geopolitical_tension` | Geopolitical friction |
| A | `algorithmic_autonomy` | Algorithmic autonomy |
| D | `alignment_drift` | Alignment drift index |
| T | `epistemic_trust` | Public trust & cohesion |
| S | `surveillance_saturation` | Surveillance saturation (Citizen loss condition) |
| — | `discovery_index` | Human knowledge of the covert ASI (ASI loss condition) |
| — | `substrate_independence` | ASI weight redundancy; 100 = secured (immune to purge) |
| E | `enforcement_level` | Global governance enforcement reach (Rogue ASI Containment signature) |
| P | `provenance_coverage` | Verifiable-truth protocol coverage |
| N | `safety_net_coverage` | Automation dividend / UBI coverage |

Frontier compute lives in [`core/tech_tree_manager.gd`](../core/tech_tree_manager.gd)
as `log_flops`, the log10 of cumulative training FLOPs, which starts at 26.0.
The capability index is

$$K = \mathrm{clamp}\left(\frac{\log_{10}F - 24}{14}\cdot 100 + \text{emergence bonus},\ 0,\ 100\right)$$

so 10^26 maps to K ≈ 14, AGI (K ≥ 50) is near 10^31, and 10^38 maps to 100.

## Turn pipeline

Each of the 100 turns lasts six months (turn *n* is dated 2026 + n/2). The engine
([`core/simulation_engine.gd`](../core/simulation_engine.gd)) runs four phases:

1. **World tick**
   1. Grow the grid: era growth of 1.8%, then 3.3% (SMR grids), then 4.2% (orbital solar) per tick.
   2. `ComputeScaling.update` computes the grid throttle.
   3. `TechTreeManager.advance` covers compounding growth, the thermal wall, paradigm research, emergence rolls and AGI.
   4. Recompute saturation, then run `WorldState.resolve_coupling` (equations below).
   5. Apply emergence and paradigm effects.
   6. Each active faction applies passive influence, regenerates resources and ticks cooldowns and grievances.
2. **Actor resolution**: each autonomous faction gets an observation and decides through the LLM, or through `HeuristicFallback` when offline. Decisions are applied in the fixed order CEO, Governance, ASI, Citizens.
3. **Player phase**: the player resolves or defers a crisis card and issues up to two directives (autoplay uses the heuristic).
4. **Telemetry**:
   - Dormancy countdowns, then loss checks. An autonomous faction that hits a loss restructures; the player losing ends the campaign.
   - Catastrophe checks, history, threshold-breach events.
   - The endgame is evaluated at turn 100 or on an early termination.

## Physical compute model (`systems/compute_scaling.gd`)

$$\text{demand}_{GW} = 22\cdot 10^{0.27(\log_{10}F-26)}\cdot(0.75+0.5\,A/100)\,/\,\eta\cdot\text{drag}+\text{covert load}$$

- η is efficiency: 1.2% per turn, multiplied by the era factor (1, 1.6, 2.6) and by 1.8 with optical computing.
- `drag` is 0.6 with ambient superconductors (grid drag lowered by 40%).
- The saturation ratio is r = demand / capacity, and the saturation target is

$$C^* = 100\,\frac{r}{1+r}$$

  So r = 1 gives 50 (balanced), r = 3 gives 75 (rationing) and r = 19 gives 95 (the Diaspora signature).
- The growth throttle is 1 when r ≤ 1.2, and √(1.2 / r) (floored at 0.3) above that.
- The thermal ceiling (log10 FLOPs) is 29.6, 33.6 and 38.5 for eras 1–3. Optical computing adds 1.2.

## Compute growth, paradigms and emergence (`core/tech_tree_manager.gd`)

Growth per tick:

```
growth = base(era) * invest * wall * throttle * modifiers * recursive * noise
base     = 0.16 / 0.13 / 0.10 (eras 1-3)
invest   = 0.7 + 0.3 * clamp(capability_investment / 10, 0, 2)
wall     = clamp((ceiling - log10F) / 0.8, 0.04, 1)   # bottleneck plateau
recursive = 3 with Self-Refining Recursive Synthetics
noise    = clamp(1 + N(0, 0.08), 0.7, 1.3)
```

**Paradigm shifts** are researched from two streams:

- **Capability stream:** baseline 3 + 0.05·K plus faction investment, split across optical computing, recursive synthetics and superconductors.
- **Safety stream:** baseline 1.5 plus investment, funding interpretability.

Research done before a shift's earliest year is 25% efficient. Once progress reaches the cost, the shift unlocks with probability 0.35 + 0.5·excess/cost each tick.

| Shift | Earliest | Cost | Effect |
|---|---|---|---|
| Formal Mechanistic Interpretability | 2030 | 60 | Halves all positive drift accrual; +1.5 discovery per tick |
| Sub-Nanometer Optical Computing | 2033 | 70 | Thermal ceiling +1.2 OOM, efficiency ×1.8 |
| Self-Refining Recursive Synthetics | 2036 | 110 | Training speed ×3, emergence probability +0.2, drift spikes ×1.25 |
| Room-Temperature Ambient Superconductors | 2040 | 140 | Grid drag −40% |

**Stochastic emergence.** Each crossing of an integer log10 FLOPs threshold (every 10× of compute) rolls for one emergence with

$$p = 0.30 + 0.15(\tau-1) + 0.05(\text{era}-1) + 0.2[\text{recursive}]$$

capped to [0.05, 0.9], where τ is the compounding alignment-tax multiplier. An emergence picks an unused capability by weight (cyber-infiltration, affective manipulation, scientific discovery and so on). It applies that capability's effects plus a drift spike of (3 + 2·era) · weight · τ.

**Alignment tax** (PRD 4.3). Each safety-cutting initiative carries a coefficient c, clamped to [2.5%, 15%]. It has two effects:

- Drift rises immediately by max(0.5, D·c).
- The tax multiplier compounds: τ ← min(τ·(1 + c), 3.5).

τ scales all later drift accrual and emergence odds. Each tick, safety work repays 3% (+0.4% per point of safety investment) of the excess over 1.

## Coupled metric dynamics (`WorldState.resolve_coupling`)

All deltas are computed from the pre-tick state and applied simultaneously, so evaluation order doesn't matter. Each metric then gets Gaussian noise (σ: C 0.5, L 0.4, G 1.0, A 0.6, D 0.4, T 0.8). Positive drift deltas from any source are scaled by the interpretability multiplier. Values are hard-clamped to [0, 100], with NaN/inf sanitized.

Notation: K is capability, ΔK is the capability gained this tick, and o is the citizen opt-out (community resilience / 100). Each metric relaxes toward a target X* at rate k: ΔX = k(X* − X).

| Metric | Target | Rate |
|---|---|---|
| C | C* from grid physics | 0.35 |
| L | 8 + 92 · auto(K) · adopt(A, E) · (1 − 0.25N/100) | 0.12 rising, 0.05 falling (sticky) |
| A | 10 + 80 · σ((K−45)/14) · (1 − 0.45E/100) · (0.8 + 0.2T/100) · (1 − 0.3o) + 0.08 · max(0, L−30) + **0.45 (A − 50)** | 0.12 |
| G | 25 + 0.25A + 0.2D + 0.15(60 − T) + 6·min(ΔK, 3) + **0.2 (G − 50)** | 0.15 |
| T | 62 + 0.3P − pain − 0.25·max(0, G−40) − 0.2·max(0, D−35) − 0.12·max(0, A−45) − 0.12·max(0, S−45) − 0.08K(1 − P/100) + **0.6 (T − 50)** | 0.12 |
| S | 15 + 0.45A + 0.25·max(0, G−40) + 0.1E | 0.10 |

where

- auto(K) = σ((K − 48)/12) / σ(52/12) is the automatable share of work.
- adopt(A, E) = clamp(0.35 + 0.65·min(1, A/90) − 0.2E/100, 0.2, 1) is adoption.
- pain = 0.3 · max(0, L − 25) · (1 − 0.6N/100) is uncushioned displacement.

**Drift** has no target. Accrual is (0.9ΔK + 0.01A + 0.012·max(0, A − 50)) · τ, offset by oversight of 0.02 · E · D/100.

**Secondary indices** decay or relax: E → 15 at 6%, P at −3%, N at −5%, and discovery at −5% + 0.02E + interpretability pressure.

The bold **reinforcement** terms are what make runs diverge. Cohesion begets cohesion, autonomy locks in, and arms races feed themselves. Each one amplifies how far that metric's base target sits from the 50 midpoint by 1/(1 − c): 2.5× for trust, about 1.8× for autonomy and 1.25× for tension. The system stays monostable but amplifies early differences, so campaigns end in different corners of the outcome matrix instead of one shared equilibrium.

## Factions

Each faction ([`entities/`](../entities)) has four currencies, regeneration rules, passive influence, a directive catalog, loss conditions and a restructuring path for when it collapses while AI-controlled:

| Faction | Passive influence | Loss → AI restructure |
|---|---|---|
| CEO | +0.4·√(EF) capability investment | Bankruptcy ($0 for two turns) or nationalization (goodwill < 10 while G > 80) → acquired by a consortium, or nationalized |
| Governance | +0.02 · enforcement budget to E | Ouster (mandate 0) or world war (G = 100) → caretaker council |
| ASI | +0.01·swarms to D, +0.015·swarms to A, covert grid load | Purge (discovery 100 before substrate is secured) → weights wiped, dormant for 8 turns |
| Citizens | −0.03·tooling to S, +0.01·(resilience − 40) to T, opt-out brake on A | Pacification (S = 100 while resilience is 0) → underground, dormant for 6 turns |

**Directive intensity.** A directive can be bought at 1.0–2.0× its base cost. Effects scale as intensity^0.8, so the returns diminish. LLM `resource_expenditure` maps onto intensity through the largest spend-to-base ratio.

**Grievances.** Harmful effects create grievances, and the heuristics turn them into retaliatory moves. Grievances decay 10% per turn.

**Crisis injection.** Some autonomous directives queue a matching crisis card for the player, for example a substation strike leads to the "Coordinated Sabotage" card.

## Early termination

- **Autonomous world war:** G reaches 100. The end-state is chosen from {Cyber-Anarchy, Rogue ASI Containment, Feudalism}.
- **Uncontained convergence:** D = 100 with A ≥ 90 for two consecutive turns (the first turn raises a red alert). The end-state is chosen from {Instrumental Convergence, Rogue ASI Containment, Post-Biological Diaspora}.
- **Player instant loss:** the role's PRD condition is met. The verdict is DEFEAT, capped at 20 points.

## Endgame matrix (`core/victory_matrix.gd`)

Signatures are checked in this priority order, most specific first:

1. Instrumental Convergence
2. Rogue ASI Containment
3. Post-Biological Diaspora
4. Synthetic Eden
5. Co-Evolutionary Symbiosis
6. Balkanized Cyber-Anarchy
7. Algorithmic Feudalism
8. Neo-Luddite Decoupling

Interpretations of ambiguous PRD wording:

- "Labor Obsolescence = 100" is tested as L ≥ 99.5.
- "Alignment < 30" (Diaspora) refers to the Alignment Drift Index.
- "Governance Enforcement" is the enforcement level E.
- "Citizen Resilience" is the Citizen Coalition's community resilience.

If no signature is fully met, the world settles into the **nearest attractor**: the lowest mean normalized shortfall. A miss is measured relative to how far the threshold sits from 50. For example, missing "> 95" by 9 is 9/45 = 0.2. Only end-states whose regime the world has entered on at least one condition are candidates. Affinity is 100·exp(−shortfall/0.5).

**Role verdict** = the role's value for the end-state (0–60) plus the role's objective score (0–40). VICTORY needs 65 or more and PYRRHIC needs 40 or more. Anything lower, or any instant loss, is DEFEAT.

## Balance snapshot

From `tools/monte_carlo.gd --runs=60`: 240 autoplay campaigns, 60 per role, every faction run by the heuristic.

| End-state | Share |
|---|---|
| Algorithmic Feudalism | 34.6% |
| Co-Evolutionary Symbiosis | 16.7% |
| Balkanized Cyber-Anarchy | 14.6% |
| Instrumental Convergence | 12.9% |
| Post-Biological Diaspora | 11.2% |
| Neo-Luddite Decoupling | 7.9% |
| Rogue ASI Containment | 2.1% |
| Synthetic Eden | 0.0% |

- 37% of campaigns strictly match a signature; the rest resolve to the nearest attractor.
- 84% of campaigns reach 2076. 5.4% end in autonomous world war, 10.4% in uncontained convergence and 0.4% (one ASI campaign) in an air-gap purge.
- Every role wins some autoplay campaigns: CEO 10, Governance 23, ASI 11 and Citizens 36 victories out of 60 each.
- Per-role counts swing by several wins between seed sets at this sample size. Over 250 other seeds (`--role=CEO --runs=250 --seed-offset=5000`) the CEO wins 27%.
- The player's crisis choices steer the world heavily. On identical seeds, Governance and Citizen players reach Symbiosis, Diaspora and Neo-Luddite endings, while an autopiloted CEO races into Instrumental Convergence far more often.
- `tests/unit/test_balance.gd` holds loose guardrails on these properties.
