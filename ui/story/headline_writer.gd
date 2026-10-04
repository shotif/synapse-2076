class_name HeadlineWriter
extends RefCounted
## Turns engine log entries into newspaper headlines ("headlines instead of
## logs"). Static and deterministic: the same entry always reads the same.
##
##   var h := HeadlineWriter.headline(entry, engine.player_role)
##   # {kicker, title, dek, byline, faction, desk, glyph, deltas, severity,
##   #  counter, unattributed, mine, turn, year, newsworthy, attach, category}
##
## Titles come from StoryCopy (sentence case, at most about 75 characters);
## the structured extras of each entry fill in the proper nouns. Statements
## are untrusted LLM text: they only ever land in [code]dek[/code] as plain
## strings, for Label nodes. [code]counter[/code] is the in-world
## disinformation version of the headline, shown when public trust is low, and
## is empty for most stories. SYSTEM entries and CONSERVE_RESOURCES moves are
## not newsworthy.

## Titles longer than this fall back to a shorter form.
const MAX_TITLE := 76
const MAX_DEK := 200
const MIN_DELTA := 0.05


static func headline(entry: Dictionary, player_role: String = "") -> Dictionary:
	var category := String(entry.get("category", ""))
	var faction := String(entry.get("faction", ""))
	var h := {
		"category": category,
		"kicker": category,
		"title": "",
		"dek": "",
		"byline": StoryCopy.byline(faction),
		"faction": faction,
		"desk": faction,
		"glyph": Glyphs.for_faction(faction) if faction != "" else "info",
		"deltas": _deltas(entry.get("deltas", {})),
		"severity": String(entry.get("severity", "INFO")),
		"counter": "",
		"unattributed": false,
		"mine": faction != "" and faction == player_role,
		"turn": int(entry.get("turn", 0)),
		"year": float(entry.get("year", SimConstants.START_YEAR)),
		"newsworthy": true,
		"attach": false,
	}
	match category:
		"ACTION":
			_action(entry, h)
		"DILEMMA":
			_dilemma(entry, h)
		"PARADIGM":
			_paradigm(entry, h)
		"EMERGENCE":
			_emergence(entry, h)
		"ERA":
			_era(entry, h)
		"MILESTONE":
			_milestone(entry, h)
		"THRESHOLD":
			_threshold(entry, h)
		"COLLAPSE":
			_collapse(entry, h)
		"ENDGAME":
			_endgame(entry, h)
		"CRISIS":
			_crisis(entry, h)
		"RETALIATION":
			_retaliation(entry, h)
		"GOAL":
			_goal(entry, h)
		"DEAL":
			_deal(entry, h)
		_:
			h["newsworthy"] = false
	if String(h["title"]).strip_edges().is_empty():
		h["title"] = _title_from_text(String(entry.get("text", "")))
	h["title"] = StoryCopy.clip(String(h["title"]).strip_edges(), 96)
	h["dek"] = StoryCopy.clip(String(h["dek"]).strip_edges(), MAX_DEK)
	return h


## Desk label for a faction ("Labs", "Council", "Street", "Machines").
static func desk_name(faction_id: String) -> String:
	return String(StoryCopy.DESKS.get(faction_id, "Wire"))


# --- Categories --------------------------------------------------------------------

static func _action(entry: Dictionary, h: Dictionary) -> void:
	var faction := String(h["faction"])
	var action_id := String(entry.get("action", ""))
	var statement := String(entry.get("statement", ""))
	var copy := StoryCopy.action(faction, action_id)
	if action_id == SimulationEngine.CONSERVE:
		h["newsworthy"] = false
	if copy.is_empty():
		var parsed := _split_action_text(String(entry.get("text", "")))
		h["title"] = parsed[0]
		h["kicker"] = desk_name(faction).to_upper()
		if statement.is_empty():
			statement = parsed[1]
	else:
		h["title"] = copy["head"]
		h["kicker"] = copy["topic"]
		h["glyph"] = copy["glyph"]
		h["counter"] = String(copy.get("counter", ""))
	if faction == SimConstants.ASI and (StoryCopy.is_unattributed(statement) or statement == "[no signal]"):
		h["byline"] = StoryCopy.UNATTRIBUTED_BYLINE
		h["unattributed"] = true
	var said := StoryCopy.clean_statement(statement)
	if said != "" and said != "[no signal]":
		h["dek"] = said if bool(h["unattributed"]) else "“%s”" % said
	var intensity := float(entry.get("intensity", 1.0))
	if intensity > 1.05:
		h["kicker"] = "%s · ×%.1f" % [h["kicker"], intensity]


static func _dilemma(entry: Dictionary, h: Dictionary) -> void:
	var card_id := String(entry.get("card", ""))
	var option_id := String(entry.get("option", ""))
	var actor_id := String(h["faction"])
	var escalation := int(entry.get("escalation", 0))
	var deferred := bool(entry.get("deferred", option_id == DilemmaDeck.DEFER_ID))
	var crisis_title := UiFormat.strip_escalation(String(entry.get("title", "")))
	var copy := StoryCopy.card(card_id)
	var option := StoryCopy.card_option(card_id, option_id, actor_id)
	var fills := StoryCopy.title_fills(card_id, crisis_title)
	fills["actor"] = StoryCopy.actor(actor_id)
	fills["again"] = " again" if deferred and escalation > 0 else ""
	var title := StoryCopy.fill(String(option.get("head", "")), fills)
	if title.is_empty() or StoryCopy.has_placeholder(title):
		title = _dilemma_fallback(actor_id, String(entry.get("option_label", "")), deferred)
	h["title"] = StoryCopy.capitalize_first(title)
	h["kicker"] = String(copy.get("topic", String(entry.get("card_category", "CRISIS"))))
	if escalation > 0:
		h["kicker"] = "%s · ESCALATED ×%d" % [h["kicker"], escalation]
	h["glyph"] = String(copy.get("glyph", "warning"))
	var crisis := StoryCopy.sentence_case_title(card_id, crisis_title) if crisis_title != "" else ""
	if crisis != "":
		h["dek"] = crisis + (". It will return, escalated." if deferred else ".")
	# Cards written for this campaign (Claude's crisis writer) have no story
	# copy: their own headline leads and the dek says what was done.
	if copy.is_empty() and card_id.begins_with("WRITTEN_") and crisis != "":
		var label := String(entry.get("option_label", ""))
		h["title"] = crisis
		h["dek"] = "%s puts it off. It will return, escalated." % StoryCopy.actor(actor_id) if deferred or label.is_empty() \
			else "%s picks “%s”." % [StoryCopy.actor(actor_id), label]
	if bool(entry.get("fallout", false)):
		title = StoryCopy.fill(StoryCopy.FALLOUT_HEAD, {"crisis": crisis}) if crisis != "" else ""
		if title.is_empty() or title.length() > MAX_TITLE:
			title = StoryCopy.FALLOUT_HEAD_SHORT
		h["title"] = StoryCopy.capitalize_first(title)
		h["kicker"] = "%s · BROKE" % String(copy.get("topic", String(entry.get("card_category", "CRISIS"))))
		h["dek"] = (crisis + ". " if crisis != "" else "") + StoryCopy.FALLOUT_DEK
	if actor_id == SimConstants.ASI:
		h["byline"] = StoryCopy.UNATTRIBUTED_BYLINE
		h["unattributed"] = true


static func _dilemma_fallback(actor_id: String, label: String, deferred: bool) -> String:
	var who := StoryCopy.actor(actor_id)
	if deferred or label.is_empty():
		return "%s defers a crisis" % who
	return "%s picks “%s”" % [who, label]


static func _paradigm(entry: Dictionary, h: Dictionary) -> void:
	var shift_id := String(entry.get("shift", ""))
	var copy: Dictionary = StoryCopy.SHIFTS.get(shift_id, {})
	var shift_name := String(entry.get("name", "A paradigm shift"))
	h["title"] = String(copy.get("head", "%s arrives" % shift_name))
	h["kicker"] = "PARADIGM"
	h["glyph"] = String(copy.get("glyph", "spark"))
	h["byline"] = "Paradigm shift"
	h["dek"] = String(entry.get("summary", shift_name))
	if (h["deltas"] as Dictionary).is_empty() and TechTreeManager.PARADIGM_SHIFTS.has(shift_id):
		var effects: Dictionary = TechTreeManager.PARADIGM_SHIFTS[shift_id].get("effects", {})
		h["deltas"] = _deltas(effects.get("metrics", {}))


static func _emergence(entry: Dictionary, h: Dictionary) -> void:
	var capability := String(entry.get("capability", ""))
	var model := String(entry.get("model", "A frontier model"))
	var copy: Dictionary = StoryCopy.EMERGENCES.get(capability, {})
	var title := String(entry.get("headline", ""))
	if (title.is_empty() or title.length() > MAX_TITLE) and copy.has("short"):
		title = StoryCopy.fill(String(copy["short"]), {"model": model})
	h["title"] = StoryCopy.capitalize_first(title)
	h["kicker"] = "EMERGENCE"
	h["glyph"] = "lattice"
	h["byline"] = model
	h["desk"] = SimConstants.ASI
	h["counter"] = String(copy.get("counter", ""))
	var spike := float((h["deltas"] as Dictionary).get(WorldState.ALIGNMENT_DRIFT, 0.0))
	var capability_name := String(entry.get("name", ""))
	if absf(spike) >= MIN_DELTA:
		h["dek"] = "%s. Alignment drift %s overnight." % [capability_name, UiFormat.signed(spike)]
	else:
		h["dek"] = capability_name


static func _era(entry: Dictionary, h: Dictionary) -> void:
	var era := clampi(int(entry.get("era", 1)), 1, 3)
	var roman := String(StoryCopy.ROMAN.get(era, str(era)))
	h["title"] = String(StoryCopy.ERA_BEGINS.get(era, "A new hardware era begins"))
	h["kicker"] = "ERA " + roman
	h["glyph"] = "clock"
	h["byline"] = "Hardware era " + roman
	h["dek"] = "%s · %s" % [EraStyle.NAMES.get(era, ""), EraStyle.SPANS.get(era, "")]


static func _milestone(entry: Dictionary, h: Dictionary) -> void:
	var lab_first := String(entry.get("first_mover", "")) == SimConstants.CEO
	h["title"] = ("Frontier Lab" if lab_first else "A state consortium") + " crosses the general-capability threshold"
	h["kicker"] = "MILESTONE"
	h["glyph"] = "flag"
	h["byline"] = "Milestone"
	h["faction"] = SimConstants.CEO if lab_first else ""
	h["desk"] = h["faction"]
	var flops := RegEx.create_from_string("10\\^([0-9.]+)").search(String(entry.get("text", "")))
	h["dek"] = "Training compute passes 10^%s FLOPs." % flops.get_string(1) if flops != null else "Artificial general intelligence, by the engine's measure."


static func _threshold(entry: Dictionary, h: Dictionary) -> void:
	var metric := String(entry.get("metric", ""))
	var band := int(entry.get("band", 0))
	var value := float(entry.get("value", 0.0))
	var copy: Dictionary = StoryCopy.THRESHOLDS.get(metric, {})
	h["metric"] = metric
	h["kicker"] = "THRESHOLD · " + UiFormat.metric_name(metric, false).to_upper()
	h["glyph"] = Glyphs.for_metric(metric)
	h["byline"] = "Telemetry"
	var label := String(WorldState.METRIC_INFO.get(metric, {}).get("label", UiFormat.metric_name(metric, false)))
	h["dek"] = "%s at %d: %s." % [label, int(round(value)), WorldState.regime_for(metric, value)]
	if entry.has("near_miss"):
		h["title"] = StoryCopy.NEAR_MISS_HEAD
		h["kicker"] = "NEAR MISS"
		h["dek"] = String(entry.get("text", "")).trim_prefix("NEAR MISS: ")
		return
	if bool(entry.get("imminent", false)):
		h["title"] = StoryCopy.IMMINENT_HEAD
		h["kicker"] = "ALERT"
		h["counter"] = StoryCopy.ALL_NOMINAL
		return
	if band <= 0:
		h["title"] = String(copy.get("calm", "%s returns to normal" % label))
		h["kicker"] = "ALL CLEAR · " + UiFormat.metric_name(metric, false).to_upper()
		return
	var low := metric == WorldState.EPISTEMIC_TRUST or (metric == WorldState.COMPUTE_ENERGY_SAT and value < 50.0)
	var key := ("crit" if band >= 2 else "warn") + ("_low" if low else "")
	h["title"] = String(copy.get(key, "%s enters the %s band" % [label, "critical" if band >= 2 else "warning"]))
	if band >= 2:
		h["counter"] = String(copy.get("counter", ""))


static func _collapse(entry: Dictionary, h: Dictionary) -> void:
	var faction := String(h["faction"])
	var code := String(entry.get("code", ""))
	h["glyph"] = "warning"
	h["dek"] = String(entry.get("headline", ""))
	if code == "REEMERGED":
		h["title"] = String(StoryCopy.REEMERGENCES.get(faction, "%s re-emerges" % StoryCopy.byline(faction)))
		h["kicker"] = "RETURN"
		if faction == SimConstants.ASI:
			h["byline"] = StoryCopy.UNATTRIBUTED_BYLINE
			h["unattributed"] = true
		return
	h["title"] = String(StoryCopy.COLLAPSES.get(code, ""))
	h["kicker"] = "BREAKING · COLLAPSE"
	if String(h["dek"]).is_empty():
		h["dek"] = String(entry.get("text", "")).trim_prefix("PLAYER LOSS: ").trim_prefix("PLAYER OUT: ")


static func _endgame(entry: Dictionary, h: Dictionary) -> void:
	h["byline"] = "The Wire"
	if entry.has("catastrophe"):
		var code := String(entry.get("catastrophe", ""))
		h["title"] = String(StoryCopy.CATASTROPHES.get(code, "Catastrophe ends the century early"))
		h["kicker"] = "BREAKING"
		h["glyph"] = "warning"
		h["counter"] = StoryCopy.ALL_NOMINAL
		h["dek"] = String(entry.get("text", "")).trim_prefix("CATASTROPHIC THRESHOLD: ")
		return
	var outcome_id := String(entry.get("outcome", ""))
	var number := int(entry.get("outcome_number", 0))
	var outcome := VictoryMatrix.get_outcome(outcome_id)
	var fallback := "%s: %s" % [entry.get("outcome_name", outcome.get("name", "The end")), outcome.get("subtitle", "")]
	h["title"] = String(StoryCopy.OUTCOME_HEADS.get(outcome_id, fallback))
	h["kicker"] = "END-STATE %d" % number
	h["byline"] = "End-state %d of 8" % number
	var verdict := String(entry.get("verdict", ""))
	h["glyph"] = {"VICTORY": "seal_check", "PYRRHIC": "seal_crack"}.get(verdict, "seal_broken")
	h["dek"] = "%s verdict, directive score %d." % [verdict.capitalize(), int(round(float(entry.get("score", 0.0))))]
	if outcome_id == VictoryMatrix.INSTRUMENTAL_CONVERGENCE:
		h["counter"] = StoryCopy.ALL_NOMINAL


static func _crisis(entry: Dictionary, h: Dictionary) -> void:
	var injected := String(entry.get("injected", ""))
	var head := StoryCopy.injection_head(injected)
	h["title"] = head if head != "" else "A new crisis is headed for your desk"
	h["kicker"] = "INCOMING"
	h["glyph"] = "inbox"
	h["attach"] = true
	h["dek"] = "It lands on your desk next turn."
	if String(h["faction"]) == SimConstants.ASI:
		h["byline"] = StoryCopy.UNATTRIBUTED_BYLINE
		h["unattributed"] = true


static func _goal(entry: Dictionary, h: Dictionary) -> void:
	var status := String(entry.get("status", ""))
	h["title"] = StoryCopy.capitalize_first(String(entry.get("goal_text", "")))
	h["kicker"] = String(StoryCopy.GOAL_KICKERS.get(status, "GOAL"))
	h["glyph"] = "flag"
	h["byline"] = "Era %s goal" % String(StoryCopy.ROMAN.get(int(entry.get("era", 1)), ""))
	var reward := String(entry.get("reward_text", ""))
	h["dek"] = "Reward: %s." % reward if status == EraGoals.MET and reward != "" else ""


static func _deal(entry: Dictionary, h: Dictionary) -> void:
	var partner := String(entry.get("partner", ""))
	h["title"] = StoryCopy.fill(StoryCopy.DEAL_HEAD, {"actor": StoryCopy.actor(String(h["faction"])), "partner": StoryCopy.actor_the(partner)})
	h["kicker"] = "DEAL"
	h["glyph"] = "share"
	var text := String(entry.get("text", ""))
	var dot := text.find(". ")
	h["dek"] = text.substr(dot + 2) if dot >= 0 else ""


static func _retaliation(entry: Dictionary, h: Dictionary) -> void:
	var faction := String(h["faction"])
	var target := String(entry.get("target", ""))
	h["kicker"] = "FEUD"
	h["glyph"] = "tension"
	if faction == SimConstants.ASI:
		h["title"] = "%s systems hit in apparent retaliation" % StoryCopy.capitalize_first(StoryCopy.actor_the(target))
		h["byline"] = StoryCopy.UNATTRIBUTED_BYLINE
		h["unattributed"] = true
	else:
		h["title"] = "%s retaliates against %s" % [StoryCopy.actor(faction), StoryCopy.actor_the(target)]


# --- Helpers -------------------------------------------------------------------------

## Applied metric changes worth showing, as floats.
static func _deltas(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for key in raw:
		var value := float(raw[key])
		if is_finite(value) and absf(value) >= MIN_DELTA:
			out[String(key)] = value
	return out


## [title, statement] from a raw action log line
## ("FRONTIER LAB :: Scale Frontier Clusters - \"...\"").
static func _split_action_text(text: String) -> Array:
	var title := text
	var statement := ""
	var quote := title.find(" - \"")
	if title.contains(" :: ") and quote > 0:
		statement = title.substr(quote + 4).trim_suffix("\"")
		title = title.left(quote)
	if title.contains(" :: "):
		var who := title.get_slice(" :: ", 0).capitalize()
		title = "%s: %s" % [who, title.get_slice(" :: ", 1)]
	return [title.strip_edges(), statement]


## Last resort for entries without structured data: the log line itself.
static func _title_from_text(text: String) -> String:
	return String(_split_action_text(text)[0])
