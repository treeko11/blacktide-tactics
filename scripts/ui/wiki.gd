class_name Wiki
extends Control

## The almanac: every pirate, trait, item, monster and wave in the game, plus
## the rules, in one browsable reference.
##
## **Why its pages are not the tooltip's.** The floating inspector answers "what
## is this thing in front of me, right now" — a pirate at the star it happens to
## be, an item's pairings ticked against what is actually in the hold. The
## almanac answers "what exists, and what would it do": all three stars side by
## side, every breakpoint of a trait, every wave of the run. Those are different
## pages, so they are built here rather than borrowed from `Tooltip`. What the
## two share is the Defs they both read, which remain the only copy of the
## numbers — nothing in this file hard-codes a stat, a breakpoint or a recipe.
##
## **Everything is cross-linked.** A pirate names its two traits, a trait lists
## its pirates, a component names what it forges into, a forged item names its
## components, a wave names its monsters. That is the difference between a wiki
## and five lists, and it is why the pages are BBCode with `[url]` in them rather
## than assembled out of Controls: a link is a tag, not a widget.
##
## **Two shapes, chosen by width and not by `Layout.compact()`.** Given room, the
## list of entries sits beside the page. A portrait phone has no such room, so it
## drills down instead — the list is the whole screen, tapping an entry replaces
## it with the page, and BACK returns. A landscape phone is 844 points wide and
## does have room, which is why the test below is the width and not the layout
## mode: "compact" says the HUD reflowed, it does not say the screen is narrow.
##
## The back stack is what makes the cross-links safe to follow. Three links deep
## into the trait that a pirate shares with an item's carrier, BACK is the only
## way anyone gets home.

## Where a link goes. `[url=section/entry]`, and an empty entry opens the
## section's list.
const LINK := "[color=#7fe3ff][url=%s/%s]%s[/url][/color]"

## Two panes need this much room. A portrait phone is 375-430 points wide and
## drills down; a landscape phone is 667-932 and does not.
const TWO_PANE_WIDTH := 620.0

## Tall enough for a figure to be a figure rather than a smear. Fifty-one pirates
## scroll either way; the question is only whether they are scannable.
const ROW_HEIGHT := 28.0

const LIST_WIDTH := 224.0

## As wide as the box ever gets. Past this a line of body text is too long to
## track back to the start of the next one.
const MAX_BOX_WIDTH := 880.0

const SECTIONS := [
	{ "id": &"guide", "label": "SAILING" },
	{ "id": &"pirates", "label": "PIRATES" },
	{ "id": &"traits", "label": "TRAITS" },
	{ "id": &"items", "label": "ITEMS" },
	{ "id": &"monsters", "label": "MONSTERS" },
	{ "id": &"seas", "label": "SEAS" },
]

## The rules, as pages rather than as one wall of text. Splitting them is what
## lets the guide sit in the same list-and-page shape as everything else, and it
## means "how does gold work" is one tap rather than a paragraph to find.
const GUIDE := [
	{ "id": &"loop", "title": "The Loop", "icon": "⚓" },
	{ "id": &"upgrading", "title": "Upgrading", "icon": "⭐" },
	{ "id": &"scaling", "title": "Ability Scaling", "icon": "🔮" },
	{ "id": &"traits", "title": "Traits", "icon": "🧭" },
	{ "id": &"gold", "title": "Gold", "icon": "🪙" },
	{ "id": &"items", "title": "Items", "icon": "🛠️" },
	{ "id": &"monsters", "title": "Monster Waves", "icon": "🐙" },
	{ "id": &"sea", "title": "The Sea", "icon": "🌊" },
	{ "id": &"controls", "title": "Controls", "icon": "🕹️" },
]

## Stages the wave table covers. Stage 7 is the repeating one, so it is the last
## row and says so.
const WAVE_STAGES := 7

var _box: PanelContainer = null
var _panes: HBoxContainer = null
var _list_pane: Control = null
var _list: VBoxContainer = null
var _page_pane: Control = null
var _page: RichTextLabel = null
var _page_portrait: UnitPortrait = null
var _page_scroll: ScrollContainer = null
var _back: Button = null
var _crumb: Label = null
var _tabs: HFlowContainer = null

var _section: StringName = &"guide"
var _entry: StringName = &"loop"

## Where BACK goes: [section, entry] pairs, pushed by every link followed.
var _history: Array = []

var _page_width: float = 400.0

## The pane shape the panes are currently built as, so `_fit_box` can tell a
## resize that crossed `TWO_PANE_WIDTH` from one that did not.
var _showing_two_panes := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Clicking off the almanac closes it. It is a reference, not a decision the
	# round is waiting on, so it must never be something to escape from.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and not event.pressed:
			close())
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0e2534"), UITheme.LINE, 10))
	centre.add_child(_box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	_box.add_child(stack)

	stack.add_child(_build_header())
	stack.add_child(_build_tabs())

	_panes = HBoxContainer.new()
	_panes.add_theme_constant_override("separation", 10)
	_panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_panes)

	_fit_box()

	_list_pane = _build_list_pane()
	_panes.add_child(_list_pane)
	_page_pane = _build_page_pane()
	_panes.add_child(_page_pane)
	_showing_two_panes = _two_pane()


## Sizes the box against the room it is actually in, on every resize.
##
## Two things were wrong with doing this once, from `Layout.css_size`. The
## measurement was of the wrong space — see the note on that field — so on any
## screen larger than the 1600x900 design the box came out taller than the space
## it is centred in, and a `CenterContainer` cannot centre a child bigger than
## itself: it pins it to the top and the whole overflow hangs off the bottom. A
## 1920x1040 window lost 15 units of the dialog and a 2560x1400 one lost a third
## of it, on the first thing a new run puts on the screen.
##
## And a fixed size set at build time goes stale: a desktop window dragged from
## 1280x720 to full screen never crosses a breakpoint, so Main never rebuilds the
## HUD, and the box would have kept the size the small window gave it. The Wiki
## is the full rect, so its own `size` is the room the box has and the resize
## notification is the one signal that arrives on the web as well.
##
## The pane shape is re-fitted here too, and not only the numbers. Reading the
## width in one place and the shape of the panes in another is how a box 580
## points wide ends up holding a 224-point list beside a page asked for 570: the
## two answers have to come out of the same measurement.
func _fit_box() -> void:
	if _box == null:
		return
	var room := size
	var box_width := minf(MAX_BOX_WIDTH, room.x - 20.0)
	var two := room.x >= TWO_PANE_WIDTH
	_box.custom_minimum_size = Vector2(box_width, room.y * 0.88)

	# The box carries 8 points of panel margin either side; each pane carries 8
	# more, and a vertical scrollbar eats about 14. Measured out rather than
	# guessed, because a RichTextLabel given no width wraps every word onto its
	# own line and a page 40 lines long scrolls forever.
	var inner := box_width - 16.0
	var page_width := inner - (LIST_WIDTH + 10.0) if two else inner
	_page_width = page_width - 30.0
	if _page != null:
		_page.custom_minimum_size = Vector2(_page_width, 0)

	if _list_pane == null:
		return
	_list_pane.custom_minimum_size = Vector2(LIST_WIDTH if two else 0.0, 0)
	_list_pane.size_flags_horizontal = (
		Control.SIZE_FILL if two else Control.SIZE_EXPAND_FILL)
	# Which pane is showing is `_render`'s answer, and it is a different answer
	# either side of the line — a drilled-in phone shows one pane and hides the
	# other, and a box that has just become wide enough must show both.
	if two != _showing_two_panes:
		_showing_two_panes = two
		_render()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_box()


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_back = UITheme.button("«  BACK", UITheme.FONT_SMALL)
	_back.pressed.connect(_go_back)
	row.add_child(_back)

	var title := UITheme.label("The Almanac", 22, UITheme.GOLD)
	row.add_child(title)

	_crumb = UITheme.label("", UITheme.FONT_TINY, UITheme.MUTED)
	_crumb.visible = not Layout.compact()
	row.add_child(_crumb)

	row.add_child(UITheme.spacer())

	var close_button := UITheme.button("CLOSE", UITheme.FONT_SMALL)
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row


## The section tabs. A flow container rather than a row: five labels at the
## desktop font are 430 points wide, which a 375-point phone does not have, and a
## tab that is off the edge is a section of the almanac nobody can reach.
func _build_tabs() -> Control:
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	_tabs.add_theme_constant_override("v_separation", 4)
	for section in SECTIONS:
		var id: StringName = section["id"]
		var tab := UITheme.button(section["label"],
			UITheme.FONT_TINY if Layout.compact() else UITheme.FONT_SMALL)
		tab.pressed.connect(func(): _open_section(id))
		tab.set_meta(&"section", id)
		_tabs.add_child(tab)
	return _tabs


func _build_list_pane() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(LIST_WIDTH if _two_pane() else 0.0, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not _two_pane():
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0a1c28"), Color("18384a"), 7))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	# Every row is a Button, and a Button swallows the drag that starts on it.
	# Without this the only part of a fifty-one pirate list a finger could scroll
	# was the two points of separation between rows.
	TouchScroll.attach(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	return panel


func _build_page_pane() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0a1c28"), Color("18384a"), 7))

	_page_scroll = ScrollContainer.new()
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_page_scroll)
	# A page is a RichTextLabel, which is STOP so its links can be clicked, so it
	# needs the same help as the list.
	TouchScroll.attach(_page_scroll)

	# A column rather than the label alone, so a champion's entry can be headed
	# by the figure the board draws. Everything else in the almanac — a trait, an
	# item, a wave, a rules page — is text and gets no header at all.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.add_child(column)

	_page_portrait = UnitPortrait.new(_portrait_size())
	_page_portrait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_page_portrait.visible = false
	column.add_child(_page_portrait)

	_page = RichTextLabel.new()
	_page.bbcode_enabled = true
	_page.fit_content = true
	_page.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.custom_minimum_size = Vector2(_page_width, 0)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_font_size_override("normal_font_size", UITheme.FONT_SMALL)
	_page.add_theme_font_size_override("bold_font_size", UITheme.FONT_SMALL)
	_page.scroll_active = false
	_page.meta_clicked.connect(_on_link)
	column.add_child(_page)
	return panel


## Big enough to be a plate rather than an icon, and still leaving a portrait
## phone's 330-point page room to be a page.
func _portrait_size() -> Vector2:
	return Vector2(92.0, 106.0) if _page_width >= 360.0 else Vector2(74.0, 86.0)


## Whether the list sits beside the page rather than being drilled into.
##
## The room the almanac has, not `Layout.css_size`: what decides this is the
## width the panes are laid out in, and on the wide layout those are different
## numbers — see the note on `Layout.css_size`.
func _two_pane() -> bool:
	return size.x >= TWO_PANE_WIDTH


# =============================================================================
#  Navigation
# =============================================================================

func is_open() -> bool:
	return visible


## Opens the almanac, at a page if one is named and where it was left otherwise.
##
## Coming back to the page you were reading is the point: the almanac is opened
## mid-decision — "what does this trait actually give me at four" — and closed
## again the moment the answer is had.
func open(section: StringName = &"", entry: StringName = &"") -> void:
	if section != &"":
		_section = section
		_entry = entry
	_history.clear()
	visible = true
	_render()


func close() -> void:
	visible = false


func _open_section(section: StringName) -> void:
	_push()
	_section = section
	_entry = &""
	_render()


## Opens an entry, unless the tap that asked for it was really a scroll.
##
## A row and a link both act on release, and a finger that has just dragged the
## list is still resting on whatever it started from — so without this, scrolling
## a phone's list opened whichever pirate the thumb happened to land on. Asked
## here rather than at each `pressed`, because both the rows and the page's
## cross-links arrive through this one door.
func _open_entry(section: StringName, entry: StringName) -> void:
	if TouchScroll.dragged():
		return
	_push()
	_section = section
	_entry = entry
	_render()


func _push() -> void:
	_history.append([_section, _entry])
	# A stack that only ever grows is a stack holding every page of a long read.
	if _history.size() > 32:
		_history.remove_at(0)


func _go_back() -> void:
	if not _history.is_empty():
		var previous: Array = _history.pop_back()
		_section = previous[0]
		_entry = previous[1]
		_render()
		return
	# Nothing to pop, but drilled into an entry on a phone: the list is "back".
	if _entry != &"" and not _two_pane():
		_entry = &""
		_render()


## A `[url=section/entry]` was clicked. Unknown links are ignored rather than
## opening a blank page — a typo in a page's BBCode should read as a dead link,
## not as the almanac breaking.
func _on_link(meta: Variant) -> void:
	var parts := String(meta).split("/", true, 1)
	if parts.size() < 1:
		return
	var section := StringName(parts[0])
	var entry := StringName(parts[1]) if parts.size() > 1 else &""
	if not _section_exists(section):
		return
	if entry != &"" and _find(section, entry).is_empty():
		return
	_open_entry(section, entry)


func _section_exists(section: StringName) -> bool:
	for s in SECTIONS:
		if s["id"] == section:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# =============================================================================
#  Drawing what is selected
# =============================================================================

func _render() -> void:
	var rows := entries(_section)
	# Given two panes there is always a page showing, because half a dialog of
	# empty panel reads as something that failed to load.
	if _entry == &"" and _two_pane() and not rows.is_empty():
		_entry = rows[0]["id"]

	for tab in _tabs.get_children():
		var button: Button = tab
		var selected: bool = button.get_meta(&"section") == _section
		button.add_theme_stylebox_override("normal", UITheme.panel_style(
			Color("17415a") if selected else UITheme.PANEL_2,
			UITheme.GOLD if selected else UITheme.LINE, 5))

	_fill_list(rows)
	_page.text = _page_text()
	_show_page_portrait()
	# A page followed from a link opens at the top of itself. Left alone the
	# scroll stays where the last page was read, which lands a short entry
	# somewhere below its own title.
	_page_scroll.scroll_vertical = 0

	var drilled := _entry != &"" and not _two_pane()
	_list_pane.visible = not drilled
	_page_pane.visible = _two_pane() or drilled
	_back.visible = not _history.is_empty() or drilled
	_crumb.text = _breadcrumb()


func _breadcrumb() -> String:
	for section in SECTIONS:
		if section["id"] != _section:
			continue
		var found := _find(_section, _entry)
		if found.is_empty():
			return String(section["label"]).capitalize()
		return "%s  ·  %s" % [String(section["label"]).capitalize(), found["title"]]
	return ""


func _fill_list(rows: Array) -> void:
	UITheme.clear_children(_list)

	var group := ""
	for entry in rows:
		var heading: String = entry.get("group", "")
		if heading != group:
			group = heading
			if group != "":
				var label := UITheme.heading(group)
				label.add_theme_constant_override("line_spacing", 4)
				_list.add_child(label)

		var id: StringName = entry["id"]
		var selected: bool = id == _entry
		# A champion row is the pirate itself; everything else keeps its emoji,
		# because a trait and an item have no body to draw.
		var champion: ChampionDef = null
		if _section in [&"pirates", &"monsters"] and id != &"waves":
			champion = Content.champion(id)

		var row := UITheme.button("%s  %s" % [entry["icon"], entry["title"]],
			UITheme.FONT_SMALL)
		if champion != null:
			row.text = entry["title"]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_color_override("font_color",
			UITheme.GOLD_BRIGHT if selected else entry.get("color", UITheme.INK))
		if selected:
			row.add_theme_stylebox_override("normal",
				UITheme.panel_style(Color("17415a"), UITheme.GOLD, 5))
		if champion != null:
			_seat_row_portrait(row, champion)
		var section := _section
		row.pressed.connect(func(): _open_entry(section, id))
		_list.add_child(row)


## Puts a figure at the left of a list row.
##
## The portrait is a child of the Button rather than beside it, so the whole row
## stays one clickable thing — a row split into a portrait and a button is a row
## with a dead patch on its left. It is `MOUSE_FILTER_IGNORE` by construction, so
## the press still reaches the button underneath it.
##
## The text is moved out of its way with the content margin, which has to be set
## on **every** state box: overriding only `normal` leaves the label jumping
## thirty points left the moment the cursor enters the row.
func _seat_row_portrait(row: Button, champion: ChampionDef) -> void:
	const INSET := 30
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBoxFlat = row.get_theme_stylebox(state).duplicate()
		box.content_margin_left = INSET
		row.add_theme_stylebox_override(state, box)

	row.custom_minimum_size.y = ROW_HEIGHT
	var portrait := UnitPortrait.new(Vector2(24.0, ROW_HEIGHT - 3.0))
	var tier: Color = UITheme.cost_color(champion.cost)
	portrait.champion = champion
	portrait.team_color = tier
	portrait.rim_color = tier
	portrait.position = Vector2(3.0, 1.5)
	row.add_child(portrait)


# =============================================================================
#  What is in each section
# =============================================================================

## Every entry of a section, in list order: id, title, icon, and optionally a
## group heading and a colour.
##
## Public, along with `page_for`, because the way an almanac breaks is quietly —
## a champion added to `data/` and never listed, a cross-link to an id that was
## renamed — and neither shows up as a crash. `test_wiki.gd` walks every section
## and follows every link, and it needs to do that without a scene tree around it.
func entries(section: StringName) -> Array:
	match section:
		&"guide":
			return GUIDE.duplicate()
		&"pirates":
			return _champion_entries(false)
		&"monsters":
			var out: Array = [{
				"id": &"waves", "title": "Every Wave", "icon": "🌊",
				"group": "The waves",
			}]
			out.append_array(_champion_entries(true))
			return out
		&"traits":
			var traits: Array = []
			for kind in [TraitDef.Kind.ORIGIN, TraitDef.Kind.CLASS]:
				var heading := "Origins" if kind == TraitDef.Kind.ORIGIN else "Classes"
				for id in Content.trait_ids_of_kind(kind):
					var def: TraitDef = Content.trait_def(id)
					traits.append({
						"id": id, "title": def.display_name, "icon": def.icon,
						"group": heading,
					})
			return traits
		&"seas":
			var seas: Array = []
			for def in Content.seas():
				seas.append({
					"id": def.id, "title": def.display_name, "icon": def.icon,
					"group": "Fair winds" if def.boon else "Hazards",
				})
			# Hazards first. There are five of each now, and a reader looking one
			# up mid-round is far more often looking up the one hurting them.
			seas.sort_custom(func(a, b): return a["group"] > b["group"])
			return seas
		&"items":
			var items: Array = []
			for component in Content.components():
				items.append({
					"id": component.id, "title": component.display_name,
					"icon": component.icon, "group": "Components",
				})
			var forged: Array = Content.forged_items().duplicate()
			forged.sort_custom(func(a, b): return a.display_name < b.display_name)
			for item in forged:
				items.append({
					"id": item.id, "title": item.display_name,
					"icon": item.icon, "group": "Forged",
				})
			var greater: Array = Content.capstones().duplicate()
			greater.sort_custom(func(a, b): return a.display_name < b.display_name)
			for item in greater:
				items.append({
					"id": item.id, "title": item.display_name,
					"icon": item.icon, "group": "Greater",
				})
			return items
	return []


## The roster, grouped by cost — which is how a player thinks about it, because
## cost is what decides both the price and how often the shop offers it.
func _champion_entries(monsters: bool) -> Array:
	var out: Array = []
	var sorted: Array = []
	for champion in Content.champions():
		if (champion.cost == 0) == monsters:
			sorted.append(champion)
	sorted.sort_custom(func(a, b):
		if a.cost != b.cost:
			return a.cost < b.cost
		return a.display_name < b.display_name)
	for champion in sorted:
		out.append({
			"id": champion.id, "title": champion.display_name, "icon": champion.icon,
			"group": "Monsters" if monsters else "%d gold" % champion.cost,
			"color": Content.cost_color(champion.cost),
		})
	return out


func _find(section: StringName, entry: StringName) -> Dictionary:
	if entry == &"":
		return {}
	for row in entries(section):
		if row["id"] == entry:
			return row
	return {}


# =============================================================================
#  The pages
# =============================================================================

func _page_text() -> String:
	if _entry == &"":
		return "[color=#7c93a4]Choose an entry.[/color]"
	return page_for(_section, _entry)


## One page, as BBCode. See `entries` for why this is public.
func page_for(section: StringName, entry: StringName) -> String:
	match section:
		&"guide":
			return _guide_page(entry)
		&"pirates", &"monsters":
			if entry == &"waves":
				return _waves_page()
			return _champion_page(entry)
		&"traits":
			return _trait_page(entry)
		&"items":
			return _item_page(entry)
		&"seas":
			return _sea_entry_page(entry)
	return ""


## The figure at the head of a champion's entry, or nothing.
##
## Driven off the section and entry rather than off the page text, because the
## page is one BBCode string by the time it exists and nothing in it says what it
## is about any more.
func _show_page_portrait() -> void:
	if _page_portrait == null:
		return
	var champion: ChampionDef = null
	if _section in [&"pirates", &"monsters"] and _entry != &"" and _entry != &"waves":
		champion = Content.champion(_entry)
	_page_portrait.visible = champion != null
	_page_portrait.champion = champion
	if champion != null:
		var tier: Color = UITheme.cost_color(champion.cost)
		_page_portrait.team_color = tier
		_page_portrait.rim_color = tier


## An empty `icon` is allowed and means the page has the thing drawn at the top
## of it already — a champion's entry does, and a glyph beside a portrait of the
## same pirate is the old identifier arguing with the new one. Traits and items
## keep theirs, having no figure to draw.
static func _title(icon: String, name: String, tail: String = "") -> String:
	var line := "[font_size=19][b]%s[/b][/font_size]" % name
	if icon != "":
		line = "[font_size=19][b]%s %s[/b][/font_size]" % [icon, name]
	if tail != "":
		line += "   %s" % tail
	return line


static func _heading(text: String) -> String:
	return "[color=#7c93a4]%s[/color]" % text.to_upper()


static func _link(section: StringName, entry: StringName, text: String) -> String:
	return LINK % [section, entry, text]


## A pirate or a monster: what it costs, what it is, what it becomes at each
## star, and what it casts.
##
## The three-star spread is the whole reason this page exists rather than the
## tooltip. A shop card shows a pirate at one star and its ability at all three;
## nothing in the game showed what its *health* would be if you found two more.
func _champion_page(id: StringName) -> String:
	var champion: ChampionDef = Content.champion(id)
	if champion == null:
		return ""

	var monster := champion.cost == 0
	var lines := PackedStringArray()
	lines.append(_title("", champion.display_name,
		"[color=#7c93a4]Monster[/color]" if monster
		else "[color=#ffd98a]%s %d[/color]" % [UITheme.COIN, champion.cost]))

	var trait_links := PackedStringArray()
	for trait_id in champion.traits:
		var def: TraitDef = Content.trait_def(trait_id)
		if def != null:
			trait_links.append(_link(&"traits", trait_id,
				"%s %s" % [def.icon, def.display_name]))
	if not trait_links.is_empty():
		lines.append("   ".join(trait_links))

	lines.append("")
	lines.append(_stat_block(champion))

	if champion.ability_name != "":
		var ability: Ability = Content.ability(champion.id)
		var scaling: Dictionary = ability.scaling() if ability != null else {}
		lines.append("")
		lines.append("[color=#7fe3ff][b]%s[/b][/color]" % champion.ability_name)
		lines.append("[color=#b9cbd8]%s[/color]" % Content.format_description(
			champion.ability_desc, champion.ability_values, 0, scaling))
		var legend := _scaling_legend(scaling)
		if legend != "":
			lines.append("")
			lines.append(legend)
	elif monster:
		lines.append("")
		lines.append("[color=#7c93a4]Casts nothing. It bites, and that is all.[/color]")

	lines.append("")
	if monster:
		lines.append(_heading("Appears in"))
		for row in _waves():
			var count := 0
			for entry in row["wave"]:
				if entry["champion"].id == id:
					count += 1
			if count > 0:
				lines.append("%s  ·  %s  ·  %d of them" % [row["label"],
					_link(&"monsters", &"waves", row["name"]), count])
	else:
		lines.append(_heading("In the pool"))
		lines.append("[color=#8fa6b5]%d copies of every %d-gold pirate are shared between all eight captains. Selling one puts it back.[/color]"
			% [Content.pool_size(champion.cost), champion.cost])
		lines.append("[color=#8fa6b5]Sells for %s %d at one star, %s %d at three.[/color]"
			% [UITheme.COIN, champion.sell_value(1), UITheme.COIN, champion.sell_value(3)])

	return "\n".join(lines)


## What the marks beside the ability numbers mean, on the reference page.
##
## Deliberately not the tooltip's version. The inspector answers "what is this
## pirate in front of me worth right now" and puts live numbers in its legend;
## this page shows all three stars at once and has no single unit to read, so a
## number here would have to pick a star and would be wrong at the other two.
## What it can do instead is name the stat and point at the page explaining it.
func _scaling_legend(scaling: Dictionary) -> String:
	var used := PackedStringArray()
	for stat in [&"ad", &"ap"]:
		if not scaling.values().has(stat):
			continue
		var mark: Dictionary = Ability.SCALING[stat]
		used.append("[color=#%s]%s[/color]  %s"
			% [mark["colour"], String(mark["tag"]).strip_edges(), mark["name"]])
	if used.is_empty():
		return ""

	var lines := PackedStringArray()
	lines.append(_heading("Scales with"))
	lines.append("   ".join(used))
	lines.append(_link(&"guide", &"scaling", "How scaling works"))
	return "\n".join(lines)


## What a pirate becomes at each star.
##
## Written as a row of numbers separated by `»` rather than as a BBCode table.
## A table looked like the right tool and is not: Godot sizes each column to its
## own widest cell, so the star headings sat off their own numbers, and four
## columns inside the 330 points a portrait phone gives the page is not a table
## at all. The separator carries the same meaning at any width, and it is
## already the game's mark for "becomes" in the forge lists.
func _stat_block(champion: ChampionDef) -> String:
	var stats := [champion.stats_at(1), champion.stats_at(2), champion.stats_at(3)]

	var spread := func(key: String) -> String:
		var parts := PackedStringArray()
		for row in stats:
			parts.append("[b]%d[/b]" % int(row[key]))
		return "  »  ".join(parts)

	var one: Dictionary = stats[0]
	var lines := PackedStringArray()
	lines.append("[color=#7c93a4]%s  »  %s  »  %s[/color]"
		% [UITheme.STAR, UITheme.STAR.repeat(2), UITheme.STAR.repeat(3)])
	lines.append("Health  %s" % spread.call("max_hp"))
	lines.append("Attack  %s" % spread.call("ad"))

	var flat := PackedStringArray()
	flat.append("Speed [b]%.2f[/b]" % one["attack_speed"])
	flat.append("Range [b]%d[/b]" % int(one["attack_range"]))
	flat.append("Armour [b]%d[/b]" % int(one["armor"]))
	flat.append("Resist [b]%d[/b]" % int(one["magic_resist"]))
	# In the flat row rather than the spread above it because that is the fact:
	# every pirate starts at the same ability power and a star-up does not move
	# it. What a star moves is the ability's own numbers, which are below.
	flat.append("Ability Power [b]%d[/b]" % int(SimUnit.BASE_AP))
	if champion.casts():
		flat.append("Mana [b]%d[/b] / [b]%d[/b]"
			% [int(one["mana_start"]), int(one["mana_max"])])
	lines.append("[color=#8fa6b5]%s[/color]" % "   ".join(flat))

	return "
".join(lines)


## A trait, every tier of it, and who carries it.
##
## The fielded count is live. Reading a trait's page is something a player does
## while deciding whether to buy the pirate that would complete it, so "4 fielded"
## is the number that makes the breakpoint list mean anything.
func _trait_page(id: StringName) -> String:
	var def: TraitDef = Content.trait_def(id)
	if def == null:
		return ""

	var count := 0
	var tier := -1
	for entry in GameState.board_traits():
		if entry["id"] == id:
			count = entry["count"]
			tier = entry["tier"]
			break

	var lines := PackedStringArray()
	lines.append(_title(def.icon, def.display_name))
	lines.append("[color=#7c93a4]%s  ·  %d fielded[/color]"
		% ["Origin" if def.kind == TraitDef.Kind.ORIGIN else "Class", count])
	lines.append("")
	lines.append("[color=#b9cbd8]%s[/color]"
		% Content.format_description(def.description, def.values))
	lines.append("")
	lines.append(_heading("Breakpoints"))

	for i in def.breakpoints.size():
		var parts := PackedStringArray()
		for key in def.values:
			var values: Array = def.values[key]
			if i < values.size():
				parts.append("%s %s" % [key, str(values[i])])
		var line := "%d pirates  ·  %s" % [def.breakpoints[i], ", ".join(parts)]
		if i == tier:
			lines.append("[color=#ffd98a][b]✔ %s[/b][/color]" % line)
		else:
			lines.append("[color=#8fa6b5]%s[/color]" % line)

	lines.append("")
	lines.append(_heading("Counts distinct pirates"))
	lines.append("[color=#8fa6b5]Three copies of one pirate is a star-up, never a trait. It takes %d [b]different[/b] pirates carrying %s to reach the first breakpoint.[/color]"
		% [def.breakpoints[0] if not def.breakpoints.is_empty() else 2, def.display_name])

	lines.append("")
	lines.append(_heading("Who has it"))
	var carriers := PackedStringArray()
	for champion in Content.champions():
		if not champion.has_trait(id):
			continue
		var section: StringName = &"monsters" if champion.cost == 0 else &"pirates"
		carriers.append(_link(section, champion.id,
			"%s %s" % [champion.icon, champion.display_name]))
	if carriers.is_empty():
		lines.append("[color=#7c93a4]Nobody, which is a content bug.[/color]")
	else:
		lines.append("   ".join(carriers))
	return "\n".join(lines)


## An item: what it does, and either what it forges into or what it came from.
func _item_page(id: StringName) -> String:
	var item: ItemDef = Content.item_def(id)
	if item == null:
		return ""

	var tier: int = Content.item_tier(id)
	var kind := "Component"
	if tier == 2:
		kind = "Forged"
	elif tier >= 3:
		kind = "Greater item"

	var lines := PackedStringArray()
	lines.append(_title(item.icon, item.display_name,
		"[color=#7c93a4]%s[/color]" % kind))
	lines.append("")
	lines.append("[color=#b9cbd8]%s[/color]" % item.description)
	lines.append("")

	if tier >= 3:
		# The slot cost is the whole decision a greater item asks for, so it is
		# said on the item's own page and not only on the SAILING one.
		lines.append("[color=#ffd98a]A pirate may carry two greater items, and two "
			+ "is all it may carry — the second one spends the third slot.[/color]")
		lines.append("")

	if tier >= 2:
		lines.append(_heading("Forged from"))
		var parts := PackedStringArray()
		for part_id in item.recipe:
			var part: ItemDef = Content.item_def(part_id)
			parts.append(_link(&"items", part_id,
				"%s %s" % [part.icon, part.display_name]))
		lines.append(" + ".join(parts))

	if tier < 3:
		if tier >= 2:
			lines.append("")
		lines.append(_heading("Forges into"))
		for pairing in Content.forges_using(item.id):
			var other: ItemDef = Content.item_def(pairing["with"])
			var result: ItemDef = Content.item_def(pairing["makes"])
			# Ticked when the player could make it now — the same mark the inspector
			# uses, because "what can I build with what I have" is the question
			# actually being asked. Tooltip owns the rule so the two cannot disagree
			# about what "now" means once a half can be worn rather than held.
			var have := Tooltip.reachable_pair(item.id, other.id)
			var mark := "[color=#4bd08a]✔[/color]" if have else "[color=#3d4d59]·[/color]"
			lines.append("%s + %s  »  %s" % [mark,
				_link(&"items", other.id, "%s %s" % [other.icon, other.display_name]),
				_link(&"items", result.id, "[b]%s %s[/b]" % [result.icon, result.display_name])])

	lines.append("")
	lines.append(_heading("Carrying"))
	lines.append("[color=#8fa6b5]A pirate holds three items, or two greater ones. Items dropped on the same pirate forge on contact, and that cannot be undone — check the %s first.[/color]"
		% _link(&"guide", &"items", "forge rules"))
	return "\n".join(lines)


# =============================================================================
#  The waves
# =============================================================================

## Every monster wave in the game, in one table.
##
## Stage 1 is three different waves and the rest are one each, because the
## opening round is fought with a single pirate and has to be beatable by one.
func _waves() -> Array:
	var out: Array = []
	for stage in range(1, WAVE_STAGES + 1):
		var rounds: Array = [1, 2, 3] if stage == 1 else [1]
		for number in rounds:
			var label := "%d-%d" % [stage, number] if stage == 1 else "Stage %d" % stage
			if stage == WAVE_STAGES:
				label = "Stage %d+" % stage
			out.append({
				"label": label,
				"name": GameState.creep_wave_name(stage),
				"wave": GameState.creep_wave(stage, number),
			})
	return out


func _waves_page() -> String:
	var lines := PackedStringArray()
	lines.append(_title("🌊", "Every Wave"))
	lines.append("[color=#b9cbd8]A monster round is a floor, not a wall: field anything at all and you should win it. Beating one pays salvage — a component for the hold — instead of the coin a captain pays.[/color]")
	lines.append("")

	for row in _waves():
		var counts: Dictionary = {}
		var order: Array = []
		for entry in row["wave"]:
			var key := "%s/%d" % [entry["champion"].id, entry["star"]]
			if not counts.has(key):
				counts[key] = { "def": entry["champion"], "star": entry["star"], "n": 0 }
				order.append(key)
			counts[key]["n"] += 1

		var parts := PackedStringArray()
		for key in order:
			var group: Dictionary = counts[key]
			var champion: ChampionDef = group["def"]
			var stars: String = UITheme.STAR.repeat(group["star"])
			parts.append("%d × %s %s" % [group["n"],
				_link(&"monsters", champion.id,
					"%s %s" % [champion.icon, champion.display_name]), stars])

		lines.append("[color=#ffd98a][b]%s  ·  %s[/b][/color]" % [row["label"], row["name"]])
		lines.append("[color=#8fa6b5]%s[/color]" % "\n".join(parts))
		lines.append("")
	return "\n".join(lines)


# =============================================================================
#  The rules
# =============================================================================

## The rules, one topic a page.
##
## These were one dialog called How to Sail, opened once at the start of a run
## and never again — which meant that the answer to "how does interest work"
## existed and nobody could find it. Folded in here they are seven entries in a
## list that also holds every pirate, and the almanac is one button rather than
## two.
func _guide_page(id: StringName) -> String:
	var found := _find(&"guide", id)
	if found.is_empty():
		return ""
	var body := ""
	match id:
		&"loop":
			body = """Buy pirates from the shop, drag them onto your half of the board, and your crew fights on its own — there is nothing to do once the battle starts but watch it and decide what to change.

Lose a fight and your [b]hull[/b] takes damage; at zero you are out. Seven rivals are doing the same thing to each other. The last captain afloat wins.

A round is a planning phase on a clock, then a battle, then the aftermath. Every other round is a monster wave rather than a captain, and the end of a stage offers an item from the %s.

A run opens on this page with that clock [b]stopped[/b]: it starts when you close the almanac, or when you press SET SAIL. Only the first one waits — after that the clock runs whether or not this is open, so a page read mid-round is read on your own time.""" % _link(&"guide", &"items", "armoury")
		&"upgrading":
			body = """Three copies of the same pirate merge into a %s version; three of those merge again into %s. Copies sitting on the bench count towards it, so a spare is never wasted.

A star-up roughly doubles health and adds half again to attack, and moves the ability to its next set of numbers — every %s page lists all three side by side.

The shop marks a card [color=#ffd98a]BUY THIS[/color] when buying it completes an upgrade, and frames one you already own in green.""" \
				% [UITheme.STAR.repeat(2), UITheme.STAR.repeat(3),
					_link(&"pirates", &"", "pirate's")]
		&"scaling":
			# The worked example is read off Darcy rather than written into the
			# prose, so a balance pass that retunes him cannot leave this page
			# quoting a number the game no longer uses.
			var doss: ChampionDef = Content.champion(&"doss")
			var doss_ad := int(doss.stats_at(1)["ad"])
			var doss_pct := int(doss.value(&"dmg", 1))
			body = """An ability's numbers are not fixed. Each one is driven by a stat, and both this page and the inspector mark every figure with which one.

[color=#ffb27a]%% AD[/color] is a percentage of the pirate's own [b]Attack Damage[/b]. %s attacks for [b]%d[/b] at one star and his slug is marked [b]%d[/b][color=#ffb27a]%% AD[/color], so it lands for [b]%d[/b]. Attack damage rises with every star and with the attack items.

[color=#c9a2ff]AP[/color] is multiplied by [b]Ability Power[/b]. Every pirate starts at exactly [b]%d[/b] — the baseline the printed numbers are written at — so one at 180 casts for [b]1.8×[/b] everything its page says. A star-up does [i]not[/i] raise it; what a star raises is the printed number itself.

Four pirates read one figure off each in the same cast — %s, %s, %s and %s — which is why the mark sits on the number and not on the ability.

Ability power comes from items (the %s alone is +80), from the %s trait, and mid-fight from Meredine and Nautica, who hand it to the whole fleet permanently every time they cast. Nothing else touches it. A number with no mark scales off nothing at all: a stun lasts as long however you build the pirate casting it.""" \
				% [_link(&"pirates", &"doss", "Darcy"), doss_ad, doss_pct,
					doss_ad * doss_pct / 100, int(SimUnit.BASE_AP),
					_link(&"pirates", &"corvane", "Corvane"),
					_link(&"pirates", &"finn", "Finn"),
					_link(&"pirates", &"hookjaw", "Hookjaw"),
					_link(&"pirates", &"selka", "Selka"),
					_link(&"items", &"abyssal_prism", "Abyssal Prism"),
					_link(&"traits", &"siren", "Siren")]
		&"traits":
			body = """Every pirate has an [b]Origin[/b] and a [b]Class[/b]. Fielding enough pirates sharing one activates a fleet-wide bonus at a breakpoint — 2, 4, 6, and sometimes higher.

It counts [i]different[/i] pirates, not bodies. Three copies of one pirate is a star-up, not a trait, and that single rule is what the whole comp-building game rests on.

The manifest down the side of the board lists what you have running and what the next breakpoint would cost. All thirteen are in %s.""" % _link(&"traits", &"", "this almanac")
		&"gold":
			body = """A wage every round — 2 at the start of the run, rising to 5 by stage 2 — plus [b]1 interest per 10 banked[/b], to a maximum of 5. Banking 50 is a whole extra wage every round, which is why sitting on gold early is a strategy and not just caution.

A [b]streak bonus[/b] arrives at 3, 5 and 6 rounds in a row — for consecutive wins [i]or[/i] consecutive losses. Being beaten every round still funds the rebuild that gets you back in.

Beating another captain pays 1 more; a monster wave pays %s instead. Refreshing the shop costs 2 and buying XP costs 4.""" % _link(&"monsters", &"waves", "salvage")
		&"items":
			body = """Monster waves drop [b]components[/b]. Drag two of them onto the same pirate and they [b]forge[/b] into a full item on contact. Five components make every one of the fifteen finished items, so a component is never a dead end.

Two [b]finished[/b] items on one pirate combine again, into a [b]greater item[/b]. Not every pair does — there are ten of them, listed under the forge chart — but every finished item is half of at least one, so a finished item is not a dead end either.

A greater item is worth about two ordinary ones, and the price is a slot: [b]a pirate may carry two greater items, and two is all it may carry[/b]. One greater item costs nothing — one greater item and two ordinary ones is still three. It is the second that shuts the third slot.

Forging cannot be undone, and a pirate holds three items — so a component welded onto the wrong carry is gone. The [b]Forge chart[/b] button over the cargo hold shows every pairing at once, and every square of it can be inspected.

At the end of a stage the [b]armoury[/b] offers three finished items and 2 gold; take one. Greater items are never handed out — the only way to have one is to have made it. Every item in the game is listed %s.""" % _link(&"items", &"", "here")
		&"monsters":
			body = """Every other round is fought against a wave of sea monsters rather than another captain. They do not level, they carry no items, and they are the same for everybody in the lobby.

They are a [b]floor, not a wall[/b]: field anything at all and you should win. Only an empty board should lose one. Beating a wave pays salvage — a component — rather than the coin a captain pays.

%s lists what is in each one.""" % _link(&"monsters", &"waves", "The wave table")
		&"sea":
			return _sea_page(found)
		&"controls":
			if Layout.touch():
				body = """[b]Drag[/b] pirates between the bench and the board, and drag items onto a pirate to equip them.

[b]Press and hold[/b] anything to inspect it — a shop card, a pirate, a trait badge, an item, a square of the forge chart. The inspector for a pirate you own carries a [b]SELL[/b] button.

[b]FLEET[/b] in the top bar opens the standings and the battle log. The clock beside the shop turns orange with eight seconds left in the planning phase."""
			else:
				body = """[b]Drag[/b] pirates between the bench and the board, and drag items onto a pirate to equip them — or over [b]the plank[/b] beside the bench to sell them.

[b]D[/b] refreshes the shop, [b]F[/b] buys XP, [b]Space[/b] starts the battle early, and [b]1 / 2 / 4[/b] set the battle speed.

Hover anything to inspect it — including a pirate mid-fight, which is the one place an item's effect shows up as a number. The clock beside the shop turns orange with eight seconds left."""
	return "%s\n\n%s" % [_title(found["icon"], found["title"]), body]


## The rules of the weather, rather than the weather itself.
##
## The seas moved to their own section the moment there was something to say
## about each of them beyond a line — this page is what a player wants the
## first time a herald appears, which is "what just happened to my round", not
## "what is the attack speed on a following sea".
func _sea_page(found: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_title(found["icon"], found["title"]))
	lines.append("")
	lines.append("[color=#b9cbd8]Once a stage, one round is fought in weather. It is always [b]round 4[/b], so you can see it coming — the chip beside the round number counts down to it, and names it once it arrives.[/color]")
	lines.append("")
	lines.append("[color=#b9cbd8]It is announced at the top of that round's planning phase, and the board marks the water it will touch. The whole phase is yours to answer it: move the crew out of a red tide, out of the wave lanes, or into a following sea.[/color]")
	lines.append("")
	lines.append(_heading("The same for everybody"))
	lines.append("[color=#8fa6b5]Every captain in the lobby fights that round in the same sea, in the same lanes. It is weather, not something aimed at you.[/color]")
	lines.append("")
	lines.append(_heading("Never on a monster round"))
	lines.append("[color=#8fa6b5]%s are a floor: field anything and you should win one. Weather never falls on them, and never on the armoury — which is why stage 1 has none at all.[/color]"
		% _link(&"guide", &"monsters", "Monster waves"))
	lines.append("")
	lines.append(_heading("A different order every run"))
	lines.append("[color=#8fa6b5]The seas are dealt from a shuffled hand rather than rolled fresh each stage, so none of them comes round again until every one has been dealt. There are more seas in the hand than there are stages in a long run, so no two weather rounds of a run are ever the same one — and the order is different every time.[/color]")
	lines.append("")
	lines.append("[color=#8fa6b5]%s lists all of them.[/color]"
		% _link(&"seas", &"", "The seas section"))

	return "\n".join(lines)


## One sea: what it does, where, and how often it does it.
func _sea_entry_page(id: StringName) -> String:
	var def: SeaDef = Content.sea(id)
	if def == null:
		return ""

	var lines := PackedStringArray()
	lines.append(_title(def.icon, def.display_name))
	lines.append("[color=#7c93a4]%s  ·  round 4 of a stage, from stage %d[/color]"
		% ["Fair wind" if def.boon else "Hazard", def.earliest_stage])
	lines.append("")
	lines.append("[color=#b9cbd8][i]%s[/i][/color]" % def.herald)
	lines.append("")
	lines.append("[color=#b9cbd8]%s[/color]" % def.text())
	lines.append("")

	lines.append(_heading("Where"))
	if def.marks_cells:
		var where := "The board marks the water before the round starts, and it stays marked through the fight."
		if def.boon:
			where += " That is the water you [b]want[/b] to be standing in."
		lines.append("[color=#8fa6b5]%s[/color]" % where)
	else:
		lines.append("[color=#8fa6b5]The whole board. There is nothing to move out of — the answer is where your crew is standing relative to each other, not to the water.[/color]")

	if def.values.has(&"interval"):
		lines.append("")
		lines.append(_heading("How often"))
		lines.append("[color=#8fa6b5]First at %s seconds, then every %s seconds until the fight ends.[/color]"
			% [SeaDef._num(def.value(&"first")), SeaDef._num(def.value(&"interval"))])

	lines.append("")
	lines.append("[color=#8fa6b5]%s explains when weather arrives and who it falls on.[/color]"
		% _link(&"guide", &"sea", "The Sea"))

	return "\n".join(lines)
