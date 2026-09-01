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

var _hold_origin := Vector2.ZERO
var _hold_time: float = 0.0
var _holding: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.game_theme()
	Layout.apply(get_window())
	_build()
	_connect_state()
	board.show_roster(GameState.board)
	modals.open_help()

	_window_size = get_window().size


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
	Events.layout_changed.emit(Layout.compact())


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_sheet = null
	_sheet_scrim = null
	_hover_kind = &""
	_hover_unit = null
	_holding = false
	_build()
	_connect_state()

	# The board is the one panel holding state the rebuild threw away, so it is
	# told again what it was showing.
	if GameState.phase == GameState.Phase.COMBAT and GameState.sim != null:
		board.show_battle(GameState.sim)
	else:
		board.show_roster(GameState.board)


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
	toasts.offset_left = toasts.offset_right - minf(320.0, Layout.css_size.x - 24.0)
	toasts.offset_top = 44 if Layout.compact() else 62
	add_child(toasts)

	# Modals first, so the inspector draws *over* a dialog: the forge chart opens
	# it on its own squares, and an inspector behind the chart is no inspector.
	modals = Modals.new()
	add_child(modals)

	tooltip = Tooltip.new()
	add_child(tooltip)


# =============================================================================
#  Wiring
# =============================================================================

func _connect_state() -> void:
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
	fleet.captain_hovered.connect(_on_captain_hovered)
	fleet.captain_unhovered.connect(_unhover)

	# --- the top bar and modals
	top_bar.speed_changed.connect(func(value): GameState.speed = value)
	top_bar.help_pressed.connect(func(): modals.open_help())
	top_bar.fleet_pressed.connect(func(): _toggle_sheet(_sheet != null and not _sheet.visible))
	tooltip.sell_requested.connect(func(unit): GameState.sell(unit))
	modals.armoury_chosen.connect(func(item_id): GameState.take_armoury_item(item_id))
	modals.restart_requested.connect(func():
		GameState.start_game()
		board.show_roster(GameState.board))

	# --- the run
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

func _on_shop_card_hovered(index: int, at: Vector2) -> void:
	if tooltip.pinned or index >= GameState.shop.size():
		return
	var champion: ChampionDef = GameState.content.champion(GameState.shop[index])
	if champion == null:
		return
	var text := Tooltip.champion_text(champion, 1)
	_note_hover(&"shop", text)
	tooltip.show_text(text, at, shop)


func _on_roster_unit_hovered(unit: RosterUnit, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var text := Tooltip.champion_text(unit.champion, unit.star, unit.items)
	_note_hover(&"unit", text, unit)
	tooltip.show_text(text, at, null)


## Hovering a pirate mid-fight shows its *live* numbers, which is the only place
## the effect of an item or a trait is visible as a figure rather than as text.
func _on_sim_unit_hovered(unit: SimUnit, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var text := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	_note_hover(&"sim", text)
	tooltip.show_text(text, at, null)


func _on_trait_hovered(trait_id: StringName, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var count := 0
	var tier := -1
	for entry in GameState.board_traits():
		if entry["id"] == trait_id:
			count = entry["count"]
			tier = entry["tier"]
			break
	var text := Tooltip.trait_text(trait_id, count, tier)
	_note_hover(&"trait", text)
	tooltip.show_text(text, at, traits)


## A square of the forge chart. Same inspector as everywhere else, so press and
## hold pins it on a phone exactly as it does in the cargo hold.
func _on_chart_item_hovered(item_id: StringName, at: Vector2, source: Control) -> void:
	if tooltip.pinned:
		return
	var text := Tooltip.item_text(item_id)
	_note_hover(&"item", text)
	tooltip.show_text(text, at, source)


func _on_item_hovered(item_id: StringName, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var text := Tooltip.item_text(item_id)
	_note_hover(&"item", text)
	tooltip.show_text(text, at, hold)


func _on_captain_hovered(captain: Captain, at: Vector2) -> void:
	if tooltip.pinned:
		return
	var text := Tooltip.captain_text(captain)
	_note_hover(&"captain", text)
	tooltip.show_text(text, at, fleet)


func _note_hover(kind: StringName, text: String, unit: RosterUnit = null) -> void:
	_hover_kind = kind
	_hover_text = text
	_hover_unit = unit


## Closes the inspector whatever state it is in, pinned included.
##
## `_unhover` deliberately leaves a pinned inspector alone, which is right for a
## cursor wandering off and wrong for a dialog closing underneath it: the forge
## chart's own inspector stayed pinned and armed over the shop, and ate the next
## tap on a card.
func _dismiss_inspector() -> void:
	_hover_kind = &""
	_hover_text = ""
	_hover_unit = null
	tooltip.hide_now()


## A hover ended. A pinned inspector ignores it — it is being held open on
## purpose, and on a touchscreen the cursor left the moment the finger did.
func _unhover() -> void:
	if tooltip.pinned:
		return
	_hover_kind = &""
	_hover_text = ""
	_hover_unit = null
	tooltip.hide_now()


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
	tooltip.pin(_hover_text, _hold_origin, sellable)


# =============================================================================
#  Keyboard
# =============================================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if modals.is_open():
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
