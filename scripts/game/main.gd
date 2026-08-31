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

const SIDE_WIDTH := 226.0

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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_connect_state()
	board.show_roster(GameState.board)
	modals.open_help()


# =============================================================================
#  Layout
# =============================================================================

func _build() -> void:
	var background := ColorRect.new()
	background.color = UITheme.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	top_bar = TopBar.new()
	column.add_child(top_bar)

	var margins := MarginContainer.new()
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		margins.add_theme_constant_override("margin_%s" % side, 8)
	margins.add_theme_constant_override("margin_top", 4)
	column.add_child(margins)

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
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)

	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(board)

	# One line under the board that says what a drop would do. Equipping and
	# selling are both irreversible, so neither should be a guess.
	_preview = UITheme.label("", UITheme.FONT_SMALL, UITheme.GOLD_BRIGHT)
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.custom_minimum_size = Vector2(0, 18)
	column.add_child(_preview)

	bench = BenchBar.new()
	column.add_child(bench)

	shop = ShopBar.new()
	column.add_child(shop)

	return column


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

	toasts = ToastLayer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toasts.anchor_left = 1.0
	toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toasts.offset_left = -330
	toasts.offset_top = 60
	toasts.offset_right = -16
	add_child(toasts)

	tooltip = Tooltip.new()
	add_child(tooltip)

	modals = Modals.new()
	add_child(modals)


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
	shop.card_unhovered.connect(func(): tooltip.hide_now())

	# --- the board
	board.unit_dropped_on_cell.connect(func(unit, cell): GameState.move_to_board(unit, cell))
	board.item_dropped_on_unit.connect(func(item_id, unit): GameState.equip_item(item_id, unit))
	board.unit_sell_requested.connect(func(unit): GameState.sell(unit))
	board.preview_changed.connect(_set_preview)
	board.unit_hovered.connect(_on_roster_unit_hovered)
	board.sim_unit_hovered.connect(_on_sim_unit_hovered)
	board.unit_unhovered.connect(func(): tooltip.hide_now())

	# --- the bench
	bench.unit_dropped.connect(func(unit, slot): GameState.move_to_bench(unit, slot))
	bench.item_dropped.connect(func(item_id, unit): GameState.equip_item(item_id, unit))
	bench.unit_sold.connect(func(unit): GameState.sell(unit))
	bench.preview_changed.connect(_set_preview)
	bench.unit_hovered.connect(_on_roster_unit_hovered)
	bench.unit_unhovered.connect(func(): tooltip.hide_now())

	# --- the panels
	traits.trait_hovered.connect(_on_trait_hovered)
	traits.trait_unhovered.connect(func(): tooltip.hide_now())
	hold.item_hovered.connect(_on_item_hovered)
	hold.item_unhovered.connect(func(): tooltip.hide_now())
	hold.forge_chart_requested.connect(func(): modals.open_forge_chart())
	fleet.captain_hovered.connect(_on_captain_hovered)
	fleet.captain_unhovered.connect(func(): tooltip.hide_now())

	# --- the top bar and modals
	top_bar.speed_changed.connect(func(value): GameState.speed = value)
	top_bar.help_pressed.connect(func(): modals.open_help())
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
	if GameState.phase == GameState.Phase.COMBAT:
		board.follow_battle(float(GameState.speed))

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer < 0.5:
			_banner.modulate.a = maxf(0.0, _banner_timer / 0.5)


# =============================================================================
#  Tooltips
# =============================================================================

func _on_shop_card_hovered(index: int, at: Vector2) -> void:
	if index >= GameState.shop.size():
		return
	var champion: ChampionDef = GameState.content.champion(GameState.shop[index])
	if champion == null:
		return
	tooltip.show_text(Tooltip.champion_text(champion, 1), at, shop)


func _on_roster_unit_hovered(unit: RosterUnit, at: Vector2) -> void:
	tooltip.show_text(Tooltip.champion_text(unit.champion, unit.star, unit.items), at, null)


## Hovering a pirate mid-fight shows its *live* numbers, which is the only place
## the effect of an item or a trait is visible as a figure rather than as text.
func _on_sim_unit_hovered(unit: SimUnit, at: Vector2) -> void:
	tooltip.show_text(
		Tooltip.champion_text(unit.def, unit.star, unit.items, unit), at, null)


func _on_trait_hovered(trait_id: StringName, at: Vector2) -> void:
	var count := 0
	var tier := -1
	for entry in GameState.board_traits():
		if entry["id"] == trait_id:
			count = entry["count"]
			tier = entry["tier"]
			break
	tooltip.show_text(Tooltip.trait_text(trait_id, count, tier), at, traits)


func _on_item_hovered(item_id: StringName, at: Vector2) -> void:
	tooltip.show_text(Tooltip.item_text(item_id), at, hold)


func _on_captain_hovered(captain: Captain, at: Vector2) -> void:
	tooltip.show_text(Tooltip.captain_text(captain), at, fleet)


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
