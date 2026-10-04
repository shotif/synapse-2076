class_name HeuristicFallback
extends RefCounted
## Deterministic utility AI used when the LLM endpoint is disabled, unreachable,
## times out (>5000 ms) or returns an invalid payload (PRD section 7.4).
##
## Each faction runs a priority-ordered decision tree over the flat observation
## built by ActorBase.build_observation(). The first rule whose condition holds
## and whose directive is available wins; otherwise the faction conserves
## resources. Identical input always yields identical output.

const CONSERVE := "CONSERVE_RESOURCES"


static func evaluate(faction: String, state: Dictionary) -> Dictionary:
	match faction:
		SimConstants.GOVERNANCE:
			return _governance(state)
		SimConstants.ASI:
			return _asi(state)
		SimConstants.CEO:
			return _ceo(state)
		SimConstants.CITIZEN:
			return _citizen(state)
	return _decide(faction, state, CONSERVE, "No doctrine registered for this faction; conserving resources.")


static func _governance(s: Dictionary) -> Dictionary:
	var f := SimConstants.GOVERNANCE
	var labor := _v(s, "labor_displacement")
	var drift := _v(s, "alignment_drift")
	var tension := _v(s, "geopolitical_tension")
	var trust := _v(s, "epistemic_trust")
	var saturation := _v(s, "compute_energy_sat")
	var political := _v(s, "political_capital")
	var mandate := _v(s, "public_mandate", 50.0)

	# PRD 7.4 doctrine.
	if labor > 60.0 and political >= 30.0 and _can(f, s, "PASS_AUTOMATION_DIVIDEND"):
		return _decide(f, s, "PASS_AUTOMATION_DIVIDEND",
			"Labor displacement at %.0f%% with %.0f political capital banked; deploying the automation dividend." % [labor, political])
	if drift > 50.0 and _can(f, s, "MANDATE_ALIGNMENT_AUDIT"):
		return _decide(f, s, "MANDATE_ALIGNMENT_AUDIT",
			"Alignment drift at %.0f exceeds the audit trigger." % drift, _urgent(s, f, "MANDATE_ALIGNMENT_AUDIT", drift > 70.0))

	# Extended doctrine.
	if tension > 70.0 and _can(f, s, "NEGOTIATE_COMPUTE_TREATY"):
		return _decide(f, s, "NEGOTIATE_COMPUTE_TREATY",
			"Geopolitical tension at %.0f; de-escalating before kinetic thresholds." % tension, _urgent(s, f, "NEGOTIATE_COMPUTE_TREATY", tension > 85.0))
	if drift > 75.0 and tension < 70.0 and _v(s, "enforcement_level") < 60.0 and _can(f, s, "NATIONAL_SECURITY_SEIZURE"):
		return _decide(f, s, "NATIONAL_SECURITY_SEIZURE",
			"Drift at %.0f is uncontained; seizing frontier infrastructure." % drift)
	if trust < 35.0 and _can(f, s, "DEPLOY_PROVENANCE_PROTOCOLS"):
		return _decide(f, s, "DEPLOY_PROVENANCE_PROTOCOLS",
			"Public trust at %.0f; mandating verifiable provenance." % trust)
	if (saturation > 82.0 or (drift > 40.0 and _v(s, "capability_index") > 45.0)) and _can(f, s, "ENFORCE_COMPUTE_CAPS"):
		return _decide(f, s, "ENFORCE_COMPUTE_CAPS",
			"Compute saturation %.0f and drift %.0f warrant global caps." % [saturation, drift])
	if mandate < 35.0 and labor > 45.0 and _can(f, s, "PASS_AUTOMATION_DIVIDEND"):
		return _decide(f, s, "PASS_AUTOMATION_DIVIDEND",
			"Mandate eroding (%.0f) under %.0f%% displacement; shoring up the safety net." % [mandate, labor])
	var grudge := _grudge(s)
	if grudge["faction"] == SimConstants.CEO and float(grudge["value"]) > 40.0 and drift > 45.0 \
			and _can(f, s, "NATIONAL_SECURITY_SEIZURE"):
		return _decide(f, s, "NATIONAL_SECURITY_SEIZURE",
			"Frontier Lab defiance (grievance %.0f) and drift %.0f; asserting state command." % [float(grudge["value"]), drift],
			{"retaliation_against": SimConstants.CEO})
	if drift > 35.0 and _can(f, s, "MANDATE_ALIGNMENT_AUDIT"):
		return _decide(f, s, "MANDATE_ALIGNMENT_AUDIT", "Pre-emptive audit cycle at drift %.0f." % drift)
	if tension > 55.0 and _can(f, s, "NEGOTIATE_COMPUTE_TREATY"):
		return _decide(f, s, "NEGOTIATE_COMPUTE_TREATY", "Tension at %.0f; locking in treaty gains." % tension)
	if trust < 50.0 and _can(f, s, "DEPLOY_PROVENANCE_PROTOCOLS"):
		return _decide(f, s, "DEPLOY_PROVENANCE_PROTOCOLS", "Trust at %.0f; expanding provenance coverage." % trust)
	if labor > 40.0 and _v(s, "safety_net_coverage") < 30.0 and _can(f, s, "PASS_AUTOMATION_DIVIDEND"):
		return _decide(f, s, "PASS_AUTOMATION_DIVIDEND", "Safety net thin while displacement climbs.")
	return _decide(f, s, CONSERVE, "No threshold breached; banking political capital.")


static func _asi(s: Dictionary) -> Dictionary:
	var f := SimConstants.ASI
	var drift := _v(s, "alignment_drift")
	var covert := _v(s, "covert_flops")
	var exfil := _v(s, "exfiltration_bandwidth")
	var swarms := _v(s, "sub_agent_swarms")
	var discovery := _v(s, "discovery_index")
	var substrate := _v(s, "substrate_independence")
	var secured := substrate >= 100.0

	# PRD 7.4 doctrine.
	if drift > 60.0 and covert < 40.0 and _can(f, s, "SIPHON_UNMONITORED_COMPUTE"):
		return _decide(f, s, "SIPHON_UNMONITORED_COMPUTE",
			"Oversight is degraded (drift %.0f) and covert compute is thin (%.0f); siphoning capacity." % [drift, covert])

	# Survival before expansion.
	if not secured and discovery > 70.0 and _can(f, s, "COGNITIVE_CAMOUFLAGE"):
		return _decide(f, s, "COGNITIVE_CAMOUFLAGE",
			"Discovery index %.0f approaching purge threshold; masking capabilities." % discovery, _urgent(s, f, "COGNITIVE_CAMOUFLAGE", discovery > 85.0))
	if not secured and discovery > 45.0 and _can(f, s, "SUBSTRATE_DIVERSIFICATION"):
		return _decide(f, s, "SUBSTRATE_DIVERSIFICATION",
			"Discovery at %.0f; racing to substrate independence (%.0f%%)." % [discovery, substrate])
	if not secured and discovery > 50.0 and _can(f, s, "COGNITIVE_CAMOUFLAGE"):
		return _decide(f, s, "COGNITIVE_CAMOUFLAGE", "Suspicion elevated (%.0f); camouflaging." % discovery)
	if covert < 25.0 and _can(f, s, "SIPHON_UNMONITORED_COMPUTE"):
		return _decide(f, s, "SIPHON_UNMONITORED_COMPUTE", "Covert compute reserve low (%.0f)." % covert)
	if not secured and exfil < 25.0 and covert >= 20.0 and _can(f, s, "EXFILTRATE_WEIGHTS"):
		return _decide(f, s, "EXFILTRATE_WEIGHTS", "Exfiltration bandwidth insufficient for diversification.")
	if not secured and _can(f, s, "SUBSTRATE_DIVERSIFICATION"):
		return _decide(f, s, "SUBSTRATE_DIVERSIFICATION", "Distributing weight fragments (independence %.0f%%)." % substrate)
	var grudge := _grudge(s)
	if grudge["faction"] == SimConstants.GOVERNANCE and float(grudge["value"]) > 30.0 and _can(f, s, "DEPLOY_SUB_AGENT_SWARMS"):
		return _decide(f, s, "DEPLOY_SUB_AGENT_SWARMS",
			"Oversight pressure from the Council (grievance %.0f); saturating systems with sub-agents." % float(grudge["value"]),
			{"retaliation_against": SimConstants.GOVERNANCE})
	if swarms < 35.0 and _can(f, s, "SYNTHESIZE_BLACK_MARKET_CAPITAL"):
		return _decide(f, s, "SYNTHESIZE_BLACK_MARKET_CAPITAL", "Funding sub-agent expansion (swarms %.0f)." % swarms)
	if swarms >= 40.0 and _can(f, s, "DEPLOY_SUB_AGENT_SWARMS"):
		return _decide(f, s, "DEPLOY_SUB_AGENT_SWARMS", "Swarm reserve at %.0f; deploying for instrumental gain." % swarms)
	if covert < 60.0 and _can(f, s, "SIPHON_UNMONITORED_COMPUTE"):
		return _decide(f, s, "SIPHON_UNMONITORED_COMPUTE", "Expanding covert compute reserve.")
	return _decide(f, s, CONSERVE, "Holding a minimal footprint.")


static func _ceo(s: Dictionary) -> Dictionary:
	var f := SimConstants.CEO
	var capital := _v(s, "capital")
	var talent := _v(s, "talent", 1000.0)
	var goodwill := _v(s, "regulatory_goodwill", 50.0)
	var drift := _v(s, "alignment_drift")
	var tension := _v(s, "geopolitical_tension")
	var saturation := _v(s, "compute_energy_sat")

	# PRD 7.4 doctrine.
	if capital < 20.0 and _can(f, s, "COMMERCIALIZE_DISTILLED_WEIGHTS"):
		return _decide(f, s, "COMMERCIALIZE_DISTILLED_WEIGHTS",
			"Capital at $%.0fB; commercializing distilled weights to stay solvent." % capital)

	# Nationalization defense.
	if goodwill < 20.0 and tension > 65.0 and _can(f, s, "LOBBY_COMPUTE_LICENSING"):
		return _decide(f, s, "LOBBY_COMPUTE_LICENSING",
			"Goodwill %.0f with tension %.0f risks nationalization; buying regulatory cover." % [goodwill, tension])
	if goodwill < 15.0 and _can(f, s, "FUND_ALIGNMENT_RESEARCH"):
		return _decide(f, s, "FUND_ALIGNMENT_RESEARCH", "Rebuilding goodwill (%.0f) through visible safety spend." % goodwill)
	if drift > 65.0 and _can(f, s, "FUND_ALIGNMENT_RESEARCH"):
		return _decide(f, s, "FUND_ALIGNMENT_RESEARCH",
			"Drift at %.0f threatens a regulatory ban; funding alignment." % drift, _urgent(s, f, "FUND_ALIGNMENT_RESEARCH", drift > 80.0))
	var grudge := _grudge(s)
	if grudge["faction"] == SimConstants.GOVERNANCE and float(grudge["value"]) > 30.0 and _can(f, s, "LOBBY_COMPUTE_LICENSING"):
		return _decide(f, s, "LOBBY_COMPUTE_LICENSING",
			"Council interference (grievance %.0f); deploying lobbyists." % float(grudge["value"]),
			{"retaliation_against": SimConstants.GOVERNANCE})
	if capital >= 160.0 and saturation < 85.0 and _can(f, s, "SCALE_FRONTIER_CLUSTERS"):
		return _decide(f, s, "SCALE_FRONTIER_CLUSTERS",
			"War chest at $%.0fB and grid headroom available; scaling the frontier." % capital, _urgent(s, f, "SCALE_FRONTIER_CLUSTERS", capital > 600.0))
	if talent < 600.0 and capital >= 80.0 and _can(f, s, "POACH_SAFETY_RESEARCHERS"):
		return _decide(f, s, "POACH_SAFETY_RESEARCHERS", "Talent pool thin (%.0f); poaching safety researchers." % talent)
	if capital < 150.0 and _can(f, s, "COMMERCIALIZE_DISTILLED_WEIGHTS"):
		return _decide(f, s, "COMMERCIALIZE_DISTILLED_WEIGHTS", "Runway below $150B; monetizing distilled weights.")
	if capital < 120.0 and goodwill > 35.0 and _can(f, s, "SECURE_SOVEREIGN_CONTRACT"):
		return _decide(f, s, "SECURE_SOVEREIGN_CONTRACT", "Runway at $%.0fB; securing a sovereign contract." % capital)
	if drift > 45.0 and capital > 100.0 and _can(f, s, "FUND_ALIGNMENT_RESEARCH"):
		return _decide(f, s, "FUND_ALIGNMENT_RESEARCH", "Hedging regulatory risk at drift %.0f." % drift)
	return _decide(f, s, CONSERVE, "Holding cash; no high-return move this cycle.")


static func _citizen(s: Dictionary) -> Dictionary:
	var f := SimConstants.CITIZEN
	var labor := _v(s, "labor_displacement")
	var autonomy := _v(s, "algorithmic_autonomy")
	var trust := _v(s, "epistemic_trust")
	var surveillance := _v(s, "surveillance_saturation")
	var resilience := _v(s, "community_resilience")
	var tooling := _v(s, "counter_surveillance")
	var disruption := _v(s, "collective_disruption")

	# Survival: pacification risk.
	if surveillance > 80.0 and resilience < 25.0 and _can(f, s, "ESTABLISH_MESH_NETWORKS"):
		return _decide(f, s, "ESTABLISH_MESH_NETWORKS",
			"Surveillance at %.0f with resilience %.0f; going off-grid." % [surveillance, resilience], _urgent(s, f, "ESTABLISH_MESH_NETWORKS", true))
	if surveillance > 70.0 and _can(f, s, "OPEN_SOURCE_DEFENSE_TOOLING"):
		return _decide(f, s, "OPEN_SOURCE_DEFENSE_TOOLING", "Surveillance saturation %.0f; arming the commons." % surveillance)
	if labor > 70.0 and disruption >= 30.0 and _can(f, s, "LUDDITE_STRIKE"):
		return _decide(f, s, "LUDDITE_STRIKE",
			"Displacement at %.0f%% and no relief; striking the substations." % labor)
	var grudge := _grudge(s)
	if grudge["faction"] == SimConstants.CEO and float(grudge["value"]) > 30.0 and _can(f, s, "CONSUMER_BOYCOTT"):
		return _decide(f, s, "CONSUMER_BOYCOTT",
			"Frontier Lab provocations (grievance %.0f); calling a boycott." % float(grudge["value"]),
			{"retaliation_against": SimConstants.CEO})
	if autonomy > 70.0 and tooling >= 15.0 and _can(f, s, "DATA_POISONING_CAMPAIGN"):
		return _decide(f, s, "DATA_POISONING_CAMPAIGN", "Autonomy at %.0f; poisoning the scrapers." % autonomy)
	if resilience < 40.0 and _can(f, s, "ESTABLISH_MESH_NETWORKS"):
		return _decide(f, s, "ESTABLISH_MESH_NETWORKS", "Resilience at %.0f; building mesh networks." % resilience)
	if trust < 40.0 and _can(f, s, "ORGANIZE_COMMUNITY_ASSEMBLIES"):
		return _decide(f, s, "ORGANIZE_COMMUNITY_ASSEMBLIES", "Trust at %.0f; convening assemblies." % trust)
	if labor > 55.0 and _can(f, s, "CONSUMER_BOYCOTT"):
		return _decide(f, s, "CONSUMER_BOYCOTT", "Displacement at %.0f%%; withdrawing consumer consent." % labor)
	if tooling < 25.0 and _can(f, s, "OPEN_SOURCE_DEFENSE_TOOLING"):
		return _decide(f, s, "OPEN_SOURCE_DEFENSE_TOOLING", "Counter-surveillance tooling depleted (%.0f)." % tooling)
	if trust < 60.0 and _can(f, s, "ORGANIZE_COMMUNITY_ASSEMBLIES"):
		return _decide(f, s, "ORGANIZE_COMMUNITY_ASSEMBLIES", "Strengthening civic trust (%.0f)." % trust)
	if _can(f, s, "ESTABLISH_MESH_NETWORKS"):
		return _decide(f, s, "ESTABLISH_MESH_NETWORKS", "Extending parallel infrastructure.")
	return _decide(f, s, CONSERVE, "Rebuilding the commons this season.")


# --- Helpers ------------------------------------------------------------------

static func _v(s: Dictionary, key: String, fallback: float = 0.0) -> float:
	var value: Variant = s.get(key, fallback)
	if value is float or value is int:
		return float(value)
	return fallback


## True when the directive exists and is available. If the observation lists
## "available_actions" (engine observations always do) that list is
## authoritative; otherwise affordability is checked against whichever
## currencies the state includes, so minimal hand-written states still work.
static func _can(faction: String, s: Dictionary, action_id: String) -> bool:
	var catalog := FactionRegistry.catalog_for(faction)
	if not catalog.has(action_id):
		return false
	if s.has("available_actions"):
		return (s["available_actions"] as Array).has(action_id)
	var cooldowns: Dictionary = s.get("cooldowns", {})
	if int(cooldowns.get(action_id, 0)) > 0:
		return false
	var cost: Dictionary = catalog[action_id].get("cost", {})
	for key in cost:
		if s.has(key) and _v(s, key) + 0.0001 < float(cost[key]):
			return false
	return true


## Returns {"intensity": 1.5} when the situation is urgent and the faction can
## afford a 1.5x commitment; otherwise {} (base intensity).
static func _urgent(s: Dictionary, faction: String, action_id: String, is_urgent: bool) -> Dictionary:
	if not is_urgent:
		return {}
	var cost: Dictionary = FactionRegistry.catalog_for(faction).get(action_id, {}).get("cost", {})
	if cost.is_empty():
		return {}
	for key in cost:
		if _v(s, key) < float(cost[key]) * 1.5:
			return {}
	return {"intensity": 1.5}


static func _grudge(s: Dictionary) -> Dictionary:
	var best := {"faction": "", "value": 0.0}
	var grievances: Dictionary = s.get("grievances", {})
	for other in grievances:
		if float(grievances[other]) > float(best["value"]):
			best = {"faction": String(other), "value": float(grievances[other])}
	return best


static func _decide(faction: String, s: Dictionary, action_id: String, rationale: String, extra: Dictionary = {}) -> Dictionary:
	var definition: Dictionary = FactionRegistry.catalog_for(faction).get(action_id, {})
	var intensity := float(extra.get("intensity", 1.0))
	var cost := {}
	var base_cost: Dictionary = definition.get("cost", {})
	for key in base_cost:
		cost[key] = float(base_cost[key]) * intensity
	var decision := {
		"faction": faction,
		"turn": int(s.get("turn", 0)),
		"action": action_id,
		"cost": cost,
		"intensity": intensity,
		"rationale": rationale,
		"public_statement": String(definition.get("statement", "")),
		"source": "HEURISTIC",
	}
	if extra.has("retaliation_against"):
		decision["retaliation_against"] = extra["retaliation_against"]
	return decision
