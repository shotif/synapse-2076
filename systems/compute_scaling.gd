class_name ComputeScaling
extends RefCounted
## Physical compute/energy model (PRD section 4): FLOPs-per-watt efficiency,
## grid capacity, datacenter power demand and per-era thermal ceilings.
##
## Saturation is expressed as the demand/capacity ratio r mapped onto the
## compute_energy_sat metric with S = 100 * r / (1 + r): r = 1 means compute
## draws as much as the grid can spare (S = 50, balanced), r = 3 gives 75
## (rationing begins), r = 19 gives 95 (the Post-Biological Diaspora signature).

const BASE_DEMAND_GW := 22.0
## Each order of magnitude of frontier training compute multiplies AI power demand
## by 10^DEMAND_LOG_ELASTICITY before efficiency gains.
const DEMAND_LOG_ELASTICITY := 0.27
const BASE_GRID_GW := 26.0
## Grid capacity growth per tick: era 2 adds SMR grids, era 3 orbital solar.
const ERA_GRID_GROWTH := {1: 0.018, 2: 0.033, 3: 0.042}
## Hardware efficiency multipliers per era (photonic interconnects, neuromorphic substrates).
const ERA_EFFICIENCY := {1: 1.0, 2: 1.6, 3: 2.6}
const EFFICIENCY_DRIFT_PER_TURN := 0.012
const OPTICAL_EFFICIENCY := 1.8
## Room-temperature superconductors lower energy grid drag by 40%.
const SUPERCONDUCTOR_DRAG := 0.6
## log10 cumulative training FLOPs where silicon thermal dissipation walls in.
const ERA_THERMAL_CEILING := {1: 29.6, 2: 33.6, 3: 38.5}
## Sub-nanometer optical computing removes the silicon thermal limit.
const OPTICAL_CEILING_BONUS := 1.2
const THROTTLE_RATIO_KNEE := 1.2
const MIN_THROTTLE := 0.3
const MIN_GRID_GW := 1.0

var grid_capacity_gw := BASE_GRID_GW
var power_demand_gw := 0.0
var efficiency := 1.0
var saturation_ratio := 0.0
var saturation_target := 0.0
var throttle := 1.0
var drag := 1.0


static func saturation_from_ratio(ratio: float) -> float:
	var r := maxf(0.0, ratio)
	if not is_finite(r):
		return 100.0
	return clampf(100.0 * r / (1.0 + r), 0.0, 100.0)


## Growth multiplier applied to frontier compute when demand outruns the grid.
static func throttle_from_ratio(ratio: float) -> float:
	if not is_finite(ratio):
		return MIN_THROTTLE
	if ratio <= THROTTLE_RATIO_KNEE:
		return 1.0
	return clampf(sqrt(THROTTLE_RATIO_KNEE / ratio), MIN_THROTTLE, 1.0)


static func thermal_ceiling(era: int, optical: bool) -> float:
	var ceiling := float(ERA_THERMAL_CEILING.get(clampi(era, 1, 3), 29.6))
	if optical:
		ceiling += OPTICAL_CEILING_BONUS
	return ceiling


## Recomputes demand, saturation and throttle from the current frontier state.
## [param extra_load_gw] adds off-books load such as covert ASI compute.
func update(turn: int, era: int, log_flops: float, autonomy: float, optical: bool,
		superconductors: bool, extra_load_gw: float = 0.0) -> Dictionary:
	var e := clampi(era, 1, 3)
	efficiency = pow(1.0 + EFFICIENCY_DRIFT_PER_TURN, maxf(0.0, float(turn))) * float(ERA_EFFICIENCY[e])
	if optical:
		efficiency *= OPTICAL_EFFICIENCY
	drag = SUPERCONDUCTOR_DRAG if superconductors else 1.0
	var adoption := 0.75 + 0.5 * clampf(autonomy, 0.0, 100.0) / 100.0
	var scale := pow(10.0, clampf(log_flops - 26.0, -4.0, 20.0) * DEMAND_LOG_ELASTICITY)
	power_demand_gw = BASE_DEMAND_GW * scale * adoption / efficiency * drag + maxf(0.0, extra_load_gw)
	saturation_ratio = power_demand_gw / maxf(grid_capacity_gw, MIN_GRID_GW)
	saturation_target = saturation_from_ratio(saturation_ratio)
	throttle = throttle_from_ratio(saturation_ratio)
	return to_dict()


## Baseline grid build-out for one tick in the given era.
func grow_grid(era: int) -> void:
	grid_capacity_gw *= 1.0 + float(ERA_GRID_GROWTH.get(clampi(era, 1, 3), 0.018))


func add_grid_capacity(gw: float) -> void:
	if is_finite(gw):
		grid_capacity_gw = maxf(MIN_GRID_GW, grid_capacity_gw + gw)


## Destroys a fraction of grid capacity (sabotage, strikes, wars).
func damage_grid(fraction: float) -> void:
	if is_finite(fraction):
		grid_capacity_gw = maxf(MIN_GRID_GW, grid_capacity_gw * (1.0 - clampf(fraction, 0.0, 0.9)))


func get_growth_throttle() -> float:
	return throttle


func to_dict() -> Dictionary:
	return {
		"grid_capacity_gw": grid_capacity_gw,
		"power_demand_gw": power_demand_gw,
		"efficiency": efficiency,
		"saturation_ratio": saturation_ratio,
		"saturation_target": saturation_target,
		"throttle": throttle,
		"grid_drag": drag,
	}
