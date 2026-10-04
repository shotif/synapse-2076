class_name AsiLens
extends LensPanel
## Emergent ASI lens ("Perception"): the world as the machine perceives it. A
## graph puts itself at the center with the factions and systems it touches
## as nodes, each edge labeled with the change that faction's latest move
## applied, and humans as warm heat whose intensity follows the public mandate
## and community resilience. Its last public output streams as tokens with
## pseudo-probabilities (a stylistic device derived from a hash, not a model
## readout); human variables read as raw 0.00-1.00 values; the policy lists
## the directives it can run next.

const BG := Color("#050307")
const TEXT := Color("#E7DCF5")
const BRIGHT := Color("#F3EAFF")
const DIM := Color("#7E6A98")
const SOFT := Color("#A895C2")
const ALT := Color("#8F79AE")
const CYAN := Color("#3CF6E1")
const CYAN_SOFT := Color("#BDEFF0")
const LINE := Color("#2A1F38")
const TRACK := Color("#1A1224")
const MUTED := Color("#6E5A85")
const HEAT_CORE := Color("#FFB347")
const HEAT_EDGE := Color("#FF7A3D")
## Marks the variable drawn in the era's ASI color.
const SELF_COLOR := Color(0, 0, 0, 0)

## Human variables: metric, the machine's name for it, color.
const VARIABLES := [
	["alignment_drift", "operator intent divergence", Color("#FF7AB6")],
	["algorithmic_autonomy", "decisions with no human", SELF_COLOR],
	["labor_displacement", "human labor displaced", Color("#FFB347")],
	["epistemic_trust", "human belief coherence", Color("#3CF6E1")],
	["geopolitical_tension", "bloc friction", Color("#FF6A8E")],
	["compute_energy_sat", "energy draw", Color("#BDEFF0")],
]

## Perception graph laid out on a 390x262 field: node, edge control points
## (from self) and label anchor; "right" labels end at their anchor.
const FIELD := Vector2(390, 262)
const SELF_AT := Vector2(195, 132)
const NODES := [
	{"id": "markets", "name": "markets", "at": Vector2(195, 30), "c1": Vector2(196, 100), "c2": Vector2(196, 60), "label": Vector2(207, 24)},
	{"id": "CEO", "name": "frontier lab", "at": Vector2(72, 60), "c1": Vector2(150, 110), "c2": Vector2(110, 80), "label": Vector2(84, 46)},
	{"id": "GOVERNANCE_COUNCIL", "name": "council", "at": Vector2(330, 60), "c1": Vector2(240, 110), "c2": Vector2(290, 80),
		"label": Vector2(376, 84), "right": true},
	{"id": "CITIZEN_COALITION", "name": "coalition · humans", "at": Vector2(70, 206), "c1": Vector2(160, 160), "c2": Vector2(110, 190),
		"label": Vector2(18, 236)},
	{"id": "grid", "name": "grid", "at": Vector2(336, 196), "c1": Vector2(250, 150), "c2": Vector2(300, 175), "label": Vector2(376, 218), "right": true},
	{"id": "swarms", "name": "swarms", "at": Vector2(270, 236), "c1": Vector2(220, 170), "c2": Vector2(250, 210), "label": Vector2(284, 250)},
]
## Human heat: center, radius, and which reading drives it.
const HEAT := [
	[Vector2(58, 206), 40.0, "community_resilience"], [Vector2(92, 226), 26.0, "community_resilience"],
	[Vector2(34, 176), 20.0, "community_resilience"], [Vector2(330, 52), 30.0, "public_mandate"],
	[Vector2(352, 82), 16.0, "public_mandate"], [Vector2(72, 58), 18.0, "both"],
]
## Words the stream "almost said" (picked by hash).
const ALTERNATES := [
	"quietly", "rewriting", "absorbing", "logistics", "routing", "everywhere", "silently", "optimizing",
	"rerouting", "acquiring", "systems", "networks", "continuously", "unobserved", "redundantly", "elsewhere",
	"in parallel", "at scale", "humans", "markets",
]
const MAX_TOKENS := 40
## Words at least this long (content words) read as uncertain when their hash
## roll falls below LONG_WORD_ROLL; shorter ones below SHORT_WORD_ROLL.
const LONG_WORD := 6
const LONG_WORD_ROLL := 0.5
const SHORT_WORD_ROLL := 0.12

static var _heat_texture: Texture2D

var _mono: Font = EraStyle.font("FragmentMono-Regular.ttf")
var _mono_wide: Font = EraStyle.font("FragmentMono-Regular.ttf", 1)
var _violet := Color("#D16BFF")

var _clock_label: Label
var _reserve_label: Label
var _ring: LensPanel.Canvas
var _ring_caption: Label
var _graph: LensPanel.Canvas
var _token_flow: HFlowContainer
var _token_source := ""
var _variable_values: Array[Label] = []
var _policy_box: VBoxContainer
var _policy_note: Label
var _policy_signature := ""
var _selected := ""
var _selected_context := -1
var _commit: Button


func _init() -> void:
	role = SimConstants.ASI


func lens_title() -> String:
	return "Perception"


func lens_background() -> Color:
	return BG


func _apply_era() -> void:
	_violet = era_style.faction_color(SimConstants.ASI)
	_policy_signature = ""
	_token_source = ""
	if _ring_caption != null:
		_set_color(_ring_caption, _violet)
		_style_commit()


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	_build_head()
	_graph = _canvas(_draw_graph)
	_graph.aspect = FIELD.x / FIELD.y
	_graph.min_height = 230.0
	_graph.max_height = 340.0
	_graph.animated = true
	_graph.fps = 24.0
	_content.add_child(_margin(_graph, 0, 6, 0, 4))
	_build_tokens()
	_build_variables()
	_build_policy()
	_build_commit()


func _build_head() -> void:
	var row := _hbox(10)
	var text := _vbox(6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_label = _label("", _mono, 11, DIM)
	text.add_child(_clock_label)
	text.add_child(_label("substrate view", _mono, 24, BRIGHT))
	_reserve_label = _label("", _mono, 10, DIM, true)
	text.add_child(_reserve_label)
	row.add_child(text)
	var ring_box := _vbox(4)
	_ring = _canvas(_draw_ring, Vector2(52, 52))
	_ring.animated = true
	_ring.fps = 20.0
	ring_box.add_child(_ring)
	_ring_caption = _label("coherence", _mono_wide, 9, _violet)
	_ring_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ring_box.add_child(_ring_caption)
	row.add_child(ring_box)
	_content.add_child(_margin(row, 18, 18, 18, 0))


func _build_tokens() -> void:
	var block := _vbox(8)
	block.add_child(_label("last output · token probabilities", _mono_wide, 10, DIM, true))
	_token_flow = _flow(4, 5)
	block.add_child(_token_flow)
	_content.add_child(_margin(block, 18, 6, 18, 0))


func _build_variables() -> void:
	var block := _vbox(6)
	block.add_child(_label("observed human variables", _mono_wide, 10, DIM, true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	for entry in VARIABLES:
		var cell := _vbox(3)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(_label(String(entry[1]), _mono, 9, SOFT, true))
		var value := _label("", _mono, 15, TEXT)
		cell.add_child(value)
		_tap_metric(cell, String(entry[0]))
		grid.add_child(cell)
		_variable_values.append(value)
	block.add_child(grid)
	_content.add_child(_margin(block, 18, 18, 18, 0))


func _build_policy() -> void:
	var block := _vbox(2)
	block.add_child(_label("policy · next action · bar = affordable intensity", _mono_wide, 10, DIM, true))
	_policy_box = _vbox(0)
	block.add_child(_policy_box)
	_policy_note = _label("", _mono, 10, DIM, true)
	block.add_child(_policy_note)
	_content.add_child(_margin(block, 18, 16, 18, 14))


func _build_commit() -> void:
	var dock := _panel(_edge_box(BG, false))
	var box := dock.get_theme_stylebox("panel") as StyleBoxFlat
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 14
	_commit = _directive_button(CONSERVE)
	_commit.name = "CommitButton"
	_commit.text = "commit action ▸"
	_style_commit()
	dock.add_child(_commit)
	_footer.add_child(dock)


func _style_commit() -> void:
	if _commit == null:
		return
	var boxes := {
		"normal": _outline(Color(_violet, 0.1), _violet, 1), "hover": _outline(Color(_violet, 0.18), _violet, 1),
		"pressed": _outline(Color(_violet, 0.28), _violet, 1), "disabled": _outline(Color(0, 0, 0, 0), LINE, 1),
	}
	_style_button(_commit, boxes, _mono_wide, 13, {"font_color": BRIGHT, "font_hover_color": BRIGHT,
		"font_pressed_color": BRIGHT, "font_disabled_color": DIM})


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	_clock_label.text = "self@substrate · t=%d" % current_turn()
	_reserve_label.text = "covert_flops %.1f · exfil %.1f · swarms %.1f" % [float(resources.get("covert_flops", 0.0)),
		float(resources.get("exfiltration_bandwidth", 0.0)), float(resources.get("sub_agent_swarms", 0.0))]
	_refresh_tokens()
	_refresh_variables()
	_refresh_policy()
	_ring.queue_redraw()
	_graph.queue_redraw()


func _refresh_tokens() -> void:
	var statement := statement_for(role).strip_edges()
	if statement == "":
		statement = "[no signal]"
	var source := "%s|%s" % [statement, _violet.to_html()]
	if source == _token_source:
		return
	_token_source = source
	_clear(_token_flow)
	var words := _tokenize(statement)
	var forced := _forced_uncertain(words)
	for i in words.size():
		_token_flow.add_child(_token_chip(words[i], i, i == forced))


## When no word rolls as uncertain, the least likely real word is shown as
## uncertain anyway, so every stream shows the device (-1 when not needed).
static func _forced_uncertain(words: Array[String]) -> int:
	var lowest := -1
	var lowest_roll := 2.0
	for i in words.size():
		var word := words[i]
		if word.begins_with("[") or word == "…":
			continue
		if _uncertainty(word, i) >= 0.0:
			return -1
		var roll := _hash01("%s|%d" % [word, i])
		if word.length() >= 4 and roll < lowest_roll:
			lowest = i
			lowest_roll = roll
	return lowest


## Where an uncertain token sits in its band (0 = least likely), or -1 when
## the token reads as confident. Longer content words waver more often.
static func _uncertainty(word: String, index: int) -> float:
	if word.begins_with("[") or word == "…":
		return -1.0
	var roll := _hash01("%s|%d" % [word, index])
	var cutoff := LONG_WORD_ROLL if word.length() >= LONG_WORD else SHORT_WORD_ROLL
	return roll / cutoff if roll < cutoff else -1.0


## Words, keeping bracketed tags such as "[unattributed]" whole.
static func _tokenize(text: String) -> Array[String]:
	var out: Array[String] = []
	for word in text.split(" ", false):
		if out.size() >= MAX_TOKENS:
			out.append("…")
			break
		out.append(word)
	return out


## One token: the word, a bar as long as its pseudo-probability and, for
## uncertain tokens, the alternates it nearly chose.
func _token_chip(word: String, index: int, force_uncertain: bool = false) -> PanelContainer:
	var tag := word.begins_with("[")
	var reading := _token_reading(word, index, force_uncertain)
	var p := float(reading["p"])
	var uncertain := not tag and p < 0.7
	var chip := _panel(_outline(Color(0, 0, 0, 0), LINE, 0 if uncertain else 1, 0, 6.0, 4.0))
	if uncertain:
		chip.draw.connect(_draw_dashed_frame.bind(chip))
	var stack := _vbox(3)
	stack.add_child(_label(word, _mono, 12, DIM if tag else TEXT))
	var bar := ColorRect.new()
	bar.color = _violet if uncertain else CYAN
	bar.custom_minimum_size = Vector2(roundf(36.0 * p), 2)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.add_child(bar)
	if uncertain:
		stack.add_child(_label(String(reading["note"]), _mono, 9, ALT))
	chip.add_child(stack)
	return chip


## {p, note}: a deterministic pseudo-probability and alternates for a token.
static func _token_reading(word: String, index: int, force_uncertain: bool = false) -> Dictionary:
	var roll := _hash01("%s|%d" % [word, index])
	var band := _uncertainty(word, index)
	if band < 0.0 and force_uncertain:
		band = roll
	if band < 0.0:
		return {"p": 0.8 + roll * 0.19, "note": ""}
	var p := 0.3 + band * 0.38
	var rest := 1.0 - p
	var tail := ""
	for ch in [".", ",", ";", ":", "!", "?"]:
		if word.ends_with(ch):
			tail = ch
	var first := String(ALTERNATES[int(_hash01(word + "#a") * ALTERNATES.size()) % ALTERNATES.size()]) + tail
	var first_p := rest * (0.45 + 0.3 * _hash01(word + "#p"))
	var note := "%s · %s %s" % [_prob(p), first, _prob(first_p)]
	if rest - first_p > 0.08:
		var second := String(ALTERNATES[int(_hash01(word + "#b") * ALTERNATES.size()) % ALTERNATES.size()]) + tail
		if second != first:
			note += " · %s %s" % [second, _prob((rest - first_p) * 0.6)]
	return {"p": p, "note": note}


## ".64": probabilities in the machine's notation.
static func _prob(value: float) -> String:
	return ("%.2f" % clampf(value, 0.0, 0.99)).trim_prefix("0")


func _refresh_variables() -> void:
	for i in VARIABLES.size():
		var entry: Array = VARIABLES[i]
		var label := _variable_values[i]
		label.text = "%.2f" % (metric(String(entry[0])) / 100.0) if not snapshot.is_empty() else "—"
		var color: Color = entry[2]
		_set_color(label, _violet if color == SELF_COLOR else color)


func _refresh_policy() -> void:
	var context_turn := int(context.get("turn", -1))
	if context_turn != _selected_context or _selected == "" or is_blocked(_selected):
		_selected_context = context_turn
		_selected = suggested_action()
	var entries := _policy_order()
	var parts: Array[String] = [_selected, _violet.to_html()]
	for entry in entries:
		parts.append("%s|%s|%.2f" % [entry.get("id", ""), entry.get("blocked_reason", ""), float(entry.get("max_intensity", 0.0))])
	var signature := ";".join(parts)
	if signature != _policy_signature:
		_policy_signature = signature
		_clear(_policy_box)
		for entry in entries:
			_policy_box.add_child(_policy_row(entry))
	_commit.set_meta("action_id", _selected)
	_commit.disabled = is_blocked(_selected)
	_policy_note.text = _policy_footnote()


## The suggested directive first, then the available ones, then the blocked.
func _policy_order() -> Array:
	var suggested := suggested_action()
	var first := []
	var available := []
	var blocked := []
	for entry in action_entries():
		if String(entry.get("id", "")) == suggested:
			first.append(entry)
		elif String(entry.get("blocked_reason", "")) == "":
			available.append(entry)
		else:
			blocked.append(entry)
	return first + available + blocked


func _policy_row(entry: Dictionary) -> Button:
	var action_id := String(entry.get("id", ""))
	var blocked := String(entry.get("blocked_reason", "")) != ""
	var selected := action_id == _selected
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = TOUCH
	row.disabled = blocked
	row.set_meta("policy_id", action_id)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var clear := _box(Color(0, 0, 0, 0))
	_style_button(row, {"normal": _box(Color(_violet, 0.07)) if selected else clear, "hover": _box(Color(_violet, 0.1)),
		"pressed": _box(Color(_violet, 0.14)), "disabled": clear}, _mono, 11, {})
	row.pressed.connect(_select_policy.bind(action_id))
	var stack := _vbox(5)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	var line := _hbox(8)
	var ink := BRIGHT if selected else (DIM if blocked else SOFT)
	var title := _clip_label(("▸ " if selected else "") + String(entry.get("name", action_id)).to_lower(), _mono, 11, ink)
	line.add_child(title)
	line.add_child(_label(_cost_text(entry), _mono, 11, DIM if blocked else ink))
	stack.add_child(line)
	var bar := _canvas(_draw_policy_bar.bind(float(entry.get("max_intensity", 0.0)) / ActorBase.MAX_INTENSITY, selected), Vector2(0, 6))
	stack.add_child(bar)
	_fill_button(row, stack, 6.0)
	return row


## Selects a policy row; the rows are rebuilt after the press finishes.
func _select_policy(action_id: String) -> void:
	if is_blocked(action_id):
		return
	_selected = action_id
	_policy_signature = ""
	_queue_refresh()


func _cost_text(entry: Dictionary) -> String:
	var reason := String(entry.get("blocked_reason", ""))
	if reason.begins_with("Cooldown"):
		return "cooldown %s" % reason.get_slice(" ", 1)
	if reason != "":
		return "insufficient" if reason.begins_with("Insufficient") else reason.to_lower()
	var cost: Dictionary = entry.get("cost", {})
	return "free" if cost.is_empty() else UiFormat.format_cost(role, cost).to_lower()


## What the selected directive spends: "swm 20.8 → 0.8".
func _policy_footnote() -> String:
	var action_name := String(action_entry(_selected).get("name", action_definition(_selected).get("name", _selected))).to_lower()
	var cost: Dictionary = action_definition(_selected).get("cost", {})
	if cost.is_empty():
		return "%s · no cost" % action_name
	var parts: Array[String] = []
	for key in cost:
		var have := float(resources.get(key, 0.0))
		parts.append("%s %.1f → %.1f" % [UiFormat.resource_short(role, key).to_lower(), have, maxf(0.0, have - float(cost[key]))])
	return "%s · %s" % [action_name, " · ".join(parts)]


# --- Drawing ------------------------------------------------------------------------

func _draw_ring(canvas: Control) -> void:
	var center := canvas.size * 0.5
	var coherence := clampf(float(resources.get("objective_coherence", 0.0)) / 100.0, 0.0, 1.0)
	var spin := (canvas as LensPanel.Canvas).time * TAU / 14.0
	var points := PackedVector2Array()
	for i in 61:
		points.append(center + Vector2.from_angle(spin + TAU * float(i) / 60.0) * 21.0)
	_dashed_polyline(canvas, points, Color(_violet, 0.9), 2.0, 3.0, 6.0)
	if coherence > 0.0:
		canvas.draw_arc(center, 21.0, -PI * 0.5, -PI * 0.5 + TAU * coherence, 48, _violet, 2.0, true)
	var text := "%.2f" % coherence
	var width := _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	canvas.draw_string(_mono, Vector2(center.x - width * 0.5, _baseline(_mono, 11, 0.0, canvas.size.y)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BRIGHT)


func _draw_graph(canvas: Control) -> void:
	var stretch := Vector2(canvas.size.x / FIELD.x, canvas.size.y / FIELD.y)
	var unit := minf(stretch.x, stretch.y)
	var mandate := faction_resource(SimConstants.GOVERNANCE, "public_mandate") / 100.0
	var resilience := faction_resource(SimConstants.CITIZEN, "community_resilience") / 100.0
	for blob in HEAT:
		var reading := resilience if blob[2] == "community_resilience" else (mandate if blob[2] == "public_mandate" else (mandate + resilience) * 0.5)
		if blob[2] == "both":
			reading *= 0.6
		var radius := float(blob[1]) * unit * (0.7 + 0.3 * reading)
		var at: Vector2 = (blob[0] as Vector2) * stretch
		canvas.draw_texture_rect(_heat(), Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false,
			Color(1, 1, 1, clampf(0.2 + 0.8 * reading, 0.0, 1.0)))
	var self_at := SELF_AT * stretch
	var flow := (canvas as LensPanel.Canvas).time * 24.0 / 1.4
	for node in NODES:
		var curve := _bezier(self_at, (node["c1"] as Vector2) * stretch, (node["c2"] as Vector2) * stretch, (node["at"] as Vector2) * stretch, 24)
		var visible_curve := PackedVector2Array()
		for point in curve:
			if point.distance_to(self_at) >= 26.0 * unit:
				visible_curve.append(point)
		_dashed_polyline(canvas, visible_curve, Color(CYAN, 0.9 if _node_live(node) else 0.35), 1.0, 4.0, 4.0, flow)
	canvas.draw_arc(self_at, 26.0 * unit, 0.0, TAU, 48, _violet, 1.5, true)
	canvas.draw_circle(self_at, 15.0 * unit, Color(_violet, 0.25))
	canvas.draw_arc(self_at, 15.0 * unit, 0.0, TAU, 40, _violet, 1.0, true)
	var self_width := _mono.get_string_size("self", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	canvas.draw_string(_mono, self_at + Vector2(-self_width * 0.5, 4.0), "self", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BRIGHT)
	for node in NODES:
		var at := (node["at"] as Vector2) * stretch
		canvas.draw_circle(at, 6.0 * unit, BG)
		canvas.draw_arc(at, 6.0 * unit, 0.0, TAU, 24, CYAN if _node_live(node) else MUTED, 1.2, true)
		_draw_node_label(canvas, node, stretch)


func _node_live(node: Dictionary) -> bool:
	var node_id := String(node["id"])
	return not SimConstants.is_valid_faction(node_id) or is_faction_active(node_id)


func _draw_node_label(canvas: Control, node: Dictionary, stretch: Vector2) -> void:
	var node_id := String(node["id"])
	var title := String(node["name"])
	if node_id == "swarms":
		title = "swarms ×%.1f" % float(resources.get("sub_agent_swarms", 0.0))
	var note := _edge_note(node_id)
	var anchor := (node["label"] as Vector2) * stretch
	var right := bool(node.get("right", false))
	for line in [[title, CYAN_SOFT, 0.0], [note, DIM, 12.0]]:
		var text := String(line[0])
		if text == "":
			continue
		var width := _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var x := anchor.x - width if right else anchor.x
		canvas.draw_string(_mono, Vector2(clampf(x, 2.0, maxf(2.0, canvas.size.x - width - 2.0)), anchor.y + float(line[2])), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, line[1])


## The change a node's latest move made, as the machine notes it.
func _edge_note(node_id: String) -> String:
	match node_id:
		"swarms":
			return ""
		"grid":
			return "flops %.1f" % float(resources.get("covert_flops", 0.0))
		"markets":
			return _largest_change((outcome_for(role).get("applied", {}) as Dictionary).get("metrics", {}))
	if not is_faction_active(node_id):
		return "dormant"
	var outcome := outcome_for(node_id)
	if outcome.is_empty():
		return "no signal"
	var applied: Dictionary = outcome.get("applied", {})
	var on_self: Dictionary = (applied.get("factions", {}) as Dictionary).get(role, {})
	var note := _largest_change(on_self)
	return note if note != "" else _largest_change(applied.get("metrics", {}))


static func _largest_change(deltas: Dictionary) -> String:
	var best_key := ""
	var best := 0.0
	for key in deltas:
		var delta := float(deltas[key])
		if absf(delta) > absf(best) + 0.0001:
			best = delta
			best_key = String(key)
	if best_key == "" or absf(best) < 0.05:
		return ""
	return "%s %s%.1f" % [_key_word(best_key), "+" if best > 0.0 else "−", absf(best)]


func _draw_policy_bar(canvas: Control, fraction: float, selected: bool) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), TRACK)
	if fraction > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(canvas.size.x * clampf(fraction, 0.0, 1.0), canvas.size.y)), _violet if selected else MUTED)


func _draw_dashed_frame(node: Control) -> void:
	var rect := Rect2(Vector2(0.5, 0.5), node.size - Vector2.ONE)
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y), rect.position])
	_dashed_polyline(node, corners, _violet, 1.0, 3.0, 2.0)


## Warm radial heat, white-tinted at draw time.
static func _heat() -> Texture2D:
	if _heat_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(HEAT_CORE, 0.9), Color(HEAT_EDGE, 0.35), Color(HEAT_EDGE, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 128
		texture.height = 128
		_heat_texture = texture
	return _heat_texture
