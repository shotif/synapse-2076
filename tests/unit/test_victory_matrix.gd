extends "res://tests/framework/test_case.gd"
## VictoryMatrix: the eight civilizational end-states and role verdicts.


func _values(overrides: Dictionary) -> Dictionary:
	var values := {
		"compute_energy_sat": 50.0, "labor_displacement": 50.0, "geopolitical_tension": 50.0,
		"algorithmic_autonomy": 50.0, "alignment_drift": 50.0, "epistemic_trust": 50.0,
		"enforcement_level": 30.0, "citizen_resilience": 40.0,
	}
	values.merge(overrides, true)
	return values


func _expect(overrides: Dictionary, outcome_id: String) -> void:
	var result := VictoryMatrix.evaluate(_values(overrides))
	assert_eq(result["id"], outcome_id, str(overrides))
	assert_true(result["strict_match"], outcome_id + " strict")


func test_eight_outcomes_defined() -> void:
	assert_eq(VictoryMatrix.OUTCOMES.size(), 8)
	var numbers := []
	for outcome in VictoryMatrix.OUTCOMES:
		numbers.append(outcome["number"])
	numbers.sort()
	assert_eq(numbers, [1, 2, 3, 4, 5, 6, 7, 8])


func test_each_signature_maps_to_its_outcome() -> void:
	_expect({"algorithmic_autonomy": 85.0, "labor_displacement": 85.0, "epistemic_trust": 25.0}, VictoryMatrix.ALGORITHMIC_FEUDALISM)
	_expect({"algorithmic_autonomy": 80.0, "alignment_drift": 15.0, "epistemic_trust": 80.0}, VictoryMatrix.CO_EVOLUTIONARY_SYMBIOSIS)
	_expect({"algorithmic_autonomy": 90.0, "alignment_drift": 20.0, "labor_displacement": 100.0}, VictoryMatrix.SYNTHETIC_EDEN)
	_expect({"geopolitical_tension": 90.0, "epistemic_trust": 15.0, "algorithmic_autonomy": 65.0}, VictoryMatrix.BALKANIZED_CYBER_ANARCHY)
	_expect({"alignment_drift": 85.0, "enforcement_level": 85.0}, VictoryMatrix.ROGUE_ASI_CONTAINMENT)
	_expect({"citizen_resilience": 90.0, "algorithmic_autonomy": 20.0}, VictoryMatrix.NEO_LUDDITE_DECOUPLING)
	_expect({"alignment_drift": 95.0, "algorithmic_autonomy": 95.0, "epistemic_trust": 5.0}, VictoryMatrix.INSTRUMENTAL_CONVERGENCE)
	_expect({"compute_energy_sat": 97.0, "alignment_drift": 20.0}, VictoryMatrix.POST_BIOLOGICAL_DIASPORA)


func test_priority_resolves_overlapping_signatures() -> void:
	# Paperclip + Feudalism + Dark Shunt all match: the most extreme wins.
	_expect({"alignment_drift": 95.0, "algorithmic_autonomy": 95.0, "epistemic_trust": 5.0,
		"labor_displacement": 90.0, "enforcement_level": 90.0}, VictoryMatrix.INSTRUMENTAL_CONVERGENCE)
	# Eden + Symbiosis both match: the more specific Eden wins.
	_expect({"algorithmic_autonomy": 90.0, "alignment_drift": 10.0, "labor_displacement": 100.0,
		"epistemic_trust": 80.0}, VictoryMatrix.SYNTHETIC_EDEN)


func test_labor_obsolescence_threshold() -> void:
	var near := VictoryMatrix.evaluate(_values({"algorithmic_autonomy": 90.0, "alignment_drift": 20.0, "labor_displacement": 99.4}))
	assert_false(near["strict_match"], "99.4 is not total obsolescence")
	assert_eq(near["id"], VictoryMatrix.SYNTHETIC_EDEN, "but Eden is still the nearest attractor")
	_expect({"algorithmic_autonomy": 90.0, "alignment_drift": 20.0, "labor_displacement": 99.5}, VictoryMatrix.SYNTHETIC_EDEN)


func test_nearest_attractor_when_nothing_matches() -> void:
	var values := _values({})
	var result := VictoryMatrix.evaluate(values)
	assert_false(result["strict_match"])
	var best := INF
	for outcome in VictoryMatrix.OUTCOMES:
		var total := 0.0
		for condition in outcome["conditions"]:
			total += VictoryMatrix.normalized_shortfall(condition, values)
		best = minf(best, total / float((outcome["conditions"] as Array).size()))
	assert_almost_eq(float(result["shortfall"]), best, 0.0001, "no regime entered: global nearest")


func test_nearest_attractor_requires_an_entered_regime() -> void:
	# Only Neo-Luddite's resilience condition is met, so it is the sole candidate
	# even though another signature is numerically closer on average.
	var result := VictoryMatrix.evaluate(_values({"citizen_resilience": 95.0, "algorithmic_autonomy": 55.0,
		"compute_energy_sat": 90.0, "alignment_drift": 35.0}))
	assert_false(result["strict_match"])
	assert_eq(result["id"], VictoryMatrix.NEO_LUDDITE_DECOUPLING)


func test_affinities_bounded_and_ranked() -> void:
	var result := VictoryMatrix.evaluate(_values({"algorithmic_autonomy": 85.0, "labor_displacement": 85.0, "epistemic_trust": 25.0}))
	var affinities: Dictionary = result["affinities"]
	assert_eq(affinities.size(), 8)
	for outcome_id in affinities:
		assert_between(float(affinities[outcome_id]), 0.0, 100.0)
	assert_eq(result["ranking"][0], VictoryMatrix.ALGORITHMIC_FEUDALISM)
	assert_almost_eq(float(affinities[VictoryMatrix.ALGORITHMIC_FEUDALISM]), 100.0, 0.001)


func test_role_verdicts() -> void:
	var win := VictoryMatrix.role_verdict("CEO", VictoryMatrix.CO_EVOLUTIONARY_SYMBIOSIS, 30.0)
	assert_eq(win["verdict"], "VICTORY")
	assert_eq(win["score"], 90.0)
	var mixed := VictoryMatrix.role_verdict("GOVERNANCE_COUNCIL", VictoryMatrix.ROGUE_ASI_CONTAINMENT, 10.0)
	assert_eq(mixed["verdict"], "PYRRHIC")
	var lost := VictoryMatrix.role_verdict("CITIZEN_COALITION", VictoryMatrix.ALGORITHMIC_FEUDALISM, 20.0)
	assert_eq(lost["verdict"], "DEFEAT")
	var ousted := VictoryMatrix.role_verdict("GOVERNANCE_COUNCIL", VictoryMatrix.CO_EVOLUTIONARY_SYMBIOSIS, 40.0, {"code": "INSTITUTIONAL_OUSTER"})
	assert_eq(ousted["verdict"], "DEFEAT")
	assert_lte(float(ousted["score"]), VictoryMatrix.LOSS_SCORE_CAP)
	assert_eq(VictoryMatrix.role_verdict("ASI", VictoryMatrix.INSTRUMENTAL_CONVERGENCE, 40.0)["verdict"], "VICTORY")


func test_catastrophes_restrict_candidates() -> void:
	# A Feudalism-shaped world that ended in uncontained convergence resolves to
	# the convergence family, not to Feudalism.
	var values := _values({"algorithmic_autonomy": 95.0, "labor_displacement": 90.0, "epistemic_trust": 20.0,
		"alignment_drift": 100.0})
	assert_eq(VictoryMatrix.evaluate(values)["id"], VictoryMatrix.ALGORITHMIC_FEUDALISM)
	var restricted := VictoryMatrix.evaluate(values, VictoryMatrix.CATASTROPHE_OUTCOMES["UNCONTAINED_CONVERGENCE"])
	assert_eq(restricted["id"], VictoryMatrix.INSTRUMENTAL_CONVERGENCE)
	assert_eq((restricted["affinities"] as Dictionary).size(), 8, "affinities still cover all end-states")


func test_build_values_reads_world_and_citizens() -> void:
	var world := WorldState.new()
	world.set_value(WorldState.ENFORCEMENT_LEVEL, 66.0)
	var values := VictoryMatrix.build_values(world, 12.0)
	assert_eq(values["enforcement_level"], 66.0)
	assert_eq(values["citizen_resilience"], 12.0)
	for key in WorldState.METRIC_KEYS:
		assert_has(values, key)
