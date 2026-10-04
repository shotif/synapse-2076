class_name GoalToast
extends Control
## A short banner for a GOAL log entry: "Goal met" with the reward paid, or
## "Goal missed", and the goal itself. It slides in at the top of the screen,
## stays for DURATION seconds (a tap dismisses it sooner) and queues the next
## one. Era-styled; the banner never gets wider than the screen.
##
##   toast.show_entry(entry)     # a SimulationEngine GOAL log entry
##
## The control covers its parent (it does not take input outside the banner);
## the dashboard adds it above the dialogs.

signal dismissed

const DURATION := 4.5
const FADE := 0.25
const MAX_WIDTH := 460.0
const MARGIN := 8.0
const TOP := 12.0
const MAX_QUEUE := 4

var _queue: Array[Dictionary] = []
var _entry := {}
var _banner: PanelContainer
var _icon: TextureRect
var _kicker: Label
var _title: Label
var _detail: Label
var _timer: Timer
var _tween: Tween
var _style: EraStyle


func _init() -> void:
	name = "GoalToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 3
	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_banner.gui_input.connect(_on_banner_input)
	add_child(_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(row)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(28, 28)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	_kicker = _label("Kicker", false)
	texts.add_child(_kicker)
	_title = _label("Goal", true)
	texts.add_child(_title)
	_detail = _label("Detail", true)
	texts.add_child(_detail)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_hide_current)
	add_child(_timer)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_place)
	# Wrapped text settles after layout; follow its height both ways.
	_banner.minimum_size_changed.connect(_place)
	_apply_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _banner != null and EraTheme.style_of(self) != _style:
		_apply_style.call_deferred()


## Shows [param entry] (a GOAL log entry: goal_text, status, reward_text, era),
## or queues it behind the banner on show. Other entries are ignored.
func show_entry(entry: Dictionary) -> void:
	if String(entry.get("category", "GOAL")) != "GOAL":
		return
	if is_showing():
		if _queue.size() < MAX_QUEUE:
			_queue.append(entry.duplicate())
		return
	_present(entry)


func is_showing() -> bool:
	return _banner.visible


## The entry on show ({} when none).
func current_entry() -> Dictionary:
	return _entry.duplicate()


func pending_count() -> int:
	return _queue.size()


## The banner's texts: {kicker, title, detail}.
func get_texts() -> Dictionary:
	return {"kicker": _kicker.text, "title": _title.text, "detail": _detail.text}


func get_banner() -> Control:
	return _banner


## Hides the banner at once and forgets the queue.
func clear() -> void:
	_queue.clear()
	_kill_tween()
	_timer.stop()
	_banner.visible = false
	_entry = {}


## Dismisses the banner on show (the next queued one follows).
func dismiss() -> void:
	_hide_current()


func _present(entry: Dictionary) -> void:
	_entry = entry.duplicate()
	var met := String(entry.get("status", "")) == EraGoals.MET
	var era := int(entry.get("era", 1))
	var reward := String(entry.get("reward_text", ""))
	_kicker.text = ("Goal met" if met else "Goal missed") + " · Era %s" % EraStyle.ROMAN.get(era, "I")
	_title.text = String(entry.get("goal_text", entry.get("text", "")))
	_detail.text = ("Reward: %s" % reward if reward != "" else "Reward paid") if met else "No reward this era. The next era brings a new goal."
	_apply_style()
	_banner.visible = true
	_place()
	_kill_tween()
	if bool(GameSettings.value("effects")) and is_inside_tree():
		_banner.modulate.a = 0.0
		_banner.position.y = TOP - 16.0
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_banner, "modulate:a", 1.0, FADE)
		_tween.tween_property(_banner, "position:y", TOP, FADE)
	if is_inside_tree():
		_timer.start(DURATION)


func _hide_current() -> void:
	_timer.stop()
	if not _banner.visible:
		return
	_kill_tween()
	if not is_inside_tree() or not bool(GameSettings.value("effects")):
		_finish_hide()
		return
	_tween = create_tween()
	_tween.tween_property(_banner, "modulate:a", 0.0, FADE)
	_tween.tween_callback(_finish_hide)


func _finish_hide() -> void:
	_banner.visible = false
	_entry = {}
	dismissed.emit()
	if not _queue.is_empty():
		_present(_queue.pop_front())


func _on_banner_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_hide_current()


## Top center, at most MAX_WIDTH wide and never wider than the screen.
func _place() -> void:
	if _banner == null:
		return
	var width := minf(MAX_WIDTH, maxf(size.x - MARGIN * 2.0, 120.0))
	if not is_equal_approx(_banner.custom_minimum_size.x, width):
		_banner.custom_minimum_size = Vector2(width, 0)
	var fitted := Vector2(width, _banner.get_combined_minimum_size().y)
	if not _banner.size.is_equal_approx(fitted):
		_banner.size = fitted
	_banner.position.x = roundf((size.x - _banner.size.x) * 0.5)
	if _tween == null or not _tween.is_valid():
		_banner.position.y = TOP


func _apply_style() -> void:
	if _banner == null:
		return
	_style = EraTheme.style_of(self)
	var s := _style
	var met := String(_entry.get("status", EraGoals.MET)) == EraGoals.MET
	var tone := s.good if met else s.bad
	var box := EraTheme.panel(s, s.overlay, Color(tone, 0.7), s.radius, 14)
	box.set_border_width_all(maxi(s.border_width, 1))
	box.border_width_left = 4
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 14
	_banner.add_theme_stylebox_override("panel", box)
	_icon.texture = Glyphs.tile("check" if met else "flag", 28, Color(tone, 0.2), tone, 8 if s.era != 3 else 14)
	_kicker.add_theme_font_override("font", s.font_mono)
	EraTheme.set_scaled_font_size(_kicker, 11)
	_kicker.add_theme_color_override("font_color", tone)
	_kicker.text = s.label(_kicker.text)
	_title.add_theme_font_override("font", s.font_ui_bold)
	EraTheme.set_scaled_font_size(_title, 15)
	_title.add_theme_color_override("font_color", s.text_bright)
	_detail.add_theme_font_override("font", s.font_ui)
	EraTheme.set_scaled_font_size(_detail, 12)
	_detail.add_theme_color_override("font_color", s.text_dim)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _banner != null:
		_banner.modulate.a = 1.0


static func _label(label_name: String, wrap: bool) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
