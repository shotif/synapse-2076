class_name NegotiationDialog
extends Control
## "Call the ..." overlay: a phone call with the leader of an autonomous
## faction (Negotiator) during the player's turn. Era-styled message bubbles
## in a scrolling history, quick replies, a text field that stays on screen,
## and an offer card with what you give, what you get, the pledge and the
## world moves (glyphs, pips and the era's good and bad colors). Accepting
## applies the deal through the engine; hanging up closes the call.
##
## Opened with a partner, the call starts at once; opened with "" it first
## lists the leaders the player can call (Negotiator.callable_partners).
## Partner lines are model output: they are stripped of markup by the
## Negotiator and shown in plain Labels, never parsed as BBCode.
##
##   dialog.open_call(engine, llm, SimConstants.GOVERNANCE)
##   dialog.deal_accepted.connect(func(applied): refresh_resources())

## The player accepted an offer; [param applied] is SimulationEngine.apply_deal's result.
signal deal_accepted(applied: Dictionary)
signal closed

const DESKTOP_WIDTH := 620.0
const DESKTOP_HISTORY_HEIGHT := 280.0
const COMPACT_HISTORY_MIN := 140.0
## A bubble is at most this share of the history's width.
const BUBBLE_SHARE := 0.82
const AVATAR_SIZE := 44
const ROW_HEIGHT := 56.0
const TOUCH_HEIGHT := 42.0

var engine: SimulationEngine
var llm: Node

var _negotiator := Negotiator.new()
var _compact := false
var _era := 0
var _style: EraStyle
var _restyling := false
var _refit_pending := false
var _rendered := 0
var _panel_width := DESKTOP_WIDTH

var _frame: MarginContainer
var _shade: ColorRect
var _panel: PanelContainer
var _column: VBoxContainer
var _partner_box: StyleBoxFlat
var _player_box: StyleBoxFlat
# The contact list.
var _picker: VBoxContainer
var _picker_title: Label
var _picker_hint: Label
var _picker_rows: VBoxContainer
var _picker_close: Button
# The call.
var _call: VBoxContainer
var _avatar: TextureRect
var _name_label: Label
var _title_label: Label
var _hang_up: Button
var _status: Label
var _history: ScrollContainer
var _bubbles: VBoxContainer
var _typing: Label
var _offer_card: PanelContainer
var _offer_kicker: Label
var _offer_summary: Label
var _offer_rows: VBoxContainer
var _offer_buttons: HBoxContainer
var _decline_button: Button
var _accept_button: Button
var _quick: HFlowContainer
var _input_row: HBoxContainer
var _input: LineEdit
var _send_button: Button


func _init() -> void:
	name = "NegotiationDialog"
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.8))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = get_child(0) as ColorRect
	_panel = PanelContainer.new()
	_panel.name = "CallPanel"
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 10)
	_panel.add_child(_column)
	_build_picker()
	_build_call()
	_picker.visible = false
	_negotiator.updated.connect(_refresh)
	resized.connect(_apply_layout)
	visible = false
	_restyle()


func _ready() -> void:
	_apply_layout()


func _notification(what: int) -> void:
	# Only a new era restyles: our own children's overrides re-send this.
	if what == NOTIFICATION_THEME_CHANGED and _column != null and not _restyling and EraTheme.style_of(self).era != _era:
		_restyle()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		hang_up()
		get_viewport().set_input_as_handled()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()


## Opens a call from [param sim]'s current player to [param partner_faction]'s
## leader; "" (or a faction that cannot be called) shows the contact list.
## [param service] answers in character when online (LLMService); without it
## the scripted negotiator does.
func open_call(sim: SimulationEngine, service: Node, partner_faction: String) -> void:
	engine = sim
	llm = service
	if partner_faction != "" and Negotiator.can_call(sim, partner_faction):
		_start(partner_faction)
	else:
		_show_picker()
	visible = true
	_apply_layout()


## Ends the call and closes the dialog.
func hang_up() -> void:
	_negotiator.hang_up()
	visible = false
	closed.emit()


## The call behind the dialog (tests, tooling).
func get_negotiator() -> Negotiator:
	return _negotiator


## Sends [param text] as if typed (tests, tooling).
func send_message(text: String) -> bool:
	return _negotiator.send(text)


# --- Building ----------------------------------------------------------------------

func _build_picker() -> void:
	_picker = VBoxContainer.new()
	_picker.name = "Picker"
	_picker.add_theme_constant_override("separation", 10)
	_column.add_child(_picker)
	_picker_title = _label("PickerTitle", true)
	_picker.add_child(_picker_title)
	_picker_hint = _label("PickerHint", true)
	_picker.add_child(_picker_hint)
	_picker_rows = VBoxContainer.new()
	_picker_rows.name = "Contacts"
	_picker_rows.add_theme_constant_override("separation", 8)
	_picker.add_child(_picker_rows)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	_picker.add_child(close_row)
	_picker_close = Button.new()
	_picker_close.name = "PickerClose"
	_picker_close.text = "Close"
	_picker_close.pressed.connect(hang_up)
	close_row.add_child(_picker_close)


func _build_call() -> void:
	_call = VBoxContainer.new()
	_call.name = "Call"
	_call.add_theme_constant_override("separation", 10)
	_call.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_call)
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	_call.add_child(header)
	_avatar = TextureRect.new()
	_avatar.name = "Avatar"
	_avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_avatar)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 2)
	header.add_child(names)
	_name_label = _label("PartnerName", true)
	names.add_child(_name_label)
	_title_label = _label("PartnerTitle", true)
	names.add_child(_title_label)
	_hang_up = Button.new()
	_hang_up.name = "HangUp"
	_hang_up.text = "Hang up"
	_hang_up.icon = Glyphs.texture("close", 16)
	_hang_up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hang_up.pressed.connect(hang_up)
	header.add_child(_hang_up)

	_status = _label("Status", true)
	_call.add_child(_status)

	_history = ScrollContainer.new()
	_history.name = "History"
	_history.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_call.add_child(_history)
	_bubbles = VBoxContainer.new()
	_bubbles.name = "Messages"
	_bubbles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubbles.add_theme_constant_override("separation", 8)
	_history.add_child(_bubbles)
	_typing = _label("Typing", false)
	_typing.visible = false
	_call.add_child(_typing)

	_build_offer_card()

	_quick = HFlowContainer.new()
	_quick.name = "QuickReplies"
	_quick.add_theme_constant_override("h_separation", 8)
	_quick.add_theme_constant_override("v_separation", 8)
	_call.add_child(_quick)
	for reply in Negotiator.QUICK_REPLIES:
		var chip := Button.new()
		chip.name = "Quick_" + String(reply["id"])
		chip.theme_type_variation = "ChipButton"
		chip.text = String(reply["text"])
		chip.set_meta("intent", String(reply["id"]))
		chip.pressed.connect(_on_quick.bind(String(reply["id"])))
		_quick.add_child(chip)

	_input_row = HBoxContainer.new()
	_input_row.name = "InputRow"
	_input_row.add_theme_constant_override("separation", 8)
	_call.add_child(_input_row)
	_input = LineEdit.new()
	_input.name = "Input"
	_input.max_length = Negotiator.MAX_PLAYER_TEXT
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(80, 0)
	_input.text_submitted.connect(_on_submit)
	_input_row.add_child(_input)
	_send_button = Button.new()
	_send_button.name = "Send"
	_send_button.theme_type_variation = "AccentButton"
	_send_button.text = "Send"
	_send_button.icon = Glyphs.texture("arrow_right", 16)
	_send_button.pressed.connect(func(): _on_submit(_input.text))
	_input_row.add_child(_send_button)
	UiLayout.pass_touch_through(_panel)


func _build_offer_card() -> void:
	_offer_card = PanelContainer.new()
	_offer_card.name = "OfferCard"
	_offer_card.visible = false
	_call.add_child(_offer_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_offer_card.add_child(box)
	_offer_kicker = _label("OfferKicker", true)
	box.add_child(_offer_kicker)
	_offer_summary = _label("OfferSummary", true)
	box.add_child(_offer_summary)
	_offer_rows = VBoxContainer.new()
	_offer_rows.name = "OfferTerms"
	_offer_rows.add_theme_constant_override("separation", 4)
	box.add_child(_offer_rows)
	_offer_buttons = HBoxContainer.new()
	_offer_buttons.name = "OfferButtons"
	_offer_buttons.add_theme_constant_override("separation", 8)
	_offer_buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_offer_buttons)
	_decline_button = Button.new()
	_decline_button.name = "DeclineButton"
	_decline_button.text = "Decline"
	_decline_button.pressed.connect(_on_decline)
	_offer_buttons.add_child(_decline_button)
	_accept_button = Button.new()
	_accept_button.name = "AcceptButton"
	_accept_button.theme_type_variation = "AccentButton"
	_accept_button.text = "Accept"
	_accept_button.icon = Glyphs.texture("check", 16)
	_accept_button.pressed.connect(_on_accept)
	_offer_buttons.add_child(_accept_button)


static func _label(label_name: String, wrap: bool) -> Label:
	var label := Label.new()
	label.name = label_name
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# --- Contact list ------------------------------------------------------------------

func _show_picker() -> void:
	_picker.visible = true
	_call.visible = false
	_negotiator.hang_up()
	for child in _picker_rows.get_children():
		_picker_rows.remove_child(child)
		child.queue_free()
	var partners := Negotiator.callable_partners(engine)
	var open := engine != null and engine.is_awaiting_player()
	_picker_title.text = _voice("Call a faction leader")
	if partners.is_empty():
		_picker_hint.text = "No one picks up: every faction is played by a person."
	elif not open:
		_picker_hint.text = "Calls are made during your turn."
	else:
		_picker_hint.text = "One deal per turn. A pledge stops that faction retaliating against you."
	for entry in partners:
		_picker_rows.add_child(_contact_row(entry, open))
	_restyle_picker()
	UiLayout.pass_touch_through(_picker)
	_refit_soon()


func _contact_row(entry: Dictionary, enabled: bool) -> Button:
	var faction_id := String(entry["faction"])
	var row := Button.new()
	row.name = "Contact_" + faction_id
	row.set_meta("faction", faction_id)
	row.disabled = not enabled
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.pressed.connect(_on_contact.bind(faction_id))
	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 6
	content.offset_bottom = -6
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)
	var s := _style_now()
	var avatar := TextureRect.new()
	avatar.name = "Avatar"
	avatar.texture = _avatar_texture(faction_id, 36)
	avatar.custom_minimum_size = Vector2(36, 36)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(avatar)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 1)
	content.add_child(texts)
	var name_label := _label("Name", true)
	name_label.text = "Call %s" % String(entry["name"])
	CrisisCard.style_label(name_label, s.font_ui_bold, 15, s.text_bright)
	texts.add_child(name_label)
	var role_label := _label("Role", true)
	role_label.text = _title_line(String(entry["title"]), String(entry["faction_name"]))
	CrisisCard.style_label(role_label, s.font_ui, 12, s.text_dim)
	texts.add_child(role_label)
	for node in content.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.minimum_size_changed.connect(_fit_row.bind(row, content))
	return row


func _fit_row(row: Button, content: Control) -> void:
	if is_instance_valid(row) and is_instance_valid(content):
		row.custom_minimum_size.y = maxf(ROW_HEIGHT, content.get_combined_minimum_size().y + 12.0)


func _on_contact(faction_id: String) -> void:
	if Negotiator.can_call(engine, faction_id):
		_start(faction_id)
		_apply_layout()


# --- The call ------------------------------------------------------------------------

func _start(partner_faction: String) -> void:
	# Hidden while the negotiator resets, so the old call's lines are not drawn again.
	_call.visible = false
	if not _negotiator.start(engine, llm, partner_faction):
		_show_picker()
		return
	_clear_bubbles()
	_picker.visible = false
	_call.visible = true
	var era: int = engine.tech.era if engine.tech != null else 1
	var actor: ActorBase = engine.factions[partner_faction]
	_avatar.texture = _avatar_texture(partner_faction, AVATAR_SIZE)
	_name_label.text = Characters.display_name(_negotiator.character)
	_title_label.text = _title_line(Characters.role_in(_negotiator.character, era), actor.display_name)
	_input.text = ""
	_refresh()
	if not _compact and is_inside_tree() and is_visible_in_tree():
		_input.grab_focus()


func _clear_bubbles() -> void:
	for child in _bubbles.get_children():
		_bubbles.remove_child(child)
		child.queue_free()
	_rendered = 0


## Brings the dialog in line with the call: new messages, the typing line,
## the offer card, the status line and what can be pressed.
func _refresh() -> void:
	if _call == null or not _call.visible:
		return
	var transcript := _negotiator.transcript
	var added := _rendered < transcript.size()
	while _rendered < transcript.size():
		_add_bubble(transcript[_rendered])
		_rendered += 1
	var short := _short_name()
	_typing.text = "%s is typing…" % short
	_typing.visible = _negotiator.waiting
	_fill_offer()
	_status.text = _status_text()
	var can_send := _negotiator.can_send()
	_input.editable = can_send
	_send_button.disabled = not can_send
	for chip in _quick.get_children():
		(chip as Button).disabled = not can_send
	if _negotiator.messages_left() == 0:
		_input.placeholder_text = "No messages left: accept, decline or hang up"
	elif not _negotiator.in_turn():
		_input.placeholder_text = "The call is over"
	else:
		_input.placeholder_text = "Say something to %s…" % short
	if added:
		_scroll_to_end()
	_refit_soon()


func _add_bubble(entry: Dictionary) -> void:
	var who := String(entry.get("who", "note"))
	var text := String(entry.get("text", ""))
	var s := _style_now()
	var row := HBoxContainer.new()
	row.name = "Message%d" % _rendered
	row.set_meta("who", who)
	_bubbles.add_child(row)
	if who == "note":
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var note := _label("Note", true)
		note.text = text
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		CrisisCard.style_label(note, s.font_ui, 12, s.text_dim)
		row.add_child(note)
		return
	row.alignment = BoxContainer.ALIGNMENT_END if who == "player" else BoxContainer.ALIGNMENT_BEGIN
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.set_meta("text", text)
	bubble.add_theme_stylebox_override("panel", _player_box if who == "player" else _partner_box)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if who == "player" else Control.SIZE_SHRINK_BEGIN
	row.add_child(bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	bubble.add_child(box)
	if who == "partner":
		var speaker := Label.new()
		speaker.name = "Speaker"
		speaker.text = _voice(_short_name())
		CrisisCard.style_label(speaker, s.font_mono, 10, s.faction_color(_negotiator.partner).lerp(s.text_bright, 0.2))
		box.add_child(speaker)
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CrisisCard.style_label(label, s.font_ui, 13 if _compact else 14, s.on_accent if who == "player" and s.era != 2 else s.text_bright)
	box.add_child(label)
	_fit_bubble(bubble)
	UiLayout.pass_touch_through(row)


## A bubble as wide as its text, at most BUBBLE_SHARE of the history.
func _fit_bubble(bubble: PanelContainer) -> void:
	var label := bubble.find_child("Text", true, false) as Label
	if label == null:
		return
	var box := bubble.get_theme_stylebox("panel")
	var padding := box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 24.0
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var natural := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else 200.0
	var widest := maxf(120.0, _history_width() * BUBBLE_SHARE)
	bubble.custom_minimum_size.x = clampf(natural + padding + 2.0, minf(96.0, widest), widest)


func _fit_bubbles() -> void:
	for row in _bubbles.get_children():
		var bubble := (row as Node).get_node_or_null("Bubble") as PanelContainer
		if bubble != null:
			_fit_bubble(bubble)


## The width the history gives its messages: the panel's inner width less the
## scroll bar.
func _history_width() -> float:
	var inner := _panel_width
	var box := _panel.get_theme_stylebox("panel") if _panel != null else null
	if box != null:
		inner -= box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	return maxf(160.0, inner - (0.0 if _compact else 12.0))


func _scroll_to_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(_history):
		_history.scroll_vertical = int(_history.get_v_scroll_bar().max_value)


## Labels that were hidden (the call view behind the contact list, a new offer
## card) are first measured at zero width, one word per line, and the
## overlay's containers size the panel to that height without shrinking it
## back. A frame later every label has its width: fit the panel again.
func _refit_soon() -> void:
	if _refit_pending or not is_inside_tree():
		return
	_refit_pending = true
	await get_tree().process_frame
	_refit_pending = false
	if not is_instance_valid(_panel):
		return
	_panel.reset_size()
	var center := _frame.get_parent() as Container
	if center != null:
		center.queue_sort()
		var scroll := center.get_parent() as Container
		if scroll != null:
			scroll.queue_sort()


func _fill_offer() -> void:
	var preview := _negotiator.preview
	_offer_card.visible = not preview.is_empty()
	if preview.is_empty():
		return
	for child in _offer_rows.get_children():
		_offer_rows.remove_child(child)
		child.queue_free()
	var s := _style_now()
	var role := _negotiator.player_role
	var partner := _negotiator.partner
	var short := _short_name()
	_offer_kicker.text = _voice("Offer from %s" % Characters.display_name(_negotiator.character))
	var summary := String(preview.get("summary", ""))
	_offer_summary.text = summary if summary != "" else Negotiator.describe_offer(_negotiator.offer, role, partner)
	_offer_summary.visible = _offer_summary.text != ""
	var give: Dictionary = preview.get("give", {})
	for key in give:
		_offer_row(Glyphs.for_currency(key), "You give %s" % _amount(role, key, float(give[key])), s.bad)
	var receive: Dictionary = preview.get("get", {})
	for key in receive:
		_offer_row(Glyphs.for_currency(key), "You get %s" % _amount(role, key, float(receive[key])), s.good)
	var pays: Dictionary = preview.get("partner_pays", {})
	for key in pays:
		_offer_row(Glyphs.for_currency(key), "%s pays %s for it" % [short, _amount(partner, key, float(pays[key]))], s.text_dim)
	var pledge := int(preview.get("pledge_turns", 0))
	if pledge > 0:
		_offer_row("support", "%s will not retaliate against you for %d turn%s" % [short, pledge, "" if pledge == 1 else "s"], s.good)
	var moves: Dictionary = preview.get("metrics", {})
	for key in WorldState.METRIC_KEYS:
		if moves.has(key):
			var delta := float(moves[key])
			var tone := s.good if UiFormat.is_improvement(key, delta) else s.bad
			_offer_row(Glyphs.for_metric(key), "%s %s  %s" % [UiFormat.metric_name(key), UiFormat.signed(delta), UiFormat.pips(delta)], tone)
	_accept_button.disabled = not _negotiator.in_turn()
	_decline_button.disabled = not _negotiator.in_turn()


func _offer_row(glyph: String, text: String, tone: Color) -> void:
	var s := _style_now()
	var row := HBoxContainer.new()
	row.name = "Term"
	row.add_theme_constant_override("separation", 8)
	row.add_child(Glyphs.icon(glyph, 16, tone, 1.9))
	var label := _label("TermText", true)
	label.text = text
	CrisisCard.style_label(label, s.font_ui, 13, tone.lerp(s.text_bright, 0.25))
	row.add_child(label)
	_offer_rows.add_child(row)


func _status_text() -> String:
	var parts: Array[String] = []
	if not _negotiator.active:
		parts.append("Call ended")
	elif _negotiator.uses_llm():
		parts.append("Live line")
	else:
		parts.append("Scripted line (no AI connected)")
	parts.append("%d of %d messages left" % [_negotiator.messages_left(), Negotiator.MAX_PLAYER_MESSAGES])
	parts.append("Grievance: %s" % Negotiator.grievance_word(_negotiator.grievance()))
	var state := _negotiator.deal_state()
	if String(state["text"]) != "":
		parts.append(String(state["text"]))
	return " · ".join(parts)


# --- Input ---------------------------------------------------------------------------

func _on_submit(text: String) -> void:
	if text.strip_edges() == "":
		return
	if _negotiator.send(text):
		_input.text = ""


func _on_quick(intent: String) -> void:
	_negotiator.send_quick(intent)


func _on_accept() -> void:
	var applied := _negotiator.accept()
	if bool(applied.get("ok", false)):
		deal_accepted.emit(applied)


func _on_decline() -> void:
	_negotiator.decline()


# --- Layout and style ----------------------------------------------------------------

func _apply_layout() -> void:
	if _panel == null:
		return
	var screen := size if size.x > 1.0 and size.y > 1.0 else get_viewport_rect().size
	UiLayout.set_overlay_margin(_frame, _compact)
	_panel_width = UiLayout.panel_width(screen.x, minf(DESKTOP_WIDTH, maxf(320.0, screen.x - 48.0)), _compact)
	var tall := maxf(0.0, screen.y - UiLayout.COMPACT_MARGIN * 2.0) if _compact else 0.0
	_panel.custom_minimum_size = Vector2(_panel_width, tall)
	_history.custom_minimum_size = Vector2(0, COMPACT_HISTORY_MIN if _compact else DESKTOP_HISTORY_HEIGHT)
	_offer_buttons.alignment = BoxContainer.ALIGNMENT_END
	for button in [_hang_up, _send_button, _accept_button, _decline_button, _picker_close]:
		(button as Button).custom_minimum_size = Vector2(0, TOUCH_HEIGHT if _compact else 0.0)
	for button in [_accept_button, _decline_button]:
		(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_END
	_hang_up.text = "" if _compact and screen.x < 360.0 else "Hang up"
	_apply_shade()
	_fit_bubbles()
	_refit_soon()


func _apply_shade() -> void:
	if _shade != null and _style != null:
		_shade.color = Color(_style.shade.r, _style.shade.g, _style.shade.b, 0.94 if _compact else maxf(_style.shade.a, 0.8))


func _restyle() -> void:
	_restyling = true
	_style = EraTheme.style_of(self)
	_era = _style.era
	var s := _style
	_partner_box = _bubble_box(s, false)
	_player_box = _bubble_box(s, true)
	var card := CrisisCard.shape_box(_card_radii(s), 1 if s.era == 2 else 10)
	card.bg_color = s.raised.lerp(s.accent, 0.06)
	card.set_border_width_all(1)
	card.border_color = Color(s.accent, 0.55)
	card.content_margin_left = 14
	card.content_margin_right = 14
	card.content_margin_top = 12
	card.content_margin_bottom = 12
	if s.glow > 0.0:
		card.shadow_color = Color(s.accent, s.glow * 0.5)
		card.shadow_size = 6
	_offer_card.add_theme_stylebox_override("panel", card)
	CrisisCard.style_label(_name_label, s.font_ui_bold if s.era == 3 else s.font_display, 18, s.text_bright)
	CrisisCard.style_label(_title_label, s.font_ui, 12, s.text_dim)
	CrisisCard.style_label(_status, s.font_mono, 11, s.text_dim)
	CrisisCard.style_label(_typing, s.font_ui, 12, s.accent)
	CrisisCard.style_label(_offer_kicker, s.font_mono, 11, s.accent)
	CrisisCard.style_label(_offer_summary, s.font_ui_bold, 14, s.text_bright)
	_hang_up.add_theme_color_override("font_color", s.critical)
	_hang_up.add_theme_color_override("font_hover_color", s.critical.lightened(0.2))
	_hang_up.add_theme_color_override("icon_normal_color", s.critical)
	_hang_up.add_theme_color_override("icon_hover_color", s.critical.lightened(0.2))
	_restyle_picker()
	if _call.visible and _negotiator.partner != "":
		_avatar.texture = _avatar_texture(_negotiator.partner, AVATAR_SIZE)
		# Bubbles carry the old era's shapes: draw the conversation again.
		_clear_bubbles()
		_refresh()
	elif _picker.visible and engine != null:
		_show_picker()
	_apply_shade()
	_restyling = false


func _restyle_picker() -> void:
	var s := _style_now()
	CrisisCard.style_label(_picker_title, s.font_ui_bold if s.era == 3 else s.font_display, 18, s.text_bright)
	CrisisCard.style_label(_picker_hint, s.font_ui, 12, s.text_dim)


## Speech bubbles in the era's shape: rounded with a tail corner in Era I,
## chamfered glass in Era II, uneven cells in Era III. The player's are filled
## with the accent; the partner's take the surface.
func _bubble_box(s: EraStyle, mine: bool) -> StyleBoxFlat:
	var radii: Array[float] = []
	match s.era:
		2:
			radii.assign([6.0, 6.0, 6.0, 6.0])
		3:
			radii.assign([20.0, 14.0, 22.0, 16.0])
		_:
			radii.assign([16.0, 16.0, 16.0, 16.0])
	if s.era != 2:
		# The tail: a tight corner toward the speaker.
		if mine:
			radii[2] = 4.0
		else:
			radii[3] = 4.0
	var box := CrisisCard.shape_box(radii, 1 if s.era == 2 else 10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 9
	match s.era:
		1:
			box.bg_color = s.accent if mine else s.raised
		2:
			box.bg_color = Color(s.accent, 0.16) if mine else Color(s.surface.lerp(s.accent, 0.05), 0.95)
			box.set_border_width_all(1)
			box.border_color = Color(s.accent, 0.7 if mine else 0.3)
		_:
			box.bg_color = s.surface.lerp(s.accent, 0.55) if mine else s.surface.lerp(s.text, 0.06)
			box.set_border_width_all(1)
			box.border_color = Color(s.accent, 0.5) if mine else Color(s.text, 0.16)
	return box


static func _card_radii(s: EraStyle) -> Array[float]:
	var radii: Array[float] = []
	match s.era:
		2:
			radii.assign([8.0, 8.0, 8.0, 8.0])
		3:
			radii.assign([24.0, 16.0, 26.0, 18.0])
		_:
			radii.assign([16.0, 16.0, 16.0, 16.0])
	return radii


func _avatar_texture(faction_id: String, avatar_size: int) -> Texture2D:
	var s := _style_now()
	var tone := s.faction_color(faction_id)
	return Glyphs.tile(Glyphs.for_faction(faction_id), avatar_size, Color(tone, 0.2), tone.lerp(s.text_bright, 0.15),
		roundi(avatar_size * 0.5) if s.era != 2 else 6)


func _style_now() -> EraStyle:
	return _style if _style != null else EraTheme.style_of(self)


func _short_name() -> String:
	return String(Characters.get_character(_negotiator.character).get("short", "They"))


## Labels in the era's voice: as written in Era I, capitals in Era II, lower
## case in Era III.
func _voice(text: String) -> String:
	match _style_now().era:
		2:
			return text.to_upper()
		3:
			return text.to_lower()
	return text


## "Data labeler in Lagos · Citizen Coalition", or the role alone when it
## already names the faction ("Chair of the Governance Council").
static func _title_line(role: String, faction_name: String) -> String:
	if role == "":
		return faction_name
	if role.to_lower().contains(faction_name.to_lower()):
		return role
	return "%s · %s" % [role, faction_name]


## "$60B" or "12 Political Capital".
static func _amount(role: String, key: String, value: float) -> String:
	if String(UiFormat.resource_info(role, key).get("unit", "")) == "$B":
		return UiFormat.format_resource(role, key, value)
	return "%s %s" % [UiFormat.format_resource(role, key, value), UiFormat.resource_label(role, key)]
