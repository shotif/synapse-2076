class_name EffectResolver
extends RefCounted
## Applies declarative effect dictionaries (directives, crisis-card options,
## emergent capabilities, paradigm shifts, faction collapses) to the simulation.
## Every world mutation outside the coupled dynamics flows through here.
##
## Effect schema (all keys optional):
##   "metrics":  {metric_key: delta}                macro meters (0-100)
##   "indices":  {index_key: delta}                 secondary indices (0-100)
##   "self":     {resource: delta}                  the acting faction's currencies
##   "factions": {faction_id: {resource: delta}}    other factions' currencies
##   "provokes": {faction_id: grievance}            explicit grievance toward the actor
##   "tech":     {"capability_investment", "safety_investment", "growth_mult",
##                "growth_turns", "alignment_tax", "paradigm_progress"}
##   "compute":  {"grid_capacity_gw", "grid_damage"}
##   "inject_dilemma": card id queued for the player (crisis injection)
##
## Context keys: world, tech, compute, factions (id -> ActorBase), deck,
## actor_id, player_id, scale (effect multiplier, default 1.0).

## Grievance generated per 1% of a rival's currency scale destroyed.
const GRIEVANCE_PER_PERCENT := 0.6


static func apply(effects: Dictionary, ctx: Dictionary) -> Dictionary:
	var world: WorldState = ctx.get("world")
	var tech: TechTreeManager = ctx.get("tech")
	var compute: ComputeScaling = ctx.get("compute")
	var factions: Dictionary = ctx.get("factions", {})
	var actor_id := String(ctx.get("actor_id", ""))
	var player_id := String(ctx.get("player_id", ""))
	var scale := float(ctx.get("scale", 1.0))
	if not is_finite(scale) or scale < 0.0:
		scale = 1.0
	var actor: ActorBase = factions.get(actor_id)

	var applied := {"metrics": {}, "indices": {}, "self": {}, "factions": {}, "tech": {}, "compute": {}, "injected": ""}

	if world != null:
		var metric_effects: Dictionary = effects.get("metrics", {})
		for key in metric_effects:
			applied["metrics"][key] = world.apply_delta(key, float(metric_effects[key]) * scale)
		var index_effects: Dictionary = effects.get("indices", {})
		for key in index_effects:
			applied["indices"][key] = world.apply_delta(key, float(index_effects[key]) * scale)

	if actor != null:
		var self_effects: Dictionary = effects.get("self", {})
		for key in self_effects:
			applied["self"][key] = actor.add_resource(key, float(self_effects[key]) * scale)

	var faction_effects: Dictionary = effects.get("factions", {})
	for target_id in faction_effects:
		var target: ActorBase = factions.get(target_id)
		if target == null or not target.is_active():
			continue
		var changes: Dictionary = faction_effects[target_id]
		var applied_changes := {}
		var harm := 0.0
		for key in changes:
			var delta := target.add_resource(key, float(changes[key]) * scale)
			applied_changes[key] = delta
			if delta < 0.0:
				harm += absf(delta) / target.resource_scale(key) * 100.0
		applied["factions"][target_id] = applied_changes
		if harm > 0.0 and actor_id != "":
			target.add_grievance(actor_id, harm * GRIEVANCE_PER_PERCENT)

	var provocations: Dictionary = effects.get("provokes", {})
	for target_id in provocations:
		var provoked: ActorBase = factions.get(target_id)
		if provoked != null and actor_id != "":
			provoked.add_grievance(actor_id, float(provocations[target_id]) * scale)

	if tech != null:
		var tech_effects: Dictionary = effects.get("tech", {})
		if tech_effects.has("capability_investment") or tech_effects.has("safety_investment"):
			var capability := float(tech_effects.get("capability_investment", 0.0)) * scale
			var safety := float(tech_effects.get("safety_investment", 0.0)) * scale
			tech.add_investment(capability, safety)
			applied["tech"]["capability_investment"] = capability
			applied["tech"]["safety_investment"] = safety
		if tech_effects.has("growth_mult"):
			# Intensity scales the deviation from 1.0, not the multiplier itself.
			var mult := 1.0 + (float(tech_effects["growth_mult"]) - 1.0) * scale
			var turns := int(tech_effects.get("growth_turns", 1))
			tech.add_growth_modifier(mult, turns, actor_id)
			applied["tech"]["growth_mult"] = mult
			applied["tech"]["growth_turns"] = turns
		if tech_effects.has("alignment_tax"):
			applied["tech"]["alignment_tax_drift"] = tech.apply_alignment_tax(float(tech_effects["alignment_tax"]) * scale, world)
		if tech_effects.has("paradigm_progress"):
			tech.add_paradigm_progress(float(tech_effects["paradigm_progress"]) * scale)
			applied["tech"]["paradigm_progress"] = float(tech_effects["paradigm_progress"]) * scale

	if compute != null:
		var compute_effects: Dictionary = effects.get("compute", {})
		if compute_effects.has("grid_capacity_gw"):
			compute.add_grid_capacity(float(compute_effects["grid_capacity_gw"]) * scale)
			applied["compute"]["grid_capacity_gw"] = float(compute_effects["grid_capacity_gw"]) * scale
		if compute_effects.has("grid_damage"):
			compute.damage_grid(float(compute_effects["grid_damage"]) * scale)
			applied["compute"]["grid_damage"] = float(compute_effects["grid_damage"]) * scale

	var card_id := String(effects.get("inject_dilemma", ""))
	var deck: DilemmaDeck = ctx.get("deck")
	if card_id != "" and deck != null and actor_id != player_id:
		if deck.inject(card_id, actor_id):
			applied["injected"] = card_id

	return applied


## Multiplies every numeric delta in an effects dictionary (used for crisis-card
## escalation). Multipliers, durations and card ids are left untouched.
static func scaled(effects: Dictionary, factor: float) -> Dictionary:
	var out := effects.duplicate(true)
	for section in ["metrics", "indices", "self"]:
		if out.has(section):
			for key in out[section]:
				out[section][key] = float(out[section][key]) * factor
	if out.has("factions"):
		for target_id in out["factions"]:
			for key in out["factions"][target_id]:
				out["factions"][target_id][key] = float(out["factions"][target_id][key]) * factor
	return out
