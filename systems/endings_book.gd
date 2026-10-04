class_name EndingsBook
extends RefCounted
## The endings collection: which of the 32 endings (8 end-states x 4 roles)
## the player has reached, the date they first did, how often, and the best
## verdict. Kept in user://endings.cfg (ConfigFile: one section per end-state,
## one key per role, so a hand-edited file stays readable).
##
##   var book := EndingsBook.new()                       # loads user://endings.cfg
##   var fresh := book.record_result(result, spectating) # on campaign_ended
##   book.progress()                                     # Vector2i(unlocked, 32)
##   EndingsBook.rarity(VictoryMatrix.SYNTHETIC_EDEN)    # "Legendary"
##
## Every human in a pass-and-play game unlocks the ending for their own role
## (result["verdicts"]). Spectated campaigns unlock nothing.

const DEFAULT_PATH := "user://endings.cfg"
const TOTAL := 32
const VERDICT_RANK := {"DEFEAT": 0, "PYRRHIC": 1, "VICTORY": 2}

## Share (%) of autoplay campaigns that end in each end-state, from
##   godot --headless --path . --script res://tools/monte_carlo.gd -- --runs=100
##   godot --headless --path . --script res://tools/monte_carlo.gd -- --runs=100 --seed-offset=5000
## (800 campaigns, 200 per role, every faction on the heuristic). Re-run both
## and update the table after a balance change.
const SHARES := {
	VictoryMatrix.ALGORITHMIC_FEUDALISM: 42.4,
	VictoryMatrix.POST_BIOLOGICAL_DIASPORA: 18.4,
	VictoryMatrix.NEO_LUDDITE_DECOUPLING: 14.3,
	VictoryMatrix.BALKANIZED_CYBER_ANARCHY: 13.6,
	VictoryMatrix.CO_EVOLUTIONARY_SYMBIOSIS: 9.1,
	VictoryMatrix.SYNTHETIC_EDEN: 1.8,
	VictoryMatrix.ROGUE_ASI_CONTAINMENT: 0.4,
	VictoryMatrix.INSTRUMENTAL_CONVERGENCE: 0.1,
}
## Minimum share for each rarity, most common first; anything rarer than the
## last tier is LEGENDARY.
const RARITY_TIERS := [[15.0, "Common"], [10.0, "Uncommon"], [2.0, "Rare"]]
const LEGENDARY := "Legendary"
const RARITY_ORDER := ["Common", "Uncommon", "Rare", "Legendary"]

## Where the book is kept ("" keeps it in memory, as in tests).
var path := DEFAULT_PATH
## "OUTCOME_ID/ROLE" -> {first, last, count, best, best_score}
var _entries := {}


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	load_book()


func load_book() -> void:
	_entries = {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for outcome in VictoryMatrix.OUTCOMES:
		var outcome_id := String(outcome["id"])
		if not config.has_section(outcome_id):
			continue
		for role in SimConstants.FACTION_ORDER:
			if not config.has_section_key(outcome_id, role):
				continue
			var entry := _clean_entry(config.get_value(outcome_id, role))
			if not entry.is_empty():
				_entries[key(outcome_id, role)] = entry


func save_book() -> bool:
	if path.is_empty():
		return true
	var config := ConfigFile.new()
	for entry_key in _entries:
		var parts := String(entry_key).split("/")
		config.set_value(parts[0], parts[1], _entries[entry_key])
	var folder := path.get_base_dir()
	if not folder.is_empty() and not folder.ends_with(":/") and not folder.ends_with("://"):
		DirAccess.make_dir_recursive_absolute(folder)
	return config.save(path) == OK


## Files the endings [param result] (SimulationEngine.result) reached for every
## human. [param spectated] campaigns are ignored. [param date] ("YYYY-MM-DD")
## defaults to today (UTC). Returns the endings unlocked for the first time:
## [{outcome, role, verdict}], and saves the book.
func record_result(result: Dictionary, spectated: bool = false, date: String = "") -> Array:
	var fresh: Array = []
	if spectated or not (result.get("outcome") is Dictionary):
		return fresh
	var outcome_id := String((result["outcome"] as Dictionary).get("id", ""))
	if VictoryMatrix.get_outcome(outcome_id).is_empty():
		return fresh
	var day := date if CampaignModes.is_valid_date(date) else CampaignModes.today_utc()
	var verdicts: Variant = result.get("verdicts", {})
	if not (verdicts is Dictionary) or (verdicts as Dictionary).is_empty():
		verdicts = {String(result.get("player_role", "")): result.get("verdict", {})}
	for role in verdicts:
		if not SimConstants.is_valid_faction(String(role)) or not (verdicts[role] is Dictionary):
			continue
		var verdict_info: Dictionary = verdicts[role]
		var verdict := String(verdict_info.get("verdict", "DEFEAT"))
		if not VERDICT_RANK.has(verdict):
			verdict = "DEFEAT"
		var score := float(verdict_info.get("score", 0.0))
		if not is_finite(score):
			score = 0.0
		var entry_key := key(outcome_id, String(role))
		if not _entries.has(entry_key):
			_entries[entry_key] = {"first": day, "last": day, "count": 1, "best": verdict, "best_score": score}
			fresh.append({"outcome": outcome_id, "role": String(role), "verdict": verdict})
			continue
		var entry: Dictionary = _entries[entry_key]
		entry["count"] = int(entry["count"]) + 1
		entry["last"] = day
		var rank := int(VERDICT_RANK[verdict])
		var best_rank := int(VERDICT_RANK.get(String(entry["best"]), 0))
		if rank > best_rank or (rank == best_rank and score > float(entry["best_score"])):
			entry["best"] = verdict
			entry["best_score"] = score
	save_book()
	return fresh


func is_unlocked(outcome_id: String, role: String) -> bool:
	return _entries.has(key(outcome_id, role))


## {first, last, count, best, best_score} for an unlocked ending, {} otherwise.
func entry(outcome_id: String, role: String) -> Dictionary:
	return (_entries.get(key(outcome_id, role), {}) as Dictionary).duplicate()


## Vector2i(unlocked, TOTAL).
func progress() -> Vector2i:
	return Vector2i(_entries.size(), TOTAL)


## Roles that reached [param outcome_id].
func roles_for(outcome_id: String) -> Array:
	var out: Array = []
	for role in SimConstants.FACTION_ORDER:
		if is_unlocked(outcome_id, role):
			out.append(role)
	return out


## Forgets every ending (and saves the empty book).
func reset() -> void:
	_entries = {}
	save_book()


static func key(outcome_id: String, role: String) -> String:
	return "%s/%s" % [outcome_id, role]


## "Common", "Uncommon", "Rare" or "Legendary", from the end-state's share of
## autoplay campaigns (SHARES).
static func rarity(outcome_id: String) -> String:
	var value := share(outcome_id)
	for tier in RARITY_TIERS:
		if value >= float(tier[0]):
			return String(tier[1])
	return LEGENDARY


## Percentage of autoplay campaigns that end in [param outcome_id].
static func share(outcome_id: String) -> float:
	return float(SHARES.get(outcome_id, 0.0))


static func _clean_entry(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var source: Dictionary = raw
	var best := String(source.get("best", "DEFEAT")) if source.get("best") is String else "DEFEAT"
	var count: Variant = source.get("count", 1)
	var best_score: Variant = source.get("best_score", 0.0)
	var first: Variant = source.get("first", "")
	var last: Variant = source.get("last", first)
	return {
		"first": String(first) if first is String else "",
		"last": String(last) if last is String else "",
		"count": maxi(1, int(count)) if (count is int or count is float) else 1,
		"best": best if VERDICT_RANK.has(best) else "DEFEAT",
		"best_score": float(best_score) if (best_score is int or best_score is float) and is_finite(float(best_score)) else 0.0,
	}
