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

## Set by Main when a press-and-hold has already served the press that is about
## to end — the player asked to read the card, not to buy it. Cleared by the
## card that consumes it.
##
## A card is the only thing in the HUD a bare tap *acts* on; everywhere else a
## tap either starts a drag or does nothing, so nothing else needs this.
static var swallow_click: bool = false

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
	add_child(_build_compact() if Layout.compact() else _build_wide())

	Events.gold_changed.connect(_on_gold_changed)
	Events.level_changed.connect(_on_level_changed)
	Events.shop_rolled.connect(func(_ids): refresh())
	Events.board_changed.connect(refresh)
	Events.plan_timer.connect(_on_plan_timer)
	Events.plan_time_warning.connect(_on_time_warning)
	Events.run_hold_changed.connect(_show_hold)
	Events.phase_changed.connect(_on_phase_changed)
	Events.shop_locked_changed.connect(func(locked): _lock_button.button_pressed = locked)

	set_process(true)
	refresh()


## Level, cards and gold in one row across the bottom of a desktop screen.
func _build_wide() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(150, 0)
	left.add_child(_make_level_row())
	left.add_child(_make_xp_bar())
	left.add_child(_make_buttons())
	row.add_child(left)

	row.add_child(_make_cards())

	# Gold and the clock, side by side with the cards rather than in the top bar.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size = Vector2(140, 0)
	right.add_child(_make_gold_panel())
	right.add_child(_make_timer_row())
	var sail := _make_ready_button()
	sail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sail)
	row.add_child(right)

	return row


## The same parts stacked, for a narrow column.
##
## Used by both phone layouts: upright it is the bottom of the screen, sideways
## it is the column beside the board. Both are narrow, which is the thing that
## decides the arrangement — the sideways screen is wide, but the shop is not.
##
## The order is the order they get used in: cards first, because the planning
## phase is mostly spent looking at them, then the money and the clock, then the
## buttons, and SET SAIL last where a thumb already rests.
func _build_compact() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)

	column.add_child(_make_cards())

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 6)

	var level := VBoxContainer.new()
	level.add_theme_constant_override("separation", 2)
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level.add_child(_make_level_row())

	# The XP bar and the round clock share a line. They are different meters, but
	# they are both thin bars and a second row of one costs the board twenty
	# points of height. Colour tells them apart: purple fills, foam drains.
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 6)
	var xp := _make_xp_bar()
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(xp)
	var clock := _make_timer_row()
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(clock)
	level.add_child(meters)

	status.add_child(level)
	status.add_child(_make_gold_panel())
	column.add_child(status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	var buttons := _make_buttons()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(buttons)
	var sail := _make_ready_button()
	sail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(sail)
	column.add_child(actions)

	return column


# --- the parts both layouts are assembled from -------------------------------

func _make_level_row() -> Control:
	var row := HBoxContainer.new()
	_level_label = UITheme.label("Lv 1",
		UITheme.FONT_BODY if Layout.compact() else UITheme.FONT_TITLE, UITheme.GOLD_BRIGHT)
	row.add_child(_level_label)
	row.add_child(UITheme.spacer())
	_crew_label = UITheme.label("Crew 0/1", UITheme.FONT_SMALL, UITheme.MUTED)
	row.add_child(_crew_label)
	return row


func _make_xp_bar() -> Control:
	_xp_bar = MeterBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 12 if Layout.compact() else 14)
	_xp_bar.fill_color = Color("a98bff")
	_xp_bar.show_text = true
	return _xp_bar


func _make_buttons() -> Control:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)

	# "Buy XP  * 4" does not fit a third of a phone. The cost still shows; the
	# verb is the half a returning player does not need read out.
	var compact := Layout.compact()

	_xp_button = UITheme.button(("XP  %s %d" if compact else "Buy XP  %s %d")
		% [UITheme.COIN, GameState.XP_COST])
	_xp_button.pressed.connect(func(): xp_pressed.emit())
	_xp_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_xp_button)

	_reroll_button = UITheme.button(("Roll  %s %d" if compact else "Refresh  %s %d")
		% [UITheme.COIN, GameState.REROLL_COST])
	_reroll_button.pressed.connect(func(): reroll_pressed.emit())
	_reroll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_reroll_button)

	_lock_button = UITheme.button("🔒")
	_lock_button.toggle_mode = true
	# Same reason as the speed buttons in TopBar: a rebuild throws this panel away
	# and the lock lives in GameState, so it has to be read back rather than
	# assumed off.
	_lock_button.button_pressed = GameState.shop_locked
	_lock_button.tooltip_text = "Keep this shop for the next round"
	_lock_button.toggled.connect(func(on): lock_toggled.emit(on))
	buttons.add_child(_lock_button)

	return buttons


func _make_cards() -> Control:
	var holder: Container
	if Layout.compact():
		# One row of five, not the JS build's three-per-row wrap. A second row of
		# cards comes out of the board's height, and the board is the panel that
		# cannot afford it — see Layout.shop_columns.
		var grid := GridContainer.new()
		grid.columns = Layout.shop_columns()
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		holder = grid
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		holder = row
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for i in GameState.SHOP_SIZE:
		var card := ShopCard.new()
		card.index = i
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(func(): card_pressed.emit(i))
		card.hovered.connect(func(at): card_hovered.emit(i, at))
		card.unhovered.connect(func(): card_unhovered.emit())
		holder.add_child(card)
		_cards.append(card)

	return holder


func _make_gold_panel() -> Control:
	var compact := Layout.compact()
	var gold_panel := PanelContainer.new()
	gold_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("1a1509"), UITheme.GOLD, 6))
	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_child(UITheme.label(UITheme.COIN,
		UITheme.FONT_BODY if compact else UITheme.FONT_TITLE, UITheme.GOLD))
	_gold_label = UITheme.label("0",
		UITheme.FONT_TITLE if compact else UITheme.FONT_HUGE, UITheme.GOLD_BRIGHT)
	gold_row.add_child(_gold_label)
	gold_panel.add_child(gold_row)
	return gold_panel


func _make_timer_row() -> Control:
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 5)
	_timer_bar = MeterBar.new()
	_timer_bar.custom_minimum_size = Vector2(0, 12)
	_timer_bar.fill_color = UITheme.FOAM
	_timer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_row.add_child(_timer_bar)
	_timer_label = UITheme.label("32", UITheme.FONT_SMALL, UITheme.MUTED)
	timer_row.add_child(_timer_label)
	# Read from the run, not from the constant. A bar built while the opening
	# almanac is up — the first build of every run, and every rotation until the
	# player closes it — would otherwise come back claiming a clock that is not
	# running, which is the same trap the speed buttons and the shop lock fell in.
	_show_hold(GameState.awaiting_start)
	return timer_row


func _make_ready_button() -> Button:
	_ready_button = UITheme.button("SET SAIL", UITheme.FONT_BODY)
	_ready_button.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("6d1a26"), UITheme.BLOOD, 6))
	_ready_button.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color("8a2130"), Color("ff8a9a"), 6))
	_ready_button.pressed.connect(func(): ready_pressed.emit())
	return _ready_button


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

	_reroll_button.disabled = state.player.gold < GameState.REROLL_COST
	_xp_button.disabled = state.player.gold < GameState.XP_COST or state.player.is_max_level()


func _on_gold_changed(amount: int, _delta: int) -> void:
	_gold_label.text = str(amount)
	_gold_flash = 1.0
	refresh()


func _on_level_changed(_level: int, _xp: int, _needed: int) -> void:
	refresh()


## The run is holding at the line: the clock does not start until the player has
## closed the opening almanac or pressed SET SAIL. A full bar frozen at "32"
## reads as a broken clock, so it says what it is waiting on instead.
func _show_hold(waiting: bool) -> void:
	_timer_bar.set_value(1.0, "")
	_timer_label.text = "HOLD" if waiting else str(ceili(GameState.plan_timer))


func _on_plan_timer(seconds_left: float, fraction: float) -> void:
	_timer_bar.set_value(fraction, "")
	_timer_label.text = str(ceili(seconds_left))


## The last few seconds turn the clock and the button orange, because a round
## ending mid-purchase was the complaint.
func _on_time_warning(_seconds_left: float) -> void:
	_set_warning(true)


## `plan_time_warning` fires once per round, so a panel built after it has already
## gone by would sit in the wrong colour for the rest of the round. Reading the
## clock instead of the signal means a rebuild — a phone rotating with eight
## seconds left — comes back up still warning.
func _set_warning(on: bool) -> void:
	_warning = on
	_timer_bar.fill_color = UITheme.WARNING if on else UITheme.FOAM
	_timer_label.add_theme_color_override("font_color",
		UITheme.WARNING if on else UITheme.MUTED)


func _on_phase_changed(phase: int) -> void:
	var planning := phase == GameState.Phase.PLAN
	_ready_button.disabled = not planning
	for card in _cards:
		card.buyable = planning
	if planning:
		_set_warning(false)
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

	## Whether the card can be bought at all — false outside the planning phase —
	## and whether the player can currently pay for it. Both fade the card, so both
	## repaint it on the way in: setting `buyable` and leaving the fade to the next
	## refresh() meant the cards stayed at full brightness through a whole battle,
	## looking exactly as buyable as they had a moment earlier.
	var buyable: bool = true:
		set(value):
			buyable = value
			_apply_fade()
	var affordable: bool = true:
		set(value):
			affordable = value
			_apply_fade()

	## What the player's own fleet already holds of this pirate, and what buying
	## the card would do about it. All of it drives the badge and the frame.
	var owned: int = 0            # star-1 copies, the ones a purchase merges with
	var fleet_count: int = 0      # every copy, at any star
	var fleet_star: int = 0       # the best star among them
	var completes_upgrade: bool = false
	var pair_completes_upgrade: bool = false
	var duplicate_in_shop: bool = false

	var _icon: UnitPortrait = null
	var _name: Label = null
	var _traits: Label = null
	var _cost: Label = null
	var _badge: Label = null

	func _init() -> void:
		custom_minimum_size = Layout.shop_card()
		mouse_filter = Control.MOUSE_FILTER_STOP

		# The bottom four pixels are the cost bar, drawn over everything. Without
		# the margin the badge sits under it and reads as struck through.
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_bottom", 6)
		pad.add_theme_constant_override("margin_right", 4)
		add_child(pad)

		var compact := Layout.compact()

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1 if compact else 2)
		pad.add_child(column)

		# The figure the board draws, not the emoji the prototype used. This is
		# the one screen where a pirate is chosen, and an emoji says nothing
		# about whether the thing being bought is a siren or a sea serpent.
		#
		# Sized close to the label it replaced on purpose: the card's height is
		# the board's height on a phone, and the shop taking two extra points a
		# row is the board losing ten.
		_icon = UnitPortrait.new(Vector2(20.0, 22.0) if compact
			else Vector2(28.0, 30.0))
		_name = UITheme.label("", UITheme.FONT_TINY if compact else UITheme.FONT_SMALL,
			UITheme.INK)
		_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cost = UITheme.label("", UITheme.FONT_TINY if compact else UITheme.FONT_SMALL,
			UITheme.GOLD_BRIGHT)

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 5)
		header.add_child(_icon)
		if compact:
			# Five cards across a phone leaves a card about seventy points wide.
			# With the icon and the price beside it the name had twenty-eight of
			# those, so "Old Anchor Ned" came out as four stacked fragments and a
			# card 150 points tall — the height the board was missing. On its own
			# line the name gets the whole card.
			header.add_child(UITheme.spacer())
			header.add_child(_cost)
			column.add_child(header)
			column.add_child(_name)
		else:
			header.add_child(_name)
			header.add_child(_cost)
			column.add_child(header)

		_traits = UITheme.label("", 9 if compact else UITheme.FONT_TINY, UITheme.MUTED)
		_traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_traits.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(_traits)

		_badge = UITheme.label("", 9 if compact else UITheme.FONT_TINY, UITheme.FOAM)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_badge.clip_text = true
		column.add_child(_badge)

		mouse_entered.connect(func(): hovered.emit(global_position + Vector2(size.x * 0.5, 0)))
		mouse_exited.connect(func(): unhovered.emit())

	## Buying happens on release, not on press.
	##
	## On press there is no way to know yet whether the player is tapping to buy
	## or holding to read: a hold is only a hold once a third of a second has
	## gone by, and by then a press-triggered purchase has already happened.
	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed or champion == null:
			return
		if ShopBar.swallow_click:
			ShopBar.swallow_click = false
			return
		pressed.emit()

	func show_champion(champion_id: StringName, info: Dictionary, gold: int) -> void:
		champion = Content.champion(champion_id) if champion_id != &"" else null
		owned = info.get("owned", 0)
		fleet_count = info.get("fleet_count", 0)
		fleet_star = info.get("fleet_star", 0)
		completes_upgrade = info.get("completes_upgrade", false)
		pair_completes_upgrade = info.get("pair_completes_upgrade", false)
		duplicate_in_shop = info.get("duplicate_in_shop", false)

		if champion == null:
			_icon.champion = null
			_name.text = ""
			_traits.text = ""
			_cost.text = ""
			_badge.text = ""
			affordable = true
			return

		affordable = gold >= champion.cost
		_icon.champion = champion
		# The plate under a shop pirate is its cost tier — nobody owns it yet, so
		# there is no team for it to be.
		var tier: Color = UITheme.cost_color(champion.cost)
		_icon.team_color = tier
		_icon.rim_color = tier
		_name.text = champion.display_name
		_cost.text = "%s %d" % [UITheme.COIN, champion.cost]

		var trait_names := PackedStringArray()
		for trait_id in champion.traits:
			var def: TraitDef = Content.trait_def(trait_id)
			if def != null:
				trait_names.append("%s %s" % [def.icon, def.display_name])
		_traits.text = "\n".join(trait_names)

		# The badge answers "is this one mine?" before it answers anything else.
		# Two copies of a card the player owns nothing of used to look exactly
		# like a card they already had one of — same wording weight, same frame —
		# so the one signal worth acting on was buried in the one that is not.
		# A phone card has room for a word, not a sentence. The frame and the pips
		# carry the same message either way.
		var narrow := Layout.compact()
		if completes_upgrade:
			_badge.text = ("%s BUY" if narrow else "%s BUY THIS") % UITheme.STAR.repeat(2)
			_badge.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		elif pair_completes_upgrade:
			_badge.text = ("%s BOTH" if narrow else "%s BUY BOTH") % UITheme.STAR.repeat(2)
			_badge.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		elif owned > 0:
			_badge.text = "%d/3" % owned if narrow else "IN FLEET  %d/3" % owned
			_badge.add_theme_color_override("font_color", UITheme.GOOD)
		elif fleet_count > 0:
			# Owned, but every copy is already starred up, so buying does not
			# merge. Still worth knowing the pirate is one of yours.
			_badge.text = UITheme.STAR.repeat(fleet_star) if narrow \
				else "IN FLEET %s" % UITheme.STAR.repeat(fleet_star)
			_badge.add_theme_color_override("font_color", UITheme.GOOD)
		elif duplicate_in_shop:
			_badge.text = "pair" if narrow else "pair in shop"
			_badge.add_theme_color_override("font_color", UITheme.MUTED)
		else:
			_badge.text = ""

		_apply_fade()

	## Dims an empty, unaffordable or unbuyable card, and repaints the frame.
	func _apply_fade() -> void:
		if _name == null:
			return                        # a setter running before _init finished
		var dim := 0.45 if (not affordable or not buyable) else 1.0
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
