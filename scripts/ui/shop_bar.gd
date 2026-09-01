class_name ShopBar
extends PanelContainer

## The shop row: level and XP, the five cards, gold, the round clock, and the
## button that starts the fight early.
##
## Four things the first playtest asked for live here, and they are all about the
## same problem — during the planning phase the player is looking at the shop and
## nowhere else, so anything they need must be *in* the shop.
##
##   - **A card the player already owns says so.** The first pass read the note
##     as "two of these are in the shop" and highlighted that, which is not what
##     was asked and drowned the signal that was: a pirate already on the bench
##     or the board is the one worth buying, and counting your own bench on a
##     timer is exactly what nobody does. Ownership now gets a green frame, a
##     pip row and an IN FLEET badge; a mere pair on the counter gets grey text
##     and no frame at all.
##   - **Gold sits beside the cards**, not diagonally opposite in the top bar.
##   - **So does the round clock**, and it warns before it runs out instead of
##     simply ending the round mid-purchase.
##   - **Unaffordable cards** are visibly out of reach rather than silently
##     refusing the click.

signal card_pressed(index: int)
signal card_hovered(index: int, at: Vector2)
signal card_unhovered()
signal reroll_pressed()
signal xp_pressed()
signal lock_toggled(locked: bool)
signal ready_pressed()

const REROLL_COST := 2
const XP_COST := 4

var _cards: Array[ShopCard] = []
var _gold_label: Label = null
var _level_label: Label = null
var _crew_label: Label = null
var _xp_bar: MeterBar = null
var _timer_bar: MeterBar = null
var _timer_label: Label = null
var _reroll_button: Button = null
var _xp_button: Button = null
var _lock_button: Button = null
var _ready_button: Button = null

var _warning: bool = false
var _gold_flash: float = 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.LINE, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	row.add_child(_build_left_controls())
	row.add_child(_build_cards())
	row.add_child(_build_right_controls())

	Events.gold_changed.connect(_on_gold_changed)
	Events.level_changed.connect(_on_level_changed)
	Events.shop_rolled.connect(func(_ids): refresh())
	Events.board_changed.connect(refresh)
	Events.plan_timer.connect(_on_plan_timer)
	Events.plan_time_warning.connect(_on_time_warning)
	Events.phase_changed.connect(_on_phase_changed)
	Events.shop_locked_changed.connect(func(locked): _lock_button.button_pressed = locked)

	set_process(true)
	refresh()


func _build_left_controls() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size = Vector2(150, 0)

	var level_row := HBoxContainer.new()
	_level_label = UITheme.label("Lv 1", UITheme.FONT_TITLE, UITheme.GOLD_BRIGHT)
	level_row.add_child(_level_label)
	level_row.add_child(UITheme.spacer())
	_crew_label = UITheme.label("Crew 0/1", UITheme.FONT_SMALL, UITheme.MUTED)
	level_row.add_child(_crew_label)
	column.add_child(level_row)

	_xp_bar = MeterBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 14)
	_xp_bar.fill_color = Color("a98bff")
	_xp_bar.show_text = true
	column.add_child(_xp_bar)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)

	_xp_button = UITheme.button("Buy XP  ● 4")
	_xp_button.pressed.connect(func(): xp_pressed.emit())
	_xp_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_xp_button)

	_reroll_button = UITheme.button("Refresh  ● 2")
	_reroll_button.pressed.connect(func(): reroll_pressed.emit())
	_reroll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_reroll_button)

	_lock_button = UITheme.button("🔒")
	_lock_button.toggle_mode = true
	_lock_button.tooltip_text = "Keep this shop for the next round"
	_lock_button.toggled.connect(func(on): lock_toggled.emit(on))
	buttons.add_child(_lock_button)

	column.add_child(buttons)
	return column


func _build_cards() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for i in GameState.SHOP_SIZE:
		var card := ShopCard.new()
		card.index = i
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(func(): card_pressed.emit(i))
		card.hovered.connect(func(at): card_hovered.emit(i, at))
		card.unhovered.connect(func(): card_unhovered.emit())
		row.add_child(card)
		_cards.append(card)

	return row


## Gold and the clock, side by side with the cards rather than in the top bar.
func _build_right_controls() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size = Vector2(140, 0)

	var gold_panel := PanelContainer.new()
	gold_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("1a1509"), UITheme.GOLD, 6))
	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_child(UITheme.label("●", UITheme.FONT_TITLE, UITheme.GOLD))
	_gold_label = UITheme.label("0", UITheme.FONT_HUGE, UITheme.GOLD_BRIGHT)
	gold_row.add_child(_gold_label)
	gold_panel.add_child(gold_row)
	column.add_child(gold_panel)

	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 5)
	_timer_bar = MeterBar.new()
	_timer_bar.custom_minimum_size = Vector2(0, 12)
	_timer_bar.fill_color = UITheme.FOAM
	_timer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_row.add_child(_timer_bar)
	_timer_label = UITheme.label("32", UITheme.FONT_SMALL, UITheme.MUTED)
	timer_row.add_child(_timer_label)
	column.add_child(timer_row)

	_ready_button = UITheme.button("SET SAIL", UITheme.FONT_BODY)
	_ready_button.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("6d1a26"), UITheme.BLOOD, 6))
	_ready_button.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color("8a2130"), Color("ff8a9a"), 6))
	_ready_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ready_button.pressed.connect(func(): ready_pressed.emit())
	column.add_child(_ready_button)

	return column


# --- state -------------------------------------------------------------------

func refresh() -> void:
	var state := GameState
	for i in _cards.size():
		var champion_id: StringName = state.shop[i] if i < state.shop.size() else &""
		var info := state.shop_slot_info(i)
		_cards[i].show_champion(champion_id, info, state.player.gold)

	_gold_label.text = str(state.player.gold)
	_level_label.text = "Lv %d" % state.player.level
	_crew_label.text = "Crew %d/%d" % [state.board.size(), state.player.board_capacity()]
	_crew_label.add_theme_color_override("font_color",
		UITheme.BLOOD if state.board.size() > state.player.board_capacity() else UITheme.MUTED)

	if state.player.is_max_level():
		_xp_bar.set_value(1.0, "MAX")
	else:
		_xp_bar.set_value(float(state.player.xp) / maxf(1.0, state.player.xp_needed()),
			"%d/%d" % [state.player.xp, state.player.xp_needed()])

	_reroll_button.disabled = state.player.gold < REROLL_COST
	_xp_button.disabled = state.player.gold < XP_COST or state.player.is_max_level()


func _on_gold_changed(amount: int, _delta: int) -> void:
	_gold_label.text = str(amount)
	_gold_flash = 1.0
	refresh()


func _on_level_changed(_level: int, _xp: int, _needed: int) -> void:
	refresh()


func _on_plan_timer(seconds_left: float, fraction: float) -> void:
	_timer_bar.set_value(fraction, "")
	_timer_label.text = str(ceili(seconds_left))


## The last few seconds turn the clock and the button orange, because a round
## ending mid-purchase was the complaint.
func _on_time_warning(_seconds_left: float) -> void:
	_warning = true
	_timer_bar.fill_color = UITheme.WARNING
	_timer_label.add_theme_color_override("font_color", UITheme.WARNING)


func _on_phase_changed(phase: int) -> void:
	var planning := phase == GameState.Phase.PLAN
	_ready_button.disabled = not planning
	for card in _cards:
		card.buyable = planning
		card.queue_redraw()
	if planning:
		_warning = false
		_timer_bar.fill_color = UITheme.FOAM
		_timer_label.add_theme_color_override("font_color", UITheme.MUTED)
		refresh()


func _process(delta: float) -> void:
	if _gold_flash > 0.0:
		_gold_flash = maxf(0.0, _gold_flash - delta * 3.0)
		_gold_label.add_theme_color_override("font_color",
			UITheme.GOLD_BRIGHT.lerp(Color.WHITE, _gold_flash))
	if _warning:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_timer_label.add_theme_color_override("font_color",
			UITheme.WARNING.lerp(Color.WHITE, pulse))


# =============================================================================
#  One shop card
# =============================================================================

class ShopCard extends PanelContainer:
	signal pressed()
	signal hovered(at: Vector2)
	signal unhovered()

	var index: int = 0
	var champion: ChampionDef = null
	var buyable: bool = true
	var affordable: bool = true

	## What the player's own fleet already holds of this pirate, and what buying
	## the card would do about it. All of it drives the badge and the frame.
	var owned: int = 0            # star-1 copies, the ones a purchase merges with
	var fleet_count: int = 0      # every copy, at any star
	var fleet_star: int = 0       # the best star among them
	var completes_upgrade: bool = false
	var pair_completes_upgrade: bool = false
	var duplicate_in_shop: bool = false

	var _icon: Label = null
	var _name: Label = null
	var _traits: Label = null
	var _cost: Label = null
	var _badge: Label = null

	func _init() -> void:
		custom_minimum_size = Vector2(126, 92)
		mouse_filter = Control.MOUSE_FILTER_STOP

		# The bottom four pixels are the cost bar, drawn over everything. Without
		# the margin the badge sits under it and reads as struck through.
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_bottom", 6)
		pad.add_theme_constant_override("margin_right", 4)
		add_child(pad)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		pad.add_child(column)

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 5)
		_icon = Label.new()
		_icon.add_theme_font_override("font", UITheme.emoji_font())
		_icon.add_theme_font_size_override("font_size", 18)
		header.add_child(_icon)
		_name = UITheme.label("", UITheme.FONT_SMALL, UITheme.INK)
		_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(_name)
		_cost = UITheme.label("", UITheme.FONT_SMALL, UITheme.GOLD_BRIGHT)
		header.add_child(_cost)
		column.add_child(header)

		_traits = UITheme.label("", UITheme.FONT_TINY, UITheme.MUTED)
		_traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_traits.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(_traits)

		_badge = UITheme.label("", UITheme.FONT_TINY, UITheme.FOAM)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		column.add_child(_badge)

		mouse_entered.connect(func(): hovered.emit(global_position + Vector2(size.x * 0.5, 0)))
		mouse_exited.connect(func(): unhovered.emit())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT and champion != null:
			pressed.emit()

	func show_champion(champion_id: StringName, info: Dictionary, gold: int) -> void:
		var content: Node = Engine.get_main_loop().root.get_node(^"/root/Content")
		champion = content.champion(champion_id) if champion_id != &"" else null
		owned = info.get("owned", 0)
		fleet_count = info.get("fleet_count", 0)
		fleet_star = info.get("fleet_star", 0)
		completes_upgrade = info.get("completes_upgrade", false)
		pair_completes_upgrade = info.get("pair_completes_upgrade", false)
		duplicate_in_shop = info.get("duplicate_in_shop", false)

		if champion == null:
			_icon.text = ""
			_name.text = ""
			_traits.text = ""
			_cost.text = ""
			_badge.text = ""
			affordable = true
			queue_redraw()
			return

		affordable = gold >= champion.cost
		_icon.text = champion.icon
		_name.text = champion.display_name
		_cost.text = "● %d" % champion.cost

		var trait_names := PackedStringArray()
		for trait_id in champion.traits:
			var def: TraitDef = content.trait_def(trait_id)
			if def != null:
				trait_names.append("%s %s" % [def.icon, def.display_name])
		_traits.text = "\n".join(trait_names)

		# The badge answers "is this one mine?" before it answers anything else.
		# Two copies of a card the player owns nothing of used to look exactly
		# like a card they already had one of — same wording weight, same frame —
		# so the one signal worth acting on was buried in the one that is not.
		if completes_upgrade:
			_badge.text = "★★  BUY THIS"
			_badge.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		elif pair_completes_upgrade:
			_badge.text = "★★  BUY BOTH"
			_badge.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		elif owned > 0:
			_badge.text = "IN FLEET  %d/3" % owned
			_badge.add_theme_color_override("font_color", UITheme.GOOD)
		elif fleet_count > 0:
			# Owned, but every copy is already starred up, so buying does not
			# merge. Still worth knowing the pirate is one of yours.
			_badge.text = "IN FLEET  %s" % "★".repeat(fleet_star)
			_badge.add_theme_color_override("font_color", UITheme.GOOD)
		elif duplicate_in_shop:
			_badge.text = "pair in shop"
			_badge.add_theme_color_override("font_color", UITheme.MUTED)
		else:
			_badge.text = ""

		var faded := not affordable or not buyable
		var dim := 0.45 if faded else 1.0
		_name.modulate.a = dim
		_traits.modulate.a = dim
		_icon.modulate.a = dim
		queue_redraw()

	func _draw() -> void:
		if champion == null:
			draw_rect(Rect2(Vector2.ZERO, size), Color("0a1720"))
			return

		var cost_color := UITheme.cost_color(champion.cost)
		var fill := UITheme.PANEL_2.lerp(cost_color, 0.10)
		if not affordable:
			fill = fill.darkened(0.45)
		draw_rect(Rect2(Vector2.ZERO, size), fill)

		# A thick bar along the bottom in the cost colour: the tier is readable
		# from across the screen without reading the number.
		draw_rect(Rect2(Vector2(0, size.y - 4), Vector2(size.x, 4)), cost_color)

		# A card that completes a star-up gets a gold frame and a glow. This is
		# the one card in a shop that is worth interrupting anything for.
		if completes_upgrade or pair_completes_upgrade:
			draw_rect(Rect2(Vector2.ZERO, size), UITheme.GOLD_BRIGHT, false, 2.5)
			var pulse := 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
			draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)),
				Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, pulse), false, 2.0)
		elif fleet_count > 0:
			# Green means "already yours". A pair sitting in the shop gets no
			# frame at all, so the two never read as the same thing again.
			draw_rect(Rect2(Vector2.ZERO, size), UITheme.GOOD, false, 2.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), UITheme.LINE, false, 1.0)

		_draw_owned_pips()

	## Three dots along the bottom-left: how many of this pirate are in the fleet
	## and how many more the star-up wants. Readable without reading the badge,
	## which is what a player scanning five cards on a timer is actually doing.
	##
	## Drawn rather than laid out, and lined up with the badge by asking the badge
	## where it ended up — the card has no fixed height, so a constant would drift
	## the moment the shop bar is resized.
	func _draw_owned_pips() -> void:
		if fleet_count <= 0:
			return
		# No star-1 copies but something in the fleet means every copy is already
		# starred up: the line is finished, so all three pips are filled.
		var filled := owned if owned > 0 else 3
		# Gold is reserved for a purchase that actually stars something up. A
		# line already complete at two stars is green like any other holding.
		var color := UITheme.GOLD_BRIGHT if owned >= 2 else UITheme.GOOD
		var y: float = _badge.global_position.y + _badge.size.y * 0.5 - global_position.y
		for i in 3:
			var centre := Vector2(9.0 + i * 8.0, y)
			if i < filled:
				draw_circle(centre, 2.6, color)
			else:
				draw_arc(centre, 2.6, 0.0, TAU, 10, Color(color.r, color.g, color.b, 0.35), 1.0)


# =============================================================================
#  A small bar with an optional label — XP, the round clock
# =============================================================================

class MeterBar extends Control:
	var fill_color: Color = UITheme.FOAM
	var show_text: bool = false

	var _fraction: float = 0.0
	var _text: String = ""

	func set_value(fraction: float, text: String) -> void:
		_fraction = clampf(fraction, 0.0, 1.0)
		_text = text
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("071219"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * _fraction, size.y)), fill_color)
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.LINE, false, 1.0)
		if not show_text or _text == "":
			return
		var font := UITheme.ui_font()
		var width := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.5 + 4.0), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("dfe8ff"))
