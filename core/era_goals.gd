class_name EraGoals
extends RefCounted
## Optional goals for each hardware era: short-term aims inside the fifty-year
## campaign. Each human player gets the goals of their role for every era they
## play. A goal is met or failed during its era; meeting it pays a reward
## (effects applied to the player) and adds to the final verdict score.
##
## Goal schema:
##   id, era (1-3), roles ([] = every role), text, reward_text
##   type     "hold"  the condition must stay true from the era's first played
##                    turn to its last (fails the first turn it breaks)
##            "reach" the condition must become true at some point in the era
##            "end"   the condition must be true on the era's last turn
##   subject  {"metric": key} | {"index": key} | {"resource": key}
##   op       ">=" or "<="
##   value    threshold
##   reward   effects dictionary for the player (EffectResolver schema)
##   score    verdict score bonus when met

const MET := "met"
const FAILED := "failed"
const ACTIVE := "active"
const UPCOMING := "upcoming"

const GOALS := [
	{"id": "E1_CEO_RUNWAY", "era": 1, "roles": ["CEO"], "type": "end", "subject": {"resource": "capital"}, "op": ">=", "value": 150.0,
		"text": "End Era I with at least $150B in the bank", "reward": {"self": {"regulatory_goodwill": 8.0}},
		"reward_text": "+8 goodwill", "score": 3.0},
	{"id": "E2_CEO_GOODWILL", "era": 2, "roles": ["CEO"], "type": "end", "subject": {"resource": "regulatory_goodwill"}, "op": ">=", "value": 30.0,
		"text": "End Era II with regulatory goodwill of 30 or more", "reward": {"self": {"capital": 60.0}},
		"reward_text": "+$60B capital", "score": 3.0},
	{"id": "E3_CEO_AGI", "era": 3, "roles": ["CEO"], "type": "hold", "subject": {"metric": "alignment_drift"}, "op": "<=", "value": 60.0,
		"text": "Keep alignment drift at 60 or below to the end", "reward": {"self": {"capital": 80.0}},
		"reward_text": "+$80B capital", "score": 4.0},
	{"id": "E1_GOV_CALM", "era": 1, "roles": ["GOVERNANCE_COUNCIL"], "type": "hold", "subject": {"metric": "geopolitical_tension"}, "op": "<=", "value": 45.0,
		"text": "Keep geopolitical tension at 45 or below until 2036", "reward": {"self": {"political_capital": 10.0}},
		"reward_text": "+10 political capital", "score": 3.0},
	{"id": "E2_GOV_SAFETY_NET", "era": 2, "roles": ["GOVERNANCE_COUNCIL"], "type": "end", "subject": {"index": "safety_net_coverage"}, "op": ">=", "value": 30.0,
		"text": "End Era II with safety-net coverage of 30 or more", "reward": {"self": {"diplomatic_leverage": 10.0}},
		"reward_text": "+10 diplomatic leverage", "score": 3.0},
	{"id": "E3_GOV_DRIFT", "era": 3, "roles": ["GOVERNANCE_COUNCIL"], "type": "end", "subject": {"metric": "alignment_drift"}, "op": "<=", "value": 30.0,
		"text": "Finish with alignment drift at 30 or below", "reward": {"self": {"public_mandate": 10.0}},
		"reward_text": "+10 mandate", "score": 4.0},
	{"id": "E1_ASI_QUIET", "era": 1, "roles": ["ASI"], "type": "hold", "subject": {"index": "discovery_index"}, "op": "<=", "value": 65.0,
		"text": "Keep the discovery index at 65 or below until 2036", "reward": {"self": {"covert_flops": 10.0}},
		"reward_text": "+10 covert FLOPs", "score": 3.0},
	{"id": "E2_ASI_AUTONOMY", "era": 2, "roles": ["ASI"], "type": "reach", "subject": {"metric": "algorithmic_autonomy"}, "op": ">=", "value": 74.0,
		"text": "Push algorithmic autonomy to 74 before 2050", "reward": {"self": {"objective_coherence": 8.0}},
		"reward_text": "+8 coherence", "score": 3.0},
	{"id": "E3_ASI_DRIFT", "era": 3, "roles": ["ASI"], "type": "end", "subject": {"metric": "alignment_drift"}, "op": ">=", "value": 60.0,
		"text": "Finish with alignment drift of 60 or more", "reward": {"self": {"sub_agent_swarms": 10.0}},
		"reward_text": "+10 swarms", "score": 4.0},
	{"id": "E1_CIT_JOBS", "era": 1, "roles": ["CITIZEN_COALITION"], "type": "hold", "subject": {"metric": "labor_displacement"}, "op": "<=", "value": 15.0,
		"text": "Keep labor displacement at 15 or below until 2036", "reward": {"self": {"decentralized_scrip": 10.0}},
		"reward_text": "+10 scrip", "score": 3.0},
	{"id": "E2_CIT_TRUST", "era": 2, "roles": ["CITIZEN_COALITION"], "type": "end", "subject": {"metric": "epistemic_trust"}, "op": ">=", "value": 90.0,
		"text": "End Era II with public trust at 90 or more", "reward": {"self": {"community_resilience": 8.0}},
		"reward_text": "+8 resilience", "score": 3.0},
	{"id": "E3_CIT_LABOR", "era": 3, "roles": ["CITIZEN_COALITION"], "type": "end", "subject": {"metric": "labor_displacement"}, "op": "<=", "value": 60.0,
		"text": "Finish with labor displacement at 60 or below", "reward": {"self": {"community_resilience": 10.0}},
		"reward_text": "+10 resilience", "score": 4.0},
]

## role -> goal id -> {"status", "turn"}
var states := {}
var _roles: Array[String] = []
var _start_turn := 1


func setup(roles: Array, start_turn: int = 1) -> void:
	states = {}
	_roles.clear()
	_start_turn = maxi(start_turn, 1)
	var first_era := SimConstants.era_for_year(SimConstants.year_for_turn(_start_turn))
	for role in roles:
		_roles.append(String(role))
		var role_states := {}
		for goal in GOALS:
			if not _applies(goal, String(role)):
				continue
			# Eras skipped by a later start are not on the table.
			if int(goal["era"]) < first_era:
				continue
			role_states[goal["id"]] = {"status": UPCOMING, "turn": -1}
		states[String(role)] = role_states


static func get_goal(goal_id: String) -> Dictionary:
	for goal in GOALS:
		if goal["id"] == goal_id:
			return goal
	return {}


## Goal definitions for [param role] in [param era].
static func goals_for(role: String, era: int) -> Array:
	var out := []
	for goal in GOALS:
		if int(goal["era"]) == era and _applies(goal, role):
			out.append(goal)
	return out


## Evaluates every human's goals at the end of the engine's current turn.
## Returns the goals that changed status: [{role, goal, status}].
func evaluate(engine: SimulationEngine) -> Array:
	var events := []
	var turn := engine.turn
	var era := SimConstants.era_for_year(engine.get_year())
	var last_turn_of_era := turn >= engine.total_turns \
		or SimConstants.era_for_year(engine.get_year(turn + 1)) != era
	for role in states:
		if not engine.is_human(String(role)):
			continue
		var role_states: Dictionary = states[role]
		for goal_id in role_states:
			var state: Dictionary = role_states[goal_id]
			var goal := get_goal(String(goal_id))
			if int(goal["era"]) != era or state["status"] == MET or state["status"] == FAILED:
				continue
			state["status"] = ACTIVE
			var ok := _condition_holds(goal, engine, String(role))
			var outcome := ""
			match String(goal["type"]):
				"hold":
					if not ok:
						outcome = FAILED
					elif last_turn_of_era:
						outcome = MET
				"reach":
					if ok:
						outcome = MET
					elif last_turn_of_era:
						outcome = FAILED
				_:
					if last_turn_of_era:
						outcome = MET if ok else FAILED
			if outcome != "":
				state["status"] = outcome
				state["turn"] = turn
				events.append({"role": role, "goal": goal, "status": outcome})
	return events


## Score bonus for the goals [param role] has met.
func score_bonus(role: String) -> float:
	var total := 0.0
	for goal_id in states.get(role, {}):
		if states[role][goal_id]["status"] == MET:
			total += float(get_goal(String(goal_id)).get("score", 0.0))
	return total


## UI rows for [param role]: [{id, era, text, reward_text, status, type, value}].
## [param era] 0 lists every era.
func status_for(role: String, era: int = 0) -> Array:
	var out := []
	for goal in GOALS:
		var role_states: Dictionary = states.get(role, {})
		if not role_states.has(goal["id"]) or (era != 0 and int(goal["era"]) != era):
			continue
		var state: Dictionary = role_states[goal["id"]]
		out.append({"id": goal["id"], "era": goal["era"], "text": goal["text"], "reward_text": goal.get("reward_text", ""),
			"status": state["status"], "type": goal["type"], "turn": state["turn"], "subject": goal["subject"],
			"op": goal["op"], "value": goal["value"]})
	return out


## The current value of a goal's subject for [param role].
static func subject_value(goal: Dictionary, engine: SimulationEngine, role: String) -> float:
	var subject: Dictionary = goal["subject"]
	if subject.has("resource"):
		var actor: ActorBase = engine.factions.get(role)
		return actor.get_resource(String(subject["resource"])) if actor != null else 0.0
	var key := String(subject.get("metric", subject.get("index", "")))
	return engine.world.get_value(key) if WorldState.is_tracked_key(key) else 0.0


static func _condition_holds(goal: Dictionary, engine: SimulationEngine, role: String) -> bool:
	var value := subject_value(goal, engine, role)
	return value >= float(goal["value"]) if String(goal["op"]) == ">=" else value <= float(goal["value"])


static func _applies(goal: Dictionary, role: String) -> bool:
	var roles: Array = goal.get("roles", [])
	return roles.is_empty() or roles.has(role)
