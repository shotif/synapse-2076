class_name CastPanel
extends VBoxContainer
## The People page: everyone the players have met, most recent first. Each
## person gets a card with a large Portrait at their age in the year shown,
## their name, what they do in this hardware era, a stance chip, what they
## remember about the players, how often they have crossed paths, and a small
## "then → now" pair: as they were at the first meeting and as they are now.
##
##   cast_panel.set_cast(CastPanel.entries_from(engine.deck.characters_met,
##       engine.deck.characters, memories), engine.get_year())
##
## Desktop: two or three columns, depending on the width. Compact (phones and
## tablets): one column. The cards scroll inside the panel (touch drags reach
## the ScrollContainer); a host that scrolls itself, such as a
## UiLayout.build_overlay() frame, calls set_scrolling(false) so the panel
## grows to fit them. Cards and type follow the era theme; set_closable()
## adds a close button that emits closed.

signal closed

const DESKTOP_PORTRAIT := 112.0
const COMPACT_PORTRAIT := 88.0
const MINI_PORTRAIT := 44.0
## Desktop widths (px) from which the cards run in two or three columns.
const TWO_COLUMNS := 700.0
const THREE_COLUMNS := 1080.0
const GAP := 12
const EMPTY_TEXT := "You haven't met anyone yet."

var compact := false
## The year the cast is shown in.
var year := SimConstants.START_YEAR

var _entries: Array = []
var _era := 0
var _restyle_queued := false
var _scrolling := true
var _title_label: Label
var _meta_label: Label
var _close_button: Button
var _scroll: ScrollContainer
var _grid: GridContainer
var _empty: VBoxContainer


## The node tree is built at construction, so the panel takes its cast before
## it joins the scene.
func _init() -> void:
	name = "CastPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.theme_type_variation = "HeaderTitle"
	titles.add_child(_title_label)
	_meta_label = Label.new()
	_meta_label.name = "Meta"
	_meta_label.theme_type_variation = "DimLabel"
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_meta_label)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.theme_type_variation = "GhostButton"
	_close_button.icon = Glyphs.texture("close", 18)
	_close_button.tooltip_text = "Close"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.visible = false
	_close_button.pressed.connect(func(): closed.emit())
	header.add_child(_close_button)

	_scroll = ScrollContainer.new()
	_scroll.name = "CastScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_grid)

	_empty = VBoxContainer.new()
	_empty.name = "Empty"
	_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.add_theme_constant_override("separation", 10)
	add_child(_empty)
	var icon := Glyphs.icon("person", 28, Color.WHITE)
	icon.name = "EmptyIcon"
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty.add_child(icon)
	var empty_label := Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = EMPTY_TEXT
	empty_label.theme_type_variation = "DimLabel"
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(empty_label)
	_apply_mode()
	_rebuild()


func _ready() -> void:
	_restyle()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_THEME_CHANGED and EraTheme.style_of(self).era != _era or what == NOTIFICATION_TRANSLATION_CHANGED) \
			and is_node_ready() and not _restyle_queued:
		_restyle_queued = true
		_restyle.call_deferred()
	elif what == NOTIFICATION_RESIZED:
		_update_columns()


# --- Public API ---------------------------------------------------------------------

## Shows [param entries] (see entries_from) as they are in [param year_value].
## Calling it again with the same cast and year changes nothing.
func set_cast(entries: Array, year_value: float) -> void:
	var value := year_value if is_finite(year_value) else SimConstants.START_YEAR
	if entries == _entries and is_equal_approx(value, year) and _grid.get_child_count() == entries.size():
		return
	_entries = entries.duplicate(true)
	year = value
	_rebuild()


## One column (phones, tablets) or two to three (desktop).
func set_compact(enabled: bool) -> void:
	if compact == enabled:
		return
	compact = enabled
	_apply_mode()
	_rebuild()


## Shows a close button that emits closed.
func set_closable(enabled: bool) -> void:
	_close_button.visible = enabled


## Scrolls the cards inside the panel (the default, for a fixed-size host
## such as a tab) or, when [param enabled] is false, grows to fit them, for a
## host that scrolls itself (a UiLayout.build_overlay() frame).
func set_scrolling(enabled: bool) -> void:
	_scrolling = enabled
	_apply_mode()


func card_count() -> int:
	return _grid.get_child_count()


func column_count() -> int:
	return _grid.columns


## The cast as entries for set_cast(), most recently met first:
## [{id, score, memory, first_turn, last_turn, count}].
## [param deck_characters_met] maps character id -> {first_turn, last_turn,
## count} (also accepted: {first, last, times}, an Array of turns or a count);
## [param scores] maps id -> score (DilemmaDeck.characters); [param memories]
## maps id -> memory line. Unknown ids are left out.
static func entries_from(deck_characters_met: Dictionary, scores: Dictionary, memories: Dictionary) -> Array:
	var out: Array = []
	for key in deck_characters_met:
		var id := String(key)
		if not Characters.exists(id):
			continue
		var info: Variant = deck_characters_met[key]
		var first := 0
		var last := 0
		var count := 1
		if info is Dictionary:
			var record: Dictionary = info
			first = int(record.get("first_turn", record.get("first", 0)))
			last = int(record.get("last_turn", record.get("last", first)))
			count = int(record.get("count", record.get("times", 1)))
		elif info is Array and not (info as Array).is_empty():
			var turns: Array = info
			first = int(turns.min())
			last = int(turns.max())
			count = turns.size()
		elif info is int or info is float:
			count = int(info)
		out.append({"id": id, "score": float(scores.get(id, 0.0)), "memory": String(memories.get(id, "")),
			"first_turn": first, "last_turn": maxi(last, first), "count": maxi(count, 1)})
	out.sort_custom(_more_recent)
	return out


static func _more_recent(a: Dictionary, b: Dictionary) -> bool:
	if int(a["last_turn"]) != int(b["last_turn"]):
		return int(a["last_turn"]) > int(b["last_turn"])
	if int(a["count"]) != int(b["count"]):
		return int(a["count"]) > int(b["count"])
	return String(a["id"]) < String(b["id"])


## "Met 3 times · since 2031" / "Met once · 2031".
static func met_line(count: int, first_turn: int) -> String:
	var since := int(SimConstants.year_for_turn(first_turn))
	if count <= 1:
		return I18n.t("Met once · %d") % since
	return I18n.t("Met %d times · since %d") % [count, since]


# --- Building -----------------------------------------------------------------------

func _apply_mode() -> void:
	# Phones scroll by dragging; the bar would push full-width cards off screen.
	if not _scrolling:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if compact else ScrollContainer.SCROLL_MODE_AUTO


func _restyle() -> void:
	_restyle_queued = false
	_era = EraTheme.style_of(self).era
	_rebuild()


func _rebuild() -> void:
	var s := EraTheme.style_of(self)
	_title_label.text = s.label(tr("People"))
	var people := _entries.size()
	if people == 1:
		_meta_label.text = tr("1 person · %d") % int(year)
	else:
		_meta_label.text = tr("%d people · %d") % [people, int(year)] if people > 0 else str(int(year))
	(_empty.get_node("EmptyIcon") as TextureRect).self_modulate = s.text_dim
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for entry in _entries:
		_grid.add_child(_card(entry, s))
	var empty := _entries.is_empty()
	_empty.visible = empty
	_scroll.visible = not empty
	_update_columns()
	UiLayout.pass_touch_through(self)


func _update_columns() -> void:
	if _grid == null:
		return
	var width := size.x if size.x > 1.0 else 0.0
	var columns := 1
	if not compact and width >= THREE_COLUMNS:
		columns = 3
	elif not compact and width >= TWO_COLUMNS:
		columns = 2
	_grid.columns = columns


func _card(entry: Dictionary, s: EraStyle) -> PanelContainer:
	var id := String(entry.get("id", ""))
	var score := float(entry.get("score", 0.0))
	var memory := String(entry.get("memory", "")).strip_edges()
	var card := PanelContainer.new()
	card.name = "Person_" + id
	card.theme_type_variation = "CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("character_id", id)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)

	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 12 if compact else 14)
	body.add_child(top)
	var side := COMPACT_PORTRAIT if compact else DESKTOP_PORTRAIT
	var face := Portrait.new()
	face.name = "Portrait"
	face.custom_minimum_size = Vector2(side, side)
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.set_character(id, year)
	face.set_mood(score)
	top.add_child(face)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	top.add_child(info)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = Characters.display_name(id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	CrisisCard.style_label(name_label, s.font_ui_bold, 16 if compact else 17, s.text_bright)
	info.add_child(name_label)
	var role := Label.new()
	role.name = "Role"
	role.text = CharacterBadge.role_line(id, year)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CrisisCard.style_label(role, s.font_ui, 13, s.text_dim)
	info.add_child(role)
	var chip_row := HBoxContainer.new()
	chip_row.add_child(_stance_chip(score, s))
	info.add_child(chip_row)
	var met := Label.new()
	met.name = "Met"
	met.text = met_line(int(entry.get("count", 1)), int(entry.get("first_turn", 0)))
	met.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CrisisCard.style_label(met, s.font_mono, 11, s.text_dim)
	info.add_child(met)

	if memory != "":
		var line := Label.new()
		line.name = "Memory"
		line.text = tr(memory)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CrisisCard.style_label(line, CharacterBadge.italic(s.font_ui), 13 if compact else 14, s.text)
		body.add_child(line)
	var then_year := SimConstants.year_for_turn(int(entry.get("first_turn", 0)))
	if _changed_since(id, then_year, year):
		body.add_child(_then_and_now(id, then_year, score, s))
	return card


func _stance_chip(score: float, s: EraStyle) -> PanelContainer:
	var stance := Characters.stance(score)
	var tone := s.good if CharacterBadge.WARM_STANCES.has(stance) else (s.bad if CharacterBadge.COLD_STANCES.has(stance) else s.text_dim)
	var chip := PanelContainer.new()
	chip.name = "Stance"
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(99 if s.era != 2 else 3)
	box.corner_detail = 1 if s.era == 2 else 8
	box.bg_color = Color(tone, 0.14)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	if s.era != 1:
		box.set_border_width_all(1)
		box.border_color = Color(tone, 0.5)
	chip.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.name = "StanceLabel"
	label.text = CharacterBadge.voice(tr(stance), s.era)
	CrisisCard.style_label(label, s.font_mono, 11, tone)
	chip.add_child(label)
	return chip


## Whether [param id] looks different in [param now] than they did earlier, in [param then].
static func _changed_since(id: String, then: float, now: float) -> bool:
	if then >= now:
		return false
	if Characters.is_machine(id):
		return Characters.version_in(id, then) != Characters.version_in(id, now)
	return Characters.age_in(id, then) != Characters.age_in(id, now)


## The person at the first meeting and now, side by side.
func _then_and_now(id: String, then_year: float, score: float, s: EraStyle) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ThenNow"
	row.add_theme_constant_override("separation", 8)
	for pass_year in [then_year, year]:
		var mini := Portrait.new()
		mini.name = "Then" if pass_year == then_year else "Now"
		mini.custom_minimum_size = Vector2(MINI_PORTRAIT, MINI_PORTRAIT)
		mini.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mini.set_character(id, float(pass_year))
		mini.set_mood(score)
		row.add_child(mini)
		if pass_year == then_year:
			var arrow := Glyphs.icon("arrow_right", 14, s.text_dim)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 0)
	row.add_child(labels)
	var years := Label.new()
	years.name = "Years"
	years.text = "%d → %d" % [int(then_year), int(year)]
	years.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CrisisCard.style_label(years, s.font_mono, 11, s.text)
	labels.add_child(years)
	var change := Label.new()
	change.name = "Change"
	if Characters.is_machine(id):
		change.text = "v%d → v%d" % [Characters.version_in(id, then_year), Characters.version_in(id, year)]
	else:
		change.text = tr("age %d → %d") % [Characters.age_in(id, then_year), Characters.age_in(id, year)]
	change.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CrisisCard.style_label(change, s.font_mono, 11, s.text_dim)
	labels.add_child(change)
	return row
