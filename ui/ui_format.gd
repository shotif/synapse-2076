class_name UiFormat
extends RefCounted
## Text formatting shared by dashboard widgets.

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
	return String(resource_info(role, key).get("label", key.capitalize()))


static func resource_short(role: String, key: String) -> String:
	return String(resource_info(role, key).get("short", key.left(3).to_upper()))


## "$90B + TAL 40", or "FREE" for zero-cost directives.
static func format_cost(role: String, cost: Dictionary) -> String:
	if cost.is_empty():
		return "FREE"
	var parts: Array[String] = []
	for key in cost:
		var amount := float(cost[key])
		if resource_info(role, key).get("unit", "") == "$B":
			parts.append("$%dB" % int(round(amount)))
		else:
			parts.append("%s %d" % [resource_short(role, key), int(round(amount))])
	return " + ".join(parts)


## One-word metric names for glyph labels and chips.
const METRIC_NAMES := {
	"compute_energy_sat": "Compute", "labor_displacement": "Labor", "geopolitical_tension": "Tension",
	"algorithmic_autonomy": "Autonomy", "alignment_drift": "Drift", "epistemic_trust": "Trust",
}


static func metric_name(key: String) -> String:
	return String(METRIC_NAMES.get(key, metric_short(key)))


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


static func metric_short(key: String) -> String:
	if WorldState.METRIC_INFO.has(key):
		return String(WorldState.METRIC_INFO[key]["short"])
	return String(INDEX_SHORT.get(key, key.capitalize()))


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
		parts.append("compute growth x%.2f (%dt)" % [float(tech["growth_mult"]), int(tech.get("growth_turns", 1))])
	if tech.has("alignment_tax"):
		parts.append("alignment tax %d%%" % int(round(float(tech["alignment_tax"]) * 100.0)))
	if tech.has("capability_investment"):
		parts.append("capability R&D +%s" % _num(float(tech["capability_investment"])))
	if tech.has("safety_investment"):
		parts.append("safety R&D +%s" % _num(float(tech["safety_investment"])))
	var compute: Dictionary = effects.get("compute", {})
	if compute.has("grid_capacity_gw"):
		parts.append("grid +%s GW" % _num(float(compute["grid_capacity_gw"])))
	if compute.has("grid_damage"):
		parts.append("grid -%d%%" % int(round(float(compute["grid_damage"]) * 100.0)))
	var targets: Dictionary = effects.get("factions", {})
	for target_id in targets:
		for key in targets[target_id]:
			var amount := float(targets[target_id][key])
			parts.append("%s %s %s%s" % [SimConstants.role_title(target_id).get_slice(" ", 0), resource_short(target_id, key),
				"+" if amount >= 0.0 else "-", _num(absf(amount))])
	if parts.is_empty():
		return "No direct effect"
	return " · ".join(parts)


static func year_label(year: float) -> String:
	return "%d" % int(floor(year))


static func _num(value: float) -> String:
	if absf(value - round(value)) < 0.05:
		return "%d" % int(round(value))
	return "%.1f" % value
