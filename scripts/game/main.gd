extends Control

## Assembles the HUD and wires it to GameState.
##
## Every panel is built in code rather than in a .tscn. That is a deliberate
## choice for this project: the layout is almost entirely containers and
## generated rows, and a scene file full of nodes nobody positions by hand is
## harder to review and harder to change than the code that would have built it.
##
## This is also the only place allowed to *ask GameState to change something*.
## Panels report what the player did and Main turns that into a call, so there is
## exactly one path from a click to a mutation.
##
## **There are two arrangements of the same panels**, chosen by `Layout` from the
## width of the window: the wide one with a column either side of the board, and
## a compact one for a phone where those columns cannot fit and become a strip
## above the bench and a sheet that slides up from the bottom. Crossing the
## breakpoint rebuilds the HUD rather than resizing it, because they are two
## layouts and not two sizes of one. All the state lives in GameState, so
## throwing the whole HUD away and building it again is safe by construction.
##
## Main also owns **press-and-hold**, for the same reason it owns mutation: the
## inspector it opens is one shared tooltip, and the alternative is a timer in
## every widget that can be inspected.

const SIDE_WIDTH := 226.0

## How long a finger has to rest before the inspector opens, and how far it may
## slide first. Matched to the JS build, which settled on 340ms after playtesting;
## much longer reads as an unresponsive tap, much shorter fires while dragging.
const HOLD_SECONDS := 0.34
const HOLD_SLOP := 10.0

var board: BoardView = null
var shop: ShopBar = null
var bench: BenchBar = null
var traits: SidePanels.TraitPanel = null
var hold: SidePanels.HoldPanel = null
var fleet: SidePanels.FleetPanel = null
var tooltip: Tooltip = null
var toasts: ToastLayer = null
var modals: Modals = null
var wiki: Wiki = null
var top_bar: TopBar = null

var _banner: Label = null
var _preview: Label = null
var _banner_timer: float = 0.0

## Last seen window size, for the resize poll below.
var _window_size := Vector2i.ZERO

## The compact layout's bottom sheet, and the scrim behind it.
var _sheet: PanelContainer = null
var _sheet_scrim: ColorRect = null

## What the cursor is over, so a press-and-hold knows what to pin and whether the
## thing under it can be sold. Set by the same handlers that open the tooltip,
## and it outlives the tooltip on purpose — see _complete_hold.
var _hover_kind: StringName = &""
var _hover_text: String = ""
var _hover_unit: RosterUnit = null

## The champion whose figure the inspector should show beside the text, or null
## when the thing being read is a trait, an item or a rival captain.
var _hover_champion: ChampionDef = null

## Rebuilds `_hover_text` from whatever it describes. The tooltip calls it while
## it is open; a hold that pins calls it once more, because a third of a second
## of a fight is long enough for the text to be stale before it appears.
var _hover_refresh: Callable = Callable()

var _hold_origin := Vector2.ZERO
var _hold_time: float = 0.0
var _holding: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.game_theme()
	Layout.apply(get_window())
	_build()
	_connect_panels()
	_connect_bus()
	board.show_roster(GameState.board)
	_open_briefing()

	_window_size = get_window().size


## The almanac a new run opens behind, at the page describing the round loop.
##
## The run is holding its clock while this is up (`GameState.awaiting_start`), so
## it is also what a rebuild has to put back: a phone rotated on the opening
## screen would otherwise throw the briefing away and leave a game that looks
## stopped. Reading the flag rather than a local is the same rule as the speed
## buttons and the shop lock — the state belongs to GameState, and the HUD is
## rebuilt around it.
func _open_briefing() -> void:
	if GameState.awaiting_start:
		wiki.open(&"guide", &"loop")


## The window size is polled rather than watched.
##
## `Window.size_changed` does not fire when a browser canvas is resized, so on
## the web a phone turned sideways kept the portrait layout stretched across a
## landscape window — verified in the export, which is the only place it goes
## wrong. A Vector2i compare once a frame is cheaper than being wrong on the one
## platform this whole layout exists for.
func _check_window_size() -> void:
	var size := get_window().size
	if size == _window_size:
		return
	_window_size = size
	if not Layout.apply(get_window()):
		return
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_sheet = null
	_sheet_scrim = null
	_forget_hover()
	_holding = false
	# The banner that was fading belonged to the label just thrown away; the new
	# one starts blank and must not inherit a countdown that fades nothing.
	_banner_timer = 0.0
	_build()
	_connect_panels()

	# The board is the one panel holding state the rebuild threw away, so it is
	# told again what it was showing.
	if GameState.phase == GameState.Phase.COMBAT and GameState.sim != null:
		board.show_battle(GameState.sim)
	else:
		board.show_roster(GameState.board)
	_open_briefing()


# =============================================================================
#  Layout
# =============================================================================

func _build() -> void:
	var compact := Layout.compact()

	var background := ColorRect.new()
	background.color = UITheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 3 if compact else 6)
	add_child(column)

	top_bar = TopBar.new()
	column.add_child(top_bar)

	var margins := MarginContainer.new()
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var edge := 4 if compact else 8
	for side in ["left", "right", "bottom"]:
		margins.add_theme_constant_override("margin_%s" % side, edge)
	margins.add_theme_constant_override("margin_top", 3 if compact else 4)
	column.add_child(margins)

	if compact:
		margins.add_child(_build_landscape() if Layout.short() else _build_centre())
		_build_sheet()
	else:
		var body := HBoxContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 8)
		margins.add_child(body)

		body.add_child(_build_left())
		body.add_child(_build_centre())
		body.add_child(_build_right())

	_build_overlays()


func _build_left() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL, UITheme.LINE, 8))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	traits = SidePanels.TraitPanel.new()
	traits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(traits)

	hold = SidePanels.HoldPanel.new()
	column.add_child(hold)

	return panel


func _build_centre() -> Control:
	var compact := Layout.compact()

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3 if compact else 6)

	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(board)

	# One line under the board that says what a drop would do. Equipping and
	# selling are both irreversible, so neither should be a guess.
	_preview = UITheme.label("", UITheme.FONT_SMALL, UITheme.GOLD_BRIGHT)
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.custom_minimum_size = Vector2(0, 14 if compact else 18)
	_preview.clip_text = true
	column.add_child(_preview)

	# With no side columns to live in, the manifest and the hold become strips
	# between the board and the bench. They share one line: two lines cost sixty
	# points of height, and on a phone that height is the board's.
	if compact:
		traits = SidePanels.TraitPanel.new()
		hold = SidePanels.HoldPanel.new()
		var strips := HBoxContainer.new()
		strips.add_theme_constant_override("separation", 6)
		traits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strips.add_child(traits)
		strips.add_child(hold)
		column.add_child(strips)

	bench = BenchBar.new()
	column.add_child(bench)

	shop = ShopBar.new()
	column.add_child(shop)

	return column


## A phone held sideways: the board on the left, everything else stacked on the
## right.
##
## Stacking the furniture the way portrait does leaves the board 94 points of a
## 390-point screen, which is less than the board is tall — it was drawn at the
## minimum scale and *clipped*, so the back rows were unreachable. But a sideways
## phone is a wide short screen, which is the shape the desktop layout is for. So
## it gets that shape instead: the height all goes to the board, and the width
## pays for it.
func _build_landscape() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)

	board = BoardView.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(board)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 3)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Wide enough for five shop cards to stay legible; the board takes the rest.
	side.custom_minimum_size = Vector2(minf(400.0, Layout.css_size.x * 0.5), 0)

	traits = SidePanels.TraitPanel.new()
	hold = SidePanels.HoldPanel.new()
	var strips := HBoxContainer.new()
	strips.add_theme_constant_override("separation", 6)
	traits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strips.add_child(traits)
	strips.add_child(hold)
	side.add_child(strips)

	_preview = UITheme.label("", UITheme.FONT_SMALL, UITheme.GOLD_BRIGHT)
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.custom_minimum_size = Vector2(0, 14)
	_preview.clip_text = true
	side.add_child(_preview)

	bench = BenchBar.new()
	side.add_child(bench)

	shop = ShopBar.new()
	side.add_child(shop)

	body.add_child(side)
	return body


## The fleet and the log, on a phone: a sheet over the bottom of the screen that
## the FLEET button in the top bar raises.
##
## They are reference material rather than controls — you read the standings, you
## do not act on them — so they are the one thing that can afford to be behind a
## tap.
func _build_sheet() -> void:
	_sheet_scrim = ColorRect.new()
	_sheet_scrim.color = Color(0, 0, 0, 0.5)
	_sheet_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_scrim.visible = false
	_sheet_scrim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_toggle_sheet(false))
	add_child(_sheet_scrim)

	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL, UITheme.LINE, 14))
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.offset_top = -minf(Layout.css_size.y * 0.72, 460.0)
	_sheet.visible = false
	add_child(_sheet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_sheet.add_child(column)

	fleet = SidePanels.FleetPanel.new()
	fleet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(fleet)

	var close := UITheme.button("CLOSE", UITheme.FONT_SMALL)
	close.pressed.connect(func(): _toggle_sheet(false))
	column.add_child(close)


func _toggle_sheet(open: bool) -> void:
	if _sheet == null:
		return
	_sheet.visible = open
	_sheet_scrim.visible = open


func _build_right() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL, UITheme.LINE, 8))

	fleet = SidePanels.FleetPanel.new()
	panel.add_child(fleet)
	return panel


func _build_overlays() -> void:
	_banner = UITheme.label("", UITheme.FONT_HUGE, UITheme.GOLD_BRIGHT)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2(0, 180)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.modulate.a = 0.0
	add_child(_banner)

	# Over the right of the *board*, not over the fleet panel — a toast that
	# covers the standings hides the thing it is interrupting.
	toasts = ToastLayer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toasts.anchor_left = 1.0
	toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Clear of the fleet panel on a desktop; there is no fleet panel to clear on a
	# phone, so it tucks against the edge instead of hanging off a missing column.
	toasts.offset_right = -12.0 if Layout.compact() else -(SIDE_WIDTH + 20.0)
	toasts.offset_left = toasts.offset_right - ToastLayer.width()
	toasts.offset_top = 44 if Layout.compact() else 62
	add_child(toasts)

	# Modals first, so the inspector draws *over* a dialog: the forge chart opens
	# it on its own squares, and an inspector behind the chart is no inspector.
	modals = Modals.new()
	add_child(modals)

	# Above the modals, because the almanac is opened *from* nothing else and
	# nothing else should ever be drawn over it; below the tooltip, which is the
	# one thing that has to sit over everything.
	wiki = Wiki.new()
	add_child(wiki)

	tooltip = Tooltip.new()
	add_child(tooltip)


# =============================================================================
#  Wiring
# =============================================================================

## Wires the panels this build produced. Re-run by every rebuild, which is safe
## because every connection here is on a node the rebuild is about to replace.
func _connect_panels() -> void:
	# --- the shop
	shop.card_pressed.connect(func(index): GameState.buy(index))
	shop.reroll_pressed.connect(func(): GameState.reroll())
	shop.xp_pressed.connect(func(): GameState.buy_xp())
	shop.lock_toggled.connect(func(locked): GameState.set_shop_locked(locked))
	shop.ready_pressed.connect(func(): GameState.start_combat_now())
	shop.card_hovered.connect(_on_shop_card_hovered)
	shop.card_unhovered.connect(_unhover)

	# --- the board
	board.unit_dropped_on_cell.connect(func(unit, cell): GameState.move_to_board(unit, cell))
	board.item_dropped_on_unit.connect(func(item_id, unit): GameState.equip_item(item_id, unit))
	board.unit_sell_requested.connect(func(unit): GameState.sell(unit))
	board.preview_changed.connect(_set_preview)
	board.unit_hovered.connect(_on_roster_unit_hovered)
	board.sim_unit_hovered.connect(_on_sim_unit_hovered)
	board.unit_unhovered.connect(_unhover)

	# --- the bench
	bench.unit_dropped.connect(func(unit, slot): GameState.move_to_bench(unit, slot))
	bench.item_dropped.connect(func(item_id, unit): GameState.equip_item(item_id, unit))
	bench.unit_sold.connect(func(unit): GameState.sell(unit))
	bench.preview_changed.connect(_set_preview)
	bench.unit_hovered.connect(_on_roster_unit_hovered)
	bench.unit_unhovered.connect(_unhover)

	# --- the panels
	traits.trait_hovered.connect(_on_trait_hovered)
	traits.trait_unhovered.connect(_unhover)
	hold.item_hovered.connect(_on_item_hovered)
	hold.item_unhovered.connect(_unhover)
	hold.forge_chart_requested.connect(func(): modals.open_forge_chart())
	modals.chart_item_hovered.connect(_on_chart_item_hovered)
	modals.chart_item_unhovered.connect(_unhover)
	# A dialog opening or closing invalidates whatever was under the cursor. Left
	# alone, resting a finger on the forge chart pinned the inspector for the shop
	# card that happened to be hovered before the chart opened.
	modals.visibility_changed.connect(_dismiss_inspector)
	wiki.visibility_changed.connect(_on_wiki_visibility)
	fleet.captain_hovered.connect(_on_captain_hovered)
	fleet.captain_unhovered.connect(_unhover)

	# --- the top bar and modals
	top_bar.speed_changed.connect(func(value): GameState.speed = value)
	top_bar.help_pressed.connect(func(): wiki.open())
	top_bar.fleet_pressed.connect(func(): _toggle_sheet(_sheet != null and not _sheet.visible))
	top_bar.dps_pressed.connect(func(): modals.open_dps())
	top_bar.sound_toggled.connect(func(): Audio.set_muted(not Audio.muted))
	tooltip.sell_requested.connect(func(unit): GameState.sell(unit))
	modals.armoury_chosen.connect(func(item_id): GameState.take_armoury_item(item_id))
	modals.restart_requested.connect(func():
		GameState.start_game()
		board.show_roster(GameState.board))


## The run's own signals, connected once and never again.
##
## **These must not be re-connected by a rebuild.** `Events` is an autoload and
## Main outlives its own children, so a rebuild that re-ran this stacked a second
## copy of every connection: Godot refused the two method connections with an
## error, and silently accepted the lambdas, which then ran once per rotation the
## player had ever made. Every panel connection above is on a node the rebuild
## throws away, so those are disconnected for us when it is freed — these are the
## only ones with nothing to free them.
##
## The lambdas reach through `self` for the panel they need rather than capturing
## it, so they keep working after a rebuild has replaced it.
func _connect_bus() -> void:
	Events.phase_changed.connect(_on_phase_changed)
	Events.board_changed.connect(func():
		if GameState.phase == GameState.Phase.PLAN:
			board.show_roster(GameState.board))
	Events.round_resolved.connect(_on_round_resolved)
	Events.game_over.connect(func(place): modals.open_game_over(place))


func _set_preview(text: String) -> void:
	_preview.text = text


func _on_phase_changed(phase: int) -> void:
	tooltip.hide_now()
	match phase:
		GameState.Phase.PLAN:
			board.show_roster(GameState.board)
			_set_preview("")
		GameState.Phase.COMBAT:
			board.show_battle(GameState.sim)
			_show_banner("ENGAGE", UITheme.FOAM)
		GameState.Phase.ARMOURY:
			modals.open_armoury(GameState.armoury_offer)


func _on_round_resolved(won: bool, _damage: int, _opponent: String) -> void:
	if won:
		_show_banner("VICTORY", UITheme.GOLD_BRIGHT)
	else:
		_show_banner("DEFEAT", Color("ff6b7d"))


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_timer = 1.9
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.25)


func _process(delta: float) -> void:
	_check_window_size()

	if GameState.phase == GameState.Phase.COMBAT:
		board.follow_battle(float(GameState.speed))

	if _holding:
		_hold_time += delta
		if _hold_time >= HOLD_SECONDS:
			_holding = false
			_complete_hold()

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer < 0.5:
			_banner.modulate.a = maxf(0.0, _banner_timer / 0.5)


# =============================================================================
#  Tooltips
# =============================================================================
#
# Each handler records *what* is under the cursor as well as showing it, because
# a press-and-hold that lands a third of a second later needs to know whether the
# thing it is pinning is a pirate the player could sell.
#
# Each also hands the tooltip a way to build its text *again*, rather than only
# the text. Everything an inspector shows is live — a pirate's health during a
# fight, a trait's count as pirates are placed, whether a component's partner is
# in the hold — and a string built at the moment of the hover is a photograph of
# all of it. The builders below are the one definition of each panel's text,
# called once to open the tooltip and then by the tooltip itself ten times a
# second. Returning "" means the subject is gone, and closes the inspector.

func _on_shop_card_hovered(index: int, at: Vector2) -> void:
	if tooltip.pinned:
		return
	# The one caller that used to hand over a finished string and nothing else,
	# which made it the one inspector that could not tell it was describing a card
	# that had gone. Buying empties the slot, so the refresh below returns "" and
	# closes it — the same way selling a pirate closes the inspector on one.
	var refresh := func() -> String: return _shop_card_text(index)
	var text: String = refresh.call()
	if text == "":
		return
	var champion: ChampionDef = GameState.content.champion(GameState.shop[index]) 		if index < GameState.shop.size() else null
	_note_hover(&"shop", text, null, refresh, champion)
	tooltip.show_text(text, at, shop, refresh, champion)


## The card in shop slot `index`, or "" once there is nothing in it.
##
## Buying sets the slot to an empty id, so this is what turns a purchase into a
## closed inspector rather than a panel still describing the pirate that is now
## on the bench.
func _shop_card_text(index: int) -> String:
	if index < 0 or index >= GameState.shop.size():
		return ""
	var champion: ChampionDef = GameState.content.champion(GameState.shop[index])
	if champion == null:
		return ""
	return Tooltip.champion_text(champion, 1)


func _on_roster_unit_hovered(unit: RosterUnit, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var refresh := func() -> String: return _roster_unit_text(unit)
	var text := _roster_unit_text(unit)
	_note_hover(&"unit", text, unit, refresh, unit.champion)
	tooltip.show_text(text, at, null, refresh, unit.champion)


## A pirate the player owns. Its star and its items both change while it is being
## read — an item dropped on it, a third copy bought — and a pinned inspector on
## a phone is still up when the unit it describes is sold or merged away, which
## is what the empty string is for.
func _roster_unit_text(unit: RosterUnit) -> String:
	if not (unit in GameState.board or unit in GameState.bench):
		return ""
	return Tooltip.champion_text(unit.champion, unit.star, unit.items)


## Hovering a pirate mid-fight shows its *live* numbers, which is the only place
## the effect of an item or a trait is visible as a figure rather than as text.
func _on_sim_unit_hovered(unit: SimUnit, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var refresh := func() -> String: return _sim_unit_text(unit)
	var text := _sim_unit_text(unit)
	_note_hover(&"sim", text, null, refresh, unit.def)
	tooltip.show_text(text, at, null, refresh, unit.def)


## The live numbers of a pirate in the fight now running: health falling, mana
## filling, a shield appearing and going again. This is the tooltip that most
## needed re-reading — the board only reports a hover when the cursor *moves*, so
## holding still to read a stat block was what froze it.
func _sim_unit_text(unit: SimUnit) -> String:
	if not unit.alive or GameState.phase != GameState.Phase.COMBAT:
		return ""
	return Tooltip.champion_text(unit.def, unit.star, unit.items, unit)


func _on_trait_hovered(trait_id: StringName, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var refresh := func() -> String: return _trait_tip_text(trait_id)
	var text := _trait_tip_text(trait_id)
	_note_hover(&"trait", text, null, refresh)
	tooltip.show_text(text, at, traits, refresh)


## A trait at its current count and tier, both of which move as pirates are put
## on the board — which is exactly when its breakpoint list is being read.
func _trait_tip_text(trait_id: StringName) -> String:
	var count := 0
	var tier := -1
	for entry in GameState.board_traits():
		if entry["id"] == trait_id:
			count = entry["count"]
			tier = entry["tier"]
			break
	return Tooltip.trait_text(trait_id, count, tier)


## A square of the forge chart. Same inspector as everywhere else, so press and
## hold pins it on a phone exactly as it does in the cargo hold.
func _on_chart_item_hovered(item_id: StringName, at: Vector2, source: Control) -> void:
	if tooltip.pinned:
		return
	# An item's text is live as well: the ticks against its pairings are the ones
	# the player could forge right now, and equipping a component changes them.
	var refresh := func() -> String: return Tooltip.item_text(item_id)
	var text := Tooltip.item_text(item_id)
	_note_hover(&"item", text, null, refresh)
	tooltip.show_text(text, at, source, refresh)


func _on_item_hovered(item_id: StringName, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var refresh := func() -> String: return Tooltip.item_text(item_id)
	var text := Tooltip.item_text(item_id)
	_note_hover(&"item", text, null, refresh)
	tooltip.show_text(text, at, hold, refresh)


## A rival captain, whose hull and streak change under the tooltip every time a
## round resolves.
func _on_captain_hovered(captain: Captain, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var refresh := func() -> String: return Tooltip.captain_text(captain)
	var text := Tooltip.captain_text(captain)
	_note_hover(&"captain", text, null, refresh)
	tooltip.show_text(text, at, fleet, refresh)


func _note_hover(kind: StringName, text: String, unit: RosterUnit = null,
		refresh: Callable = Callable(), champion: ChampionDef = null) -> void:
	_hover_kind = kind
	_hover_text = text
	_hover_unit = unit
	_hover_refresh = refresh
	# Recorded for the same reason the text is: a press-and-hold re-opens the
	# inspector from what the hover noted, a third of a second later, and the
	# panel it is re-opening from has usually gone.
	_hover_champion = champion


## Closes the inspector whatever state it is in, pinned included.
##
## `_unhover` deliberately leaves a pinned inspector alone, which is right for a
## cursor wandering off and wrong for a dialog closing underneath it: the forge
## chart's own inspector stayed pinned and armed over the shop, and ate the next
## tap on a card.
## The almanac opened or closed. Closing it is how the player says they have read
## enough to start, so it releases a run that is still holding its clock — but
## only a run that is: the almanac opened mid-round is a reference, and the round
## it was opened during keeps running behind it.
func _on_wiki_visibility() -> void:
	_dismiss_inspector()
	if not wiki.is_open():
		GameState.begin_run()


func _dismiss_inspector() -> void:
	_forget_hover()
	tooltip.hide_now()


## A hover ended. A pinned inspector ignores it — it is being held open on
## purpose, and on a touchscreen the cursor left the moment the finger did.
func _unhover() -> void:
	if tooltip.pinned:
		return
	_forget_hover()
	tooltip.hide_now()


## Drops the record of what was under the cursor, without touching the inspector.
func _forget_hover() -> void:
	_hover_kind = &""
	_hover_text = ""
	_hover_unit = null
	_hover_champion = null
	_hover_refresh = Callable()


# =============================================================================
#  Press and hold
# =============================================================================
#
# A finger has no hover, so on a touchscreen the inspector is opened by resting
# on something. Only real touch events are watched: an emulated mouse cannot be
# told from a real one, and a mouse held still for a third of a second is a slow
# click, not a request to read the manual.
#
# The hover handlers above have already run by the time a hold completes — the
# emulated cursor arrives with the touch — so this only has to decide to pin.

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_hold(event.position)
		else:
			_holding = false
			# The inspector only starts swallowing taps now, with the finger off
			# the glass. Doing it the moment it opened broke every later tap.
			tooltip.arm_input()
			# **A finger has no hover, so nothing else would ever close this.**
			# The emulated cursor stops wherever the tap landed, still inside the
			# panel that opened the inspector, so the un-hover that closes it on a
			# desktop never comes: a tooltip opened on the way into a tap stayed up
			# until the next tap somewhere else. A pinned one is exempt — that was
			# opened deliberately by a hold and has its own way out.
			if not tooltip.pinned:
				_dismiss_inspector()
	elif event is InputEventScreenDrag and _holding:
		# Past the slop this is a drag, and dragging a pirate somewhere is not a
		# request to read about it.
		if event.position.distance_to(_hold_origin) > HOLD_SLOP:
			_holding = false


func _begin_hold(at: Vector2) -> void:
	# A stale flag must never outlive the press that set it, or it eats an
	# unrelated tap later on.
	ShopBar.swallow_click = false

	if tooltip.pinned:
		# A tap anywhere but on the inspector dismisses it, and that tap does
		# nothing else — closing a panel should not also spend gold.
		if not Rect2(tooltip.global_position, tooltip.size).has_point(at):
			tooltip.hide_now()
			ShopBar.swallow_click = true
		return
	_hold_origin = at
	_hold_time = 0.0
	_holding = true


## Opens the inspector on whatever the finger came down on.
##
## It reads `_hover_kind` rather than asking the tooltip what it is showing,
## because by now the tooltip has usually closed itself: it watches the cursor,
## and the emulated cursor behind a finger is not reliably still inside the
## control it entered a third of a second ago.
func _complete_hold() -> void:
	if _hover_kind == &"":
		return
	# A shop card acts on a tap, so the release that ends this hold has to be
	# thrown away or the pirate the player wanted to read about gets bought.
	if _hover_kind == &"shop":
		ShopBar.swallow_click = true
	# Only a pirate you own between fights can be sold from the inspector.
	var sellable: RosterUnit = _hover_unit if _hover_kind == &"unit" else null

	# The recorded text is a third of a second old, and in a fight that is several
	# attacks ago. Read it again before it goes up — and abandon the pin entirely
	# if whatever the finger came down on has gone in the meantime.
	var text := _hover_text
	if _hover_refresh.is_valid():
		text = _hover_refresh.call()
		if text == "":
			_forget_hover()
			return
	tooltip.pin(text, _hold_origin, sellable, _hover_refresh, _hover_champion)


# =============================================================================
#  Keyboard
# =============================================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if modals.is_open() or wiki.is_open():
		return

	match event.keycode:
		KEY_D: GameState.reroll()
		KEY_F: GameState.buy_xp()
		KEY_SPACE: GameState.start_combat_now()
		KEY_1: GameState.speed = 1
		KEY_2: GameState.speed = 2
		KEY_4: GameState.speed = 4
		_: return
	get_viewport().set_input_as_handled()
