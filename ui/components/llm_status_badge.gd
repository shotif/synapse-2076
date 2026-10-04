class_name LLMStatusBadge
extends PanelContainer
## Header connectivity indicator (PRD section 7.2):
##   ● [LLM ONLINE: <MODEL> / <PROVIDER>]                 muted cyan  #00E5FF
##   ▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]  alert amber #FFB300
## Click to open the LLM settings dialog.

signal settings_requested

const ONLINE_COLOR := Color("#00E5FF")
const OFFLINE_COLOR := Color("#FFB300")

var service: LLMService
var _label: Label
var _style: StyleBoxFlat
var _pulse := 0.0
var _online := false
var _probing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "LLM decision layer status. Click to configure the endpoint."
	_style = StyleBoxFlat.new()
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(3)
	_style.content_margin_left = 10
	_style.content_margin_right = 10
	_style.content_margin_top = 4
	_style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", _style)
	_label = get_node_or_null("Label")
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		add_child(_label)
	_label.add_theme_font_override("font", CyberPalette.MONO_BOLD)
	_label.add_theme_font_size_override("font_size", 13)
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
	var text := ""
	if online:
		text = "● [LLM ONLINE: %s]" % provider_name
	elif _probing:
		text = "◌ [LLM PROBING: %s]" % provider_name
	else:
		text = "▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]"
	if _label != null:
		_label.text = text
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
	var color := ONLINE_COLOR if _online else OFFLINE_COLOR
	_label.add_theme_color_override("font_color", Color(color, intensity))
	_style.bg_color = Color(color, 0.07)
	_style.border_color = Color(color, 0.55 * intensity)


func _on_status_changed(_is_online: bool, _provider: String) -> void:
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		settings_requested.emit()
		accept_event()
