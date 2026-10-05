class_name LLMStatusBadge
extends PanelContainer
## Header indicator of the player's LLM (PRD section 7.2), drawn as a pill in
## the active era's shape:
##   ● [LLM ONLINE: <MODEL> / <PROVIDER>]                 the era's accent
##   ◌ [LLM PROBING: <PROVIDER>]                          the era's warning
##   ▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]  the era's warning, pulsing
##   ▲ [LLM RESTING - DAILY LIMIT REACHED]                the backend's daily limit
##   ○ [LLM OFF - RUNNING HEURISTIC ENGINE]               switched off (dim)
##   ○ [NO LLM - RUNNING HEURISTIC ENGINE]                a build without a backend (dim)
## Clicking it asks to switch the LLM on or off (switch_requested; the
## dashboard flips GameSettings "llm"). The compact variant (phone header)
## shortens the text to "● LLM ON" / "▲ LLM OFF" / "○ LLM OFF" / "○ NO LLM".
## [method status_line] words the same state as a sentence for the settings
## dialog and the campaign setup.

signal switch_requested

var service: LLMService
var _label: Label
var _style: StyleBoxFlat
var _pulse := 0.0
var _state := LLMService.STATE_OFFLINE
var _compact := false
var _provider := ""
var _era_style: EraStyle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	_show(LLMService.STATE_OFFLINE, "")


## The player's LLM state as a sentence (the settings dialog and the campaign
## setup show it under their On/Off switch).
static func status_line(llm_service: LLMService) -> String:
	if llm_service == null:
		return I18n.t("This version has no LLM: the built-in rules play the other factions.")
	match llm_service.get_state():
		LLMService.STATE_ONLINE:
			var model := llm_service.display_model()
			return I18n.t("Online: %s") % model if model != "" else I18n.t("Online")
		LLMService.STATE_CONNECTING:
			return I18n.t("Connecting…")
		LLMService.STATE_LIMITED:
			return I18n.t("Today's limit is reached: the built-in rules play until 00:00 UTC.")
		LLMService.STATE_OFF:
			return I18n.t("Off: the built-in rules play the other factions.")
		LLMService.STATE_NONE:
			return I18n.t("This version has no LLM: the built-in rules play the other factions.")
	return I18n.t("Unavailable right now: the built-in rules play until it is back.")


## Follows an LLMService: refreshes on every status change.
func bind(llm_service: LLMService) -> void:
	service = llm_service
	if not service.llm_status_changed.is_connected(_on_status_changed):
		service.llm_status_changed.connect(_on_status_changed)
	refresh()


func refresh() -> void:
	if service != null:
		_show(service.get_state(), service.get_provider_name())


## Shows [param online] without a service (the PRD's two states).
func set_status(online: bool, provider_name: String) -> void:
	_show(LLMService.STATE_ONLINE if online else LLMService.STATE_OFFLINE, provider_name)


func _show(state: String, provider_name: String) -> void:
	_state = state
	_provider = provider_name
	if _label != null:
		_label.text = _text_for(state, provider_name)
	var switchable := state != LLMService.STATE_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if switchable else Control.CURSOR_ARROW
	tooltip_text = I18n.mark("LLM on or off: click to switch.") if switchable \
		else I18n.mark("This version has no LLM: the built-in rules play the other factions.")
	_apply_colors(1.0)


func _text_for(state: String, provider_name: String) -> String:
	match state:
		LLMService.STATE_ONLINE:
			return tr("● LLM ON") if _compact else tr("● [LLM ONLINE: %s]") % provider_name
		LLMService.STATE_CONNECTING:
			return tr("◌ LLM") if _compact else tr("◌ [LLM PROBING: %s]") % provider_name
		LLMService.STATE_LIMITED:
			return tr("▲ LLM OFF") if _compact else tr("▲ [LLM RESTING - DAILY LIMIT REACHED]")
		LLMService.STATE_OFF:
			return tr("○ LLM OFF") if _compact else tr("○ [LLM OFF - RUNNING HEURISTIC ENGINE]")
		LLMService.STATE_NONE:
			return tr("○ NO LLM") if _compact else tr("○ [NO LLM - RUNNING HEURISTIC ENGINE]")
	return tr("▲ LLM OFF") if _compact else tr("▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]")


func set_compact(compact: bool) -> void:
	_compact = compact
	if _label != null:
		_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	if _style != null:
		_style.content_margin_left = 9 if compact else 12
		_style.content_margin_right = 9 if compact else 12
	_show(_state, _provider)


func _notification(what: int) -> void:
	# Our own style box edits re-send this notification; only a new era restyles.
	if what == NOTIFICATION_THEME_CHANGED and _style != null and _label != null \
			and EraTheme.style_of(self) != _era_style:
		_restyle()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_show.call_deferred(_state, _provider)


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


func get_state() -> String:
	return _state


func is_showing_online() -> bool:
	return _state == LLMService.STATE_ONLINE


## Warning states pulse so the fallback stays noticeable; a choice (off) or a
## build without a backend stays still.
func _is_warning() -> bool:
	return _state in [LLMService.STATE_OFFLINE, LLMService.STATE_CONNECTING, LLMService.STATE_LIMITED]


func _process(delta: float) -> void:
	if not _is_warning():
		return
	# Slow amber pulse while degraded so the fallback state stays noticeable.
	_pulse = fmod(_pulse + delta * 1.6, TAU)
	_apply_colors(0.72 + 0.28 * (0.5 + 0.5 * sin(_pulse)))


func _apply_colors(intensity: float) -> void:
	if _label == null or _style == null:
		return
	var s := _era_style if _era_style != null else EraTheme.style_of(self)
	var color := s.accent if _state == LLMService.STATE_ONLINE else (s.warn if _is_warning() else s.text_dim)
	_label.add_theme_color_override("font_color", Color(color, intensity))
	_style.bg_color = Color(color, 0.1)
	_style.border_color = Color(color, 0.5 * intensity)


func _on_status_changed(_is_online: bool, _provider_name: String) -> void:
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _state != LLMService.STATE_NONE:
			switch_requested.emit()
		accept_event()
