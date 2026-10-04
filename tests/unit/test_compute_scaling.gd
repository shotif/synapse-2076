extends "res://tests/framework/test_case.gd"
## ComputeScaling: grid physics, saturation mapping, throttles and walls.


func test_saturation_mapping() -> void:
	assert_almost_eq(ComputeScaling.saturation_from_ratio(0.0), 0.0, 0.001)
	assert_almost_eq(ComputeScaling.saturation_from_ratio(1.0), 50.0, 0.001, "balanced grid")
	assert_almost_eq(ComputeScaling.saturation_from_ratio(3.0), 75.0, 0.001, "rationing begins")
	assert_almost_eq(ComputeScaling.saturation_from_ratio(19.0), 95.0, 0.001, "diaspora threshold")
	assert_eq(ComputeScaling.saturation_from_ratio(INF), 100.0)
	assert_eq(ComputeScaling.saturation_from_ratio(-4.0), 0.0)


func test_saturation_is_monotonic() -> void:
	var previous := -1.0
	for i in 200:
		var value := ComputeScaling.saturation_from_ratio(float(i) * 0.25)
		assert_true(value >= previous, "monotonic at ratio %.2f" % (float(i) * 0.25))
		previous = value


func test_throttle_bounds() -> void:
	assert_eq(ComputeScaling.throttle_from_ratio(0.5), 1.0)
	assert_eq(ComputeScaling.throttle_from_ratio(ComputeScaling.THROTTLE_RATIO_KNEE), 1.0)
	assert_lt(ComputeScaling.throttle_from_ratio(4.0), 1.0)
	assert_eq(ComputeScaling.throttle_from_ratio(1000.0), ComputeScaling.MIN_THROTTLE)
	assert_eq(ComputeScaling.throttle_from_ratio(NAN), ComputeScaling.MIN_THROTTLE)


func test_baseline_2026_grid_is_balanced() -> void:
	var compute := ComputeScaling.new()
	compute.update(0, 1, 26.0, 18.0, false, false)
	assert_between(compute.saturation_target, 35.0, 55.0)
	assert_eq(compute.throttle, 1.0)


func test_superconductors_cut_grid_drag_by_forty_percent() -> void:
	var plain := ComputeScaling.new()
	var superconducting := ComputeScaling.new()
	plain.update(30, 2, 31.0, 50.0, false, false)
	superconducting.update(30, 2, 31.0, 50.0, false, true)
	assert_almost_eq(superconducting.power_demand_gw / plain.power_demand_gw, 0.6, 0.0001)


func test_optical_raises_ceiling_and_efficiency() -> void:
	assert_almost_eq(ComputeScaling.thermal_ceiling(1, true) - ComputeScaling.thermal_ceiling(1, false),
		ComputeScaling.OPTICAL_CEILING_BONUS, 0.0001)
	var silicon := ComputeScaling.new()
	var optical := ComputeScaling.new()
	silicon.update(20, 2, 30.0, 40.0, false, false)
	optical.update(20, 2, 30.0, 40.0, true, false)
	assert_lt(optical.power_demand_gw, silicon.power_demand_gw)


func test_eras_raise_thermal_ceilings() -> void:
	assert_lt(ComputeScaling.thermal_ceiling(1, false), ComputeScaling.thermal_ceiling(2, false))
	assert_lt(ComputeScaling.thermal_ceiling(2, false), ComputeScaling.thermal_ceiling(3, false))


func test_grid_growth_and_damage() -> void:
	var compute := ComputeScaling.new()
	var start := compute.grid_capacity_gw
	compute.grow_grid(2)
	assert_almost_eq(compute.grid_capacity_gw, start * (1.0 + float(ComputeScaling.ERA_GRID_GROWTH[2])), 0.0001)
	var before := compute.grid_capacity_gw
	compute.damage_grid(0.1)
	assert_almost_eq(compute.grid_capacity_gw, before * 0.9, 0.0001)
	compute.damage_grid(50.0)
	assert_gte(compute.grid_capacity_gw, ComputeScaling.MIN_GRID_GW)
	compute.add_grid_capacity(NAN)
	assert_finite(compute.grid_capacity_gw)


func test_demand_outrunning_grid_throttles_growth() -> void:
	var compute := ComputeScaling.new()
	compute.update(10, 1, 29.5, 60.0, false, false)
	assert_gt(compute.saturation_ratio, ComputeScaling.THROTTLE_RATIO_KNEE)
	assert_lt(compute.get_growth_throttle(), 1.0)
	assert_gt(compute.saturation_target, 60.0)
