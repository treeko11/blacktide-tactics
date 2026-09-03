class_name Tooltip
extends PanelContainer

## The floating inspector.
##
## **Why it watches its own owner.** The playtest note was that tooltips felt
## sticky. The cause was structural rather than cosmetic: a tooltip was opened by
## a hover and only closed by the matching un-hover, so any panel that rebuilt
## itself while the cursor was over it — the shop on every purchase, the manifest
## on every placement — destroyed the control that owed the tooltip its close,
## and the tooltip simply stayed up.
##
## So it is closed from two directions. Callers still say `hide_now()`, but every
## frame it also checks that the control that opened it still exists and still
## has the cursor. A tooltip whose owner has gone closes itself.
##
## **Pinning is the touch half of the same problem.** A finger has no hover, so
## on a touchscreen the inspector is opened by a press-and-hold and then has to
## stay open with nothing holding it there. A pinned tooltip stops watching the
## cursor, takes input instead of ignoring it, and grows a footer with a close
## button — and a SELL button when the thing being inspected is a pirate the
## player owns, because selling is otherwise bound to a right-click a phone does
## not have.
##
## **It re-reads what it is showing rather than remembering it.** The text was
## built once, at the moment of the hover, which made every number in it a
## photograph: a pirate's health sat at whatever it was when the cursor arrived
## and only changed if the cursor moved, so the mid-fight inspector — the one
## place an item's effect is visible as a figure — was wrong for as long as you
## held still to read it, and a pinned one on a phone never changed at all. So a
## caller hands over a `refresh` Callable that rebuilds the text from the live
## object, and the tooltip calls it a few times a second. A refresh returning ""
## means the thing is gone (sold, merged, dead, the fight over) and closes the
## inspector, which is the only way a pinned one on a touchscreen finds out.

signal sell_requested(unit: RosterUnit)

## Distance kept from the owning control and from the screen edges.
const GAP := 12.0
const EDGE := 8.0
const MAX_WIDTH := 340.0

## How often the text is rebuilt. Ten a second is smooth to read and keeps the
## bbcode re-parse off every frame of a 4x fight; the label is only assigned when
## the string actually differs, so a static tooltip costs one comparison.
const REFRESH_SECONDS := 0.1

## The figure beside a champion's stat block, and the space it takes from it.
const PORTRAIT_SIZE := Vector2(48.0, 56.0)
const PORTRAIT_GAP := 8

var pinned: bool = false

## The body's width with no portrait beside it. Kept so showing one can take the
## difference and hiding one can give it back, without re-deriving the layout.
var _full_body_width: float = 0.0

var _column: VBoxContainer = null
var _row: HBoxContainer = null
var _portrait: UnitPortrait = null
var _body: RichTextLabel = null
var _footer: HBoxContainer = null
var _sell_button: Button = null
var _sell_unit: RosterUnit = null
var _owner: Control = null

## Rebuilds the body text from whatever the tooltip is describing. Empty when
## the caller had nothing live to read back from.
var _refresh_source: Callable = Callable()
var _refresh_timer: float = 0.0

## Where the tooltip was asked to appear, and the size it was placed at. Kept so
## that text which grows or shrinks under a refresh can be re-anchored without
## the caller being involved.
var _anchor: Vector2 = Vector2.ZERO
var _placed_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.panel_style(Color("0d2231"), UITheme.LINE, 7))

	# On a phone the inspector is most of the screen, and a fixed 340 would run
	# off the edge of a 375-point one.
	var width := minf(MAX_WIDTH, maxf(200.0, Layout.css_size.x - 28.0))
	custom_minimum_size = Vector2(minf(230.0, width), 0)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	# The portrait sits beside the stat block rather than above it, so the panel
	# grows sideways into space it already had rather than downwards on a phone
	# where the inspector is most of the screen.
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", PORTRAIT_GAP)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_row)

	_portrait = UnitPortrait.new(PORTRAIT_SIZE)
	# Top-aligned: a champion's stat block is a dozen lines and a figure centred
	# against it floats in the middle of the panel.
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait.visible = false
	_row.add_child(_portrait)

	_full_body_width = width - 24.0
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(_full_body_width, 0)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("normal_font_size", UITheme.FONT_SMALL)
	_body.add_theme_font_size_override("bold_font_size", UITheme.FONT_SMALL)
	_row.add_child(_body)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	_footer.visible = false
	_column.add_child(_footer)

	_sell_button = UITheme.button("SELL", UITheme.FONT_SMALL)
	_sell_button.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("3a0f18"), UITheme.BLOOD, 5))
	_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_button.pressed.connect(func():
		var unit := _sell_unit
		hide_now()
		if unit != null:
			sell_requested.emit(unit))
	_footer.add_child(_sell_button)

	var close := UITheme.button("Close", UITheme.FONT_SMALL)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(hide_now)
	_footer.add_child(close)

	set_process(true)


## Shows `text`, anchored near `at`. `owned_by` is the control the cursor is over.
##
## `refresh` rebuilds the text from the live object a few times a second, so the
## numbers in an open inspector are the current ones rather than the ones that
## happened to be true when the cursor arrived. Pass nothing for anything that
## cannot change while it is on screen.
func show_text(text: String, at: Vector2, owned_by: Control = null,
		refresh: Callable = Callable(), champion: ChampionDef = null) -> void:
	_body.text = text
	_set_portrait(champion)
	_owner = owned_by
	_set_refresh(refresh)
	visible = true
	reset_size()
	# Wait a frame for the label to lay out before measuring it to place it.
	await get_tree().process_frame
	if visible:
		_place(at)


## Opens the inspector and keeps it open until it is dismissed, with buttons.
##
## Takes the text rather than pinning whatever happens to be showing: on a
## touchscreen the hover that opened the tooltip has usually closed it again by
## the time the hold completes a third of a second later, because the emulated
## cursor is not guaranteed to still be sitting on the thing under the finger.
## Re-showing it here means a hold does not depend on that.
##
## `sell_unit` is the pirate the SELL button would sell, or null for anything
## that is not a pirate the player owns. `refresh` is as in `show_text`, and
## matters more here: a pinned inspector is the only one on a touchscreen, and
## nothing else will ever tell it that its pirate died or was sold.
func pin(text: String, at: Vector2, sell_unit: RosterUnit = null,
		refresh: Callable = Callable(), champion: ChampionDef = null) -> void:
	_body.text = text
	_set_portrait(champion)
	visible = true
	pinned = true
	_sell_unit = sell_unit
	_owner = null                       # nothing to watch; it is held open now
	_set_refresh(refresh)
	_footer.visible = true
	# Note what it does *not* do: change mouse_filter. See arm_input.
	_sell_button.visible = sell_unit != null and GameState.phase == GameState.Phase.PLAN
	if _sell_button.visible:
		_sell_button.text = "SELL  %s %d" % [UITheme.COIN, sell_unit.sell_value()]
	reset_size()
	await get_tree().process_frame
	if visible:
		_place(at)


## Starts blocking taps that land on the panel, once the finger that opened it
## has lifted.
##
## **Never do this while a press is live.** A pinned tooltip has to swallow taps
## on its own body, but it is opened by a press-and-hold, which means the finger
## is still down when it appears. Turning mouse_filter to STOP under a live press
## left Godot's press/release bookkeeping unbalanced: the release went somewhere
## else, and from then on every tap was delivered one event behind — a press with
## no release, then a release with no press. The shop looked completely dead
## after inspecting an item, because the first tap on a card only ever arrived as
## a press, and buying happens on release.
func arm_input() -> void:
	if not pinned:
		return
	# A frame, not just "after the touch": `_input` runs *before* the viewport
	# hands the emulated mouse release to the GUI, so arming there is still
	# arming mid-press. Waiting a frame puts it after both.
	await get_tree().process_frame
	if not pinned:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	_column.mouse_filter = Control.MOUSE_FILTER_PASS


func hide_now() -> void:
	visible = false
	pinned = false
	_owner = null
	_sell_unit = null
	_set_portrait(null)
	# Dropped rather than kept: a refresh for a fight is a lambda holding a
	# SimUnit, and `Sim.dispose()` exists because those keep a whole battle alive.
	_set_refresh(Callable())
	# Both filters, not just this node's. Leaving the inner column on PASS meant
	# that the next hover — which makes the tooltip visible again — put an
	# invisible-to-the-eye but very much hit-testable panel over the shop, and the
	# card underneath never saw the tap.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _column != null:
		_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _footer != null:
		_footer.visible = false


## Shows the champion's figure beside the text, or nothing at all.
##
## Only a champion gets one. A trait, an item and a rival captain are not things
## with bodies, and a portrait column reserved for them would be an empty gap on
## most of the inspectors in the game.
##
## The width is moved between the two rather than left to the container, because
## a RichTextLabel with `fit_content` reports the width it was given as its
## minimum — so a body sized for the full panel simply pushes the portrait off
## the edge instead of making room for it.
func _set_portrait(champion: ChampionDef) -> void:
	if _portrait == null:
		return
	_portrait.visible = champion != null
	_portrait.champion = champion
	if champion != null:
		var tier: Color = UITheme.cost_color(champion.cost)
		_portrait.team_color = tier
		_portrait.rim_color = tier
		_body.custom_minimum_size.x = _full_body_width - PORTRAIT_SIZE.x - PORTRAIT_GAP
	else:
		_body.custom_minimum_size.x = _full_body_width


func _set_refresh(refresh: Callable) -> void:
	_refresh_source = refresh
	_refresh_timer = REFRESH_SECONDS


func _place(at: Vector2) -> void:
	_anchor = at
	_placed_size = size
	var viewport := get_viewport_rect().size
	var wanted := size
	var pos := at + Vector2(GAP, GAP)
	if pos.x + wanted.x > viewport.x - EDGE:
		pos.x = at.x - wanted.x - GAP
	if pos.y + wanted.y > viewport.y - EDGE:
		pos.y = viewport.y - wanted.y - EDGE
	global_position = pos.clamp(Vector2(EDGE, EDGE), viewport - wanted - Vector2(EDGE, EDGE))


## The other half of the stickiness fix: nothing is trusted to tell us to close.
##
## A pinned tooltip opts out — it is held open deliberately, and on a touchscreen
## the emulated cursor sits wherever the last tap landed, which is rarely still
## over the thing being read.
func _process(delta: float) -> void:
	if not visible:
		return

	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_SECONDS
		_reread()
		if not visible:
			return

	# Text that grew or shrank is re-anchored, so a refreshed inspector near an
	# edge does not slide off it. Nothing moves while the size is steady, which
	# is the usual case — the numbers change, the line count does not.
	if size != _placed_size:
		_place(_anchor)

	if pinned or _owner == null:
		return
	if not is_instance_valid(_owner) or not _owner.is_inside_tree():
		hide_now()
		return
	var rect := Rect2(_owner.global_position, _owner.size)
	if not rect.has_point(get_viewport().get_mouse_position()):
		hide_now()


## Rebuilds the body from the live object, if the caller gave us a way to.
##
## An empty string is the source saying it is gone — a pirate sold, merged into a
## star-up, killed in the fight it was being read during — and closes the
## inspector rather than leaving a panel describing something no longer there.
func _reread() -> void:
	if not _refresh_source.is_valid():
		return
	var text: String = _refresh_source.call()
	if text == "":
		hide_now()
		return
	if text != _body.text:
		_body.text = text
		reset_size()


# =============================================================================
#  Content builders
# =============================================================================

## A champion, with its stats, its ability at the right star, and full text for
## everything it is carrying.
##
## Item descriptions are spelled out here rather than named, because "what does
## this item actually do" was a question the old build only answered by hovering
## something else.
static func champion_text(champion: ChampionDef, star: int,
		items: Array = [], live: SimUnit = null) -> String:
	var stats := champion.stats_at(star)
	var lines := PackedStringArray()

	# No emoji on the title. Every caller of this text is the inspector, and the
	# inspector now draws the pirate's actual figure beside it — a glyph of a
	# bird next to a drawing of the same pirate is the old identifier arguing
	# with the new one.
	lines.append("[font_size=17][b]%s[/b][/font_size]  [color=#ffd98a]%s %d[/color]"
		% [champion.display_name, UITheme.COIN, champion.cost])
	if star > 1:
		lines.append("%s" % UITheme.STAR.repeat(star))

	var trait_names := PackedStringArray()
	for trait_id in champion.traits:
		var def: TraitDef = Content.trait_def(trait_id)
		if def != null:
			trait_names.append("%s %s" % [def.icon, def.display_name])
	if not trait_names.is_empty():
		lines.append("[color=#a9c4d4]%s[/color]" % "   ".join(trait_names))

	lines.append("")
	# Live numbers during a fight, base numbers outside one — a unit with items
	# and traits applied is a different unit and should read as one.
	if live != null:
		lines.append("Health [b]%d[/b] / %d    Attack [b]%d[/b]"
			% [roundi(live.hp), roundi(live.max_hp), roundi(live.ad)])
		lines.append("Speed [b]%.2f[/b]    Range [b]%d[/b]" % [live.attack_speed, live.attack_range])
		lines.append("Armour [b]%d[/b]    Resist [b]%d[/b]"
			% [roundi(live.armor), roundi(live.magic_resist)])
		lines.append(_power_line(live.ability_power))
		if live.casts():
			lines.append("Mana [b]%d[/b] / %d" % [roundi(live.mana), roundi(live.max_mana)])
		if live.shield > 0.0:
			lines.append("[color=#cfe9ff]Shield %d[/color]" % roundi(live.shield))
	else:
		lines.append("Health [b]%d[/b]    Attack [b]%d[/b]" % [stats["max_hp"], stats["ad"]])
		lines.append("Speed [b]%.2f[/b]    Range [b]%d[/b]"
			% [stats["attack_speed"], stats["attack_range"]])
		lines.append("Armour [b]%d[/b]    Resist [b]%d[/b]"
			% [stats["armor"], stats["magic_resist"]])
		lines.append(_power_line(SimUnit.BASE_AP))
		if champion.casts():
			lines.append("Mana [b]%d[/b] / %d" % [stats["mana_start"], stats["mana_max"]])

	if champion.ability_name != "":
		var ability: Ability = Content.ability(champion.id)
		var scaling: Dictionary = ability.scaling() if ability != null else {}
		lines.append("")
		lines.append("[color=#7fe3ff][b]%s[/b][/color]" % champion.ability_name)
		lines.append("[color=#b9cbd8]%s[/color]" % Content.format_description(
			champion.ability_desc, champion.ability_values, star, scaling))
		var legend := _scaling_legend(scaling)
		if legend != "":
			lines.append(legend)

	if not items.is_empty():
		lines.append("")
		lines.append("[color=#7c93a4]CARRYING[/color]")
		for item_id in items:
			var item: ItemDef = Content.item_def(item_id)
			if item == null:
				continue
			lines.append("%s [b]%s[/b]" % [item.icon, item.display_name])
			lines.append("[color=#8fa6b5]%s[/color]" % item.description)

	return "\n".join(lines)


## Ability power in the stat block, on every champion rather than only on the
## ones that cast.
##
## It is the one stat nothing in the HUD ever showed, and it does not appear on a
## ChampionDef at all — every pirate starts at exactly SimUnit.BASE_AP and only
## items, the Siren trait and two abilities move it. Shown even at base, and even
## on a body that casts nothing, because a stat that only appears once it is
## already bonused is one nobody learns exists in time to go looking for it.
##
## The multiplier is the half that means something: 100 is the baseline the
## ability numbers are written at, so the figure a player wants is not "180" but
## "everything this casts hits for 1.8 times what the page says".
static func _power_line(ability_power: float) -> String:
	return "Ability Power [b]%d[/b]  [color=#c9a2ff]×%.2f[/color]" % [
		roundi(ability_power), ability_power / SimUnit.BASE_AP]


## What the marks beside the ability numbers mean.
##
## One line, and no numbers in it. The figures are already directly above — the
## stat block carries Attack and Ability Power, which are exactly the two stats
## a mark can name — and repeating them here would cost three more lines of a
## panel that is most of the screen on a phone. What is missing without this is
## only the decoding: what "AP" is short for, and which colour is which.
##
## Only the stats this ability uses are listed, so it is one entry for most
## champions and two for the four hybrids. Tuck, whose ability scales off
## nothing, gets no line at all rather than a heading with nothing under it.
static func _scaling_legend(scaling: Dictionary) -> String:
	# Walked in a fixed order rather than collected and sorted, so a hybrid's two
	# entries come out the same way round on every champion instead of following
	# whatever order that ability happened to declare its keys in. Attack damage
	# first: it is the number an AD figure is a percentage of, and ability power
	# is the thing that multiplies the rest.
	var used := PackedStringArray()
	for stat in [&"ad", &"ap"]:
		if not scaling.values().has(stat):
			continue
		var mark: Dictionary = Ability.SCALING[stat]
		used.append("[color=#%s]%s[/color] %s"
			% [mark["colour"], String(mark["tag"]).strip_edges(), mark["name"]])
	if used.is_empty():
		return ""
	return "\n[color=#7c93a4]SCALES WITH[/color]  [color=#8fa6b5]%s[/color]" \
		% "   ".join(used)


static func trait_text(trait_id: StringName, count: int, tier: int) -> String:
	var def: TraitDef = Content.trait_def(trait_id)
	if def == null:
		return ""

	var kind := "Origin" if def.kind == TraitDef.Kind.ORIGIN else "Class"
	var lines := PackedStringArray()
	lines.append("[font_size=17][b]%s %s[/b][/font_size]" % [def.icon, def.display_name])
	lines.append("[color=#7c93a4]%s · %d fielded[/color]" % [kind, count])
	lines.append("")
	lines.append("[color=#b9cbd8]%s[/color]"
		% Content.format_description(def.description, def.values, tier + 1))
	lines.append("")

	for i in def.breakpoints.size():
		var parts := PackedStringArray()
		for key in def.values:
			var values: Array = def.values[key]
			if i < values.size():
				parts.append("%s %s" % [key, str(values[i])])
		var line := "%d — %s" % [def.breakpoints[i], ", ".join(parts)]
		if i == tier:
			lines.append("[color=#ffd98a][b]%s[/b][/color]" % line)
		else:
			lines.append("[color=#7c93a4]%s[/color]" % line)

	lines.append("")
	lines.append(_carrier_lines(trait_id))
	return "\n".join(lines)


## Every pirate that carries a trait, grouped by what they cost, and marked with
## where the player's own copies are.
##
## The breakpoint list says a trait wants two more pirates; it does not say
## *which* two, and until now the only place that answered was the almanac — a
## full-screen dialog opened over the shop, mid-decision, with a clock running.
## The inspector is already open on the badge, so the answer belongs in it.
##
## Grouped by cost, because that is the shape of the decision: reaching a
## breakpoint off a 1-cost bench body and reaching it off a 5-cost are not the
## same plan. Names inside a cost share a line rather than taking one each, so
## the widest trait — nine carriers — is five lines instead of nine.
##
## The marks are live, because this text is rebuilt ten times a second: a pirate
## on the board is one of the ones being counted right now (gold), one on the
## bench is a breakpoint sitting in the hold, and the rest are dim. That is the
## "what would complete this" question answered in the colours.
static func _carrier_lines(trait_id: StringName) -> String:
	# Where each owned copy is. The board wins over the bench: a champion seated
	# is counted by the trait however many spares sit behind it.
	# The bench is fixed length and holds a null in every empty slot.
	var placed: Dictionary = {}
	for unit in GameState.bench:
		if unit != null:
			placed[unit.id()] = false
	for unit in GameState.board:
		placed[unit.id()] = true

	# Cost -> the names at that cost, already marked up.
	var by_cost: Dictionary = {}
	for champion in Content.champions():
		# Monsters carry no traits, but a creep that grew one has no business in
		# a shopping list for a trait the player cannot buy into.
		if champion.cost <= 0 or not champion.has_trait(trait_id):
			continue
		var entry := champion.display_name
		if placed.get(champion.id, null) == true:
			entry = "[color=#ffd98a][b]✔ %s[/b][/color]" % entry
		elif placed.has(champion.id):
			entry = "[color=#b9cbd8]· %s[/color]" % entry
		else:
			entry = "[color=#5f7280]%s[/color]" % entry
		# A plain Array, not a PackedStringArray: a packed array held in a
		# Dictionary is a value, so appending through the subscript appends to a
		# copy and the line comes out empty.
		if not by_cost.has(champion.cost):
			by_cost[champion.cost] = []
		by_cost[champion.cost].append(entry)

	var costs := by_cost.keys()
	costs.sort()
	if costs.is_empty():
		return "[color=#7c93a4]Nobody carries it, which is a content bug.[/color]"

	var lines := PackedStringArray()
	lines.append("[color=#7c93a4]WHO HAS IT[/color]")
	for cost in costs:
		lines.append("[color=#ffd98a]%s %d[/color]  %s"
			% [UITheme.COIN, cost, "   ".join(by_cost[cost])])
	return "\n".join(lines)


## An item, and — for a component — every pairing it takes part in.
##
## This is the "what do items combine into" answer. A player holding two
## components had no way to find out what they made short of trying it, and
## equipping cannot be undone.
static func item_text(item_id: StringName) -> String:
	var item: ItemDef = Content.item_def(item_id)
	if item == null:
		return ""

	var lines := PackedStringArray()
	lines.append("[font_size=17][b]%s %s[/b][/font_size]" % [item.icon, item.display_name])
	lines.append("")
	lines.append("[color=#b9cbd8]%s[/color]" % item.description)
	lines.append("")

	if item.is_component:
		lines.append("[color=#7c93a4]FORGES INTO[/color]")
		var held: Dictionary = {}
		for other in GameState.player.items:
			held[other] = int(held.get(other, 0)) + 1
		for pairing in Content.forges_using(item.id):
			var other: ItemDef = Content.item_def(pairing["with"])
			var result: ItemDef = Content.item_def(pairing["makes"])
			# Mark the ones the player could make right now.
			var have: bool = held.has(other.id) and (other.id != item.id or int(held[other.id]) >= 2)
			var marker := "[color=#4bd08a]✔[/color] " if have else "[color=#3d4d59]·[/color] "
			lines.append("%s+ %s %s  »  [b]%s %s[/b]"
				% [marker, other.icon, other.display_name, result.icon, result.display_name])
	else:
		var parts := PackedStringArray()
		for component_id in item.recipe:
			var component: ItemDef = Content.item_def(component_id)
			parts.append("%s %s" % [component.icon, component.display_name])
		lines.append("[color=#7c93a4]Forged from %s[/color]" % " + ".join(parts))

	return "\n".join(lines)


## A rival captain: their standing, their traits, their board, and their items.
##
## The items are listed because "I don't think I saw the AI use items" was a
## visibility problem as much as a behaviour one.
static func captain_text(captain: Captain) -> String:
	var lines := PackedStringArray()
	lines.append("[font_size=17][b]%s %s[/b][/font_size]" % [captain.icon, captain.display_name])
	lines.append("[color=#7c93a4]Level %d · %d hull · %s[/color]"
		% [captain.level, maxi(0, captain.hp), captain.streak_label()])

	if not (captain is Bot):
		return "\n".join(lines)

	var bot: Bot = captain
	var summary := bot.trait_summary(Content)
	if not summary.is_empty():
		lines.append("")
		var trait_names := PackedStringArray()
		for entry in summary.slice(0, 5):
			var def: TraitDef = Content.trait_def(entry["id"])
			trait_names.append("%s %s %d" % [def.icon, def.display_name, entry["count"]])
		lines.append("[color=#a9c4d4]%s[/color]" % "   ".join(trait_names))

	lines.append("")
	var fielded := bot.board_units()
	if fielded.is_empty():
		lines.append("[color=#7c93a4]An empty deck.[/color]")
	for unit in fielded:
		var stars := " %s" % UITheme.STAR.repeat(unit.star) if unit.star > 1 else ""
		var carried := ""
		if not unit.items.is_empty():
			var icons := PackedStringArray()
			for item_id in unit.items:
				icons.append(Content.item_def(item_id).icon)
			carried = "   [color=#ffd98a]%s[/color]" % "".join(icons)
		lines.append("%s %s%s%s"
			% [unit.champion.icon, unit.champion.display_name, stars, carried])

	return "\n".join(lines)
