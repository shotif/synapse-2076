extends "res://tests/framework/test_case.gd"
## WorldState: the six normalized macro metrics, secondary indices and the
## coupled difference equations.


func _all_keys() -> Array:
	return WorldState.METRIC_KEYS + WorldState.INDEX_KEYS


func test_baseline_values_are_in_range() -> void:
	var world := WorldState.new()
	for key in _all_keys():
		assert_between(world.get_value(key), 0.0, 100.0, key)
	assert_eq(world.validate().size(), 0, "baseline validates")
	assert_eq(WorldState.METRIC_KEYS.size(), 6, "six macro metrics")


func test_apply_delta_clamps_to_bounds_and_reports_applied_delta() -> void:
	var world := WorldState.new()
	world.set_value(WorldState.GEOPOLITICAL_TENSION, 95.0)
	var applied := world.apply_delta(WorldState.GEOPOLITICAL_TENSION, 500.0)
	assert_eq(world.geopolitical_tension, 100.0)
	assert_almost_eq(applied, 5.0, 0.0001)
	world.apply_delta(WorldState.GEOPOLITICAL_TENSION, -1000.0)
	assert_eq(world.geopolitical_tension, 0.0)


func test_non_finite_deltas_are_ignored() -> void:
	var world := WorldState.new()
	var before := world.epistemic_trust
	assert_eq(world.apply_delta(WorldState.EPISTEMIC_TRUST, NAN), 0.0)
	assert_eq(world.apply_delta(WorldState.EPISTEMIC_TRUST, INF), 0.0)
	assert_eq(world.epistemic_trust, before)


func test_sanitize_maps_nan_and_inf() -> void:
	assert_eq(WorldState.sanitize(NAN), 0.0)
	assert_eq(WorldState.sanitize(INF), 100.0)
	assert_eq(WorldState.sanitize(-INF), 0.0)
	assert_eq(WorldState.sanitize(42.5), 42.5)
	assert_eq(WorldState.sanitize(-3.0), 0.0)


func test_drift_accrual_multiplier_halves_only_positive_drift() -> void:
	var world := WorldState.new()
	world.set_value(WorldState.ALIGNMENT_DRIFT, 40.0)
	world.drift_accrual_multiplier = 0.5
	assert_almost_eq(world.apply_delta(WorldState.ALIGNMENT_DRIFT, 10.0), 5.0, 0.0001, "accrual halved")
	assert_almost_eq(world.apply_delta(WorldState.ALIGNMENT_DRIFT, -4.0), -4.0, 0.0001, "reductions untouched")
	assert_almost_eq(world.apply_delta(WorldState.LABOR_DISPLACEMENT, 10.0), 10.0, 0.0001, "other metrics untouched")


func test_band_thresholds() -> void:
	assert_eq(WorldState.band_for(WorldState.ALIGNMENT_DRIFT, 49.0), 0)
	assert_eq(WorldState.band_for(WorldState.ALIGNMENT_DRIFT, 50.0), 1)
	assert_eq(WorldState.band_for(WorldState.ALIGNMENT_DRIFT, 75.0), 2)
	assert_eq(WorldState.band_for(WorldState.EPISTEMIC_TRUST, 36.0), 0)
	assert_eq(WorldState.band_for(WorldState.EPISTEMIC_TRUST, 35.0), 1)
	assert_eq(WorldState.band_for(WorldState.EPISTEMIC_TRUST, 20.0), 2)
	assert_eq(WorldState.band_for(WorldState.COMPUTE_ENERGY_SAT, 50.0), 0)
	assert_eq(WorldState.band_for(WorldState.COMPUTE_ENERGY_SAT, 76.0), 1)
	assert_eq(WorldState.band_for(WorldState.COMPUTE_ENERGY_SAT, 91.0), 2)
	assert_eq(WorldState.band_for(WorldState.COMPUTE_ENERGY_SAT, 10.0), 1, "deficit warning")
	assert_eq(WorldState.band_for(WorldState.COMPUTE_ENERGY_SAT, 5.0), 2, "grid collapse")


func test_regime_descriptors_follow_prd_table() -> void:
	assert_string_contains(WorldState.regime_for(WorldState.GEOPOLITICAL_TENSION, 10.0), "treaties")
	assert_string_contains(WorldState.regime_for(WorldState.GEOPOLITICAL_TENSION, 50.0), "trade wars")
	assert_string_contains(WorldState.regime_for(WorldState.GEOPOLITICAL_TENSION, 90.0), "kinetic")
	assert_string_contains(WorldState.regime_for(WorldState.EPISTEMIC_TRUST, 90.0), "verifiable truth")


func test_coupling_stays_bounded_under_extreme_drivers() -> void:
	var world := WorldState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		if i % 50 == 0:
			for key in _all_keys():
				world.set_value(key, [0.0, 100.0, rng.randf_range(0.0, 100.0)][rng.randi_range(0, 2)])
		world.drift_accrual_multiplier = [0.5, 1.0][i % 2]
		world.resolve_coupling({
			"capability_index": rng.randf_range(-50.0, 150.0),
			"capability_delta": rng.randf_range(0.0, 40.0),
			"saturation_target": rng.randf_range(-20.0, 140.0),
			"tax_multiplier": rng.randf_range(0.0, 10.0),
			"discovery_pressure": rng.randf_range(0.0, 20.0),
		}, rng)
	assert_eq(world.validate().size(), 0, "no NaN / out-of-range after 2000 extreme ticks: %s" % str(world.validate()))


func test_coupling_without_noise_is_deterministic() -> void:
	var a := WorldState.new()
	var b := WorldState.new()
	var drivers := {"capability_index": 55.0, "capability_delta": 1.2, "saturation_target": 70.0, "tax_multiplier": 1.3}
	for _i in 25:
		a.resolve_coupling(drivers)
		b.resolve_coupling(drivers)
	assert_eq(a.to_dict(), b.to_dict())


func test_capability_growth_pushes_labor_autonomy_and_drift_up() -> void:
	var world := WorldState.new()
	var start := world.to_dict()
	for _i in 30:
		world.resolve_coupling({"capability_index": 80.0, "capability_delta": 1.5, "saturation_target": 60.0})
	assert_gt(world.labor_displacement, float(start["labor_displacement"]) + 20.0, "labor displacement rises")
	assert_gt(world.algorithmic_autonomy, float(start["algorithmic_autonomy"]) + 20.0, "autonomy rises")
	assert_gt(world.alignment_drift, float(start["alignment_drift"]) + 10.0, "drift accrues")
	assert_lt(world.epistemic_trust, float(start["epistemic_trust"]), "trust erodes")


func test_provenance_and_safety_net_support_trust() -> void:
	var shielded := WorldState.new()
	var exposed := WorldState.new()
	var drivers := {"capability_index": 70.0, "capability_delta": 0.5, "saturation_target": 60.0}
	for _i in 40:
		shielded.set_value(WorldState.PROVENANCE_COVERAGE, 90.0)
		shielded.set_value(WorldState.SAFETY_NET_COVERAGE, 90.0)
		shielded.resolve_coupling(drivers)
		exposed.resolve_coupling(drivers)
	assert_gt(shielded.epistemic_trust, exposed.epistemic_trust + 10.0)


func test_enforcement_restrains_autonomy() -> void:
	var strict := WorldState.new()
	var lax := WorldState.new()
	var drivers := {"capability_index": 75.0, "capability_delta": 0.5, "saturation_target": 60.0}
	for _i in 40:
		strict.set_value(WorldState.ENFORCEMENT_LEVEL, 95.0)
		lax.set_value(WorldState.ENFORCEMENT_LEVEL, 5.0)
		strict.resolve_coupling(drivers)
		lax.resolve_coupling(drivers)
	assert_lt(strict.algorithmic_autonomy, lax.algorithmic_autonomy - 10.0)


func test_compute_saturation_relaxes_toward_grid_target() -> void:
	var world := WorldState.new()
	for _i in 20:
		world.resolve_coupling({"capability_index": 14.0, "saturation_target": 90.0})
	assert_almost_eq(world.compute_energy_sat, 90.0, 1.0)


func test_history_records_flat_entries() -> void:
	var world := WorldState.new()
	world.record_history(3, 2027.5, {"log_flops": 26.5})
	assert_eq(world.history.size(), 1)
	var entry: Dictionary = world.history[0]
	assert_eq(entry["turn"], 3)
	assert_eq(entry["log_flops"], 26.5)
	for key in _all_keys():
		assert_has(entry, key)


func test_round_trip_serialization() -> void:
	var world := WorldState.new()
	world.set_value(WorldState.ALIGNMENT_DRIFT, 77.7)
	world.set_value(WorldState.DISCOVERY_INDEX, 12.5)
	world.drift_accrual_multiplier = 0.5
	var copy := WorldState.new()
	copy.from_dict(world.to_dict())
	assert_eq(copy.to_dict(), world.to_dict())
