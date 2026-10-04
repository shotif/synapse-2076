extends "res://tests/framework/test_case.gd"
## TechTreeManager: scaling laws, thermal walls, eras, paradigm shifts,
## stochastic emergence and the alignment tax.


func test_starts_at_ten_to_the_26() -> void:
	var tech := TechTreeManager.new()
	assert_eq(tech.log_flops, 26.0)
	assert_almost_eq(tech.get_capability_index(), 14.29, 0.05)
	assert_eq(tech.era, 1)
	assert_false(tech.is_agi_crossed())


func test_growth_never_exceeds_the_thermal_ceiling() -> void:
	var tech := TechTreeManager.new()
	var compute := ComputeScaling.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for turn in range(1, 101):
		tech.add_investment(30.0, 0.0)
		tech.add_growth_modifier(2.0, 1)
		tech.advance(turn, SimConstants.year_for_turn(turn), compute, rng)
		var ceiling := ComputeScaling.thermal_ceiling(tech.era, tech.has_shift(TechTreeManager.OPTICAL_COMPUTING))
		assert_true(tech.log_flops <= ceiling + 0.0001, "turn %d: %.3f <= %.3f" % [turn, tech.log_flops, ceiling])
		assert_finite(tech.log_flops)


func test_scaling_wall_plateaus_growth() -> void:
	var tech := TechTreeManager.new()
	var compute := ComputeScaling.new()
	tech.log_flops = 29.58
	var report := tech.advance(5, 2028.5, compute, null)
	assert_lt(float(report["growth"]), 0.03, "growth flattens against the era-1 wall")
	assert_lt(float(report["wall_factor"]), 0.1)


func test_era_transitions_follow_the_calendar() -> void:
	var tech := TechTreeManager.new()
	var report := tech.advance(19, 2035.5, null, null)
	assert_eq(tech.era, 1)
	assert_false(report["era_changed"])
	report = tech.advance(20, 2036.0, null, null)
	assert_eq(tech.era, 2)
	assert_true(report["era_changed"])
	tech.advance(48, 2050.0, null, null)
	assert_eq(tech.era, 3)


func test_emergence_rolls_once_per_ten_x_threshold() -> void:
	var tech := TechTreeManager.new()
	tech.log_flops = 26.95
	tech.emergence_probability_override = 1.0
	var generation := tech.model_generation
	var report := tech.advance(1, 2026.5, null, null)
	assert_gt(tech.log_flops, 27.0)
	assert_eq((report["emergences"] as Array).size(), 1)
	assert_eq(tech.model_generation, generation + 1)
	var emergence: Dictionary = report["emergences"][0]
	assert_gt(float(emergence["drift_spike"]), 0.0)
	assert_string_contains(String(emergence["headline"]), "Frontier Model-")
	report = tech.advance(2, 2027.0, null, null)
	assert_eq((report["emergences"] as Array).size(), 0, "no new threshold crossed")


func test_no_emergence_when_probability_is_zero() -> void:
	var tech := TechTreeManager.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	tech.emergence_probability_override = 0.0
	for turn in range(1, 60):
		tech.add_investment(20.0, 0.0)
		var report := tech.advance(turn, SimConstants.year_for_turn(turn), null, rng)
		assert_eq((report["emergences"] as Array).size(), 0)


func test_capabilities_emerge_at_most_once() -> void:
	var tech := TechTreeManager.new()
	tech.emergence_probability_override = 1.0
	for turn in range(1, 101):
		tech.add_investment(40.0, 0.0)
		tech.add_growth_modifier(3.0, 1)
		tech.advance(turn, SimConstants.year_for_turn(turn), null, null)
	var seen := {}
	for capability in tech.emerged_capabilities:
		assert_false(seen.has(capability), "%s emerged twice" % capability)
		seen[capability] = true
	assert_gt(tech.emerged_capabilities.size(), 3)


func test_alignment_tax_is_clamped_and_compounds() -> void:
	var tech := TechTreeManager.new()
	var world := WorldState.new()
	world.set_value(WorldState.ALIGNMENT_DRIFT, 40.0)
	var applied := tech.apply_alignment_tax(0.5, world)
	assert_almost_eq(tech.alignment_tax_multiplier, 1.15, 0.0001, "clamped to the 15% ceiling")
	assert_almost_eq(applied, 6.0, 0.0001, "drift rises by 15% of 40")
	tech.apply_alignment_tax(0.001, world)
	assert_almost_eq(tech.alignment_tax_multiplier, 1.15 * 1.025, 0.0001, "clamped to the 2.5% floor and compounded")
	assert_eq(tech.alignment_tax_events, 2)
	assert_eq(tech.apply_alignment_tax(-1.0, world), 0.0, "non-positive coefficients are ignored")


func test_alignment_tax_debt_decays_with_safety_work() -> void:
	var tech := TechTreeManager.new()
	tech.alignment_tax_multiplier = 2.0
	tech.add_investment(0.0, 30.0)
	tech.advance(1, 2026.5, null, null)
	assert_lt(tech.alignment_tax_multiplier, 2.0)
	assert_gte(tech.alignment_tax_multiplier, 1.0)


func test_interpretability_halves_drift_accrual() -> void:
	var tech := TechTreeManager.new()
	assert_eq(tech.get_drift_accrual_multiplier(), 1.0)
	tech.unlock_shift(TechTreeManager.MECHANISTIC_INTERPRETABILITY, 10)
	assert_eq(tech.get_drift_accrual_multiplier(), 0.5)
	assert_gt(tech.get_discovery_pressure(), 0.0)


func test_recursive_synthetics_triples_training_speed() -> void:
	var baseline := TechTreeManager.new()
	var recursive := TechTreeManager.new()
	recursive.unlock_shift(TechTreeManager.RECURSIVE_SYNTHETICS, 1)
	baseline.log_flops = 30.0
	recursive.log_flops = 30.0
	var slow := baseline.advance(40, 2046.0, null, null)
	var fast := recursive.advance(40, 2046.0, null, null)
	assert_almost_eq(float(fast["growth"]) / float(slow["growth"]), 3.0, 0.01)
	assert_gt(recursive.get_emergence_probability(), baseline.get_emergence_probability(), "emergence volatility rises")


func test_paradigm_breakthrough_requires_year_and_progress() -> void:
	var tech := TechTreeManager.new()
	tech.paradigm_progress[TechTreeManager.OPTICAL_COMPUTING] = 500.0
	tech.advance(8, 2030.0, null, null)
	assert_false(tech.has_shift(TechTreeManager.OPTICAL_COMPUTING), "too early (min year 2033)")
	var report := tech.advance(16, 2034.0, null, null)
	assert_true(tech.has_shift(TechTreeManager.OPTICAL_COMPUTING))
	var ids := []
	for shift in report["shifts"]:
		ids.append(shift["id"])
	assert_has(ids, TechTreeManager.OPTICAL_COMPUTING)


func test_safety_investment_funds_interpretability() -> void:
	var tech := TechTreeManager.new()
	tech.add_investment(0.0, 100.0)
	tech.advance(10, 2031.0, null, null)
	assert_gt(float(tech.paradigm_progress[TechTreeManager.MECHANISTIC_INTERPRETABILITY]), 60.0)
	# Capability-track shifts only receive baseline R&D, at pre-research efficiency.
	assert_lt(float(tech.paradigm_progress[TechTreeManager.OPTICAL_COMPUTING]), 1.0, "capability track funded separately")


func test_agi_milestone_is_recorded_once() -> void:
	var tech := TechTreeManager.new()
	tech.log_flops = 31.0
	var report := tech.advance(30, 2041.0, null, null)
	assert_true(report["agi_crossed"])
	assert_eq(tech.agi_turn, 30)
	report = tech.advance(31, 2041.5, null, null)
	assert_false(report["agi_crossed"])
	assert_eq(tech.agi_turn, 30)


func test_growth_modifiers_expire() -> void:
	var tech := TechTreeManager.new()
	tech.add_growth_modifier(0.5, 2, "caps")
	assert_almost_eq(tech.get_growth_modifier_product(), 0.5, 0.0001)
	tech.advance(1, 2026.5, null, null)
	assert_almost_eq(tech.get_growth_modifier_product(), 0.5, 0.0001)
	tech.advance(2, 2027.0, null, null)
	assert_almost_eq(tech.get_growth_modifier_product(), 1.0, 0.0001)
	tech.add_growth_modifier(NAN, 3)
	tech.add_growth_modifier(2.0, 0)
	assert_eq(tech.growth_modifiers.size(), 0, "invalid modifiers rejected")
