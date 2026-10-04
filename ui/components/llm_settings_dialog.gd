class_name LLMSettingsDialog
extends Control
## Endpoint configuration overlay for the LLM decision layer: any
## OpenAI-compatible chat-completions URL (Ollama, vLLM, Claude API proxy...).

signal closed

var service: LLMService
var _endpoint: LineEdit
var _model: LineEdit
var _api_key: LineEdit
var _timeout: LineEdit
var _enabled: CheckBox
var _remember_key: CheckBox
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "OverlayPanel"
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "PanelTitle"
	title.text = "LLM DECISION LAYER // OPENAI-COMPATIBLE ENDPOINT"
	box.add_child(title)
	_endpoint = _field(box, "Chat completions URL", "http://127.0.0.1:11434/v1/chat/completions")
	_model = _field(box, "Model", "llama3:8b")
	_api_key = _field(box, "API key (sent as Bearer token; leave empty for local servers)", "")
	_api_key.secret = true
	_timeout = _field(box, "Timeout (seconds)", "5.0")
	_enabled = CheckBox.new()
	_enabled.text = "Enable LLM-driven factions (heuristic fallback is always available)"
	box.add_child(_enabled)
	_remember_key = CheckBox.new()
	_remember_key.text = "Remember API key in user:// (plain text)"
	box.add_child(_remember_key)
	_status = Label.new()
	_status.theme_type_variation = "DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	var test_button := Button.new()
	test_button.text = "TEST CONNECTION"
	test_button.pressed.connect(_on_test_pressed)
	buttons.add_child(test_button)
	var save_button := Button.new()
	save_button.theme_type_variation = "AccentButton"
	save_button.text = "SAVE & CLOSE"
	save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(save_button)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.pressed.connect(func():
		visible = false
		closed.emit())
	buttons.add_child(cancel)
	box.add_child(buttons)
	visible = false


func open(llm_service: LLMService) -> void:
	service = llm_service
	if not service.probe_finished.is_connected(_on_probe_finished):
		service.probe_finished.connect(_on_probe_finished)
	_endpoint.text = service.endpoint_url
	_model.text = service.model_name
	_api_key.text = service.api_key
	_timeout.text = "%.1f" % service.request_timeout_sec
	_enabled.button_pressed = service.enabled
	_status.text = "Status: %s%s" % ["ONLINE" if service.is_online else "OFFLINE",
		"" if service.last_error == "" else " (" + service.last_error + ")"]
	visible = true


func _apply() -> void:
	service.configure({
		"endpoint_url": _endpoint.text,
		"model_name": _model.text,
		"api_key": _api_key.text,
		"request_timeout_sec": _timeout.text.to_float() if _timeout.text.is_valid_float() else 5.0,
		"enabled": _enabled.button_pressed,
	})


func _on_test_pressed() -> void:
	_apply()
	_status.text = "Probing %s ..." % service.models_url()
	service.probe_connection()


func _on_save_pressed() -> void:
	_apply()
	service.save_user_configuration(_remember_key.button_pressed)
	service.probe_connection()
	visible = false
	closed.emit()


func _on_probe_finished(online: bool, detail: String) -> void:
	if visible:
		_status.text = "Probe result: %s (%s)" % ["ONLINE" if online else "OFFLINE", detail]


func _field(parent: Control, caption: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = "DimLabel"
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	parent.add_child(edit)
	return edit
