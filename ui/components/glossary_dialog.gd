class_name GlossaryDialog
extends Control
## A searchable glossary of the game's jargon (PlainLanguage): every vital
## sign, background reading, currency, faction, idea, era and ending, each with
## its plain name, the model's technical name and a one-line explanation.
## Typing filters the list (every word must match a name or the explanation).
##
##   glossary.open()            # or open("drift") to start with a search
##
## Built on UiLayout.build_overlay(): centered on desktop, full width and
## scrolling on phones (set_compact). Era-styled.

signal closed

const DESKTOP_WIDTH := 620.0

var _compact := false
var _style: EraStyle
var _frame: MarginContainer
var _shade: ColorRect
var _panel: PanelContainer
var _title: Label
var _intro: Label
var _search: LineEdit
var _list: VBoxContainer
var _count: Label
var _done: Button
var _shown: Array = []
var _restyle_queued := false


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.7))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = get_child(0) as ColorRect
	_panel = PanelContainer.new()
	_panel.name = "GlossaryPanel"
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_title = Label.new()
	_title.text = "Glossary"
	_title.theme_type_variation = "DisplayTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_title)
	var close_icon := Button.new()
	close_icon.name = "CloseIcon"
	close_icon.icon = Glyphs.texture("close", 18)
	close_icon.theme_type_variation = "GhostButton"
	close_icon.tooltip_text = "Close"
	close_icon.custom_minimum_size = Vector2(44, 44)
	close_icon.pressed.connect(close)
	head.add_child(close_icon)

	_intro = Label.new()
	_intro.theme_type_variation = "DimLabel"
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.text = "Plain words for the model's jargon: what each number, currency and idea means."
	box.add_child(_intro)

	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search: drift, trust, FLOPs…"
	_search.clear_button_enabled = true
	_search.right_icon = Glyphs.texture("search", 16)
	_search.custom_minimum_size = Vector2(0, 40)
	_search.text_changed.connect(func(_text: String) -> void: _rebuild_list())
	box.add_child(_search)

	_list = VBoxContainer.new()
	_list.name = "Terms"
	_list.add_theme_constant_override("separation", 12)
	box.add_child(_list)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	box.add_child(foot)
	_count = Label.new()
	_count.theme_type_variation = "Caption"
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_count)
	_done = Button.new()
	_done.name = "DoneButton"
	_done.text = "Done"
	_done.theme_type_variation = "AccentButton"
	_done.custom_minimum_size = Vector2(96, 40)
	_done.pressed.connect(close)
	foot.add_child(_done)

	resized.connect(_apply_layout)
	GameSettings.instance().changed.connect(_on_setting_changed)
	visible = false
	z_index = 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _panel != null and EraTheme.style_of(self) != _style and not _restyle_queued:
		_restyle_queued = true
		_restyle.call_deferred()


func _restyle() -> void:
	_restyle_queued = false
	_style = EraTheme.style_of(self)
	_shade.color = Color(_style.shade, maxf(_style.shade.a, 0.7))
	if visible:
		_rebuild_list()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "plain_language" and visible:
		_rebuild_list()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()


## Opens the glossary, filtered by [param query] when given.
func open(query: String = "") -> void:
	_style = EraTheme.style_of(self)
	_shade.color = Color(_style.shade, maxf(_style.shade.a, 0.7))
	_search.text = query
	_apply_layout()
	_rebuild_list()
	visible = true
	(get_node("OverlayScroll") as ScrollContainer).scroll_vertical = 0


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Filters the list as if [param query] were typed.
func set_query(query: String) -> void:
	_search.text = query
	_rebuild_list()


## The ids of the terms on show, in order.
func visible_terms() -> Array:
	var ids := []
	for item in _shown:
		ids.append(String(item["id"]))
	return ids


func get_search_field() -> LineEdit:
	return _search


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(UiLayout.panel_width(size.x if size.x > 1.0 else get_viewport_rect().size.x,
		DESKTOP_WIDTH, _compact), 0)
	UiLayout.set_overlay_margin(_frame, _compact)
	for button in [_done]:
		(button as Control).custom_minimum_size.y = 44 if _compact else 40


func _rebuild_list() -> void:
	if _style == null:
		_style = EraTheme.style_of(self)
	var s := _style
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_shown = PlainLanguage.search(_search.text)
	var kind := ""
	for item in _shown:
		if String(item["kind"]) != kind:
			kind = String(item["kind"])
			var section := Label.new()
			section.text = s.label(String(PlainLanguage.KIND_TITLES.get(kind, kind.capitalize())))
			section.theme_type_variation = "PanelTitle"
			_list.add_child(section)
		_list.add_child(_term(s, item))
	if _shown.is_empty():
		var none := Label.new()
		none.theme_type_variation = "DimLabel"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.text = "No term matches “%s”." % _search.text.strip_edges()
		_list.add_child(none)
	var total := PlainLanguage.glossary().size()
	_count.text = "%d of %d terms" % [_shown.size(), total] if _shown.size() != total else "%d terms" % total
	UiLayout.pass_touch_through(_list)


## One term: the plain name, the model's name and what it means.
func _term(s: EraStyle, item: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Term_" + String(item["id"])
	card.theme_type_variation = "CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var plain := Label.new()
	plain.name = "Plain"
	plain.text = String(item["name"])
	plain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plain.add_theme_font_override("font", s.font_ui_bold)
	EraTheme.set_scaled_font_size(plain, 15)
	plain.add_theme_color_override("font_color", s.text_bright)
	box.add_child(plain)
	var technical := Label.new()
	technical.name = "Technical"
	technical.text = String(item["technical"])
	technical.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	technical.add_theme_font_override("font", s.font_mono)
	EraTheme.set_scaled_font_size(technical, 11)
	technical.add_theme_color_override("font_color", s.accent if s.era != 1 else s.text_dim)
	box.add_child(technical)
	var explanation := Label.new()
	explanation.name = "Explain"
	explanation.text = String(item["explain"])
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_font_override("font", s.font_ui)
	EraTheme.set_scaled_font_size(explanation, 13)
	explanation.add_theme_color_override("font_color", s.text)
	box.add_child(explanation)
	return card
