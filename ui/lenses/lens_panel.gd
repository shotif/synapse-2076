class_name LensPanel
extends PanelContainer
## "Each faction sees a different world": the same simulation state seen
## through the instruments, voice and priorities of the player's faction. The
## Frontier Lab reads a trading terminal, the Governance Chair a daily brief,
## the emergent ASI its raw perception and the Citizen Coalition a civic social
## network. Lenses only display data; their buttons ask the dashboard to open
## the ACT panel with a directive selected.
##
##   var lens := LensPanel.create(engine.player_role)
##   engine.event_logged.connect(lens.record_event)
##   lens.update_state(engine.get_snapshot(), engine.get_player().resources)
##   lens.set_context(context)  # SimulationEngine.get_player_context()
##   lens.directive_requested.connect(_open_act_with_directive)
##
## A lens keeps its own typography and palette; its frame (corner shape and
## border) follows the hardware era of the surrounding theme. Its text follows
## the player's text size and plain-language setting. Subclasses build their
## sections once in _build() and fill them in _refresh(); widgets that show a
## metric or index call _tap_metric() so a tap emits metric_pressed. Text is
## translated as it is built (tr()); the dashboard builds a new lens when the
## language changes. lens_title() returns an English message id.

## Asks the dashboard to open ACT with [param action_id] (a directive of this
## lens's role) selected.
signal directive_requested(action_id: String)
## The player tapped a metric or index this lens shows (the dashboard explains
## its change in a WhyPopup).
signal metric_pressed(metric_key: String)

## Samples of the player's currencies kept for sparklines and charts.
const HISTORY_LIMIT := 40
const EVENT_LIMIT := 80
const CONSERVE := "CONSERVE_RESOURCES"
## Minimum height of anything a finger has to hit.
const TOUCH := 44.0
## A press that moves further than this is a drag (scrolling), not a tap.
const TAP_SLOP := 12.0
## Short lowercase names for currencies in the lenses' plain voice.
const KEY_WORDS := {
	"capital": "capital", "talent": "talent", "compute_clusters": "clusters", "regulatory_goodwill": "goodwill",
	"political_capital": "political", "enforcement_budget": "enforcement", "diplomatic_leverage": "diplomacy",
	"public_mandate": "mandate", "covert_flops": "flops", "exfiltration_bandwidth": "exfil",
	"sub_agent_swarms": "swarms", "objective_coherence": "coherence", "community_resilience": "resilience",
	"decentralized_scrip": "scrip", "counter_surveillance": "counter-surveillance", "collective_disruption": "disruption",
}

var role := ""
## True in the phone and tablet layouts (full-width tab, no scroll bar).
var compact := false
## One sample per update_state(): {turn, year, resources, metrics, indices}.
var history: Array[Dictionary] = []
## Recent log entries (SimulationEngine.event_log format), oldest first.
var events: Array[Dictionary] = []
## The latest SimulationEngine.get_snapshot().
var snapshot := {}
## The player's currencies at the latest update.
var resources := {}
## The latest SimulationEngine.get_player_context(), plus the optional
## "suggested_action" the dashboard adds.
var context := {}
## The era style of the surrounding theme.
var era_style: EraStyle = EraStyle.for_era(1)

var _built := false
var _building := false
var _styling := false
var _refresh_queued := false
var _latest_outcomes := {}
var _frame_box: StyleBoxFlat
var _root: VBoxContainer
var _header: VBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: VBoxContainer
var _overlay: Control


## The lens for [param role_id] (a SimConstants faction id), or null.
static func create(role_id: String) -> LensPanel:
	match role_id:
		SimConstants.CEO:
			return CeoLens.new()
		SimConstants.GOVERNANCE:
			return GovLens.new()
		SimConstants.ASI:
			return AsiLens.new()
		SimConstants.CITIZEN:
			return CitizenLens.new()
	push_error("LensPanel: no lens for role '%s'" % role_id)
	return null


# --- Public API ------------------------------------------------------------------

## Tab label for the dashboard (an English message id).
func lens_title() -> String:
	return I18n.mark("Lens")


## Glyph name (see Glyphs) for the lens tab.
func lens_glyph() -> String:
	return Glyphs.for_faction(role)


## Feeds a new SimulationEngine.get_snapshot() and the player's currencies.
## Every call appends one sample to [member history].
func update_state(new_snapshot: Dictionary, player_resources: Dictionary) -> void:
	_ensure_built()
	var turn := int(new_snapshot.get("turn", 0))
	if not history.is_empty() and turn < int(history[-1]["turn"]):
		# A new campaign is being fed into this lens.
		history.clear()
		_latest_outcomes.clear()
		var kept: Array[Dictionary] = []
		for entry in events:
			if int(entry.get("turn", 0)) <= turn:
				kept.append(entry)
		events = kept
	snapshot = new_snapshot
	resources = player_resources.duplicate()
	history.append({
		"turn": turn,
		"year": float(new_snapshot.get("year", SimConstants.year_for_turn(turn))),
		"resources": resources.duplicate(),
		"metrics": (new_snapshot.get("metrics", {}) as Dictionary).duplicate(),
		"indices": (new_snapshot.get("indices", {}) as Dictionary).duplicate(),
	})
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	var actions: Dictionary = new_snapshot.get("turn_actions", {})
	for faction_id in actions:
		_latest_outcomes[faction_id] = actions[faction_id]
	_refresh_now()


## Records a log entry (SimulationEngine.event_logged). The lens redraws once
## per frame at most, however many entries arrive.
func record_event(entry: Dictionary) -> void:
	_ensure_built()
	events.append(entry)
	while events.size() > EVENT_LIMIT:
		events.pop_front()
	_queue_refresh()


## Feeds the player phase context (directives with costs and blocked reasons).
func set_context(new_context: Dictionary) -> void:
	_ensure_built()
	context = new_context.duplicate()
	_refresh_now()


## Phone and tablet layout (a full-width tab): hides the scroll bar, since
## touch screens scroll by dragging. Desktop columns keep a thin bar.
func set_compact(enabled: bool) -> void:
	_ensure_built()
	compact = enabled
	# Phones scroll by dragging; a scroll bar would push full-width content off-screen.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if enabled else ScrollContainer.SCROLL_MODE_AUTO
	_compact_changed()
	_refresh_now()


## Forgets every sample, event and context (for reuse in a new campaign).
func reset() -> void:
	history.clear()
	events.clear()
	snapshot = {}
	resources = {}
	context = {}
	_latest_outcomes.clear()
	if _built:
		_refresh_now()


# --- Subclass hooks ----------------------------------------------------------------

## Background behind the era frame.
func lens_background() -> Color:
	return Color.BLACK


## Builds the sections into [member _header], [member _content] and [member _footer].
func _build() -> void:
	pass


## Fills every section from snapshot, resources, context, events and history.
func _refresh() -> void:
	pass


## Re-applies colors that follow the era (called when the theme changes).
func _apply_era() -> void:
	pass


func _compact_changed() -> void:
	pass


# --- Data helpers -------------------------------------------------------------------

func current_turn() -> int:
	return int(snapshot.get("turn", 0))


func current_year() -> float:
	return float(snapshot.get("year", SimConstants.year_for_turn(current_turn())))


## "H1 2056" for the first half of 2056.
func half_label() -> String:
	var year := current_year()
	return tr("H%d %d") % [2 if year - floorf(year) >= 0.25 else 1, int(floorf(year))]


func metric(key: String) -> float:
	return float((snapshot.get("metrics", {}) as Dictionary).get(key, 0.0))


func index_value(key: String) -> float:
	return float((snapshot.get("indices", {}) as Dictionary).get(key, 0.0))


func faction_data(faction_id: String) -> Dictionary:
	return (snapshot.get("factions", {}) as Dictionary).get(faction_id, {})


func faction_resource(faction_id: String, key: String) -> float:
	if faction_id == role and resources.has(key):
		return float(resources[key])
	return float((faction_data(faction_id).get("resources", {}) as Dictionary).get(key, 0.0))


func is_faction_active(faction_id: String) -> bool:
	return String(faction_data(faction_id).get("status", ActorBase.STATUS_ACTIVE)) == ActorBase.STATUS_ACTIVE


## The faction's directive outcome this turn, or the latest one this lens saw.
func outcome_for(faction_id: String) -> Dictionary:
	var actions: Dictionary = snapshot.get("turn_actions", {})
	if actions.has(faction_id):
		return actions[faction_id]
	return _latest_outcomes.get(faction_id, {})


## True when [method outcome_for] is from the current turn.
func outcome_is_current(faction_id: String) -> bool:
	return (snapshot.get("turn_actions", {}) as Dictionary).has(faction_id)


## The faction's latest public statement.
func statement_for(faction_id: String) -> String:
	var outcome := outcome_for(faction_id)
	if not outcome.is_empty():
		return String(outcome.get("public_statement", ""))
	return String(faction_data(faction_id).get("last_statement", ""))


## The sample from the latest update of an earlier turn ({} when none), so
## deltas read "since last turn" however often the dashboard updates.
func previous_sample() -> Dictionary:
	if history.size() < 2:
		return {}
	var current := int(history[-1]["turn"])
	for i in range(history.size() - 2, -1, -1):
		if int(history[i]["turn"]) < current:
			return history[i]
	return {}


func metric_delta(key: String) -> float:
	var before := previous_sample()
	if before.is_empty():
		return 0.0
	return metric(key) - float((before["metrics"] as Dictionary).get(key, metric(key)))


func index_delta(key: String) -> float:
	var before := previous_sample()
	if before.is_empty():
		return 0.0
	return index_value(key) - float((before.get("indices", {}) as Dictionary).get(key, index_value(key)))


func resource_delta(key: String) -> float:
	var before := previous_sample()
	if before.is_empty():
		return 0.0
	var now := float(resources.get(key, 0.0))
	return now - float((before["resources"] as Dictionary).get(key, now))


## One value per history sample.
func resource_series(key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for sample in history:
		out.append(float((sample["resources"] as Dictionary).get(key, 0.0)))
	return out


## The player's directives: {id, name, cost, blocked_reason, max_intensity}.
## Before the first player phase they are judged against the currencies alone.
func action_entries() -> Array:
	var listed: Array = context.get("actions", [])
	if not listed.is_empty():
		return listed
	var out := []
	var catalog := FactionRegistry.catalog_for(role)
	for action_id in catalog:
		var definition: Dictionary = catalog[action_id]
		var cost: Dictionary = definition.get("cost", {})
		var intensity := _affordable_intensity(cost)
		out.append({"id": action_id, "name": String(definition.get("name", action_id)), "cost": cost,
			"blocked_reason": "" if intensity > 0.0 else I18n.mark("Insufficient resources"), "max_intensity": intensity})
	return out


func action_entry(action_id: String) -> Dictionary:
	for entry in action_entries():
		if String(entry.get("id", "")) == action_id:
			return entry
	return {}


func action_definition(action_id: String) -> Dictionary:
	return FactionRegistry.catalog_for(role).get(action_id, {})


func is_blocked(action_id: String) -> bool:
	var entry := action_entry(action_id)
	return entry.is_empty() or String(entry.get("blocked_reason", "")) != ""


## The directive to put forward: the dashboard's suggestion when present,
## else the first available one, else conserving.
func suggested_action() -> String:
	var suggested := String(context.get("suggested_action", ""))
	if suggested != "" and FactionRegistry.catalog_for(role).has(suggested):
		return suggested
	for entry in action_entries():
		var action_id := String(entry.get("id", ""))
		if action_id != CONSERVE and String(entry.get("blocked_reason", "")) == "":
			return action_id
	return CONSERVE


## Emits [signal directive_requested] for a directive of this role.
func request_directive(action_id: String) -> void:
	if FactionRegistry.catalog_for(role).has(action_id):
		directive_requested.emit(action_id)


## Recent events, newest first, passing [param keep].
func recent_events(keep: Callable, limit: int = 8) -> Array:
	var out := []
	for i in range(events.size() - 1, -1, -1):
		if keep.call(events[i]):
			out.append(events[i])
			if out.size() >= limit:
				break
	return out


func _affordable_intensity(cost: Dictionary) -> float:
	if cost.is_empty():
		return 1.0
	var best := ActorBase.MAX_INTENSITY
	for key in cost:
		var need := float(cost[key])
		if need > 0.0:
			best = minf(best, float(resources.get(key, 0.0)) / need)
	return 0.0 if best + 0.0001 < ActorBase.MIN_INTENSITY else clampf(best, ActorBase.MIN_INTENSITY, ActorBase.MAX_INTENSITY)


# --- Frame ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_built()
	_refresh_now()
	GameSettings.instance().changed.connect(_on_game_setting_changed)


## Plain names and color-blind colors show at the next refresh.
func _on_game_setting_changed(key: String, _value: Variant) -> void:
	if key == "plain_language" or key == "colorblind":
		_queue_refresh()


## Makes [param control] report taps as [signal metric_pressed] with
## [param metric_key] (or, when empty, its "metric_key" meta, which a refresh
## can change). Drags still scroll the lens.
func _tap_metric(control: Control, metric_key: String = "") -> void:
	if metric_key != "":
		control.set_meta("metric_key", metric_key)
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not control.has_meta("metric_tap"):
		control.set_meta("metric_tap", true)
		control.gui_input.connect(_on_metric_input.bind(control))


func _on_metric_input(event: InputEvent, control: Control) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		control.set_meta("tap_from", button.global_position)
	elif control.has_meta("tap_from"):
		var start: Vector2 = control.get_meta("tap_from")
		control.remove_meta("tap_from")
		var key := String(control.get_meta("metric_key", ""))
		if key != "" and start.distance_to(button.global_position) <= TAP_SLOP:
			metric_pressed.emit(key)


func _notification(what: int) -> void:
	# The frame override set below notifies again; _styling stops the echo.
	if what == NOTIFICATION_THEME_CHANGED and not _styling and not _building:
		_ensure_built()
		_styling = true
		era_style = EraTheme.style_of(self)
		_apply_frame()
		_apply_era()
		_styling = false
		_refresh_now()


func _ensure_built() -> void:
	if _built or _building:
		return
	_building = true
	_styling = true
	if is_inside_tree():
		era_style = EraTheme.style_of(self)
	clip_contents = true
	# A lens fills its column unless the dashboard chose otherwise.
	if size_flags_horizontal == Control.SIZE_FILL:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if size_flags_vertical == Control.SIZE_FILL:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root = VBoxContainer.new()
	_root.name = "LensRoot"
	_root.add_theme_constant_override("separation", 0)
	add_child(_root)
	_header = _vbox(0)
	_header.name = "LensHeader"
	_root.add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.name = "LensScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_scroll)
	_content = _vbox(0)
	_content.name = "LensContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_footer = _vbox(0)
	_footer.name = "LensFooter"
	_root.add_child(_footer)
	_apply_frame()
	_build()
	_apply_era()
	_styling = false
	_building = false
	_built = true


## Layer above the lens for floating buttons (anchored by the subclass).
func _overlay_layer() -> Control:
	if _overlay == null:
		_overlay = Control.new()
		_overlay.name = "LensOverlay"
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overlay)
	return _overlay


## Re-applies the frame (after the background color changes).
func _restyle_frame() -> void:
	var was_styling := _styling
	_styling = true
	_apply_frame()
	_styling = was_styling


func _apply_frame() -> void:
	var s := era_style
	var box := EraTheme.panel(s, lens_background(), s.border, s.radius, 0.0)
	var inset := float(maxi(s.border_width, 0))
	box.content_margin_left = inset
	box.content_margin_right = inset
	box.content_margin_top = inset
	box.content_margin_bottom = inset
	_frame_box = box
	add_theme_stylebox_override("panel", box)
	var grabber := EraTheme.box(Color(_scrollbar_color(), 0.28), Color(0, 0, 0, 0), 0, 3, 3, 3)
	var bar := _scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", EraTheme.box(Color(_scrollbar_color(), 0.45), Color(0, 0, 0, 0), 0, 3, 3, 3))


## Scroll bar tint: light on dark lenses, dark on paper and light themes.
func _scrollbar_color() -> Color:
	return Color.WHITE if lens_background().get_luminance() < 0.5 else Color.BLACK


## A background for a header (top) or footer (bottom) band that follows the
## frame's rounded corners.
func _edge_box(bg: Color, top: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.corner_detail = era_style.corner_detail
	if _frame_box != null:
		var inset := maxi(era_style.border_width, 0)
		if top:
			box.corner_radius_top_left = maxi(0, _frame_box.corner_radius_top_left - inset)
			box.corner_radius_top_right = maxi(0, _frame_box.corner_radius_top_right - inset)
		else:
			box.corner_radius_bottom_left = maxi(0, _frame_box.corner_radius_bottom_left - inset)
			box.corner_radius_bottom_right = maxi(0, _frame_box.corner_radius_bottom_right - inset)
	return box


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()


func _flush_refresh() -> void:
	if _refresh_queued:
		_refresh_now()


func _refresh_now() -> void:
	_refresh_queued = false
	if not _built:
		return
	_refresh()
	UiLayout.pass_touch_through(_content)


# --- Building blocks ---------------------------------------------------------------

static func _vbox(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func _hbox(separation: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func _flow(h_separation: int, v_separation: int) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", h_separation)
	flow.add_theme_constant_override("v_separation", v_separation)
	return flow


static func _margin(node: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	margin.add_child(node)
	return margin


static func _label(text: String, font: Font, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	EraTheme.set_scaled_font_size(label, font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A single-line label that trims with an ellipsis instead of widening its column.
static func _clip_label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var label := _label(text, font, font_size, color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func _set_color(label: Control, color: Color) -> void:
	label.add_theme_color_override("font_color", color)


static func _box(bg: Color, radius: int = 0, margin_h: float = 0.0, margin_v: float = 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.anti_aliasing = radius > 0
	return box


static func _outline(bg: Color, border: Color, width: int, radius: int = 0, margin_h: float = 0.0, margin_v: float = 0.0) -> StyleBoxFlat:
	var box := _box(bg, radius, margin_h, margin_v)
	box.border_color = border
	box.set_border_width_all(width)
	return box


static func _panel(style: StyleBox) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	return panel


## Styles a button for every state. [param boxes] maps state -> StyleBox
## ("normal" is the fallback); [param colors] maps theme color names.
static func _style_button(button: Button, boxes: Dictionary, font: Font, font_size: int, colors: Dictionary) -> void:
	var normal: StyleBox = boxes["normal"]
	var pressed: StyleBox = boxes.get("pressed", normal)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", boxes.get("hover", normal))
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", boxes.get("disabled", normal))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_override("font", font)
	EraTheme.set_scaled_font_size(button, font_size)
	for key in colors:
		button.add_theme_color_override(key, colors[key])


## A button that asks for [param action_id]; tagged with the "action_id" meta.
func _directive_button(action_id: String) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, TOUCH)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("action_id", action_id)
	button.pressed.connect(func() -> void: request_directive(String(button.get_meta("action_id", ""))))
	return button


## Lays [param child] over [param button] with horizontal padding, ignoring
## the mouse so the button keeps every press.
static func _fill_button(button: Button, child: Control, padding: float) -> void:
	child.set_anchors_preset(Control.PRESET_FULL_RECT)
	child.offset_left = padding
	child.offset_right = -padding
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in child.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(child)


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- Text helpers ----------------------------------------------------------------------

## "27.3" or "100": one decimal unless the value is whole.
static func _num(value: float, decimals: int = 1) -> String:
	var factor := pow(10.0, decimals)
	var rounded := roundf(value * factor) / factor
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d" % int(roundf(rounded))
	return ("%." + str(decimals) + "f") % rounded


## "▲11", "▼0.2" or "=" when the change rounds to zero.
static func _arrow(delta: float, decimals: int = 0) -> String:
	var factor := pow(10.0, decimals)
	var shown := roundf(absf(delta) * factor) / factor
	if shown <= 0.0:
		return "="
	return ("▲" if delta > 0.0 else "▼") + (("%." + str(decimals) + "f") % shown)


## "+3" or "−4.5" with a true minus sign.
static func _signed(value: float, decimals: int = 1) -> String:
	return ("+" if value >= 0.0 else "−") + _num(absf(value), decimals)


## A short lowercase name for a metric, index or currency key, in the
## interface language (German keeps its capitals).
static func _key_word(key: String) -> String:
	if WorldState.METRIC_KEYS.has(key):
		return I18n.lowercase(UiFormat.metric_name(key))
	if WorldState.INDEX_KEYS.has(key):
		return I18n.lowercase(UiFormat.metric_short(key))
	return I18n.t(String(KEY_WORDS.get(key, key.replace("_", " "))))


## Deterministic 0..1 value for [param text] (stylistic devices only).
static func _hash01(text: String) -> float:
	return float(text.hash() & 0xFFFF) / 65535.0


# --- Drawing ---------------------------------------------------------------------------

## A Control drawn by a callable, so a lens can draw charts, maps and stamps
## without a script per widget: [member painter] receives the canvas. An
## animated canvas redraws at [member fps] while it is visible in the tree.
class Canvas:
	extends Control

	var painter := Callable()
	var animated := false:
		set(value):
			animated = value
			_sync_process()
	var fps := 30.0
	## Width / height ratio; when set the minimum height follows the width,
	## between [member min_height] and [member max_height] (0 = unbounded).
	var aspect := 0.0
	var min_height := 0.0
	var max_height := 0.0
	## Seconds of animation so far.
	var time := 0.0
	var _since_draw := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
			_sync_process()
		elif what == NOTIFICATION_RESIZED and aspect > 0.0:
			var height := size.x / aspect
			if max_height > 0.0:
				height = minf(height, max_height)
			height = roundf(maxf(height, min_height))
			if absf(custom_minimum_size.y - height) > 0.5:
				custom_minimum_size.y = height

	func _sync_process() -> void:
		set_process(animated and is_inside_tree() and is_visible_in_tree())

	func _process(delta: float) -> void:
		time += delta
		_since_draw += delta
		if _since_draw >= 1.0 / maxf(fps, 1.0):
			_since_draw = 0.0
			queue_redraw()

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _canvas(painter: Callable, min_size: Vector2 = Vector2.ZERO) -> Canvas:
	var canvas := Canvas.new()
	canvas.painter = painter
	canvas.custom_minimum_size = min_size
	return canvas


## Baseline y that vertically centers one line of [param font] in [param height].
static func _baseline(font: Font, font_size: int, top: float, height: float) -> float:
	return top + (height - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)


## Points along a cubic Bezier.
static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var u := 1.0 - t
		out.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return out


## Draws [param points] as a dashed polyline; [param phase] shifts the dashes.
static func _dashed_polyline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float,
		dash: float, gap: float, phase: float = 0.0) -> void:
	var period := dash + gap
	var segments := PackedVector2Array()
	var walked := fposmod(-phase, period)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var t := 0.0
		while t < length:
			var position_in_period := fposmod(walked + t, period)
			var step := minf(length - t, (dash - position_in_period) if position_in_period < dash else (period - position_in_period))
			if position_in_period < dash:
				segments.append(a.lerp(b, t / length))
				segments.append(a.lerp(b, (t + step) / length))
			t += maxf(step, 0.01)
		walked += length
	if segments.size() >= 2:
		canvas.draw_multiline(segments, color, width)
