class_name NeuralLattice
extends Node3D
## Neural architecture lattice (PRD section 8.2): an interactive force-directed
## node graph whose depth tracks frontier capability. As alignment drift
## accumulates, nodes shift from cold cyan to erratic crimson with jitter
## shaders; emergent capabilities light up as amber nodes. A tensor loss
## landscape below the graph grows rugged with drift.

const NodeShader := preload("res://viewports_3d/shaders/neural_glow.gdshader")
const FlowShader := preload("res://viewports_3d/shaders/data_flow.gdshader")
const LandscapeShader := preload("res://viewports_3d/shaders/loss_landscape.gdshader")

const MIN_LAYERS := 5
const MAX_LAYERS := 12
const NODES_PER_LAYER := 11
const LAYER_SPAN := 4.8
const SPRING_REST := 0.85
const RELAX_STEPS := 160

var layer_count := 0
var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _layer_of: Array[int] = []
var _edges: Array[Vector2i] = []
var _emergent: Array[bool] = []
var _custom: Array[Color] = []
var _relax_left := 0
var _emergent_count := -1
var _drift := 0.16
var _target_drift := 0.16
var _activity := 0.3
var _rng := RandomNumberGenerator.new()

var _graph_root: Node3D
var _node_multimesh: MultiMesh
var _node_material: ShaderMaterial
var _edge_instance: MeshInstance3D
var _edge_material: ShaderMaterial
var _landscape_material: ShaderMaterial


func _ready() -> void:
	_graph_root = get_node_or_null("GraphRoot")
	if _graph_root == null:
		_graph_root = Node3D.new()
		_graph_root.name = "GraphRoot"
		add_child(_graph_root)
	_build_landscape()
	_node_material = ShaderMaterial.new()
	_node_material.shader = NodeShader
	_node_multimesh = MultiMesh.new()
	_node_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_node_multimesh.use_custom_data = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.065
	sphere.height = 0.13
	sphere.radial_segments = 12
	sphere.rings = 6
	_node_multimesh.mesh = sphere
	var nodes := MultiMeshInstance3D.new()
	nodes.name = "Neurons"
	nodes.multimesh = _node_multimesh
	nodes.material_override = _node_material
	_graph_root.add_child(nodes)
	_edge_material = ShaderMaterial.new()
	_edge_material.shader = FlowShader
	_edge_material.set_shader_parameter("pulse_count", 1.0)
	_edge_material.set_shader_parameter("base_alpha", 0.4)
	_edge_material.set_shader_parameter("pulse_alpha", 1.2)
	_edge_instance = MeshInstance3D.new()
	_edge_instance.name = "Synapses"
	_edge_instance.mesh = ArrayMesh.new()
	_edge_instance.material_override = _edge_material
	_graph_root.add_child(_edge_instance)
	rebuild(7, 0)


func _exit_tree() -> void:
	GlobeViewport.release_meshes(self)


## Binds telemetry: alignment drift colors and destabilizes the lattice,
## capability sets its depth, emergences add amber nodes, autonomy speeds firing.
func update_from_snapshot(snapshot: Dictionary) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	var tech: Dictionary = snapshot.get("tech", {})
	_target_drift = clampf(float(metrics.get("alignment_drift", _target_drift * 100.0)) / 100.0, 0.0, 1.0)
	_activity = clampf(float(metrics.get("algorithmic_autonomy", 30.0)) / 100.0, 0.0, 1.0)
	var capability := float(tech.get("capability_index", 20.0))
	var layers := clampi(MIN_LAYERS + int(capability / 14.0), MIN_LAYERS, MAX_LAYERS)
	var emergent := (tech.get("emerged_capabilities", []) as Array).size()
	if layers != layer_count or emergent != _emergent_count:
		rebuild(layers, emergent)


func get_drift_level() -> float:
	return _drift


func rebuild(layers: int, emergent_count: int) -> void:
	layer_count = layers
	_emergent_count = emergent_count
	_rng.seed = 2076 + layers * 31
	_positions.clear()
	_velocities.clear()
	_layer_of.clear()
	_edges.clear()
	_emergent.clear()
	_custom.clear()
	for layer in layers:
		var x := -LAYER_SPAN * 0.5 + LAYER_SPAN * float(layer) / float(maxi(1, layers - 1))
		var count := NODES_PER_LAYER - (2 if layer == 0 or layer == layers - 1 else 0)
		for i in count:
			var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.2, 0.2)
			var radius := 0.8 + _rng.randf_range(-0.25, 0.35)
			_positions.append(Vector3(x, sin(angle) * radius, cos(angle) * radius))
			_velocities.append(Vector3.ZERO)
			_layer_of.append(layer)
			_emergent.append(false)
	# Each neuron projects to 2-3 neurons in the next layer.
	for i in _positions.size():
		var layer := _layer_of[i]
		if layer >= layers - 1:
			continue
		var candidates: Array[int] = []
		for j in _positions.size():
			if _layer_of[j] == layer + 1:
				candidates.append(j)
		candidates.sort_custom(func(a: int, b: int) -> bool:
			return _positions[i].distance_squared_to(_positions[a]) < _positions[i].distance_squared_to(_positions[b]))
		var links := 2 + (_rng.randi() % 2)
		for k in mini(links, candidates.size()):
			_edges.append(Vector2i(i, candidates[k]))
	# Emergent capabilities surface in the deeper half of the network.
	var deep: Array[int] = []
	for i in _positions.size():
		if float(_layer_of[i]) >= float(layers) * 0.5:
			deep.append(i)
	for k in mini(emergent_count, deep.size()):
		_emergent[deep[(k * 7 + 3) % deep.size()]] = true
	for i in _positions.size():
		_custom.append(Color(_rng.randf(), _rng.randf(), 1.0 if _emergent[i] else 0.0,
			float(_layer_of[i]) / float(maxi(1, layers - 1))))
	_node_multimesh.instance_count = _positions.size()
	_relax_left = RELAX_STEPS
	_sync_meshes()


func _process(delta: float) -> void:
	_drift = lerpf(_drift, _target_drift, clampf(delta * 1.5, 0.0, 1.0))
	if _relax_left > 0:
		for _i in 2:
			_force_step(0.04)
		_relax_left -= 2
		_sync_meshes()
	var hot := CyberPalette.CYAN.lerp(CyberPalette.CRIMSON, smoothstep(0.2, 0.85, _drift))
	_node_material.set_shader_parameter("drift_level", _drift)
	_node_material.set_shader_parameter("activity", _activity)
	_edge_material.set_shader_parameter("line_color", hot)
	_edge_material.set_shader_parameter("flow_speed", 0.25 + 1.2 * _activity)
	_landscape_material.set_shader_parameter("drift_level", _drift)
	_graph_root.rotate_y(delta * 0.05)


## One explicit-Euler step of the force-directed layout: springs along
## synapses, repulsion within a layer, anchoring to the layer plane.
func _force_step(dt: float) -> void:
	var count := _positions.size()
	var forces: Array[Vector3] = []
	forces.resize(count)
	for i in count:
		forces[i] = Vector3.ZERO
	for i in count:
		for j in range(i + 1, count):
			if _layer_of[i] != _layer_of[j]:
				continue
			var d := _positions[i] - _positions[j]
			var dist2 := maxf(d.length_squared(), 0.02)
			var push := d / dist2 * 0.12
			forces[i] += push
			forces[j] -= push
	for edge in _edges:
		var d := _positions[edge.y] - _positions[edge.x]
		var dist := maxf(d.length(), 0.001)
		var pull := d / dist * (dist - SPRING_REST) * 0.9
		forces[edge.x] += pull
		forces[edge.y] -= pull
	for i in count:
		var p := _positions[i]
		var layer_x := -LAYER_SPAN * 0.5 + LAYER_SPAN * float(_layer_of[i]) / float(maxi(1, layer_count - 1))
		forces[i] += Vector3((layer_x - p.x) * 6.0, -p.y * 0.35, -p.z * 0.35)
		_velocities[i] = (_velocities[i] + forces[i] * dt) * 0.86
		_positions[i] = p + _velocities[i] * dt


func _sync_meshes() -> void:
	for i in _positions.size():
		var scale := 1.6 if _emergent[i] else 1.0
		_node_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), _positions[i]))
		_node_multimesh.set_instance_custom_data(i, _custom[i])
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for edge_index in _edges.size():
		var edge := _edges[edge_index]
		var offset := fmod(float(edge_index) * 0.618, 1.0)
		vertices.append(_positions[edge.x])
		vertices.append(_positions[edge.y])
		uvs.append(Vector2(0.0, offset))
		uvs.append(Vector2(1.0, offset))
		var alpha := 1.0 if _emergent[edge.x] or _emergent[edge.y] else 0.7
		colors.append(Color(1, 1, 1, alpha))
		colors.append(Color(1, 1, 1, alpha))
	GlobeViewport._fill_line_mesh(_edge_instance.mesh as ArrayMesh, vertices, uvs, colors)


func _build_landscape() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.5, 5.0)
	plane.subdivide_width = 90
	plane.subdivide_depth = 60
	_landscape_material = ShaderMaterial.new()
	_landscape_material.shader = LandscapeShader
	plane.material = _landscape_material
	var landscape := MeshInstance3D.new()
	landscape.name = "LossLandscape"
	landscape.mesh = plane
	landscape.position = Vector3(0, -1.75, 0)
	add_child(landscape)
