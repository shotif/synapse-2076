class_name LLMSettingsDialog
extends Control
## Endpoint configuration overlay for the LLM decision layer: Claude's
## Messages API (Anthropic directly or a proxy) or any OpenAI-compatible
## chat-completions URL (Ollama, vLLM, LM Studio...).

signal closed

const DESKTOP_WIDTH := 640.0

var service: LLMService
var _compact := false
var _frame: MarginContainer
var _panel: PanelContainer
var _endpoint: LineEdit
var _model: LineEdit
var _api_key: LineEdit
var _timeout: LineEdit
var _enabled: CheckBox
var _write_crises: CheckBox
var _remember_key: CheckBox
var _status: Label


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0.02, 0.03, 0.05, 0.75))
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "OverlayPanel"
	_panel.custom_minimum_size = Vector2(DESKTOP_WIDTH, 0)
	_frame.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "PanelTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = "AI decision layer · Claude or any OpenAI-compatible endpoint"
	box.add_child(title)
	_endpoint = _field(box, I18n.mark("Endpoint URL. Claude: https://api.anthropic.com/v1/messages or your proxy's /v1/messages. OpenAI-compatible: .../v1/chat/completions"),
		"https://api.anthropic.com/v1/messages")
	_model = _field(box, I18n.mark("Model"), "claude-sonnet-5-5")
	_api_key = _field(box, I18n.mark("API key or proxy access code (Claude: x-api-key header, otherwise a Bearer token). Leave empty for local servers."), "")
	_api_key.secret = true
	_timeout = _field(box, I18n.mark("Timeout (seconds)"), "5.0")
	_enabled = CheckBox.new()
	_enabled.text = "Enable LLM-driven factions (heuristic fallback is always available)"
	box.add_child(_enabled)
	_write_crises = CheckBox.new()
	_write_crises.name = "WriteCrises"
	_write_crises.text = "Write crises with Claude: every few turns your crisis card is written for the world you are in (uses more tokens)"
	box.add_child(_write_crises)
	_remember_key = CheckBox.new()
	_remember_key.text = "Remember the key on this device (plain text in user://, browser site storage on the web)"
	box.add_child(_remember_key)
	for check in [_enabled, _write_crises, _remember_key]:
		(check as CheckBox).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if OS.has_feature("web"):
		var hint := Label.new()
		hint.theme_type_variation = "DimLabel"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "On a phone: open this page with #llm-key=YOUR_KEY after the address once. The key is stored on this device and removed from the address bar."
		box.add_child(hint)
	_status = Label.new()
	# Status lines carry server messages (English).
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.theme_type_variation = "DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	var test_button := Button.new()
	test_button.text = "Test connection"
	test_button.pressed.connect(_on_test_pressed)
	buttons.add_child(test_button)
	var save_button := Button.new()
	save_button.theme_type_variation = "AccentButton"
	save_button.text = "Save & close"
	save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(save_button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func():
		visible = false
		closed.emit())
	buttons.add_child(cancel)
	box.add_child(buttons)
	for label in box.find_children("*", "Label", true, false):
		(label as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiLayout.pass_touch_through(_panel)
	resized.connect(_apply_layout)
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _frame != null:
		(get_child(0) as ColorRect).color = EraTheme.style_of(self).shade


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact), 0)
	UiLayout.set_overlay_margin(_frame, _compact)
	for button in _panel.find_children("*", "Button", true, false):
		if not (button is CheckBox):
			(button as Control).custom_minimum_size = Vector2(0, 42 if _compact else 0)
	_reflow_checks()


## Godot 4.3 keeps the height an autowrapped CheckBox measured at an earlier
## width (a few pixels wide: one word per line, over a thousand pixels tall).
## Once the panel has its width, setting the wrap mode again measures it anew.
func _reflow_checks() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	for check in [_enabled, _write_crises, _remember_key]:
		var box := check as CheckBox
		if is_instance_valid(box):
			box.autowrap_mode = TextServer.AUTOWRAP_OFF
			box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func open(llm_service: LLMService) -> void:
	service = llm_service
	if not service.probe_finished.is_connected(_on_probe_finished):
		service.probe_finished.connect(_on_probe_finished)
	_endpoint.text = service.endpoint_url
	_model.text = service.model_name
	_api_key.text = service.api_key
	_timeout.text = "%.1f" % service.request_timeout_sec
	_enabled.button_pressed = service.enabled
	_write_crises.button_pressed = service.write_crises
	_status.text = tr("Status: %s") % (tr("ONLINE") if service.is_online else tr("OFFLINE")) \
		+ ("" if service.last_error == "" else " (" + service.last_error + ")")
	visible = true
	_reflow_checks()


func _apply() -> void:
	service.configure({
		"endpoint_url": _endpoint.text,
		"model_name": _model.text,
		"api_key": _api_key.text,
		"request_timeout_sec": _timeout.text.to_float() if _timeout.text.is_valid_float() else 5.0,
		"enabled": _enabled.button_pressed,
		"write_crises": _write_crises.button_pressed,
	})


func _on_test_pressed() -> void:
	_apply()
	_status.text = tr("Probing %s ...") % service.models_url()
	service.probe_connection()


func _on_save_pressed() -> void:
	_apply()
	service.save_user_configuration(_remember_key.button_pressed)
	service.probe_connection()
	visible = false
	closed.emit()


func _on_probe_finished(online: bool, detail: String) -> void:
	if visible:
		_status.text = tr("Probe result: %s (%s)") % [tr("ONLINE") if online else tr("OFFLINE"), detail]


func _field(parent: Control, caption: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = "DimLabel"
	parent.add_child(label)
	var edit := LineEdit.new()
	# Example values (URLs, model names) are not translated.
	edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	edit.placeholder_text = placeholder
	parent.add_child(edit)
	return edit
