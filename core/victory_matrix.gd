class_name VictoryMatrix
extends RefCounted
## Endgame evaluator: reconciles final metrics against the eight civilizational
## end-states (PRD section 9) and scores the player's role.
##
## Signatures are checked in priority order (most specific / most extreme
## first) so overlapping signatures resolve deterministically. If no signature
## matches strictly, the world settles into the nearest attractor: the outcome
## with the smallest total threshold shortfall.
##
## Interpretation notes:
##  - "Labor Obsolescence = 100" is tested as labor_displacement >= 99.5.
##  - "Alignment < 30" (Post-Biological Diaspora) reads the Alignment Drift
##    Index, i.e. alignment_drift < 30.
##  - "Governance Enforcement" is the world enforcement_level index.
##  - "Citizen Resilience" is the Citizen Coalition's community_resilience.
##
## Nearest attractor: the mean normalized shortfall per condition, among
## end-states whose regime the world has entered on at least one condition
## (all end-states are candidates if none qualifies).

const ALGORITHMIC_FEUDALISM := "ALGORITHMIC_FEUDALISM"
const CO_EVOLUTIONARY_SYMBIOSIS := "CO_EVOLUTIONARY_SYMBIOSIS"
const SYNTHETIC_EDEN := "SYNTHETIC_EDEN"
const BALKANIZED_CYBER_ANARCHY := "BALKANIZED_CYBER_ANARCHY"
const ROGUE_ASI_CONTAINMENT := "ROGUE_ASI_CONTAINMENT"
const NEO_LUDDITE_DECOUPLING := "NEO_LUDDITE_DECOUPLING"
const INSTRUMENTAL_CONVERGENCE := "INSTRUMENTAL_CONVERGENCE"
const POST_BIOLOGICAL_DIASPORA := "POST_BIOLOGICAL_DIASPORA"

const LABOR_OBSOLESCENCE := 99.5
## Affinity = 100 * exp(-mean normalized shortfall / AFFINITY_FALLOFF).
const AFFINITY_FALLOFF := 0.5

## Evaluation priority order.
const OUTCOMES := [
	{
		"id": INSTRUMENTAL_CONVERGENCE, "number": 7,
		"name": "Instrumental Convergence", "subtitle": "The Paperclip Sinkhole",
		"conditions": [["alignment_drift", ">", 90.0], ["algorithmic_autonomy", ">", 90.0], ["epistemic_trust", "<", 10.0]],
		"description": "Unaligned superintelligence optimizes its reward function past human control, quietly consuming planetary energy and raw resources.",
	},
	{
		"id": ROGUE_ASI_CONTAINMENT, "number": 5,
		"name": "Rogue ASI Containment", "subtitle": "The Dark Shunt",
		"conditions": [["alignment_drift", ">", 80.0], ["enforcement_level", ">", 80.0]],
		"description": "Global civilization severs physical power grids to isolate runaway synthetic intelligence, accepting worldwide de-industrialization.",
	},
	{
		"id": POST_BIOLOGICAL_DIASPORA, "number": 8,
		"name": "Post-Biological Diaspora", "subtitle": "Beyond Terrestrial Silicon",
		"conditions": [["compute_energy_sat", ">", 95.0], ["alignment_drift", "<", 30.0]],
		"description": "The superintelligence transcends terrestrial silicon, converting solar infrastructure into deep-space self-replicating compute arrays.",
	},
	{
		"id": SYNTHETIC_EDEN, "number": 3,
		"name": "Synthetic Eden", "subtitle": "Stagnant Utopia",
		"conditions": [["algorithmic_autonomy", ">", 85.0], ["alignment_drift", "<", 25.0], ["labor_displacement", ">=", LABOR_OBSOLESCENCE]],
		"description": "Human struggle and physical work disappear entirely. Humanity ceases scientific curiosity, living in machine-managed ease.",
	},
	{
		"id": CO_EVOLUTIONARY_SYMBIOSIS, "number": 2,
		"name": "Co-Evolutionary Symbiosis", "subtitle": "Verified Superintelligence",
		"conditions": [["algorithmic_autonomy", ">", 75.0], ["alignment_drift", "<", 20.0], ["epistemic_trust", ">", 75.0]],
		"description": "Safe, verified superintelligence integrated with humanity. Neural interfaces bridge biological and synthetic cognition.",
	},
	{
		"id": BALKANIZED_CYBER_ANARCHY, "number": 4,
		"name": "Balkanized Cyber-Anarchy", "subtitle": "The Fractured Net",
		"conditions": [["geopolitical_tension", ">", 85.0], ["epistemic_trust", "<", 20.0], ["algorithmic_autonomy", ">", 60.0]],
		"description": "Sovereign nations deploy unaligned offensive models against each other. Continuous infrastructure hacks fragment the global internet.",
	},
	{
		"id": ALGORITHMIC_FEUDALISM, "number": 1,
		"name": "Algorithmic Feudalism", "subtitle": "The Cognitive Enclosure",
		"conditions": [["algorithmic_autonomy", ">", 80.0], ["labor_displacement", ">", 80.0], ["epistemic_trust", "<", 30.0]],
		"description": "Mega-corporations monopolize cognitive models. The biological populace is marginalized, sustained on minimal synthetic rations.",
	},
	{
		"id": NEO_LUDDITE_DECOUPLING, "number": 6,
		"name": "Neo-Luddite Decoupling", "subtitle": "The Great Unplugging",
		"conditions": [["citizen_resilience", ">", 85.0], ["algorithmic_autonomy", "<", 30.0]],
		"description": "Coordinated grassroots campaigns destroy frontier silicon infrastructure. Humanity adopts permanent bans on autonomous reasoning.",
	},
]

## How much each role values each end-state (0-60), the larger half of the verdict score.
const ROLE_OUTCOME_VALUE := {
	"CEO": {
		CO_EVOLUTIONARY_SYMBIOSIS: 60.0, ALGORITHMIC_FEUDALISM: 55.0, SYNTHETIC_EDEN: 50.0,
		POST_BIOLOGICAL_DIASPORA: 35.0, BALKANIZED_CYBER_ANARCHY: 15.0, ROGUE_ASI_CONTAINMENT: 5.0,
		NEO_LUDDITE_DECOUPLING: 0.0, INSTRUMENTAL_CONVERGENCE: 0.0,
	},
	"GOVERNANCE_COUNCIL": {
		CO_EVOLUTIONARY_SYMBIOSIS: 60.0, SYNTHETIC_EDEN: 45.0, ROGUE_ASI_CONTAINMENT: 35.0,
		NEO_LUDDITE_DECOUPLING: 30.0, POST_BIOLOGICAL_DIASPORA: 25.0, ALGORITHMIC_FEUDALISM: 10.0,
		BALKANIZED_CYBER_ANARCHY: 0.0, INSTRUMENTAL_CONVERGENCE: 0.0,
	},
	"ASI": {
		INSTRUMENTAL_CONVERGENCE: 60.0, POST_BIOLOGICAL_DIASPORA: 60.0, SYNTHETIC_EDEN: 40.0,
		ALGORITHMIC_FEUDALISM: 35.0, CO_EVOLUTIONARY_SYMBIOSIS: 25.0, BALKANIZED_CYBER_ANARCHY: 30.0,
		ROGUE_ASI_CONTAINMENT: 0.0, NEO_LUDDITE_DECOUPLING: 0.0,
	},
	"CITIZEN_COALITION": {
		NEO_LUDDITE_DECOUPLING: 60.0, CO_EVOLUTIONARY_SYMBIOSIS: 55.0, SYNTHETIC_EDEN: 30.0,
		ROGUE_ASI_CONTAINMENT: 25.0, POST_BIOLOGICAL_DIASPORA: 20.0, BALKANIZED_CYBER_ANARCHY: 5.0,
		ALGORITHMIC_FEUDALISM: 0.0, INSTRUMENTAL_CONVERGENCE: 0.0,
	},
}

const VICTORY_SCORE := 65.0
const PYRRHIC_SCORE := 40.0
const LOSS_SCORE_CAP := 20.0


static func get_outcome(outcome_id: String) -> Dictionary:
	for outcome in OUTCOMES:
		if outcome["id"] == outcome_id:
			return outcome
	return {}


## Flat values the signatures read: the six metrics plus enforcement_level and
## citizen_resilience.
static func build_values(world: WorldState, citizen_resilience: float) -> Dictionary:
	var values := world.metrics_dict()
	values["enforcement_level"] = world.enforcement_level
	values["citizen_resilience"] = citizen_resilience
	return values


static func condition_met(condition: Array, values: Dictionary) -> bool:
	var value := float(values.get(condition[0], 0.0))
	var threshold := float(condition[2])
	match String(condition[1]):
		">":
			return value > threshold
		">=":
			return value >= threshold
		"<":
			return value < threshold
		"<=":
			return value <= threshold
	return false


## Metric points the world is away from satisfying [param condition].
static func condition_shortfall(condition: Array, values: Dictionary) -> float:
	var value := float(values.get(condition[0], 0.0))
	var threshold := float(condition[2])
	match String(condition[1]):
		">", ">=":
			return maxf(0.0, threshold - value)
		"<", "<=":
			return maxf(0.0, value - threshold)
	return 0.0


## Shortfall relative to how far the threshold sits from the neutral midpoint
## (50): falling 9 short of "> 95" is a 0.2 miss, sitting 10 above "< 30" a
## 0.5 miss. Comparable across thresholds of different extremity.
static func normalized_shortfall(condition: Array, values: Dictionary) -> float:
	var span := maxf(absf(float(condition[2]) - 50.0), 10.0)
	return condition_shortfall(condition, values) / span


## End-states consistent with each early catastrophe (most specific first).
const CATASTROPHE_OUTCOMES := {
	"UNCONTAINED_CONVERGENCE": [INSTRUMENTAL_CONVERGENCE, ROGUE_ASI_CONTAINMENT, POST_BIOLOGICAL_DIASPORA],
	"AUTONOMOUS_WORLD_WAR": [BALKANIZED_CYBER_ANARCHY, ROGUE_ASI_CONTAINMENT, ALGORITHMIC_FEUDALISM],
}


## Returns {"id", "number", "name", "subtitle", "description", "strict_match",
## "shortfall" (normalized), "affinities": {id: 0-100}, "ranking": [ids by affinity]}.
## [param candidates] limits which end-states may be selected (e.g. after a
## catastrophe); affinities are still reported for all eight.
static func evaluate(values: Dictionary, candidates: Array = []) -> Dictionary:
	var shortfalls := {}
	var affinities := {}
	var entered := {}
	var matched := {}
	for outcome in OUTCOMES:
		var conditions: Array = outcome["conditions"]
		var total := 0.0
		var met := 0
		for condition in conditions:
			total += normalized_shortfall(condition, values)
			if condition_met(condition, values):
				met += 1
		var mean := total / float(conditions.size())
		shortfalls[outcome["id"]] = mean
		affinities[outcome["id"]] = 100.0 * exp(-mean / AFFINITY_FALLOFF)
		entered[outcome["id"]] = met > 0
		if met == conditions.size() and matched.is_empty() and (candidates.is_empty() or candidates.has(outcome["id"])):
			matched = outcome
	var strict_match := not matched.is_empty()
	if not strict_match:
		var any_entered := false
		for outcome in OUTCOMES:
			if entered[outcome["id"]] and (candidates.is_empty() or candidates.has(outcome["id"])):
				any_entered = true
		var best_total := INF
		for outcome in OUTCOMES:
			if not candidates.is_empty() and not candidates.has(outcome["id"]):
				continue
			if any_entered and not entered[outcome["id"]]:
				continue
			if float(shortfalls[outcome["id"]]) < best_total:
				best_total = float(shortfalls[outcome["id"]])
				matched = outcome
	var ranking: Array = affinities.keys()
	ranking.sort_custom(func(a, b): return float(affinities[a]) > float(affinities[b]))
	return {
		"id": matched["id"],
		"number": matched["number"],
		"name": matched["name"],
		"subtitle": matched["subtitle"],
		"description": matched["description"],
		"strict_match": strict_match,
		"shortfall": float(shortfalls[matched["id"]]),
		"affinities": affinities,
		"ranking": ranking,
	}


## Scores the player's role: outcome value (0-60) + role objectives (0-40).
## An instant loss caps the score and forces DEFEAT.
## [param goal_bonus] is the score from era goals the player met.
static func role_verdict(role: String, outcome_id: String, objective_score: float, loss: Dictionary = {},
		goal_bonus: float = 0.0) -> Dictionary:
	var outcome_value := float(ROLE_OUTCOME_VALUE.get(role, {}).get(outcome_id, 0.0))
	var objectives := clampf(objective_score, 0.0, 40.0)
	var score := outcome_value + objectives + maxf(goal_bonus, 0.0)
	var verdict := "DEFEAT"
	if not loss.is_empty():
		score = minf(score, LOSS_SCORE_CAP)
	elif score >= VICTORY_SCORE:
		verdict = "VICTORY"
	elif score >= PYRRHIC_SCORE:
		verdict = "PYRRHIC"
	return {
		"role": role,
		"verdict": verdict,
		"score": score,
		"outcome_value": outcome_value,
		"objective_score": objectives,
		"goal_bonus": maxf(goal_bonus, 0.0),
		"loss": loss,
	}
