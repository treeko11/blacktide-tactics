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

signal sell_requested(unit: RosterUnit)

## Distance kept from the owning control and from the screen edges.
const GAP := 12.0
const EDGE := 8.0
const MAX_WIDTH := 340.0

var pinned: bool = false

var _column: VBoxContainer = null
var _body: RichTextLabel = null
var _footer: HBoxContainer = null
var _sell_button: Button = null
var _sell_unit: RosterUnit = null
var _owner: Control = null


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

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(width - 24.0, 0)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("normal_font_size", UITheme.FONT_SMALL)
	_body.add_theme_font_size_override("bold_font_size", UITheme.FONT_SMALL)
	_column.add_child(_body)

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
func show_text(text: String, at: Vector2, owned_by: Control = null) -> void:
	_body.text = text
	_owner = owned_by
	visible = true
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
## that is not a pirate the player owns.
func pin(text: String, at: Vector2, sell_unit: RosterUnit = null) -> void:
	_body.text = text
	visible = true
	pinned = true
	_sell_unit = sell_unit
	_owner = null                       # nothing to watch; it is held open now
	_footer.visible = true
	# Note what it does *not* do: change mouse_filter. See arm_input.
	_sell_button.visible = sell_unit != null and GameState.phase == GameState.Phase.PLAN
	if _sell_button.visible:
		_sell_button.text = "SELL  %s %d" % [UITheme.COIN, sell_unit.sell_value()]
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
	# Both filters, not just this node's. Leaving the inner column on PASS meant
	# that the next hover — which makes the tooltip visible again — put an
	# invisible-to-the-eye but very much hit-testable panel over the shop, and the
	# card underneath never saw the tap.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _column != null:
		_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _footer != null:
		_footer.visible = false


func _place(at: Vector2) -> void:
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
func _process(_delta: float) -> void:
	if not visible or pinned or _owner == null:
		return
	if not is_instance_valid(_owner) or not _owner.is_inside_tree():
		hide_now()
		return
	var rect := Rect2(_owner.global_position, _owner.size)
	if not rect.has_point(get_viewport().get_mouse_position()):
		hide_now()


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
	var content: Node = Engine.get_main_loop().root.get_node(^"/root/Content")
	var stats := champion.stats_at(star)
	var lines := PackedStringArray()

	lines.append("[font_size=17][b]%s %s[/b][/font_size]  [color=#ffd98a]%s %d[/color]"
		% [champion.icon, champion.display_name, UITheme.COIN, champion.cost])
	if star > 1:
		lines.append("%s" % UITheme.STAR.repeat(star))

	var trait_names := PackedStringArray()
	for trait_id in champion.traits:
		var def: TraitDef = content.trait_def(trait_id)
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
		if champion.casts():
			lines.append("Mana [b]%d[/b] / %d" % [stats["mana_start"], stats["mana_max"]])

	if champion.ability_name != "":
		lines.append("")
		lines.append("[color=#7fe3ff][b]%s[/b][/color]" % champion.ability_name)
		lines.append("[color=#b9cbd8]%s[/color]" % Content.format_description(
			champion.ability_desc, champion.ability_values, star))

	if not items.is_empty():
		lines.append("")
		lines.append("[color=#7c93a4]CARRYING[/color]")
		for item_id in items:
			var item: ItemDef = content.item_def(item_id)
			if item == null:
				continue
			lines.append("%s [b]%s[/b]" % [item.icon, item.display_name])
			lines.append("[color=#8fa6b5]%s[/color]" % item.description)

	return "\n".join(lines)


static func trait_text(trait_id: StringName, count: int, tier: int) -> String:
	var content: Node = Engine.get_main_loop().root.get_node(^"/root/Content")
	var def: TraitDef = content.trait_def(trait_id)
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

	return "\n".join(lines)


## An item, and — for a component — every pairing it takes part in.
##
## This is the "what do items combine into" answer. A player holding two
## components had no way to find out what they made short of trying it, and
## equipping cannot be undone.
static func item_text(item_id: StringName) -> String:
	var content: Node = Engine.get_main_loop().root.get_node(^"/root/Content")
	var item: ItemDef = content.item_def(item_id)
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
		for pairing in content.forges_using(item.id):
			var other: ItemDef = content.item_def(pairing["with"])
			var result: ItemDef = content.item_def(pairing["makes"])
			# Mark the ones the player could make right now.
			var have: bool = held.has(other.id) and (other.id != item.id or int(held[other.id]) >= 2)
			var marker := "[color=#4bd08a]✔[/color] " if have else "[color=#3d4d59]·[/color] "
			lines.append("%s+ %s %s  »  [b]%s %s[/b]"
				% [marker, other.icon, other.display_name, result.icon, result.display_name])
	else:
		var parts := PackedStringArray()
		for component_id in item.recipe:
			var component: ItemDef = content.item_def(component_id)
			parts.append("%s %s" % [component.icon, component.display_name])
		lines.append("[color=#7c93a4]Forged from %s[/color]" % " + ".join(parts))

	return "\n".join(lines)


## A rival captain: their standing, their traits, their board, and their items.
##
## The items are listed because "I don't think I saw the AI use items" was a
## visibility problem as much as a behaviour one.
static func captain_text(captain: Captain) -> String:
	var content: Node = Engine.get_main_loop().root.get_node(^"/root/Content")
	var lines := PackedStringArray()
	lines.append("[font_size=17][b]%s %s[/b][/font_size]" % [captain.icon, captain.display_name])
	lines.append("[color=#7c93a4]Level %d · %d hull · %s[/color]"
		% [captain.level, maxi(0, captain.hp), captain.streak_label()])

	if not (captain is Bot):
		return "\n".join(lines)

	var bot: Bot = captain
	var summary := bot.trait_summary(content)
	if not summary.is_empty():
		lines.append("")
		var trait_names := PackedStringArray()
		for entry in summary.slice(0, 5):
			var def: TraitDef = content.trait_def(entry["id"])
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
				icons.append(content.item_def(item_id).icon)
			carried = "   [color=#ffd98a]%s[/color]" % "".join(icons)
		lines.append("%s %s%s%s"
			% [unit.champion.icon, unit.champion.display_name, stars, carried])

	return "\n".join(lines)
