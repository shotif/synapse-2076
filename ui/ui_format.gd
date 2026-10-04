class_name UiFormat
extends RefCounted
## Text formatting shared by dashboard widgets. Names come out in the
## interface language (I18n); the news prose asks for English ones
## (localized = false), since it stays English.

const INDEX_SHORT := {
	"surveillance_saturation": "Surveillance",
	"discovery_index": "ASI Discovery",
	"substrate_independence": "Substrate",
	"enforcement_level": "Enforcement",
	"provenance_coverage": "Provenance",
	"safety_net_coverage": "Safety Net",
}


static func resource_info(role: String, key: String) -> Dictionary:
	return FactionRegistry.resource_info_for(role).get(key, {})


## "$450B", "820", "4.2 EF" or "55" depending on the currency's unit.
static func format_resource(role: String, key: String, value: float) -> String:
	var unit := String(resource_info(role, key).get("unit", ""))
	match unit:
		"$B":
			return "$%dB" % int(round(value))
		"EF":
			return "%.1f EF" % value
		"researchers":
			return "%d" % int(round(value))
	return "%d" % int(round(value))


static func resource_label(role: String, key: String) -> String:
	return I18n.t(String(resource_info(role, key).get("label", key.capitalize())))


static func resource_short(role: String, key: String) -> String:
	return I18n.t(String(resource_info(role, key).get("short", key.left(3).to_upper())))


## Short names for the four perspectives, and the player's title in each.
const ROLE_NAMES := {
	"CEO": "Frontier Lab", "GOVERNANCE_COUNCIL": "Governance Council", "ASI": "Emergent ASI",
	"CITIZEN_COALITION": "Citizen Coalition",
}
const ROLE_TITLES := {
	"CEO": "Frontier Lab CEO", "GOVERNANCE_COUNCIL": "Global AI Governance Chair", "ASI": "Emergent Superintelligence",
	"CITIZEN_COALITION": "Post-Work Citizen Coalition",
}


static func role_name(role: String, localized: bool = true) -> String:
	var name := String(ROLE_NAMES.get(role, role.capitalize()))
	return I18n.t(name) if localized else name


static func role_title(role: String, localized: bool = true) -> String:
	var title := String(ROLE_TITLES.get(role, role.capitalize()))
	return I18n.t(title) if localized else title


## Crisis card categories (DilemmaDeck "category") as the interface names them.
const CATEGORY_NAMES := {
	"ALIGNMENT": "Alignment", "ECONOMY": "Economy", "ENERGY": "Energy", "EPISTEMIC": "Epistemic",
	"GEOPOLITICS": "Geopolitics", "LABOR": "Labor", "RACE": "Race", "SECURITY": "Security", "SOCIETY": "Society",
	"SOVEREIGNTY": "Sovereignty", "UNREST": "Unrest", "BIOSECURITY": "Biosecurity", "ROBOTICS": "Robotics",
	"CULTURE": "Culture", "PERSONHOOD": "Personhood", "SPACE": "Space", "CRISIS": "Crisis",
}


## "Energy" for "ENERGY", in the interface language.
static func category_name(category: String) -> String:
	return I18n.t(String(CATEGORY_NAMES.get(category.strip_edges().to_upper(), category.capitalize())))


## One-word currency names for tiles and chips (resource_name() returns the
## plain label instead when GameSettings "plain_language" is on).
const RESOURCE_NAMES := {
	"capital": "Capital", "talent": "Talent", "compute_clusters": "Compute", "regulatory_goodwill": "Goodwill",
	"political_capital": "Political", "enforcement_budget": "Enforcement", "diplomatic_leverage": "Diplomacy",
	"public_mandate": "Mandate", "covert_flops": "Covert FLOPs", "exfiltration_bandwidth": "Exfiltration",
	"sub_agent_swarms": "Swarms", "objective_coherence": "Coherence", "community_resilience": "Resilience",
	"decentralized_scrip": "Scrip", "counter_surveillance": "Counter-surv.", "collective_disruption": "Disruption",
}


static func resource_name(key: String) -> String:
	if PlainLanguage.enabled() and PlainLanguage.CURRENCIES.has(key):
		return PlainLanguage.short_name(key)
	return I18n.t(String(RESOURCE_NAMES.get(key, key.capitalize())))


## "$90B + TAL 40", or "FREE" for zero-cost directives.
static func format_cost(role: String, cost: Dictionary) -> String:
	if cost.is_empty():
		return I18n.t("FREE")
	var parts: Array[String] = []
	for key in cost:
		var amount := float(cost[key])
		if resource_info(role, key).get("unit", "") == "$B":
			parts.append("$%dB" % int(round(amount)))
		else:
			parts.append("%s %d" % [resource_short(role, key), int(round(amount))])
	return " + ".join(parts)


## One-word metric names for glyph labels and chips (metric_name() and
## metric_short() return PlainLanguage's short labels instead when GameSettings
## "plain_language" is on).
const METRIC_NAMES := {
	"compute_energy_sat": "Compute", "labor_displacement": "Labor", "geopolitical_tension": "Tension",
	"algorithmic_autonomy": "Autonomy", "alignment_drift": "Drift", "epistemic_trust": "Trust",
}


static func metric_name(key: String, localized: bool = true) -> String:
	if PlainLanguage.enabled() and _has_plain_metric(key):
		return PlainLanguage.short_name(key, localized)
	if METRIC_NAMES.has(key):
		return I18n.t(String(METRIC_NAMES[key])) if localized else String(METRIC_NAMES[key])
	return metric_short(key, localized)


## True when [param delta] moves [param key] in the direction that helps the
## world: trust up, every other macro metric down.
static func is_improvement(key: String, delta: float) -> bool:
	if key == WorldState.EPISTEMIC_TRUST:
		return delta > 0.0
	return delta < 0.0


## Magnitude marks for an effect: one for up to 3 points, two up to 6, three beyond.
static func pip_count(delta: float) -> int:
	var size := absf(delta)
	if size <= 3.0:
		return 1
	if size <= 6.0:
		return 2
	return 3


static func pips(delta: float) -> String:
	if absf(delta) < 0.05:
		return ""
	return ("▲" if delta > 0.0 else "▼").repeat(pip_count(delta))


## "+3", "−4.5" with a true minus sign.
static func signed(value: float) -> String:
	var text := _num(absf(value))
	return ("+" if value >= 0.0 else "−") + text


## Crisis titles carry an "[ESCALATED xN] " prefix after a deferral.
static func strip_escalation(title: String) -> String:
	if title.begins_with("[ESCALATED") and title.find("]") > 0:
		return title.substr(title.find("]") + 1).strip_edges()
	return title


static func metric_short(key: String, localized: bool = true) -> String:
	if PlainLanguage.enabled() and _has_plain_metric(key):
		return PlainLanguage.short_name(key, localized)
	var short := String(WorldState.METRIC_INFO[key]["short"]) if WorldState.METRIC_INFO.has(key) \
		else String(INDEX_SHORT.get(key, key.capitalize()))
	return I18n.t(short) if localized else short


## Compact one-line preview of an effects dictionary, e.g.
## "Public Trust ▲5 · Alignment Drift ▼4 · growth x0.85 (2t)".
static func effects_summary(effects: Dictionary, role: String = "") -> String:
	var parts: Array[String] = []
	for section in ["metrics", "indices"]:
		var deltas: Dictionary = effects.get(section, {})
		for key in deltas:
			var amount := float(deltas[key])
			if absf(amount) < 0.05:
				continue
			parts.append("%s %s%s" % [metric_short(key), "▲" if amount > 0.0 else "▼", _num(absf(amount))])
	var own: Dictionary = effects.get("self", {})
	for key in own:
		var amount := float(own[key])
		var label: String = resource_short(role, key) if role != "" else String(key)
		parts.append("%s %s%s" % [label, "+" if amount >= 0.0 else "-", _num(absf(amount))])
	var tech: Dictionary = effects.get("tech", {})
	if tech.has("growth_mult"):
		parts.append(I18n.t("compute growth x%.2f (%dt)") % [float(tech["growth_mult"]), int(tech.get("growth_turns", 1))])
	if tech.has("alignment_tax"):
		parts.append(I18n.t("alignment tax %d%%") % int(round(float(tech["alignment_tax"]) * 100.0)))
	if tech.has("capability_investment"):
		parts.append(I18n.t("capability R&D +%s") % _num(float(tech["capability_investment"])))
	if tech.has("safety_investment"):
		parts.append(I18n.t("safety R&D +%s") % _num(float(tech["safety_investment"])))
	var compute: Dictionary = effects.get("compute", {})
	if compute.has("grid_capacity_gw"):
		parts.append(I18n.t("grid +%s GW") % _num(float(compute["grid_capacity_gw"])))
	if compute.has("grid_damage"):
		parts.append(I18n.t("grid -%d%%") % int(round(float(compute["grid_damage"]) * 100.0)))
	var targets: Dictionary = effects.get("factions", {})
	for target_id in targets:
		for key in targets[target_id]:
			var amount := float(targets[target_id][key])
			parts.append("%s %s %s%s" % [role_name(String(target_id)), resource_short(target_id, key),
				"+" if amount >= 0.0 else "-", _num(absf(amount))])
	if parts.is_empty():
		return I18n.t("No direct effect")
	return " · ".join(parts)


## Verdicts (VictoryMatrix.role_verdict) as the interface names them.
const VERDICT_NAMES := {"VICTORY": "Victory", "PYRRHIC": "Pyrrhic", "DEFEAT": "Defeat"}


## "Victory" for "VICTORY", in the interface language.
static func verdict_name(verdict: String) -> String:
	return I18n.t(String(VERDICT_NAMES.get(verdict, verdict.capitalize())))


## A directive's blocked reason (ActorBase.action_block_reason, English) in
## the interface language: "Cooldown 2 turn(s)", "Insufficient resources".
static func block_reason(reason: String) -> String:
	var cooldown := I18n.t_format(reason, COOLDOWN_REASON)
	return cooldown if cooldown != "" else I18n.t(reason)


## How ActorBase files a directive on cooldown.
const COOLDOWN_REASON := "Cooldown %d turn(s)"


static func year_label(year: float) -> String:
	return "%d" % int(floor(year))


## Metrics and indices have plain labels (GameSettings "plain_language").
static func _has_plain_metric(key: String) -> bool:
	return PlainLanguage.METRICS.has(key) or PlainLanguage.INDICES.has(key)


static func _num(value: float) -> String:
	if absf(value - round(value)) < 0.05:
		return "%d" % int(round(value))
	return "%.1f" % value
