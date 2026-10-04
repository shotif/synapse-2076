class_name GlobeViewport
extends Node3D
## 3D holographic wireframe Earth (PRD section 8.2): dotted landmasses, major
## datacenter clusters with heat signatures, animated undersea-cable
## throughput and regional compute embargoes. Bound to simulation telemetry
## through [method update_from_snapshot].

const GLOBE_RADIUS := 1.0
const WireframeShader := preload("res://viewports_3d/shaders/wireframe_globe.gdshader")
const PointShader := preload("res://viewports_3d/shaders/hologram_point.gdshader")
const FlowShader := preload("res://viewports_3d/shaders/data_flow.gdshader")

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
## Cable routes between hub indices.
const CABLES := [[0, 6], [0, 8], [5, 6], [1, 19], [2, 22], [1, 18], [4, 21], [14, 13], [13, 12],
	[14, 15], [15, 20], [19, 18], [16, 17], [14, 21], [22, 23], [23, 13], [7, 12], [12, 15], [6, 10], [9, 7]]

var _globe_material: ShaderMaterial
var _hub_material: ShaderMaterial
var _land_material: ShaderMaterial
var _cable_material: ShaderMaterial
var _embargo_material: ShaderMaterial
var _hub_multimesh: MultiMesh
var _beam_multimesh: MultiMesh
var _cable_mesh: MeshInstance3D
var _embargo_mesh: MeshInstance3D
var _spin_root: Node3D

var _saturation := 42.0
var _tension := 38.0
var _trust := 58.0
var _target_alert := 0.0
var _alert := 0.0


func _ready() -> void:
	_spin_root = get_node_or_null("SpinRoot")
	if _spin_root == null:
		_spin_root = Node3D.new()
		_spin_root.name = "SpinRoot"
		add_child(_spin_root)
	_build_globe()
	_build_landmass()
	_build_hubs()
	_build_cables()
	_apply_telemetry()


func _exit_tree() -> void:
	release_meshes(self)


## Detaches meshes before the nodes are freed; freeing an instance together
## with its mesh trips "mesh_get_surface_count" errors in the headless dummy
## renderer (Godot 4.3).
static func release_meshes(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).mesh = null
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		(node as MultiMeshInstance3D).multimesh = null


func _process(delta: float) -> void:
	_alert = lerpf(_alert, _target_alert, clampf(delta * 2.0, 0.0, 1.0))
	if _globe_material != null:
		_globe_material.set_shader_parameter("alert_mix", _alert)
	_spin_root.rotate_y(delta * 0.02)


## Binds simulation telemetry: saturation drives cluster heat, tension drives
## embargo overlays and the alert tint, trust drives cable throughput.
func update_from_snapshot(snapshot: Dictionary) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	_saturation = float(metrics.get("compute_energy_sat", _saturation))
	_tension = float(metrics.get("geopolitical_tension", _tension))
	_trust = float(metrics.get("epistemic_trust", _trust))
	_apply_telemetry()


static func lat_lon_to_vector(lat_deg: float, lon_deg: float, radius: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon)) * radius


func _build_globe() -> void:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = GLOBE_RADIUS * 0.985
	core_mesh.height = GLOBE_RADIUS * 1.97
	core_mesh.radial_segments = 48
	core_mesh.rings = 24
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color("#04080D")
	core_mesh.material = core_material
	core.mesh = core_mesh
	_spin_root.add_child(core)

	var shell := MeshInstance3D.new()
	shell.name = "WireframeShell"
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = GLOBE_RADIUS
	shell_mesh.height = GLOBE_RADIUS * 2.0
	shell_mesh.radial_segments = 64
	shell_mesh.rings = 32
	_globe_material = ShaderMaterial.new()
	_globe_material.shader = WireframeShader
	shell_mesh.material = _globe_material
	shell.mesh = shell_mesh
	_spin_root.add_child(shell)

	var halo := MeshInstance3D.new()
	halo.name = "Atmosphere"
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = GLOBE_RADIUS * 1.06
	halo_mesh.height = GLOBE_RADIUS * 2.12
	var halo_material := ShaderMaterial.new()
	halo_material.shader = WireframeShader
	halo_material.set_shader_parameter("lat_lines", 0.0)
	halo_material.set_shader_parameter("lon_lines", 0.0)
	halo_material.set_shader_parameter("glow_strength", 0.35)
	halo_material.set_shader_parameter("rim_power", 4.0)
	halo_mesh.material = halo_material
	halo.mesh = halo_mesh
	add_child(halo)


func _build_landmass() -> void:
	var points: Array[Vector3] = []
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
			points.append(lat_lon_to_vector(lat, lon, GLOBE_RADIUS * 1.003))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var dot := SphereMesh.new()
	dot.radius = 0.0065
	dot.height = 0.013
	dot.radial_segments = 6
	dot.rings = 3
	multimesh.mesh = dot
	multimesh.instance_count = points.size()
	for i in points.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
		multimesh.set_instance_color(i, Color(0.0, 0.9, 1.0, 0.55))
		multimesh.set_instance_custom_data(i, Color(randf(), 0, 0, 0))
	_land_material = ShaderMaterial.new()
	_land_material.shader = PointShader
	_land_material.set_shader_parameter("intensity", 1.3)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Landmass"
	instance.multimesh = multimesh
	instance.material_override = _land_material
	_spin_root.add_child(instance)


func _build_hubs() -> void:
	_hub_material = ShaderMaterial.new()
	_hub_material.shader = PointShader
	_hub_material.set_shader_parameter("intensity", 1.6)
	_hub_material.set_shader_parameter("flicker", 0.35)

	_hub_multimesh = MultiMesh.new()
	_hub_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_hub_multimesh.use_colors = true
	_hub_multimesh.use_custom_data = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.022
	sphere.height = 0.044
	sphere.radial_segments = 10
	sphere.rings = 6
	_hub_multimesh.mesh = sphere
	_hub_multimesh.instance_count = HUBS.size()
	var hubs := MultiMeshInstance3D.new()
	hubs.name = "DatacenterHubs"
	hubs.multimesh = _hub_multimesh
	hubs.material_override = _hub_material
	_spin_root.add_child(hubs)

	_beam_multimesh = MultiMesh.new()
	_beam_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_beam_multimesh.use_colors = true
	_beam_multimesh.use_custom_data = true
	var beam := CylinderMesh.new()
	beam.top_radius = 0.002
	beam.bottom_radius = 0.009
	beam.height = 1.0
	beam.radial_segments = 6
	beam.rings = 1
	_beam_multimesh.mesh = beam
	_beam_multimesh.instance_count = HUBS.size()
	var beams := MultiMeshInstance3D.new()
	beams.name = "HeatSignatures"
	beams.multimesh = _beam_multimesh
	beams.material_override = _hub_material
	_spin_root.add_child(beams)
	for i in HUBS.size():
		_hub_multimesh.set_instance_custom_data(i, Color(float(i) / float(HUBS.size()), 0, 0, 0))
		_beam_multimesh.set_instance_custom_data(i, Color(float(i) * 0.37, 0, 0, 0))


func _build_cables() -> void:
	_cable_material = ShaderMaterial.new()
	_cable_material.shader = FlowShader
	_cable_material.set_shader_parameter("pulse_count", 2.0)
	_cable_material.set_shader_parameter("base_alpha", 0.45)
	_cable_mesh = MeshInstance3D.new()
	_cable_mesh.name = "CableThroughput"
	_cable_mesh.mesh = ArrayMesh.new()
	_cable_mesh.material_override = _cable_material
	_spin_root.add_child(_cable_mesh)

	_embargo_material = ShaderMaterial.new()
	_embargo_material.shader = FlowShader
	_embargo_material.set_shader_parameter("line_color", CyberPalette.CRIMSON)
	_embargo_material.set_shader_parameter("pulse_count", 1.0)
	_embargo_material.set_shader_parameter("flow_speed", 0.6)
	_embargo_mesh = MeshInstance3D.new()
	_embargo_mesh.name = "EmbargoZones"
	_embargo_mesh.mesh = ArrayMesh.new()
	_embargo_mesh.material_override = _embargo_material
	_spin_root.add_child(_embargo_mesh)


func _apply_telemetry() -> void:
	if _hub_multimesh == null:
		return
	var heat := clampf(_saturation / 100.0, 0.0, 1.0)
	var heat_color := CyberPalette.CYAN.lerp(CyberPalette.AMBER, smoothstep(0.45, 0.75, heat)).lerp(CyberPalette.CRIMSON, smoothstep(0.75, 0.95, heat))
	var embargo := _tension >= 60.0
	for i in HUBS.size():
		var hub: Array = HUBS[i]
		var normal := lat_lon_to_vector(float(hub[1]), float(hub[2]), 1.0)
		var weight := float(hub[4])
		var scale := 0.7 + weight * (0.6 + heat)
		var hub_color := heat_color
		if embargo and String(hub[3]) == "EAST":
			hub_color = CyberPalette.CRIMSON
		_hub_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), normal * (GLOBE_RADIUS + 0.01)))
		_hub_multimesh.set_instance_color(i, Color(hub_color, 0.95))
		var height := 0.04 + 0.22 * weight * heat
		var axes := _basis_along(normal)
		var beam_basis := Basis(axes.x, axes.y * height, axes.z)
		_beam_multimesh.set_instance_transform(i, Transform3D(beam_basis, normal * (GLOBE_RADIUS + height * 0.5)))
		_beam_multimesh.set_instance_color(i, Color(hub_color, 0.55))

	_rebuild_cable_mesh(_cable_mesh.mesh as ArrayMesh, embargo)
	_rebuild_embargo_mesh(_embargo_mesh.mesh as ArrayMesh, embargo)
	_cable_material.set_shader_parameter("flow_speed", 0.15 + 0.45 * clampf(_trust / 100.0, 0.0, 1.0))
	_cable_material.set_shader_parameter("intensity", 0.6 + 0.8 * clampf(_trust / 100.0, 0.0, 1.0))
	_embargo_material.set_shader_parameter("intensity", 0.6 + 1.2 * clampf((_tension - 60.0) / 40.0, 0.0, 1.0))
	_target_alert = clampf((_tension - 55.0) / 45.0, 0.0, 1.0) * 0.85
	if _globe_material != null:
		_globe_material.set_shader_parameter("pulse", heat)


func _rebuild_cable_mesh(mesh: ArrayMesh, embargo: bool) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var segments := 40
	for index in CABLES.size():
		var cable: Array = CABLES[index]
		var a: Array = HUBS[cable[0]]
		var b: Array = HUBS[cable[1]]
		var crosses_bloc := (String(a[3]) == "EAST") != (String(b[3]) == "EAST")
		var color := Color(1, 1, 1, 0.9)
		if embargo and crosses_bloc:
			color = Color(1.0, 0.09, 0.27, 0.35)
		var start := lat_lon_to_vector(float(a[1]), float(a[2]), 1.0)
		var finish := lat_lon_to_vector(float(b[1]), float(b[2]), 1.0)
		var offset := fmod(float(index) * 0.137, 1.0)
		for s in segments:
			for k in [s, s + 1]:
				var t := float(k) / float(segments)
				var direction := start.slerp(finish, t).normalized()
				var lift := GLOBE_RADIUS + 0.01 + 0.12 * sin(PI * t) * start.distance_to(finish) * 0.5
				vertices.append(direction * lift)
				uvs.append(Vector2(t, offset))
				colors.append(color)
	_fill_line_mesh(mesh, vertices, uvs, colors)


func _rebuild_embargo_mesh(mesh: ArrayMesh, embargo: bool) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var segments := 32
	if not embargo:
		mesh.clear_surfaces()
		return
	for hub in HUBS:
		if String(hub[3]) != "EAST":
			continue
		var normal := lat_lon_to_vector(float(hub[1]), float(hub[2]), 1.0)
		var basis := _basis_along(normal)
		var radius := 0.07
		for s in segments:
			for k in [s, s + 1]:
				var angle := TAU * float(k) / float(segments)
				var local := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
				vertices.append(normal * (GLOBE_RADIUS + 0.015) + basis * local)
				uvs.append(Vector2(float(k) / float(segments), 0.0))
				colors.append(Color(1, 1, 1, 1))
	_fill_line_mesh(mesh, vertices, uvs, colors)


## Replaces [param mesh]'s surface in place (reusing the mesh avoids churning
## render-server resources every telemetry update).
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
