class_name LLMStatusBadge
extends PanelContainer
## Header connectivity indicator (PRD section 7.2):
##   ● [LLM ONLINE: <MODEL> / <PROVIDER>]                 the era's accent
##   ▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]  the era's warning
## drawn as a pill in the active era's shape. Click to open the LLM settings
## dialog. The compact variant (phone header) shortens the text to
## "● LLM ON" / "▲ LLM OFF".

signal settings_requested

var service: LLMService
var _label: Label
var _style: StyleBoxFlat
var _pulse := 0.0
var _online := false
var _probing := false
var _compact := false
var _provider := ""
var _era_style: EraStyle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "LLM decision layer status. Click to configure the endpoint."
	_style = StyleBoxFlat.new()
	_style.set_border_width_all(1)
	_style.content_margin_left = 12
	_style.content_margin_right = 12
	_style.content_margin_top = 5
	_style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", _style)
	_label = get_node_or_null("Label")
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		add_child(_label)
	_label.add_theme_font_size_override("font_size", 12)
	_restyle()
	set_status(false, "")


## Follows an LLMService: refreshes on every status change.
func bind(llm_service: LLMService) -> void:
	service = llm_service
	if not service.llm_status_changed.is_connected(_on_status_changed):
		service.llm_status_changed.connect(_on_status_changed)
	refresh()


func refresh() -> void:
	if service != null:
		_probing = service.is_probing
		set_status(service.is_online, service.get_provider_name())


func set_status(online: bool, provider_name: String) -> void:
	_online = online
	_provider = provider_name
	var text := ""
	if online:
		text = "● LLM ON" if _compact else "● [LLM ONLINE: %s]" % provider_name
	elif _probing:
		text = "◌ LLM" if _compact else "◌ [LLM PROBING: %s]" % provider_name
	else:
		text = "▲ LLM OFF" if _compact else "▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]"
	if _label != null:
		_label.text = text
	_apply_colors(1.0)


func set_compact(compact: bool) -> void:
	_compact = compact
	if _label != null:
		_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	if _style != null:
		_style.content_margin_left = 9 if compact else 12
		_style.content_margin_right = 9 if compact else 12
	set_status(_online, _provider)


func _notification(what: int) -> void:
	# Our own style box edits re-send this notification; only a new era restyles.
	if what == NOTIFICATION_THEME_CHANGED and _style != null and _label != null \
			and EraTheme.style_of(self) != _era_style:
		_restyle()


## Shape and type follow the era: pills in Eras I and III, a chamfered tag in II.
func _restyle() -> void:
	var s := EraTheme.style_of(self)
	_era_style = s
	_label.add_theme_font_override("font", s.font_mono_bold)
	_style.corner_detail = s.corner_detail
	_style.set_corner_radius_all(6 if s.era == 2 else 999)
	_apply_colors(1.0)


func get_text() -> String:
	return _label.text if _label != null else ""


func is_showing_online() -> bool:
	return _online


func _process(delta: float) -> void:
	if _online:
		return
	# Slow amber pulse while degraded so the fallback state stays noticeable.
	_pulse = fmod(_pulse + delta * 1.6, TAU)
	_apply_colors(0.72 + 0.28 * (0.5 + 0.5 * sin(_pulse)))


func _apply_colors(intensity: float) -> void:
	if _label == null or _style == null:
		return
	var s := _era_style if _era_style != null else EraTheme.style_of(self)
	var color := s.accent if _online else s.warn
	_label.add_theme_color_override("font_color", Color(color, intensity))
	_style.bg_color = Color(color, 0.1)
	_style.border_color = Color(color, 0.5 * intensity)


func _on_status_changed(_is_online: bool, _provider: String) -> void:
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		settings_requested.emit()
		accept_event()
