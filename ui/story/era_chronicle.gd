class_name EraChronicle
extends RefCounted
## Writes the story of each hardware era from the campaign's own record: the
## front page printed when an era closes ([method summarize_era]) and the
## chapters of the closing history book ([method chapters]).
##
## Everything is derived from real events: the player's crisis choices counted
## by card and option, deferrals, paradigm shifts, emergent capabilities,
## threshold breaches and collapses, plus the history snapshots for the
## figures. Static and deterministic: the same campaign always reads the same.

## The three lines every front page charts.
const STAT_KEYS := [["Trust", WorldState.EPISTEMIC_TRUST], ["Compute", WorldState.COMPUTE_ENERGY_SAT],
	["Drift", WorldState.ALIGNMENT_DRIFT]]
## How metrics are named in prose.
const METRIC_PROSE := {
	"compute_energy_sat": "compute saturation", "labor_displacement": "labor displacement",
	"geopolitical_tension": "geopolitical tension", "algorithmic_autonomy": "algorithmic autonomy",
	"alignment_drift": "alignment drift", "epistemic_trust": "public trust",
}
## Past-tense collapses for the chronicles.
const COLLAPSE_DID := {
	"BANKRUPTCY": "the Frontier Lab went bankrupt", "NATIONALIZATION": "the state nationalized the Frontier Lab",
	"INSTITUTIONAL_OUSTER": "the Council was ousted", "AUTONOMOUS_WORLD_WAR": "the Council was suspended as war broke out",
	"AIR_GAP_PURGE": "an air-gap purge wiped the rogue weights", "PACIFICATION": "the Coalition was pacified",
}
const CATASTROPHE_DID := {
	"AUTONOMOUS_WORLD_WAR": "the war swarms launched, and the blocs went to war",
	"UNCONTAINED_CONVERGENCE": "containment failed, and instrumental convergence took hold",
}
const ERA_NEXT := {2: "optical interconnects and modular reactors", 3: "neuromorphic and post-biological substrates"}
## A theme needs at least this weighted count to name an era.
const MIN_THEME_SCORE := 2.0
const MAX_ALSO := 4
const MAX_CHAPTER_EMERGENCES := 4
## Directives count for less than crisis choices when naming an era.
const DIRECTIVE_THEME_WEIGHT := 0.5


# --- Public API ----------------------------------------------------------------------

## Nominal first and last turn of [param era] (Era I is turns 0-19).
static func era_turns(era: int) -> Vector2i:
	var first := -1
	var last := -1
	for turn in range(0, SimConstants.TOTAL_TURNS + 1):
		if SimConstants.era_for_year(SimConstants.year_for_turn(turn)) == era:
			if first < 0:
				first = turn
			last = turn
	return Vector2i(maxi(first, 0), maxi(last, 0))


## The front page for the era that just closed:
## {era, era_name, years, title, deck, paragraphs (1-3), stats [{label, key,
## from, to}] (trust, compute, drift from the last snapshot before the era to
## its last one), also (up to 4), highlights [{turn, year, category, title,
## glyph}], period ("Decade"), next_line, edition {volume, number, year},
## era_start_turn, era_end_turn, lines [{label, key, points}] for the chart}.
## Call it when the next era's ERA entry is logged (or at the campaign's end
## for the last era); the history then ends with the closing era.
static func summarize_era(event_log: Array, history: Array, era: int, role: String) -> Dictionary:
	var ctx := _analyze(event_log, history, era, role)
	var paragraphs: Array[String] = []
	var used := {}
	var series: Array = ctx["series"]
	if not series.is_empty():
		paragraphs.append(" ".join(_series_sentences(series[0], ctx, true)))
		used[series[0]["card"]] = true
	var middle: Array[String] = []
	for item in series.slice(1, 3):
		middle.append(" ".join(_series_sentences(item, ctx, false)))
		used[item["card"]] = true
	if middle.is_empty():
		middle = _directive_sentences(ctx, 2)
	if not middle.is_empty():
		paragraphs.append(" ".join(middle))
	var machines := _machine_sentences(ctx, 3)
	if not machines.is_empty():
		paragraphs.append(" ".join(machines))
	if paragraphs.is_empty():
		paragraphs.append(_quiet_paragraph(ctx))
	var end_turn: int = ctx["end_turn"]
	var next_era := era + 1
	return {
		"era": era,
		"years": _years(ctx),
		"title": _title(ctx),
		"deck": _deck(ctx),
		"paragraphs": paragraphs,
		"stats": ctx["stats"],
		"also": _also(ctx, used),
		"highlights": _highlights(ctx),
		"period": String(StoryCopy.ERA_PERIOD.get(era, "Era")),
		"era_name": String(EraStyle.NAMES.get(era, "")),
		"next_line": ("Era %s begins: %s." % [StoryCopy.ROMAN.get(next_era, str(next_era)), ERA_NEXT[next_era]]) \
			if ERA_NEXT.has(next_era) else "",
		"edition": {
			"volume": String(StoryCopy.ROMAN.get(era, str(era))),
			"number": end_turn + 1 if ERA_NEXT.has(next_era) else end_turn,
			"year": int(floor(SimConstants.year_for_turn(end_turn + 1 if ERA_NEXT.has(next_era) else end_turn))),
		},
		"era_start_turn": int(ctx["start_turn"]),
		"era_end_turn": end_turn,
		"lines": _lines(history, maxi(0, int(ctx["start_turn"]) - 1), end_turn),
	}


## Chart series for the three stats: [{label, key, points: [Vector2(turn, value)]}].
static func _lines(history: Array, from_turn: int, to_turn: int) -> Array:
	var out: Array = []
	for pair in STAT_KEYS:
		var points: Array = []
		for item in history:
			var entry: Dictionary = item
			var turn := int(entry.get("turn", 0))
			if turn >= from_turn and turn <= to_turn:
				points.append(Vector2(float(turn), float(entry.get(String(pair[1]), 0.0))))
		out.append({"label": String(pair[0]), "key": String(pair[1]), "points": points})
	return out


## One chapter per era the campaign reached: {number ("I"), era, title, years,
## paragraphs, footnotes, era_start_turn, era_end_turn, stats, figure
## {from_turn, to_turn, mark_turn, mark_year}}.
static func chapters(event_log: Array, history: Array, result: Dictionary) -> Array:
	var role := String(result.get("player_role", ""))
	var max_spike := _max_spike(event_log)
	var out: Array = []
	for era in _eras_reached(history, result):
		var ctx := _analyze(event_log, history, era, role)
		var footnotes: Array[String] = []
		var paragraphs: Array[String] = []
		if (ctx["events"] as Array).is_empty():
			# No log to read (an old save or a bare result): tell it from the figures.
			paragraphs.append(_quiet_paragraph(ctx))
		else:
			var opening := _opening_sentences(ctx)
			if not opening.is_empty():
				paragraphs.append(" ".join(opening))
			var machines := _chapter_machine_sentences(ctx, max_spike, footnotes)
			if not machines.is_empty():
				paragraphs.append(" ".join(machines))
			var desk := _chapter_desk_sentences(ctx)
			if not desk.is_empty():
				paragraphs.append(" ".join(desk))
		out.append({
			"number": String(StoryCopy.ROMAN.get(era, str(era))),
			"era": era,
			"title": _title(ctx),
			"years": _years(ctx),
			"paragraphs": paragraphs,
			"footnotes": footnotes,
			"era_start_turn": int(ctx["start_turn"]),
			"era_end_turn": int(ctx["end_turn"]),
			"stats": ctx["stats"],
			"figure": {"from_turn": maxi(0, int(ctx["start_turn"]) - 1), "to_turn": int(ctx["end_turn"]),
				"mark_turn": int(ctx.get("mark_turn", -1)), "mark_year": int(ctx.get("mark_year", 0))},
		})
	return out


## The closing page: {title, subtitle, years, paragraphs, verdict, score, outcome}.
static func epilogue(result: Dictionary) -> Dictionary:
	var outcome: Dictionary = result.get("outcome", {})
	var verdict: Dictionary = result.get("verdict", {})
	var role := String(result.get("player_role", ""))
	var year := int(floor(float(result.get("year", SimConstants.year_for_turn(int(result.get("turn", 0)))))))
	var outcome_name := String(outcome.get("name", "an unnamed end-state"))
	var paragraphs: Array[String] = []
	var opening := "In %d the century came to rest in %s." % [year, outcome_name]
	var catastrophe: Dictionary = result.get("catastrophe", {})
	if not catastrophe.is_empty():
		opening = "In %d %s. The century ended early, in what the record calls %s." % [year,
			CATASTROPHE_DID.get(String(catastrophe.get("code", "")), "catastrophe struck"), outcome_name]
	paragraphs.append(opening + " " + String(outcome.get("description", "")))
	var history: Array = result.get("history", [])
	var last: Dictionary = history[-1] if not history.is_empty() else {}
	var values: Dictionary = result.get("final_values", last)
	if not values.is_empty():
		paragraphs.append("By then public trust stood at %d, alignment drift at %d and algorithmic autonomy at %d." % [
			int(round(float(values.get(WorldState.EPISTEMIC_TRUST, 0.0)))),
			int(round(float(values.get(WorldState.ALIGNMENT_DRIFT, 0.0)))),
			int(round(float(values.get(WorldState.ALGORITHMIC_AUTONOMY, 0.0))))])
	var verdict_name := String(verdict.get("verdict", "DEFEAT"))
	var judgement: String = {"VICTORY": "a victory", "PYRRHIC": "a pyrrhic victory"}.get(verdict_name, "a defeat")
	paragraphs.append("For %s it was %s, with a directive score of %d out of 100." % [
		StoryCopy.actor_the(role), judgement, int(round(float(verdict.get("score", 0.0))))])
	return {
		"title": "How It Ended",
		"subtitle": String(outcome.get("name", "")),
		"years": str(year),
		"paragraphs": paragraphs,
		"verdict": verdict_name,
		"score": float(verdict.get("score", 0.0)),
		"outcome": outcome,
	}


# --- Analysis -------------------------------------------------------------------------

static func _analyze(event_log: Array, history: Array, era: int, role: String) -> Dictionary:
	var span := era_turns(era)
	var last_turn := span.y
	if not history.is_empty():
		last_turn = mini(span.y, int((history[-1] as Dictionary).get("turn", span.y)))
	var ctx := {
		"era": era, "role": role, "start_turn": span.x, "end_turn": maxi(span.x, last_turn),
		"events": [], "series": [], "emergences": [], "shifts": [], "milestones": [], "collapses": [],
		"thresholds": [], "catastrophes": [], "actions": {},
	}
	var by_card := {}
	for item in event_log:
		var entry: Dictionary = item
		if SimConstants.era_for_year(float(entry.get("year", SimConstants.START_YEAR))) != era:
			continue
		var category := String(entry.get("category", ""))
		match category:
			"DILEMMA":
				_count_choice(by_card, entry, role)
			"EMERGENCE":
				ctx["emergences"].append(entry)
			"PARADIGM":
				ctx["shifts"].append(entry)
			"MILESTONE":
				ctx["milestones"].append(entry)
			"COLLAPSE":
				if String(entry.get("code", "")) != "REEMERGED":
					ctx["collapses"].append(entry)
			"THRESHOLD":
				if int(entry.get("band", 0)) >= 2 and not bool(entry.get("imminent", false)):
					ctx["thresholds"].append(entry)
			"ENDGAME":
				if entry.has("catastrophe"):
					ctx["catastrophes"].append(entry)
			"ACTION":
				_count_action(ctx["actions"], entry)
		if category != "SYSTEM":
			ctx["events"].append(entry)
	var series: Array = by_card.values()
	series.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) > float(b["score"])
		return int(a["first_turn"]) < int(b["first_turn"]))
	ctx["series"] = series
	ctx["stats"] = _stats(history, int(ctx["start_turn"]), int(ctx["end_turn"]))
	return ctx


static func _count_choice(by_card: Dictionary, entry: Dictionary, role: String) -> void:
	var card_id := String(entry.get("card", ""))
	if card_id.is_empty():
		return
	var actor_id := String(entry.get("faction", role))
	var key := _option_key(card_id, String(entry.get("option", "")), actor_id)
	if not by_card.has(card_id):
		by_card[card_id] = {"card": card_id, "count": 0, "options": {}, "first_turn": int(entry.get("turn", 0)),
			"first": entry, "actor": actor_id, "score": 0.0, "deferred": 0}
	var series: Dictionary = by_card[card_id]
	series["count"] = int(series["count"]) + 1
	series["options"][key] = int(series["options"].get(key, 0)) + 1
	if key == DilemmaDeck.DEFER_ID:
		series["deferred"] = int(series["deferred"]) + 1
	series["score"] = float(series["count"]) * float(StoryCopy.card(card_id).get("weight", 1.0))


static func _count_action(actions: Dictionary, entry: Dictionary) -> void:
	var action_id := String(entry.get("action", ""))
	if action_id.is_empty() or action_id == SimulationEngine.CONSERVE:
		return
	var key := "%s/%s" % [entry.get("faction", ""), action_id]
	actions[key] = int(actions.get(key, 0)) + 1


## Option keys as StoryCopy names them ("C@ASI" for a role-specific option).
static func _option_key(card_id: String, option_id: String, actor_id: String) -> String:
	var options: Dictionary = StoryCopy.card(card_id).get("options", {})
	var scoped := "%s@%s" % [option_id, actor_id]
	return scoped if options.has(scoped) else option_id


## Options of a series by count (most chosen first, then option order).
static func _ranked_options(series: Dictionary) -> Array:
	var keys: Array = (series["options"] as Dictionary).keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ca := int(series["options"][a])
		var cb := int(series["options"][b])
		return ca > cb if ca != cb else a < b)
	return keys


static func _stats(history: Array, start_turn: int, end_turn: int) -> Array:
	var out: Array = []
	if history.is_empty():
		return out
	var from_entry := _history_at(history, maxi(0, start_turn - 1))
	var to_entry := _history_at(history, end_turn)
	for pair in STAT_KEYS:
		var key := String(pair[1])
		out.append({"label": String(pair[0]), "key": key, "from": float(from_entry.get(key, 0.0)),
			"to": float(to_entry.get(key, 0.0))})
	return out


## The last history snapshot at or before [param turn] (the first one if none).
static func _history_at(history: Array, turn: int) -> Dictionary:
	var found: Dictionary = history[0]
	for item in history:
		var entry: Dictionary = item
		if int(entry.get("turn", 0)) > turn:
			break
		found = entry
	return found


static func _eras_reached(history: Array, result: Dictionary) -> Array:
	var last_turn := int(result.get("turn", 0))
	if not history.is_empty():
		last_turn = maxi(last_turn, int((history[-1] as Dictionary).get("turn", 0)))
	var final_era := SimConstants.era_for_year(SimConstants.year_for_turn(last_turn))
	var eras: Array = []
	for era in range(1, final_era + 1):
		eras.append(era)
	return eras


static func _max_spike(event_log: Array) -> float:
	var best := 0.0
	for item in event_log:
		var entry: Dictionary = item
		if String(entry.get("category", "")) == "EMERGENCE":
			best = maxf(best, _spike(entry))
	return best


static func _spike(entry: Dictionary) -> float:
	return float((entry.get("deltas", {}) as Dictionary).get(WorldState.ALIGNMENT_DRIFT, 0.0))


# --- Titles, decks and stats ------------------------------------------------------------

static func _title(ctx: Dictionary) -> String:
	var era := int(ctx["era"])
	var scores := {}
	for item in ctx["series"]:
		var series: Dictionary = item
		var weight := float(StoryCopy.card(series["card"]).get("weight", 1.0))
		for key in series["options"]:
			var theme := String(StoryCopy.card_option(series["card"], String(key), String(series["actor"])).get("theme", ""))
			if theme != "":
				scores[theme] = float(scores.get(theme, 0.0)) + weight * float(series["options"][key])
	var actions: Dictionary = ctx["actions"]
	for key in actions:
		if not String(key).begins_with(String(ctx["role"]) + "/"):
			continue
		var theme := String(StoryCopy.ACTIONS.get(key, {}).get("theme", ""))
		if theme != "":
			scores[theme] = float(scores.get(theme, 0.0)) + DIRECTIVE_THEME_WEIGHT * float(actions[key])
	var best := ""
	var best_score := MIN_THEME_SCORE - 0.001
	var themes: Array = scores.keys()
	themes.sort()
	for theme in themes:
		if float(scores[theme]) > best_score:
			best_score = float(scores[theme])
			best = String(theme)
	if best.is_empty():
		return String(StoryCopy.ERA_GENERIC_TITLE.get(era, "The Long Years"))
	return "The %s of %s" % [StoryCopy.ERA_PERIOD.get(era, "Era"), best]


static func _deck(ctx: Dictionary) -> String:
	var stat := _stat_clause(ctx)
	var series: Array = ctx["series"]
	if series.is_empty():
		return StoryCopy.capitalize_first(stat) + "." if stat != "" else "A quiet stretch on the record."
	var lead: Dictionary = series[0]
	var who := StoryCopy.actor_the(String(lead["actor"]))
	var copy := StoryCopy.card(lead["card"])
	var count := int(lead["count"])
	var opening := ""
	if int(lead["deferred"]) == count and count >= 2:
		opening = "%s came before %s %s" % [StoryCopy.capitalize_first(String(copy.get("subject", "a crisis"))), who,
			StoryCopy.times(count)]
	else:
		var key := String(_ranked_options(lead)[0])
		var did := String(StoryCopy.card_option(lead["card"], key, String(lead["actor"])).get("did", "chose"))
		var n := int(lead["options"][key])
		opening = "%s %s %s" % [StoryCopy.capitalize_first(StoryCopy.times(n)), who, did] if n > 1 \
			else "%s %s" % [StoryCopy.capitalize_first(who), did]
	return opening + (", and %s." % stat if stat != "" else ".")


## "public trust climbed from 58 to 97" for the metric that moved most.
static func _stat_clause(ctx: Dictionary) -> String:
	var stats: Array = ctx["stats"]
	if stats.is_empty():
		return ""
	var best: Dictionary = stats[0]
	for item in stats:
		var stat: Dictionary = item
		if absf(float(stat["to"]) - float(stat["from"])) > absf(float(best["to"]) - float(best["from"])) + 0.001:
			best = stat
	return _movement(String(best["key"]), float(best["from"]), float(best["to"]))


static func _movement(key: String, from_value: float, to_value: float) -> String:
	var name := String(METRIC_PROSE.get(key, UiFormat.metric_name(key, false).to_lower()))
	var a := int(round(from_value))
	var b := int(round(to_value))
	var change := to_value - from_value
	if absf(change) < 2.0:
		return "%s held near %d" % [name, b]
	var verb := ""
	if change > 0.0:
		verb = "soared" if change >= 25.0 else ("climbed" if change >= 10.0 else "rose")
	else:
		verb = "collapsed" if change <= -25.0 else ("fell" if change <= -10.0 else "slipped")
	return "%s %s from %d to %d" % [name, verb, a, b]


static func _years(ctx: Dictionary) -> String:
	return "%d–%d" % [int(floor(SimConstants.year_for_turn(int(ctx["start_turn"])))),
		int(floor(SimConstants.year_for_turn(int(ctx["end_turn"]))))]


static func _start_year(ctx: Dictionary) -> int:
	return int(floor(SimConstants.year_for_turn(int(ctx["start_turn"]))))


# --- Sentences ----------------------------------------------------------------------------

## One crisis series in the voice of the front page.
static func _series_sentences(series: Dictionary, ctx: Dictionary, lead: bool) -> Array[String]:
	var out: Array[String] = []
	var card_id := String(series["card"])
	var copy := StoryCopy.card(card_id)
	var actor_id := String(series["actor"])
	var who := StoryCopy.actor_the(actor_id)
	var count := int(series["count"])
	var event := String(copy.get("event", "a crisis struck"))
	var ranked := _ranked_options(series)
	if count >= 2 and int(series["deferred"]) == count:
		out.append("%s came before %s %s." % [StoryCopy.capitalize_first(String(copy.get("subject", "A crisis"))), who,
			StoryCopy.times(count)])
		out.append("It was deferred %s." % StoryCopy.times(count))
		return out
	if count == 1:
		var first: Dictionary = series["first"]
		var did := _did(card_id, String(ranked[0]), actor_id)
		out.append("In %d, %s, and %s %s." % [int(floor(float(first.get("year", 0.0)))), _one(card_id, first), who, did])
		return out
	if ranked.size() == 1:
		var did := _did(card_id, String(ranked[0]), actor_id)
		if lead:
			out.append("%s since %d %s, and %s %s %s." % [StoryCopy.capitalize_first(StoryCopy.times(count)),
				_start_year(ctx), event, StoryCopy.times(count), who, did])
		else:
			out.append("%s %s, and each time %s %s." % [StoryCopy.capitalize_first(event), StoryCopy.times(count), who, did])
		return out
	var parts: Array[String] = []
	for key in ranked.slice(0, 2):
		parts.append("%s %s" % [_did(card_id, String(key), actor_id), StoryCopy.times(int(series["options"][key]))])
	if lead:
		out.append("%s since %d %s." % [StoryCopy.capitalize_first(StoryCopy.times(count)), _start_year(ctx), event])
		out.append("%s %s." % [StoryCopy.capitalize_first(who), " and ".join(parts)])
	else:
		out.append("%s %s; %s %s." % [StoryCopy.capitalize_first(event), StoryCopy.times(count), who, " and ".join(parts)])
	return out


static func _did(card_id: String, key: String, actor_id: String) -> String:
	return String(StoryCopy.card_option(card_id, key, actor_id).get("did", "made a choice"))


## The past-tense clause of one crisis with its proper nouns.
static func _one(card_id: String, entry: Dictionary) -> String:
	var copy := StoryCopy.card(card_id)
	var fills := StoryCopy.title_fills(card_id, String(entry.get("title", "")))
	var text := StoryCopy.fill(String(copy.get("one", copy.get("event", "a crisis struck"))), fills)
	if StoryCopy.has_placeholder(text):
		text = String(copy.get("event", "a crisis struck"))
	return text


## Sentences about what the other factions kept doing, from their directives.
static func _directive_sentences(ctx: Dictionary, limit: int) -> Array[String]:
	var out: Array[String] = []
	var actions: Dictionary = ctx["actions"]
	var keys: Array = actions.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(actions[a]) > int(actions[b]) if int(actions[a]) != int(actions[b]) else a < b)
	for key in keys:
		if out.size() >= limit or int(actions[key]) < 2:
			break
		var copy: Dictionary = StoryCopy.ACTIONS.get(key, {})
		if copy.is_empty():
			continue
		var faction := String(key).get_slice("/", 0)
		if faction == SimConstants.ASI:
			continue
		out.append("%s %s %s." % [StoryCopy.capitalize_first(StoryCopy.actor_the(faction)), copy["did"],
			StoryCopy.times(int(actions[key]))])
	return out


## Emergences, paradigm shifts, the AGI milestone, collapses and critical
## thresholds in order, at most [param limit] sentences.
static func _machine_sentences(ctx: Dictionary, limit: int) -> Array[String]:
	var items: Array = []
	for entry in ctx["emergences"]:
		items.append({"turn": int(entry["turn"]), "rank": 0, "entry": entry})
	for entry in ctx["shifts"]:
		items.append({"turn": int(entry["turn"]), "rank": 1, "entry": entry})
	for entry in ctx["milestones"]:
		items.append({"turn": int(entry["turn"]), "rank": 1, "entry": entry})
	for entry in ctx["collapses"]:
		items.append({"turn": int(entry["turn"]), "rank": 2, "entry": entry})
	for entry in ctx["thresholds"]:
		items.append({"turn": int(entry["turn"]), "rank": 3, "entry": entry})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["rank"]) < int(b["rank"]) if int(a["rank"]) != int(b["rank"]) else int(a["turn"]) < int(b["turn"]))
	var picked := items.slice(0, limit)
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["turn"]) < int(b["turn"]) if int(a["turn"]) != int(b["turn"]) else int(a["rank"]) < int(b["rank"]))
	var biggest := 0.0
	for entry in ctx["emergences"]:
		biggest = maxf(biggest, _spike(entry))
	var out: Array[String] = []
	var spike_told := false
	var previous_year := 0
	for item in picked:
		var entry: Dictionary = item["entry"]
		var year := _year_of(entry)
		if String(entry.get("category", "")) == "THRESHOLD":
			out.append("By %d, %s had gone critical." % [year, METRIC_PROSE.get(String(entry.get("metric", "")), "a metric")])
		else:
			out.append(_dated(entry, year, previous_year, false, false))
		previous_year = year
		var spike := _spike(entry)
		if not spike_told and spike >= 4.0 and is_equal_approx(spike, biggest):
			out.append(_spike_sentence(spike))
			spike_told = true
	return out


static func _spike_sentence(spike: float) -> String:
	return "Alignment drift rose %s points overnight." % StoryCopy.number_word(int(round(spike)))


static func _year_of(entry: Dictionary) -> int:
	return int(floor(float(entry.get("year", SimConstants.START_YEAR))))


## A dated sentence: "In 2051, ...", "That same year, ..." after an event of
## the same year, or "Model-11 ... in 2051." when [param inline] (emergences).
static func _dated(entry: Dictionary, year: int, previous_year: int, short_model: bool, inline: bool) -> String:
	if year == previous_year:
		return "That same year, %s." % _event_clause(entry, short_model)
	if inline and String(entry.get("category", "")) == "EMERGENCE":
		return "%s." % StoryCopy.capitalize_first(_event_clause(entry, short_model, "in %d" % year))
	return "In %d, %s." % [year, _event_clause(entry, short_model)]


## The past-tense clause for an emergence, shift, milestone or collapse.
## [param when] ("in 2053") is placed where the clause asks for it ({when}),
## else appended.
static func _event_clause(entry: Dictionary, short_model: bool = false, when: String = "") -> String:
	var suffix := (" " + when) if when != "" else ""
	match String(entry.get("category", "")):
		"EMERGENCE":
			var copy: Dictionary = StoryCopy.EMERGENCES.get(String(entry.get("capability", "")), {})
			var model := String(entry.get("model", "a frontier model"))
			if short_model:
				model = model.trim_prefix("Frontier ")
			var did := String(copy.get("did", "{model} surprised its makers"))
			if not did.contains("{when}"):
				did += "{when}"
			return StoryCopy.fill(did, {"model": model, "when": suffix})
		"PARADIGM":
			var copy: Dictionary = StoryCopy.SHIFTS.get(String(entry.get("shift", "")), {})
			return String(copy.get("did", "%s arrived" % String(entry.get("name", "a new paradigm")).to_lower())) + suffix
		"MILESTONE":
			if String(entry.get("first_mover", "")) == SimConstants.CEO:
				return "the Frontier Lab crossed the general-capability threshold" + suffix
			return "a state consortium crossed the general-capability threshold" + suffix
		"COLLAPSE":
			return String(COLLAPSE_DID.get(String(entry.get("code", "")), "a faction collapsed")) + suffix
	return "the record went quiet" + suffix


static func _quiet_paragraph(ctx: Dictionary) -> String:
	var era := int(ctx["era"])
	var text := "The %s hardware era ran from %s." % [StoryCopy.ORDINAL.get(era, "next"), _years(ctx).replace("–", " to ")]
	var clauses: Array[String] = []
	for item in ctx["stats"]:
		var stat: Dictionary = item
		clauses.append(_movement(String(stat["key"]), float(stat["from"]), float(stat["to"])))
	if not clauses.is_empty():
		text += " " + StoryCopy.capitalize_first(StoryCopy.join_and(clauses)) + "."
	return text


# --- "Also in this edition" and highlights ---------------------------------------------------

static func _also(ctx: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	for item in ctx["series"]:
		var series: Dictionary = item
		if out.size() >= MAX_ALSO:
			break
		if used.has(series["card"]):
			continue
		out.append(_series_tally(series))
	for item in ctx["series"]:
		var series: Dictionary = item
		if out.size() >= MAX_ALSO:
			break
		if used.has(series["card"]) and series != (ctx["series"] as Array)[0] and int(series["count"]) >= 2:
			out.append(_series_tally(series))
	var actions: Dictionary = ctx["actions"]
	var keys: Array = actions.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(actions[a]) > int(actions[b]) if int(actions[a]) != int(actions[b]) else a < b)
	for key in keys:
		if out.size() >= MAX_ALSO:
			break
		var copy: Dictionary = StoryCopy.ACTIONS.get(key, {})
		if copy.is_empty() or int(actions[key]) < 2 or String(key).begins_with(String(ctx["role"]) + "/"):
			continue
		var count := int(actions[key])
		out.append(StoryCopy.capitalize_first(StoryCopy.fill(String(copy["tally"]),
			{"n": StoryCopy.number_word(count), "times": StoryCopy.times(count)})))
	return out


## "Three claims of circuit-level transparency, all shelved", or a single
## crisis's own headline.
static func _series_tally(series: Dictionary) -> String:
	var card_id := String(series["card"])
	var count := int(series["count"])
	if count == 1:
		return String(HeadlineWriter.headline(series["first"]).get("title", ""))
	var copy := StoryCopy.card(card_id)
	if int(series["deferred"]) == count:
		return "%s, deferred %s" % [StoryCopy.capitalize_first(String(copy.get("subject", "A crisis"))), StoryCopy.times(count)]
	var ranked := _ranked_options(series)
	var key := String(ranked[0])
	var verdict := String(StoryCopy.card_option(card_id, key, String(series["actor"])).get("verdict", "resolved"))
	var quantifier := "mostly"
	if ranked.size() == 1:
		quantifier = "both" if count == 2 else "all"
	return "%s %s, %s %s" % [StoryCopy.capitalize_first(StoryCopy.number_word(count)), copy.get("plural", "crises"), quantifier, verdict]


static func _highlights(ctx: Dictionary) -> Array:
	var out: Array = []
	for item in ctx["events"]:
		var entry: Dictionary = item
		var category := String(entry.get("category", ""))
		var notable := category in ["EMERGENCE", "PARADIGM", "MILESTONE", "COLLAPSE", "ENDGAME"]
		if category == "THRESHOLD" and int(entry.get("band", 0)) >= 2:
			notable = true
		if not notable:
			continue
		var h := HeadlineWriter.headline(entry, String(ctx["role"]))
		out.append({"turn": int(entry.get("turn", 0)), "year": float(entry.get("year", 0.0)), "category": category,
			"title": h["title"], "glyph": h["glyph"]})
	return out


# --- Chapters ---------------------------------------------------------------------------------

## "The third hardware era opened in 2050 with a machine caught editing
## itself. When Frontier Model-10 was found rewriting its own training code,
## the Council froze the frontier runs. Within a year, ..."
static func _opening_sentences(ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var era := int(ctx["era"])
	var first: Dictionary = {}
	for item in ctx["events"]:
		if String((item as Dictionary).get("category", "")) == "DILEMMA":
			first = item
			break
	var start_year := _start_year(ctx)
	var ordinal := String(StoryCopy.ORDINAL.get(era, "next"))
	if first.is_empty():
		out.append("The %s hardware era opened in %d." % [ordinal, start_year])
	else:
		var card_id := String(first.get("card", ""))
		var copy := StoryCopy.card(card_id)
		var actor_id := String(first.get("faction", ctx["role"]))
		var key := _option_key(card_id, String(first.get("option", "")), actor_id)
		out.append("The %s hardware era opened in %d with %s." % [ordinal, start_year, copy.get("subject", "a crisis")])
		out.append("When %s, %s %s." % [_one(card_id, first), StoryCopy.actor_the(actor_id), _did(card_id, key, actor_id)])
		ctx["opening_card"] = card_id
	var opened_turn := int(first.get("turn", ctx["start_turn"])) if not first.is_empty() else int(ctx["start_turn"])
	var told := 0
	var previous_year := 0
	for item in ctx["shifts"]:
		var entry: Dictionary = item
		if told >= 2:
			break
		var year := _year_of(entry)
		if told == 0 and int(entry.get("turn", 0)) - opened_turn <= 2:
			out.append("Within a year, %s." % _event_clause(entry))
		else:
			out.append(_dated(entry, year, previous_year, false, false))
		previous_year = year
		told += 1
	return out


## Emergences, the AGI milestone and collapses in order; the largest drift
## jump of the whole campaign gets a footnote and marks the chapter's figure.
static func _chapter_machine_sentences(ctx: Dictionary, max_spike: float, footnotes: Array[String]) -> Array[String]:
	var items: Array = ctx["emergences"] + ctx["milestones"] + ctx["collapses"]
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("turn", 0)) < int(b.get("turn", 0)))
	var out: Array[String] = []
	var named_before := false
	var emergences := 0
	var previous_year := 0
	var biggest := 0.0
	for item in ctx["emergences"]:
		biggest = maxf(biggest, _spike(item))
	for item in items:
		var entry: Dictionary = item
		var year := _year_of(entry)
		var is_emergence := String(entry.get("category", "")) == "EMERGENCE"
		var marked := is_emergence and max_spike >= 4.0 and is_equal_approx(_spike(entry), max_spike) and footnotes.is_empty()
		if is_emergence and emergences >= MAX_CHAPTER_EMERGENCES and not marked:
			continue
		if marked:
			var lead_in := "Then, in %d, " % year if not out.is_empty() else "In %d, " % year
			out.append("%s%s: the century's largest single jump in drift.¹" % [lead_in, _event_clause(entry, named_before)])
			footnotes.append("%s, turn %d of the campaign." % [entry.get("name", "Emergent capability"), int(entry.get("turn", 0))])
			ctx["mark_turn"] = int(entry.get("turn", 0))
			ctx["mark_year"] = year
		else:
			out.append(_dated(entry, year, previous_year, named_before, true))
			if is_emergence and biggest >= 5.0 and is_equal_approx(_spike(entry), biggest):
				out.append(_spike_sentence(biggest))
		previous_year = year
		if is_emergence:
			named_before = true
			emergences += 1
	if out.is_empty():
		for item in ctx["thresholds"]:
			var entry: Dictionary = item
			out.append("By %d, %s had gone critical." % [int(floor(float(entry.get("year", 0.0)))),
				METRIC_PROSE.get(String(entry.get("metric", "")), "a metric")])
			if out.size() >= 2:
				break
	for item in ctx["catastrophes"]:
		var entry: Dictionary = item
		out.append("In %d, %s." % [int(floor(float(entry.get("year", 0.0)))),
			CATASTROPHE_DID.get(String(entry.get("catastrophe", "")), "catastrophe struck")])
	if not ctx.has("mark_turn") and not ctx["emergences"].is_empty():
		var top: Dictionary = ctx["emergences"][0]
		for item in ctx["emergences"]:
			if _spike(item) > _spike(top):
				top = item
		ctx["mark_turn"] = int(top.get("turn", 0))
		ctx["mark_year"] = _year_of(top)
	return out


## The crisis the desk saw most, unless the opening already told it.
static func _chapter_desk_sentences(ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for item in ctx["series"]:
		var series: Dictionary = item
		if out.size() >= 2:
			break
		if int(series["count"]) < 2:
			continue
		if String(series["card"]) == String(ctx.get("opening_card", "")) and int(series["count"]) < 3:
			continue
		out.append(" ".join(_series_sentences(series, ctx, false)))
	return out
