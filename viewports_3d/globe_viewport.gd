class_name GlobeViewport
extends Node3D
## Night-side globe that shows the state of the world at a glance ("the world
## is the interface"). Every macro metric (0-100) drives one layer:
##
##   compute_energy_sat    heat blooms and beams over the datacenter hubs grow
##                         and brighten; above 66 they flicker (brownouts)
##   labor_displacement    ~800 city lights around 48 metro areas switch off as
##                         work automates, shift-change pulse rings fade out,
##                         and above 45 crowds gather at the datacenters
##   geopolitical_tension  walls rise along three bloc fault lines and glow;
##                         a heartbeat above 55, launch arcs above 75
##   algorithmic_autonomy  an agent swarm rides the trade routes (8 + a^2 * 210
##                         particles); above 30 a growing share wanders off
##                         and the swarm turns from white-cyan to violet
##   alignment_drift       the graticule warps and tints toward the drift color
##   epistemic_trust       undersea cable pulses: even and steady while people
##                         trust what they read; below ~60 they jitter, drop
##                         out and the cables break into dashes
##
## Bind telemetry with [method update_from_snapshot] (missing metrics keep
## their last value). [method set_era] recolors from the era palette,
## [method set_layer_focus] isolates one layer and [method get_layer_state]
## reports the targets. Layers are MultiMeshes and static meshes animated in
## shaders (WebGL2-safe); a frame costs a few uniform updates while values
## ease, and nothing at rest.

const GLOBE_RADIUS := 1.0
## Layer order (one per macro metric, as in WorldState.METRIC_KEYS).
const LAYER_KEYS := ["compute_energy_sat", "labor_displacement", "geopolitical_tension",
	"algorithmic_autonomy", "alignment_drift", "epistemic_trust"]
## Values used until a snapshot provides them (the 2026 world).
const DEFAULT_METRICS := {
	"compute_energy_sat": 42.0, "labor_displacement": 14.0, "geopolitical_tension": 38.0,
	"algorithmic_autonomy": 18.0, "alignment_drift": 16.0, "epistemic_trust": 58.0,
}
## Opacity of the other layers while one layer is focused.
const DIMMED_ALPHA := 0.1
## Easing rates (per second) toward new telemetry and focus.
const EASE_RATE := 2.5
const FOCUS_RATE := 9.0
const SPIN_SPEED := 0.02
## Longitude that faces the camera when the globe appears.
const HOME_LONGITUDE := 30.0
## Swarm particles start white-cyan and turn to the autonomy color.
const SWARM_START := Color(0.745, 0.941, 1.0)
const SWARM_SIZE := 230
const CROWD_SIZE := 110
const CITY_SEED := 2076

const WireframeShader := preload("res://viewports_3d/shaders/wireframe_globe.gdshader")
const PointShader := preload("res://viewports_3d/shaders/hologram_point.gdshader")
const FlowShader := preload("res://viewports_3d/shaders/data_flow.gdshader")
const CoreShader := preload("res://viewports_3d/shaders/globe_core.gdshader")
const AtmosphereShader := preload("res://viewports_3d/shaders/globe_atmosphere.gdshader")
const SpriteShader := preload("res://viewports_3d/shaders/globe_sprite.gdshader")
const RingShader := preload("res://viewports_3d/shaders/globe_ring.gdshader")
const WallShader := preload("res://viewports_3d/shaders/globe_wall.gdshader")
const RibbonShader := preload("res://viewports_3d/shaders/globe_ribbon.gdshader")
const RouteShader := preload("res://viewports_3d/shaders/globe_route.gdshader")

## Major compute hubs: [name, latitude, longitude, bloc, weight].
const HUBS := [
	["N. Virginia", 39.0, -77.5, "WEST", 1.0], ["Oregon", 45.6, -121.2, "WEST", 0.7],
	["Texas", 32.8, -96.8, "WEST", 0.8], ["Iowa", 41.6, -93.6, "WEST", 0.5],
	["Phoenix", 33.4, -112.0, "WEST", 0.5], ["Montreal", 45.5, -73.6, "WEST", 0.4],
	["Dublin", 53.3, -6.3, "WEST", 0.6], ["Frankfurt", 50.1, 8.7, "WEST", 0.6],
	["Amsterdam", 52.4, 4.9, "WEST", 0.5], ["Nordic Arctic", 65.6, 22.1, "WEST", 0.4],
	["Reykjavik", 64.1, -21.9, "WEST", 0.3], ["Tel Aviv", 32.1, 34.8, "WEST", 0.3],
	["Abu Dhabi", 24.5, 54.4, "GULF", 0.6], ["Mumbai", 19.1, 72.9, "SOUTH", 0.5],
	["Singapore", 1.35, 103.8, "SOUTH", 0.7], ["Shenzhen", 22.5, 114.1, "EAST", 0.8],
	["Beijing", 39.9, 116.4, "EAST", 0.8], ["Shanghai", 31.2, 121.5, "EAST", 0.7],
	["Seoul", 37.6, 127.0, "WEST", 0.5], ["Tokyo", 35.7, 139.7, "WEST", 0.6],
	["Hsinchu", 24.8, 121.0, "WEST", 0.6], ["Sydney", -33.9, 151.2, "WEST", 0.4],
	["Sao Paulo", -23.5, -46.6, "SOUTH", 0.4], ["Johannesburg", -26.2, 28.0, "SOUTH", 0.3],
]
## Undersea cable routes between hub indices.
const CABLES := [[0, 6], [0, 8], [5, 6], [1, 19], [2, 22], [1, 18], [4, 21], [14, 13], [13, 12],
	[14, 15], [15, 20], [19, 18], [16, 17], [14, 21], [22, 23], [23, 13], [7, 12], [12, 15], [6, 10], [9, 7]]
## Metro areas lit at night: [name, latitude, longitude, size 0-1].
const METROS := [
	["Phoenix", 33.4, -112.1, 0.7], ["Oregon", 45.6, -121.2, 0.35], ["N. Virginia", 39.0, -77.5, 0.8],
	["Dublin", 53.3, -6.3, 0.55], ["Lulea", 65.6, 22.1, 0.3], ["Riyadh", 24.7, 46.7, 0.65],
	["Mumbai", 19.1, 72.9, 1.0], ["Shenzhen", 22.5, 114.1, 1.0], ["Hsinchu", 24.8, 121.0, 0.5],
	["Seoul", 37.6, 127.0, 0.9], ["Tokyo", 35.7, 139.7, 1.0], ["Singapore", 1.35, 103.8, 0.7],
	["Bangalore", 12.97, 77.6, 0.7], ["New York", 40.7, -74.0, 1.0], ["Los Angeles", 34.1, -118.2, 0.9],
	["Chicago", 41.9, -87.6, 0.7], ["Houston", 29.8, -95.4, 0.6], ["Mexico City", 19.4, -99.1, 0.9],
	["Toronto", 43.7, -79.4, 0.6], ["Sao Paulo", -23.5, -46.6, 0.9], ["Buenos Aires", -34.6, -58.4, 0.7],
	["Bogota", 4.7, -74.1, 0.6], ["Lima", -12.0, -77.0, 0.5], ["London", 51.5, -0.1, 0.9],
	["Paris", 48.9, 2.35, 0.8], ["Berlin", 52.5, 13.4, 0.6], ["Madrid", 40.4, -3.7, 0.6],
	["Rome", 41.9, 12.5, 0.5], ["Warsaw", 52.2, 21.0, 0.4], ["Moscow", 55.8, 37.6, 0.8],
	["Istanbul", 41.0, 29.0, 0.8], ["Cairo", 30.0, 31.2, 0.8], ["Lagos", 6.5, 3.4, 0.8],
	["Nairobi", -1.3, 36.8, 0.5], ["Johannesburg", -26.2, 28.0, 0.6], ["Kinshasa", -4.3, 15.3, 0.5],
	["Tehran", 35.7, 51.4, 0.6], ["Karachi", 24.9, 67.0, 0.7], ["Delhi", 28.6, 77.2, 1.0],
	["Dhaka", 23.8, 90.4, 0.7], ["Bangkok", 13.8, 100.5, 0.7], ["Jakarta", -6.2, 106.8, 0.8],
	["Manila", 14.6, 121.0, 0.7], ["Beijing", 39.9, 116.4, 0.9], ["Shanghai", 31.2, 121.5, 1.0],
	["Osaka", 34.7, 135.5, 0.6], ["Sydney", -33.9, 151.2, 0.6], ["Melbourne", -37.8, 145.0, 0.4],
]
## Trade routes the agent swarm rides (metro names).
const ROUTES := [["Shanghai", "Los Angeles"], ["Shenzhen", "Singapore"], ["Singapore", "Mumbai"],
	["Mumbai", "Riyadh"], ["Riyadh", "Istanbul"], ["Istanbul", "London"], ["London", "New York"],
	["New York", "Sao Paulo"], ["Lagos", "London"], ["Tokyo", "Los Angeles"], ["Seoul", "Shanghai"],
	["Jakarta", "Sydney"], ["Mexico City", "Houston"], ["Bangalore", "Singapore"], ["Cairo", "Mumbai"]]
## Bloc fault lines as [latitude, longitude] polylines: Eurasia, the western
## Pacific and the Gulf.
const WALLS := [
	[[71, 28], [64, 29], [58, 27], [53, 24], [49, 23], [46, 28], [44, 33], [42, 41], [39, 46], [36, 54],
		[31, 61], [29, 69], [32, 76], [29, 86], [27, 95], [22, 100], [15, 104], [9, 108]],
	[[47, 143], [42, 139], [36, 131], [30, 128], [25.5, 123], [22, 121.2], [17, 119.5], [11, 117.5], [5, 114]],
	[[33, 36], [30, 41], [27, 45], [24.5, 51], [23, 57], [20, 60]],
]
## Launch arcs between blocs: [lat, lon, lat, lon, lift, phase].
const ARCS := [[52.0, 88.0, 47.0, -98.0, 0.34, 0.0], [24.0, 119.0, 27.0, 128.0, 0.12, 0.33],
	[29.0, 49.0, 33.0, 37.0, 0.1, 0.66], [40.0, 128.0, 37.0, 117.0, 0.1, 0.5]]
## Seconds per launch (the arcs fly at 0.35 cycles per second).
const ARC_PERIOD := 1.0 / 0.35
## Values eased between snapshots (the rest switch at once).
const EASED := ["heat", "brownout", "dark", "pulse", "crowd_count", "wall_height", "wall_glow", "heartbeat",
	"swarm_count", "swarm_mix", "free_fraction", "warp", "drift_mix", "coherence"]

var _metrics := DEFAULT_METRICS.duplicate()
var _targets := {}
var _current := {}
var _era := 1
var _focus := ""
var _focus_alpha := {}
var _focus_target := {}
var _built := false
var _view_inset := 0.0
var _base_fov := 40.0
var _spin_root: Node3D
var _camera: Camera3D
var _environment: Environment

var _globe_material: ShaderMaterial
var _core_material: ShaderMaterial
var _atmosphere_material: ShaderMaterial
var _land_material: ShaderMaterial
var _bloom_material: ShaderMaterial
var _beam_material: ShaderMaterial
var _beam_multimesh: MultiMesh
var _light_material: ShaderMaterial
var _city_glow_material: ShaderMaterial
var _pulse_material: ShaderMaterial
var _crowd_material: ShaderMaterial
var _crowd_multimesh: MultiMesh
var _wall_material: ShaderMaterial
var _crest_material: ShaderMaterial
var _arc_material: ShaderMaterial
var _flash_material: ShaderMaterial
var _route_material: ShaderMaterial
var _swarm_material: ShaderMaterial
var _swarm_multimesh: MultiMesh
var _cable_material: ShaderMaterial
var _cable_pulse_material: ShaderMaterial
## metric key -> materials whose "intensity" follows the layer focus.
var _layer_materials := {}


func _init() -> void:
	_targets = layer_targets(_metrics)
	_current = _targets.duplicate()
	for key in LAYER_KEYS:
		_focus_alpha[key] = 1.0
		_focus_target[key] = 1.0


func _ready() -> void:
	_spin_root = get_node_or_null("SpinRoot")
	if _spin_root == null:
		_spin_root = Node3D.new()
		_spin_root.name = "SpinRoot"
		add_child(_spin_root)
	_camera = get_node_or_null("OrbitCamera") as Camera3D
	if _camera != null:
		_base_fov = _camera.fov
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		# Recoloring per era must not leak into other instances of the scene.
		_environment = world.environment.duplicate()
		world.environment = _environment
	_face_longitude(HOME_LONGITUDE)
	_build_globe()
	_build_compute_layer()
	_build_labor_layer()
	_build_tension_layer()
	_build_autonomy_layer()
	_build_trust_layer()
	_built = true
	_current = _targets.duplicate()
	set_era(_era)
	_apply_focus()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_fit_camera):
		viewport.size_changed.connect(_fit_camera)
	_fit_camera()


func _exit_tree() -> void:
	release_meshes(self)


## Detaches meshes before the nodes are freed; freeing an instance together
## with its mesh trips "mesh_get_surface_count" errors in the headless dummy
## renderer (seen in Godot 4.3).
static func release_meshes(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).mesh = null
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		(node as MultiMeshInstance3D).multimesh = null


func _process(delta: float) -> void:
	_spin_root.rotate_y(delta * SPIN_SPEED)
	if not _built:
		return
	if _view_inset > 0.0:
		_update_view_offset()
	var step := 1.0 - exp(-EASE_RATE * delta)
	var moved := false
	for key in EASED:
		var target := float(_targets[key])
		var value := float(_current[key])
		if absf(target - value) > 0.0005:
			_current[key] = lerpf(value, target, step) if absf(target - value) > 0.002 else target
			moved = true
	if moved:
		_apply_current()
	var focus_step := 1.0 - exp(-FOCUS_RATE * delta)
	var refocused := false
	for key in LAYER_KEYS:
		var goal := float(_focus_target[key])
		var alpha := float(_focus_alpha[key])
		if absf(goal - alpha) > 0.001:
			_focus_alpha[key] = lerpf(alpha, goal, focus_step) if absf(goal - alpha) > 0.004 else goal
			refocused = true
	if refocused:
		_apply_focus()


# --- Public API --------------------------------------------------------------------

## Binds simulation telemetry: reads snapshot["metrics"] (0-100 each). Missing
## or non-finite metrics keep their previous value.
func update_from_snapshot(snapshot: Dictionary) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	for key in LAYER_KEYS:
		if metrics.has(key):
			var value := float(metrics[key])
			if is_finite(value):
				_metrics[key] = clampf(value, 0.0, 100.0)
	_targets = layer_targets(_metrics)
	if _built:
		_apply_discrete()


## Recolors every layer from the era palette (EraStyle.for_era(era).globe and
## the era's metric colors).
func set_era(era: int) -> void:
	_era = clampi(era, 1, 3)
	if not _built:
		return
	var style := EraStyle.for_era(_era)
	var palette: Dictionary = style.globe
	var core: Color = palette["core"]
	var atmosphere: Color = palette["atmosphere"]
	var lights: Color = palette["lights"]
	var heat: Color = palette["heat"]
	var land: Color = palette["land"]
	var grid: Color = palette["grid"]
	_core_material.set_shader_parameter("sea_color", core.lerp(atmosphere, 0.05))
	_core_material.set_shader_parameter("highlight_color", core.lerp(atmosphere, 0.15))
	_atmosphere_material.set_shader_parameter("glow_color", atmosphere)
	_land_material.set_shader_parameter("color", Color(land, 1.0))
	_land_material.set_shader_parameter("strength", land.a)
	_globe_material.set_shader_parameter("grid_color", Color(grid, 1.0))
	_globe_material.set_shader_parameter("drift_color", style.metric_color("alignment_drift"))
	_globe_material.set_shader_parameter("scan_strength", [0.0, 0.0, 0.3, 0.1][_era])
	_bloom_material.set_shader_parameter("color", heat)
	_bloom_material.set_shader_parameter("core_color", heat.lerp(Color.WHITE, 0.85))
	_light_material.set_shader_parameter("color", lights)
	_city_glow_material.set_shader_parameter("color", lights.lerp(Color(1.0, 0.7, 0.24), 0.4))
	_city_glow_material.set_shader_parameter("core_color", lights.lerp(Color.WHITE, 0.45))
	var labor := style.metric_color("labor_displacement")
	_pulse_material.set_shader_parameter("color", labor)
	_crowd_material.set_shader_parameter("color", labor)
	var tension := style.metric_color("geopolitical_tension")
	for material in [_wall_material, _crest_material, _arc_material]:
		(material as ShaderMaterial).set_shader_parameter("color", tension)
	_crest_material.set_shader_parameter("core_color", tension.lerp(Color.WHITE, 0.6))
	_arc_material.set_shader_parameter("core_color", tension.lerp(Color.WHITE, 0.5))
	_flash_material.set_shader_parameter("color", tension.lerp(Color.WHITE, 0.25))
	var trust := style.metric_color("epistemic_trust")
	_cable_material.set_shader_parameter("line_color", trust)
	_cable_pulse_material.set_shader_parameter("tint", trust.lerp(Color.WHITE, 0.4))
	_route_material.set_shader_parameter("line_color", SWARM_START)
	if _environment != null:
		_environment.background_color = style.bg
	_apply_current()


## Shows every layer ("") or brings one metric's layer forward and dims the
## others to about 10%. Unknown keys clear the focus.
func set_layer_focus(metric_key: String) -> void:
	_focus = metric_key if LAYER_KEYS.has(metric_key) else ""
	for key in LAYER_KEYS:
		_focus_target[key] = 1.0 if _focus == "" or _focus == key else DIMMED_ALPHA


func get_layer_focus() -> String:
	return _focus


## Reserves [param bottom_pixels] at the bottom of the globe's viewport (an
## overlay's chips and ticker): the globe re-centers in the space above.
func set_view_inset(bottom_pixels: float) -> void:
	_view_inset = maxf(0.0, bottom_pixels) if is_finite(bottom_pixels) else 0.0
	_update_view_offset()


func get_era() -> int:
	return _era


## Current targets per layer, for tests and HUD hints: metrics, heat,
## brownout, dark_fraction, pulse, crowd_count, wall_height, wall_glow,
## heartbeat, arcs_active, swarm_count, swarm_mix, free_fraction, warp,
## drift_mix, coherence, dashes, plus focus, layer_alpha (focus targets), era
## and palette (the colors in use).
func get_layer_state() -> Dictionary:
	var state := _targets.duplicate()
	state["heartbeat"] = float(_targets["heartbeat"]) > 0.5
	state["crowd_count"] = int(_targets["crowd_count"])
	state["swarm_count"] = int(_targets["swarm_count"])
	state["metrics"] = _metrics.duplicate()
	state["focus"] = _focus
	state["layer_alpha"] = _focus_target.duplicate()
	state["era"] = _era
	state["palette"] = _palette()
	return state


## The layer parameters for metric values (0-100; missing keys use
## DEFAULT_METRICS). Pure: the globe eases toward these.
static func layer_targets(metrics: Dictionary) -> Dictionary:
	var compute := _metric_value(metrics, "compute_energy_sat")
	var labor := _metric_value(metrics, "labor_displacement")
	var tension := _metric_value(metrics, "geopolitical_tension")
	var autonomy := _metric_value(metrics, "algorithmic_autonomy")
	var drift := _metric_value(metrics, "alignment_drift")
	var trust := _metric_value(metrics, "epistemic_trust")
	var dark := clampf((labor - 25.0) / 70.0, 0.0, 1.0)
	var incoherence := clampf((62.0 - trust) / 42.0, 0.0, 1.0)
	var arcs := 0
	if tension > 75.0:
		arcs = mini(ARCS.size(), int(floor(clampf((tension - 75.0) / 15.0, 0.0, 1.0) * ARCS.size())) + 1)
	var tension_unit := tension / 100.0
	var autonomy_unit := autonomy / 100.0
	return {
		"heat": clampf((compute - 25.0) / 55.0, 0.0, 1.0),
		"brownout": clampf((compute - 66.0) / 40.0, 0.0, 1.0),
		"dark": dark,
		"dark_fraction": dark * 0.85,
		"pulse": pow(1.0 - labor / 100.0, 1.4),
		"crowd_count": floorf(clampf((labor - 45.0) / 45.0, 0.0, 1.0) * CROWD_SIZE),
		"wall_height": 0.01 + tension_unit * tension_unit * 0.11,
		"wall_glow": tension_unit,
		"heartbeat": 1.0 if tension > 55.0 else 0.0,
		"arcs_active": arcs,
		"swarm_count": minf(SWARM_SIZE, floorf(8.0 + autonomy_unit * autonomy_unit * 210.0)),
		"swarm_mix": autonomy_unit,
		"free_fraction": clampf((autonomy - 30.0) / 70.0, 0.0, 1.0),
		"warp": pow(drift / 100.0, 1.6) * 9.0,
		"drift_mix": drift / 100.0,
		"coherence": 1.0 - incoherence,
		"dashes": incoherence > 0.2,
	}


static func lat_lon_to_vector(lat_deg: float, lon_deg: float, radius: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon)) * radius


static func _metric_value(metrics: Dictionary, key: String) -> float:
	var value := float(metrics.get(key, DEFAULT_METRICS[key]))
	if not is_finite(value):
		value = float(DEFAULT_METRICS[key])
	return clampf(value, 0.0, 100.0)


# --- Applying values ---------------------------------------------------------------

## Values that switch at once (counts of arcs, dashes).
func _apply_discrete() -> void:
	var arcs := float(_targets["arcs_active"])
	_arc_material.set_shader_parameter("active_count", arcs)
	_flash_material.set_shader_parameter("active_count", arcs)


func _apply_current() -> void:
	if not _built:
		return
	var c := _current
	var heat := float(c["heat"])
	_bloom_material.set_shader_parameter("strength", 0.35 + heat * 0.55)
	_bloom_material.set_shader_parameter("radius", 0.03 + heat * 0.08)
	_bloom_material.set_shader_parameter("radius_spread", heat * 0.053)
	_bloom_material.set_shader_parameter("flicker_chance", float(c["brownout"]))
	_beam_material.set_shader_parameter("flicker", 0.35 + 0.5 * float(c["brownout"]))
	_update_beams(heat)

	var dark := float(c["dark"])
	_light_material.set_shader_parameter("cutoff", dark * 0.85)
	_city_glow_material.set_shader_parameter("strength", 0.7 * (1.0 - dark * 0.6))
	_pulse_material.set_shader_parameter("strength", float(c["pulse"]) * 0.8)
	_crowd_multimesh.visible_instance_count = clampi(int(round(float(c["crowd_count"]))), 0, CROWD_SIZE)

	var height := float(c["wall_height"])
	var glow := float(c["wall_glow"])
	var beat := float(c["heartbeat"])
	_wall_material.set_shader_parameter("height", height)
	_wall_material.set_shader_parameter("glow", glow)
	_wall_material.set_shader_parameter("heartbeat", beat)
	_crest_material.set_shader_parameter("lift", height)
	_crest_material.set_shader_parameter("glow", minf(1.0, 0.25 + glow * 0.7))
	_crest_material.set_shader_parameter("width", 0.0024 + glow * 0.006)
	_crest_material.set_shader_parameter("heartbeat", beat)

	var wander := float(c["free_fraction"])
	_swarm_multimesh.visible_instance_count = clampi(int(round(float(c["swarm_count"]))), 0, SWARM_SIZE)
	_swarm_material.set_shader_parameter("free_share", wander)
	_swarm_material.set_shader_parameter("tint", SWARM_START.lerp(EraStyle.for_era(_era).metric_color("algorithmic_autonomy"), float(c["swarm_mix"])))
	_route_material.set_shader_parameter("base_alpha", 0.07 * (1.0 - wander * 0.6))

	var drift := float(c["drift_mix"])
	_globe_material.set_shader_parameter("warp", float(c["warp"]))
	_globe_material.set_shader_parameter("drift_mix", drift)
	_globe_material.set_shader_parameter("grid_alpha", _grid_alpha() * (1.0 + drift * 1.6))
	_globe_material.set_shader_parameter("line_width", 0.9 + drift * 0.9)

	var incoherence := 1.0 - float(c["coherence"])
	_cable_material.set_shader_parameter("coherence", 1.0 - incoherence)
	_cable_material.set_shader_parameter("dash_gap", 0.018 + incoherence * 0.084 if incoherence > 0.2 else 0.0)
	_cable_pulse_material.set_shader_parameter("incoherence", incoherence)
	_apply_discrete()


func _apply_focus() -> void:
	for key in _layer_materials:
		var alpha := float(_focus_alpha[key])
		for entry in _layer_materials[key]:
			var material: ShaderMaterial = entry[0]
			material.set_shader_parameter(String(entry[1]), float(entry[2]) * alpha)


func _grid_alpha() -> float:
	var grid: Color = EraStyle.for_era(_era).globe["grid"]
	return grid.a


func _palette() -> Dictionary:
	var palette: Dictionary = EraStyle.for_era(_era).globe
	return palette.duplicate()


## Beam heights follow the eased heat (24 transforms).
func _update_beams(heat: float) -> void:
	var color: Color = EraStyle.for_era(_era).globe["heat"]
	for i in HUBS.size():
		var hub: Array = HUBS[i]
		var normal := lat_lon_to_vector(float(hub[1]), float(hub[2]), 1.0)
		var height := 0.015 + 0.13 * float(hub[4]) * heat
		var axes := _basis_along(normal)
		var beam_basis := Basis(axes.x, axes.y * height, axes.z)
		_beam_multimesh.set_instance_transform(i, Transform3D(beam_basis, normal * (GLOBE_RADIUS + height * 0.5)))
		_beam_multimesh.set_instance_color(i, Color(color, 0.22 + 0.25 * heat))


## Keeps the whole globe in view: portrait viewports fit the width.
func _fit_camera() -> void:
	if _camera == null:
		return
	var size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if size.x > 0.0 and size.x < size.y else Camera3D.KEEP_HEIGHT
	_update_view_offset()


## Fits the globe into the space above the reserved inset: the view widens
## until the globe's usual frame (the full height in landscape, a square of
## the width in portrait) fits the height left above the inset, and shifts
## so the globe centers there (follows zoom).
func _update_view_offset() -> void:
	if _camera == null or not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var landscape := _camera.keep_aspect == Camera3D.KEEP_HEIGHT
	var span := viewport_size.y if landscape else viewport_size.x
	if span <= 0.0 or viewport_size.y <= 0.0:
		return
	var usable := maxf(viewport_size.y - _view_inset, viewport_size.y * 0.4)
	var widen := maxf(1.0, span / usable)
	var fov := rad_to_deg(2.0 * atan(tan(deg_to_rad(_base_fov) * 0.5) * widen))
	if absf(_camera.fov - fov) > 0.01:
		_camera.fov = fov
	var distance := _camera.global_position.distance_to(global_position)
	var units_per_pixel := 2.0 * distance * tan(deg_to_rad(fov) * 0.5) / span
	var offset := -_view_inset * 0.5 * units_per_pixel
	if absf(_camera.v_offset - offset) > 0.0001:
		_camera.v_offset = offset


## Turns the globe so [param longitude] faces the orbit camera's start yaw.
func _face_longitude(longitude: float) -> void:
	var yaw := 0.6
	if _camera != null and "yaw" in _camera:
		yaw = float(_camera.get("yaw"))
	_spin_root.rotation.y = yaw - PI * 0.5 - deg_to_rad(longitude)


func _register(metric_key: String, material: ShaderMaterial, parameter: String, base: float) -> void:
	if not _layer_materials.has(metric_key):
		_layer_materials[metric_key] = []
	_layer_materials[metric_key].append([material, parameter, base])


# --- Building --------------------------------------------------------------------------

func _build_globe() -> void:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = GLOBE_RADIUS * 0.995
	core_mesh.height = GLOBE_RADIUS * 1.99
	core_mesh.radial_segments = 64
	core_mesh.rings = 32
	_core_material = _material(CoreShader)
	core_mesh.material = _core_material
	core.mesh = core_mesh
	_spin_root.add_child(core)

	var shell := MeshInstance3D.new()
	shell.name = "WireframeShell"
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = GLOBE_RADIUS
	shell_mesh.height = GLOBE_RADIUS * 2.0
	shell_mesh.radial_segments = 64
	shell_mesh.rings = 32
	_globe_material = _material(WireframeShader, {
		"lat_lines": 6.0, "lon_lines": 12.0, "rim_strength": 0.0, "scan_speed": 0.05, "glow_strength": 1.0,
	})
	shell_mesh.material = _globe_material
	shell.mesh = shell_mesh
	_spin_root.add_child(shell)
	_register("alignment_drift", _globe_material, "intensity", 1.0)

	var halo := MeshInstance3D.new()
	halo.name = "Atmosphere"
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = GLOBE_RADIUS * 1.25
	halo_mesh.height = GLOBE_RADIUS * 2.5
	halo_mesh.radial_segments = 48
	halo_mesh.rings = 24
	_atmosphere_material = _material(AtmosphereShader)
	halo_mesh.material = _atmosphere_material
	halo.mesh = halo_mesh
	add_child(halo)

	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	var rows: Array = LandmaskData.ROWS
	var resolution := LandmaskData.RESOLUTION_DEG
	for row in rows.size():
		var lat := 90.0 - resolution * 0.5 - float(row) * resolution
		var line: String = rows[row]
		# Thin columns toward the poles so dot density stays roughly even.
		var stride := maxi(1, int(round(1.0 / maxf(cos(deg_to_rad(lat)), 0.2))))
		for column in range(0, line.length(), stride):
			if line[column] != "1":
				continue
			var lon := -180.0 + resolution * 0.5 + float(column) * resolution
			transforms.append(_surface_transform(lat, lon, GLOBE_RADIUS * 1.003))
			custom.append(Color(1.0, 1.0, 0.0, 0.0))
	_land_material = _material(SpriteShader, {
		"radius": 0.0066, "min_pixels": 0.8, "square": 1.0, "facing_floor": 0.32, "limb_fade": 1.0, "shrink_at_limb": 0.45,
	})
	_add_sprites("Landmass", transforms, PackedColorArray(), custom, _land_material)


func _build_compute_layer() -> void:
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	for i in HUBS.size():
		var hub: Array = HUBS[i]
		transforms.append(_surface_transform(float(hub[1]), float(hub[2]), GLOBE_RADIUS * 1.012))
		custom.append(Color(1.0, 1.0, float(hub[4]), float(i) / float(HUBS.size())))
	_bloom_material = _material(SpriteShader, {
		"bloom": 1.0, "rings": 1.0, "bloom_stop": 0.25, "bloom_mid": 0.65, "color_stop": 0.25, "min_pixels": 3.0,
	})
	_add_sprites("HeatBlooms", transforms, PackedColorArray(), custom, _bloom_material)
	_register("compute_energy_sat", _bloom_material, "intensity", 1.0)

	_beam_material = _material(PointShader, {"intensity": 1.4, "flicker": 0.35})
	_beam_multimesh = MultiMesh.new()
	_beam_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_beam_multimesh.use_colors = true
	_beam_multimesh.use_custom_data = true
	var beam := CylinderMesh.new()
	beam.top_radius = 0.0015
	beam.bottom_radius = 0.006
	beam.height = 1.0
	beam.radial_segments = 6
	beam.rings = 1
	_beam_multimesh.mesh = beam
	_beam_multimesh.instance_count = HUBS.size()
	for i in HUBS.size():
		_beam_multimesh.set_instance_custom_data(i, Color(float(i) * 0.37, 0, 0, 0))
	_add_multimesh("HeatBeams", _beam_multimesh, _beam_material)
	_register("compute_energy_sat", _beam_material, "intensity", 1.4)


func _build_labor_layer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_SEED
	var light_transforms: Array[Transform3D] = []
	var light_custom := PackedColorArray()
	var metro_transforms: Array[Transform3D] = []
	var metro_custom := PackedColorArray()
	var ring_transforms: Array[Transform3D] = []
	var ring_custom := PackedColorArray()
	for metro in METROS:
		var lat := float(metro[1])
		var lon := float(metro[2])
		var size := float(metro[3])
		var squash := maxf(0.3, cos(deg_to_rad(lat)))
		for _k in int(round(5.0 + size * 16.0)):
			var angle := rng.randf() * TAU
			var reach := pow(rng.randf(), 0.7) * (0.8 + size * 2.2)
			light_transforms.append(_surface_transform(lat + sin(angle) * reach, lon + cos(angle) * reach / squash, 1.004))
			# Threshold: the share of lights already dark when this one goes out.
			light_custom.append(Color(rng.randf(), 0.4 + rng.randf() * 0.6, 0.0, 0.0))
		metro_transforms.append(_surface_transform(lat, lon, 1.005))
		metro_custom.append(Color(1.0, 1.0, size, 0.0))
		var quad := 2.0 * (0.012 + 0.06 + 0.048 * size) + 0.02
		var ring := _surface_transform(lat, lon, 1.006)
		ring.basis = ring.basis.scaled(Vector3.ONE * quad)
		ring_transforms.append(ring)
		ring_custom.append(Color(rng.randf(), size, 0.0, 0.0))

	_light_material = _material(SpriteShader, {"radius": 0.0052, "min_pixels": 0.8, "square": 1.0, "cutoff": 0.0})
	_add_sprites("CityLights", light_transforms, PackedColorArray(), light_custom, _light_material)
	_city_glow_material = _material(SpriteShader, {
		"bloom": 1.0, "bloom_stop": 0.0, "bloom_mid": 1.0, "color_stop": 1.0, "radius": 0.018, "radius_spread": 0.03,
		"min_pixels": 2.0,
	})
	_add_sprites("CityGlows", metro_transforms, PackedColorArray(), metro_custom, _city_glow_material)
	_pulse_material = _material(RingShader, {"period": 4.0, "start_radius": 0.012, "growth": 0.06, "growth_spread": 0.048})
	_add_rings("ShiftPulses", ring_transforms, ring_custom, _pulse_material)

	var crowd_transforms: Array[Transform3D] = []
	var crowd_custom := PackedColorArray()
	var campuses: Array = []
	for hub in HUBS:
		if float(hub[4]) >= 0.5:
			campuses.append(hub)
	for _i in CROWD_SIZE:
		var hub: Array = campuses[int(rng.randf() * campuses.size()) % campuses.size()]
		crowd_transforms.append(_surface_transform(float(hub[1]), float(hub[2]), 1.006))
		crowd_custom.append(Color(1.0, 1.0, rng.randf(), rng.randf()))
	_crowd_material = _material(SpriteShader, {"radius": 0.0062, "min_pixels": 1.0, "square": 1.0, "orbit": 0.045, "limb_fade": 2.2})
	_crowd_multimesh = _add_sprites("Crowds", crowd_transforms, PackedColorArray(), crowd_custom, _crowd_material)
	for material in [_light_material, _city_glow_material, _pulse_material, _crowd_material]:
		_register("labor_displacement", material, "intensity", 1.0)


func _build_tension_layer() -> void:
	var wall_mesh := ArrayMesh.new()
	var crest_mesh := ArrayMesh.new()
	var wall := {"vertices": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}
	var crest := _ribbon_arrays()
	for index in WALLS.size():
		var points := _wall_points(WALLS[index])
		_append_curtain(wall, points)
		_append_ribbon(crest, points, Vector2(float(index), 0.0))
	_commit_triangles(wall_mesh, wall["vertices"], wall["uvs"], PackedVector3Array(), PackedVector2Array(), wall["indices"])
	_commit_ribbon(crest_mesh, crest)
	_wall_material = _material(WallShader)
	_add_mesh("BlocWalls", wall_mesh, _wall_material)
	_crest_material = _material(RibbonShader, {"min_pixels": 0.8})
	_add_mesh("WallCrests", crest_mesh, _crest_material)

	var arc_mesh := ArrayMesh.new()
	var arcs := _ribbon_arrays()
	var flash_transforms: Array[Transform3D] = []
	var flash_custom := PackedColorArray()
	for index in ARCS.size():
		var arc: Array = ARCS[index]
		var a := lat_lon_to_vector(float(arc[0]), float(arc[1]), 1.0)
		var b := lat_lon_to_vector(float(arc[2]), float(arc[3]), 1.0)
		var points := PackedVector3Array()
		for k in 41:
			var u := float(k) / 40.0
			points.append(a.slerp(b, u).normalized() * (GLOBE_RADIUS + 0.004 + float(arc[4]) * sin(PI * u)))
		_append_ribbon(arcs, points, Vector2(float(index), float(arc[5])))
		var flash := _surface_transform(float(arc[2]), float(arc[3]), 1.007)
		flash.basis = flash.basis.scaled(Vector3.ONE * 0.26)
		flash_transforms.append(flash)
		flash_custom.append(Color(float(arc[5]), 0.0, float(index), 0.0))
	_commit_ribbon(arc_mesh, arcs)
	_arc_material = _material(RibbonShader, {"animate": true, "speed": 1.0 / ARC_PERIOD, "width": 0.0042, "glow": 0.85})
	_add_mesh("LaunchArcs", arc_mesh, _arc_material)
	_flash_material = _material(RingShader, {
		"period": ARC_PERIOD, "window_start": 0.71, "start_radius": 0.018, "growth": 0.096, "growth_spread": 0.0,
		"line_pixels": 1.5,
	})
	_add_rings("ImpactFlashes", flash_transforms, flash_custom, _flash_material)
	for material in [_wall_material, _crest_material, _arc_material, _flash_material]:
		_register("geopolitical_tension", material, "intensity", 1.0)


func _build_autonomy_layer() -> void:
	var metro_dirs := {}
	for metro in METROS:
		metro_dirs[String(metro[0])] = lat_lon_to_vector(float(metro[1]), float(metro[2]), 1.0)
	var routes: Array = []
	for route in ROUTES:
		routes.append([metro_dirs[String(route[0])], metro_dirs[String(route[1])]])
	var route_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for index in routes.size():
		var ends: Array = routes[index]
		for s in 24:
			for k in [s, s + 1]:
				var u := float(k) / 24.0
				vertices.append((ends[0] as Vector3).slerp(ends[1], u).normalized() * 1.008)
				uvs.append(Vector2(u, fmod(float(index) * 0.29, 1.0)))
				colors.append(Color(1, 1, 1, 1))
	_fill_line_mesh(route_mesh, vertices, uvs, colors)
	_route_material = _material(FlowShader, {"base_alpha": 0.07, "pulse_alpha": 0.0, "intensity": 1.0})
	_add_mesh("TradeRoutes", route_mesh, _route_material)

	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_SEED + 1
	var transforms: Array[Transform3D] = []
	var colors_data := PackedColorArray()
	var custom := PackedColorArray()
	for i in SWARM_SIZE:
		var ends: Array = routes[int(rng.randf() * routes.size()) % routes.size()]
		var direction := 1.0 if rng.randf() < 0.5 else -1.0
		var speed := (0.025 + rng.randf() * 0.045) * direction
		transforms.append(_route_transform(ends[0], ends[1]))
		custom.append(Color(rng.randf(), speed, (rng.randf() - 0.5) * 0.025, rng.randf()))
		colors_data.append(Color(rng.randf(), rng.randf(), float(i) / 256.0, fmod(float(i) * 0.618034, 1.0)))
	_swarm_material = _material(RouteShader, {"lift": 1.01, "dot_radius": 0.0072, "trail": 0.014, "trail_alpha": 0.4, "min_pixels": 1.2})
	_swarm_multimesh = _add_sprites("AgentSwarm", transforms, colors_data, custom, _swarm_material)
	for material in [_route_material, _swarm_material]:
		_register("algorithmic_autonomy", material, "intensity", 1.0)


func _build_trust_layer() -> void:
	var cable_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var transforms: Array[Transform3D] = []
	var pulse_colors := PackedColorArray()
	var pulse_custom := PackedColorArray()
	var segments := 40
	for index in CABLES.size():
		var cable: Array = CABLES[index]
		var a: Array = HUBS[cable[0]]
		var b: Array = HUBS[cable[1]]
		var start := lat_lon_to_vector(float(a[1]), float(a[2]), 1.0)
		var finish := lat_lon_to_vector(float(b[1]), float(b[2]), 1.0)
		var arc_length := start.angle_to(finish)
		# Pulse k of this cable sits at u = k / 4 + index * 0.13; the line's
		# own pulses use the matching phase so both stay in step.
		var offset := fposmod(-float(index) * 0.52, 1.0)
		var packed := floorf(arc_length * 100.0) + offset
		for s in segments:
			for k in [s, s + 1]:
				var t := float(k) / float(segments)
				vertices.append(start.slerp(finish, t).normalized() * 1.004)
				uvs.append(Vector2(t, packed))
				colors.append(Color(1, 1, 1, 1))
		for k in 4:
			transforms.append(_route_transform(start, finish))
			pulse_custom.append(Color(fposmod(float(k) / 4.0 + float(index) * 0.13, 1.0), 0.12, 0.0, 2.0))
			var pulse_seed := float(index * 4 + k)
			pulse_colors.append(Color(0.0, 0.0, pulse_seed / 128.0, fposmod(pulse_seed * 0.618034, 1.0)))
	_fill_line_mesh(cable_mesh, vertices, uvs, colors)
	_cable_material = _material(FlowShader, {
		"base_alpha": 0.22, "pulse_alpha": 0.35, "pulse_count": 4.0, "flow_speed": 0.48, "dash_length": 0.03,
	})
	_add_mesh("CableThroughput", cable_mesh, _cable_material)
	_cable_pulse_material = _material(RouteShader, {"lift": 1.004, "dot_radius": 0.0085, "trail": 0.0, "min_pixels": 1.2})
	_add_sprites("CablePulses", transforms, pulse_colors, pulse_custom, _cable_pulse_material)
	for material in [_cable_material, _cable_pulse_material]:
		_register("epistemic_trust", material, "intensity", 1.0)


# --- Geometry helpers ---------------------------------------------------------------

func _material(shader: Shader, parameters: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in parameters:
		material.set_shader_parameter(key, parameters[key])
	return material


## A MultiMesh of camera-facing quads (sprites, swarm particles) under the spin root.
func _add_sprites(node_name: String, transforms: Array[Transform3D], colors: PackedColorArray, custom: PackedColorArray,
		material: ShaderMaterial) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	return _add_instances(node_name, quad, transforms, colors, custom, material)


## A MultiMesh of quads lying on the surface (rings).
func _add_rings(node_name: String, transforms: Array[Transform3D], custom: PackedColorArray, material: ShaderMaterial) -> MultiMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	return _add_instances(node_name, plane, transforms, PackedColorArray(), custom, material)


func _add_instances(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colors: PackedColorArray,
		custom: PackedColorArray, material: ShaderMaterial) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	_fill_multimesh(multimesh, transforms, colors, custom)
	_add_multimesh(node_name, multimesh, material)
	return multimesh


func _add_multimesh(node_name: String, multimesh: MultiMesh, material: ShaderMaterial) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.custom_aabb = _globe_bounds()
	_spin_root.add_child(instance)


func _add_mesh(node_name: String, mesh: Mesh, material: ShaderMaterial) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.custom_aabb = _globe_bounds()
	_spin_root.add_child(instance)


static func _globe_bounds() -> AABB:
	return AABB(Vector3.ONE * -1.6, Vector3.ONE * 3.2)


## Uploads all instances in one buffer: 12 transform floats (rows of the 3x4
## matrix), then the raw color and custom data.
static func _fill_multimesh(multimesh: MultiMesh, transforms: Array[Transform3D], colors: PackedColorArray,
		custom: PackedColorArray) -> void:
	var count := transforms.size()
	multimesh.instance_count = count
	var stride := 12 + (4 if multimesh.use_colors else 0) + (4 if multimesh.use_custom_data else 0)
	var buffer := PackedFloat32Array()
	buffer.resize(count * stride)
	for i in count:
		var t := transforms[i]
		var o := i * stride
		buffer[o] = t.basis.x.x
		buffer[o + 1] = t.basis.y.x
		buffer[o + 2] = t.basis.z.x
		buffer[o + 3] = t.origin.x
		buffer[o + 4] = t.basis.x.y
		buffer[o + 5] = t.basis.y.y
		buffer[o + 6] = t.basis.z.y
		buffer[o + 7] = t.origin.y
		buffer[o + 8] = t.basis.x.z
		buffer[o + 9] = t.basis.y.z
		buffer[o + 10] = t.basis.z.z
		buffer[o + 11] = t.origin.z
		o += 12
		if multimesh.use_colors:
			var c := colors[i]
			buffer[o] = c.r
			buffer[o + 1] = c.g
			buffer[o + 2] = c.b
			buffer[o + 3] = c.a
			o += 4
		if multimesh.use_custom_data:
			var d := custom[i]
			buffer[o] = d.r
			buffer[o + 1] = d.g
			buffer[o + 2] = d.b
			buffer[o + 3] = d.a
	multimesh.buffer = buffer


## A pose on the surface: Y along the normal, at [param radius].
static func _surface_transform(lat: float, lon: float, radius: float) -> Transform3D:
	var normal := lat_lon_to_vector(lat, lon, 1.0)
	return Transform3D(_basis_along(normal), normal * radius)


## Route "pose" for the route shader: X = start, Y = end, Z = plane normal.
static func _route_transform(start: Vector3, finish: Vector3) -> Transform3D:
	var normal := start.cross(finish)
	normal = normal.normalized() if normal.length() > 0.00001 else _basis_along(start).x
	return Transform3D(Basis(start.normalized(), finish.normalized(), normal), Vector3.ZERO)


## Points along a fault line (6 per segment, on the unit sphere).
static func _wall_points(polyline: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in polyline.size() - 1:
		var a := lat_lon_to_vector(float(polyline[i][0]), float(polyline[i][1]), 1.0)
		var b := lat_lon_to_vector(float(polyline[i + 1][0]), float(polyline[i + 1][1]), 1.0)
		for k in 6:
			points.append(a.slerp(b, float(k) / 6.0).normalized())
	var last: Array = polyline[polyline.size() - 1]
	points.append(lat_lon_to_vector(float(last[0]), float(last[1]), 1.0))
	return points


## A curtain: two vertices per point (foot UV.y = 0, crest UV.y = 1), UV.x = arc length.
static func _append_curtain(arrays: Dictionary, points: PackedVector3Array) -> void:
	var vertices: PackedVector3Array = arrays["vertices"]
	var uvs: PackedVector2Array = arrays["uvs"]
	var indices: PackedInt32Array = arrays["indices"]
	var first := vertices.size()
	var along := 0.0
	for i in points.size():
		if i > 0:
			along += points[i - 1].angle_to(points[i])
		vertices.append(points[i])
		uvs.append(Vector2(along, 0.0))
		vertices.append(points[i])
		uvs.append(Vector2(along, 1.0))
		if i > 0:
			var v := first + i * 2
			indices.append_array(PackedInt32Array([v - 2, v - 1, v, v - 1, v + 1, v]))
	arrays["vertices"] = vertices
	arrays["uvs"] = uvs
	arrays["indices"] = indices


static func _ribbon_arrays() -> Dictionary:
	return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
		"uv2s": PackedVector2Array(), "indices": PackedInt32Array()}


## A camera-facing ribbon: two vertices per point with the tangent in NORMAL,
## UV = (0-1 along, side -1/+1) and UV2 = [param line_data].
static func _append_ribbon(arrays: Dictionary, points: PackedVector3Array, line_data: Vector2) -> void:
	var vertices: PackedVector3Array = arrays["vertices"]
	var normals: PackedVector3Array = arrays["normals"]
	var uvs: PackedVector2Array = arrays["uvs"]
	var uv2s: PackedVector2Array = arrays["uv2s"]
	var indices: PackedInt32Array = arrays["indices"]
	var first := vertices.size()
	var count := points.size()
	for i in count:
		var ahead := points[mini(i + 1, count - 1)]
		var behind := points[maxi(i - 1, 0)]
		var tangent := (ahead - behind).normalized()
		if tangent.length() < 0.5:
			tangent = Vector3.RIGHT
		var t := float(i) / float(maxi(count - 1, 1))
		for side in [-1.0, 1.0]:
			vertices.append(points[i])
			normals.append(tangent)
			uvs.append(Vector2(t, side))
			uv2s.append(line_data)
		if i > 0:
			var v := first + i * 2
			indices.append_array(PackedInt32Array([v - 2, v - 1, v, v - 1, v + 1, v]))
	arrays["vertices"] = vertices
	arrays["normals"] = normals
	arrays["uvs"] = uvs
	arrays["uv2s"] = uv2s
	arrays["indices"] = indices


static func _commit_ribbon(mesh: ArrayMesh, arrays: Dictionary) -> void:
	_commit_triangles(mesh, arrays["vertices"], arrays["uvs"], arrays["normals"], arrays["uv2s"], arrays["indices"])


static func _commit_triangles(mesh: ArrayMesh, vertices: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, uv2s: PackedVector2Array, indices: PackedInt32Array) -> void:
	mesh.clear_surfaces()
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if not uv2s.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Replaces [param mesh]'s surface in place with line segments.
static func _fill_line_mesh(mesh: ArrayMesh, vertices: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray) -> void:
	mesh.clear_surfaces()
	if vertices.size() < 2:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


## Basis whose Y axis points along [param up].
static func _basis_along(up: Vector3) -> Basis:
	var y := up.normalized()
	var helper := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
