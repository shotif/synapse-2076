class_name TurningPoints
extends RefCounted
## The moments a campaign turned on, read from the engine's event log, for the
## debrief's "What if?" rewinds:
##   choice    a crisis the player answered, weighted by how far the answer moved
##             the world (the sum of its |metric deltas|)
##   fallout   a crisis the player put off twice until it broke
##   moment    what changed the era: a paradigm shift, the AGI milestone, a
##             large emergent capability, the catastrophe that ended the world
##   collapse  a faction that went under (the player's own loss included)
##
##   for point in TurningPoints.find(engine.event_log, engine.player_role):
##       # {turn, year, title, summary, kind, rewind_turn, score, faction,
##       #  deltas, card, option, option_label}
##       var rewound := SimulationEngine.from_record(engine.record, point["rewind_turn"])
##
## [code]rewind_turn[/code] is the last decision before the moment: the turn
## itself for choices, fallouts, collapses and catastrophes (the player decides
## before the turn's telemetry), the turn before for moments (they happen in
## the world tick, ahead of the player). It never precedes the first turn the
## humans played (late starts run their prologue on autopilot).
## Static, headless and deterministic. Titles are plain text for Labels.

const CHOICE := "choice"
const FALLOUT := "fallout"
const MOMENT := "moment"
const COLLAPSE := "collapse"
const DEFAULT_COUNT := 5

## A crisis that broke counts this much more than its deltas.
const FALLOUT_BONUS := 8.0
const COLLAPSE_SCORE := 30.0
const PLAYER_COLLAPSE_SCORE := 45.0
const CATASTROPHE_SCORE := 50.0
const MILESTONE_SCORE := 14.0
const PARADIGM_SCORE := 10.0
## An emergent capability scores its drift jump times this; smaller jumps than
## MIN_EMERGENCE_SPIKE are routine.
const EMERGENCE_PER_DRIFT := 2.0
const MIN_EMERGENCE_SPIKE := 4.0
## Choices that barely moved the world are not turning points.
const MIN_CHOICE_WEIGHT := 0.5
const MAX_SUMMARY_DELTAS := 3
## Order within a turn: the world tick, then the decision, then telemetry.
const PHASE := {MOMENT: 0, CHOICE: 1, FALLOUT: 1, COLLAPSE: 2}

const METRIC_PROSE := {
	"compute_energy_sat": "compute saturation", "labor_displacement": "labor displacement",
	"geopolitical_tension": "geopolitical tension", "algorithmic_autonomy": "algorithmic autonomy",
	"alignment_drift": "alignment drift", "epistemic_trust": "public trust",
}
const COLLAPSE_TITLES := {
	"BANKRUPTCY": "The Frontier Lab goes bankrupt", "NATIONALIZATION": "The state nationalizes the Frontier Lab",
	"INSTITUTIONAL_OUSTER": "The Council is ousted", "AUTONOMOUS_WORLD_WAR": "The Council is suspended as war breaks out",
	"AIR_GAP_PURGE": "An air-gap purge wipes the machine", "PACIFICATION": "The Coalition is pacified",
}
const CATASTROPHE_TITLES := {
	"AUTONOMOUS_WORLD_WAR": "The war swarms launch",
	"UNCONTAINED_CONVERGENCE": "Containment fails",
}


## The turning points of [param role]'s campaign, at most [param max_count],
## sorted by turn. Moments and collapses take at most half the places; the
## player's own choices fill the rest, one per crisis while there are enough
## different crises.
static func find(event_log: Array, role: String, max_count: int = DEFAULT_COUNT) -> Array:
	return find_for(event_log, [role], max_count)


## [method find] for several players at once (pass-and-play): every listed
## role's choices, and the shared moments and collapses once.
static func find_for(event_log: Array, roles: Array, max_count: int = DEFAULT_COUNT) -> Array:
	if max_count <= 0 or event_log.is_empty():
		return []
	var first_turn := first_played_turn(event_log)
	var choices: Array = []
	var events: Array = []
	var seen := {}
	for item in event_log:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var turn := int(entry.get("turn", 0))
		if turn < first_turn:
			continue
		var point := {}
		match String(entry.get("category", "")):
			"DILEMMA":
				if roles.has(String(entry.get("faction", ""))):
					point = _choice(entry)
			"COLLAPSE":
				point = _collapse(entry, roles)
			"PARADIGM":
				point = _paradigm(entry, first_turn)
			"MILESTONE":
				point = _milestone(entry, first_turn)
			"EMERGENCE":
				point = _emergence(entry, first_turn)
			"ENDGAME":
				if entry.has("catastrophe"):
					point = _catastrophe(entry)
		if point.is_empty():
			continue
		if String(point["kind"]) == CHOICE or String(point["kind"]) == FALLOUT:
			choices.append(point)
			continue
		var key := "%d|%s" % [turn, point["title"]]
		if not seen.has(key):
			seen[key] = true
			events.append(point)
	choices = _distinct_first(choices, "card")
	events = _distinct_first(events, "title")
	var event_places := mini(events.size(), floori(max_count / 2.0))
	var choice_places := mini(choices.size(), max_count - event_places)
	event_places = mini(events.size(), max_count - choice_places)
	var picked: Array = choices.slice(0, choice_places) + events.slice(0, event_places)
	picked.sort_custom(_by_turn)
	return picked


## [param points] by score, the best of each [param field] value first (the
## same crisis answered the same way three times is one turning point), then
## the repeats in score order.
static func _distinct_first(points: Array, field: String) -> Array:
	var ranked := points.duplicate()
	ranked.sort_custom(_by_score)
	var first: Array = []
	var repeats: Array = []
	var seen := {}
	for point in ranked:
		var value := String(point.get(field, ""))
		if value.is_empty():
			first.append(point)
		elif not seen.has(value):
			seen[value] = true
			first.append(point)
		else:
			repeats.append(point)
	return first + repeats


## The first turn the humans played: after the autopilot prologue of a late
## start (its SYSTEM entry carries "prologue_turns"), otherwise turn 1.
static func first_played_turn(event_log: Array) -> int:
	for item in event_log:
		if item is Dictionary and (item as Dictionary).has("prologue_turns"):
			return int(item["prologue_turns"]) + 1
	return 1


# --- Kinds ------------------------------------------------------------------------

static func _choice(entry: Dictionary) -> Dictionary:
	var deltas := _clean_deltas(entry.get("deltas", {}))
	var weight := 0.0
	for key in deltas:
		weight += absf(float(deltas[key]))
	var fallout := bool(entry.get("fallout", false))
	if weight < MIN_CHOICE_WEIGHT and not fallout:
		return {}
	var deferred := bool(entry.get("deferred", false))
	var label := String(entry.get("option_label", "")).strip_edges()
	var said := "You chose “%s”" % label if label != "" else "You made your choice"
	if fallout:
		said = "You put it off twice and it broke"
	elif deferred:
		said = "You put it off"
	var turn := int(entry.get("turn", 0))
	return _point(entry, FALLOUT if fallout else CHOICE, _crisis_title(String(entry.get("title", ""))),
		said + _effects(deltas) + ".", turn, weight + (FALLOUT_BONUS if fallout else 0.0) + 0.5 * float(entry.get("escalation", 0)),
		{"deltas": deltas, "card": String(entry.get("card", "")), "option": String(entry.get("option", "")),
			"option_label": label, "deferred": deferred})


static func _collapse(entry: Dictionary, roles: Array) -> Dictionary:
	var code := String(entry.get("code", ""))
	if code == "REEMERGED" or code.is_empty():
		return {}
	var faction := String(entry.get("faction", ""))
	var player := bool(entry.get("player", false)) and roles.has(faction)
	var text := String(entry.get("text", "")).trim_prefix("PLAYER LOSS: ").trim_prefix("PLAYER OUT: ")
	var title := String(COLLAPSE_TITLES.get(code, ""))
	if title.is_empty():
		title = String(entry.get("headline", "")).strip_edges()
	if title.is_empty():
		title = _sentence(text)
	var summary := _sentence(String(entry.get("headline", ""))) if not player else _sentence(text)
	if summary.is_empty() or summary == title + ".":
		summary = _sentence(text)
	return _point(entry, COLLAPSE, title, summary, int(entry.get("turn", 0)),
		PLAYER_COLLAPSE_SCORE if player else COLLAPSE_SCORE, {"code": code, "player": player})


static func _paradigm(entry: Dictionary, first_turn: int) -> Dictionary:
	var shift_name := String(entry.get("name", "A paradigm shift"))
	return _point(entry, MOMENT, "Paradigm shift: %s" % shift_name, _sentence(String(entry.get("summary", shift_name))),
		maxi(first_turn, int(entry.get("turn", 0)) - 1), PARADIGM_SCORE, {"shift": String(entry.get("shift", ""))})


static func _milestone(entry: Dictionary, first_turn: int) -> Dictionary:
	var lab := String(entry.get("first_mover", "")) == SimConstants.CEO
	return _point(entry, MOMENT, "The AGI threshold is crossed",
		"%s crosses the general-capability threshold first." % ("The Frontier Lab" if lab else "A state consortium"),
		maxi(first_turn, int(entry.get("turn", 0)) - 1), MILESTONE_SCORE, {"milestone": String(entry.get("milestone", "AGI"))})


static func _emergence(entry: Dictionary, first_turn: int) -> Dictionary:
	var deltas := _clean_deltas(entry.get("deltas", {}))
	var spike := float(deltas.get(WorldState.ALIGNMENT_DRIFT, 0.0))
	if spike < MIN_EMERGENCE_SPIKE:
		return {}
	var capability := String(entry.get("name", "An emergent capability"))
	var title := String(entry.get("headline", "")).strip_edges()
	if title.is_empty():
		title = "Emergent capability: %s" % capability
	return _point(entry, MOMENT, title, "%s%s." % [capability, _effects(deltas)],
		maxi(first_turn, int(entry.get("turn", 0)) - 1), spike * EMERGENCE_PER_DRIFT,
		{"deltas": deltas, "capability": String(entry.get("capability", ""))})


static func _catastrophe(entry: Dictionary) -> Dictionary:
	var code := String(entry.get("catastrophe", ""))
	return _point(entry, MOMENT, String(CATASTROPHE_TITLES.get(code, "Catastrophe")),
		_sentence(String(entry.get("text", "")).trim_prefix("CATASTROPHIC THRESHOLD: ")), int(entry.get("turn", 0)),
		CATASTROPHE_SCORE, {"code": code})


static func _point(entry: Dictionary, kind: String, title: String, summary: String, rewind_turn: int, score: float,
		extra: Dictionary) -> Dictionary:
	var point := {
		"turn": int(entry.get("turn", 0)),
		"year": float(entry.get("year", SimConstants.year_for_turn(int(entry.get("turn", 0))))),
		"title": title.strip_edges(),
		"summary": summary.strip_edges(),
		"kind": kind,
		"rewind_turn": rewind_turn,
		"score": score,
		"faction": String(entry.get("faction", "")),
		"deltas": {},
		"card": "",
		"option": "",
		"option_label": "",
	}
	point.merge(extra, true)
	return point


# --- Text --------------------------------------------------------------------------

## ": public trust −4, alignment drift +3" for the largest deltas ("" for none).
static func _effects(deltas: Dictionary) -> String:
	var keys: Array = deltas.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var da := absf(float(deltas[a]))
		var db := absf(float(deltas[b]))
		return da > db if not is_equal_approx(da, db) else a < b)
	var parts: Array[String] = []
	for key in keys.slice(0, MAX_SUMMARY_DELTAS):
		parts.append("%s %s" % [METRIC_PROSE.get(key, String(key).replace("_", " ")), signed(float(deltas[key]))])
	return (": " + ", ".join(parts)) if not parts.is_empty() else ""


## "+3", "−4", "+0.4" with a true minus sign.
static func signed(value: float) -> String:
	var magnitude := absf(value)
	var number := str(int(round(magnitude))) if magnitude >= 0.95 else "%.1f" % magnitude
	return ("−" if value < 0.0 else "+") + number


## Metric deltas worth naming: finite, at least 0.05, metrics only.
static func _clean_deltas(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for key in raw:
		var value: Variant = raw[key]
		if not (value is float or value is int) or not METRIC_PROSE.has(String(key)):
			continue
		if is_finite(float(value)) and absf(float(value)) >= 0.05:
			out[String(key)] = float(value)
	return out


## A crisis title without its "[ESCALATED xN]" prefix.
static func _crisis_title(title: String) -> String:
	var plain := title.strip_edges()
	if plain.begins_with("[ESCALATED"):
		plain = plain.substr(plain.find("]") + 1).strip_edges()
	return plain if not plain.is_empty() else "A crisis on your desk"


## [param text] as a sentence: trimmed, ending in a full stop.
static func _sentence(text: String) -> String:
	var out := text.strip_edges()
	if out.is_empty():
		return out
	return out if out.ends_with(".") or out.ends_with("!") or out.ends_with("?") else out + "."


static func _by_score(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["score"]), float(b["score"])):
		return float(a["score"]) > float(b["score"])
	return int(a["turn"]) < int(b["turn"])


static func _by_turn(a: Dictionary, b: Dictionary) -> bool:
	if int(a["turn"]) != int(b["turn"]):
		return int(a["turn"]) < int(b["turn"])
	return int(PHASE.get(a["kind"], 1)) < int(PHASE.get(b["kind"], 1))
