class_name SidePanels
extends RefCounted

## The three standing panels: the manifest of active traits, the cargo hold, and
## the fleet with its log.
##
## One file because they are three variations on "a titled column of rows", and
## three near-identical files drift apart.
##
## Two of the three have a compact form. On a phone there are no side columns to
## stand in, so the manifest and the hold become horizontal strips that scroll
## sideways above the bench — icons and counts, no names — and the fleet moves
## into a sheet that slides up from the bottom. See scripts/ui/layout.gd.

# =============================================================================
#  Ship's Manifest — which traits are live, and what is one pirate away
# =============================================================================

class TraitPanel extends VBoxContainer:
	signal trait_hovered(trait_id: StringName, at: Vector2)
	signal trait_unhovered()

	## Rows go in here rather than straight into the panel, so refresh() can clear
	## them by emptying one container. It used to walk its own children and delete
	## anything that was a TraitRow "or a Label starting with Field", which is the
	## kind of test that quietly stops matching.
	var _rows: Container = null
	var _compact: bool = false

	func _init() -> void:
		_compact = Layout.compact()
		add_theme_constant_override("separation", 3)

		if _compact:
			# A sideways strip of badges. No heading: on a phone the row of trait
			# icons above the bench is self-evident, and the words cost a line.
			var scroll := ScrollContainer.new()
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size = Vector2(0, 26 if Layout.short() else 30)
			var strip := HBoxContainer.new()
			strip.add_theme_constant_override("separation", 4)
			scroll.add_child(strip)
			add_child(scroll)
			_rows = strip
		else:
			add_child(UITheme.heading("Ship's Manifest"))
			_rows = VBoxContainer.new()
			_rows.add_theme_constant_override("separation", 3)
			add_child(_rows)

	func _ready() -> void:
		Events.board_changed.connect(refresh)
		refresh()

	func refresh() -> void:
		for child in _rows.get_children():
			child.queue_free()

		var traits: Array = GameState.board_traits()
		if traits.is_empty():
			if _compact:
				# The strip just stays empty; a phone has no line to spare for
				# saying so, and the bench underneath makes the point.
				return
			var empty := UITheme.label("Field your crew to muster traits.",
				UITheme.FONT_TINY, Color("4d6373"))
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_rows.add_child(empty)
			return

		for entry in traits:
			var row := TraitRow.new()
			row.show_trait(entry)
			row.hovered.connect(func(at): trait_hovered.emit(entry["id"], at))
			row.unhovered.connect(func(): trait_unhovered.emit())
			_rows.add_child(row)


class TraitRow extends PanelContainer:
	signal hovered(at: Vector2)
	signal unhovered()

	var _icon: Label = null
	var _name: Label = null
	var _count: Label = null
	var _tier_color: Color = UITheme.LINE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4 if Layout.compact() else 6)
		add_child(row)

		_icon = Label.new()
		_icon.add_theme_font_override("font", UITheme.emoji_font())
		_icon.add_theme_font_size_override("font_size", 13 if Layout.compact() else 14)
		row.add_child(_icon)

		# The name is the first thing to go on a phone: eight trait badges have to
		# fit across a strip, and the icon already identifies the trait.
		_name = UITheme.label("", UITheme.FONT_SMALL, UITheme.INK)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.visible = not Layout.compact()
		row.add_child(_name)

		_count = UITheme.label("", UITheme.FONT_SMALL, UITheme.MUTED)
		row.add_child(_count)

		mouse_entered.connect(func(): hovered.emit(global_position + Vector2(size.x, 0)))
		mouse_exited.connect(func(): unhovered.emit())

	func show_trait(entry: Dictionary) -> void:
		var def: TraitDef = entry["def"]
		var tier: int = entry["tier"]
		var count: int = entry["count"]
		_tier_color = UITheme.tier_color(def.tier_style(tier))

		_icon.text = def.icon
		_name.text = def.display_name
		# "3/4" reads as progress; a live trait with nothing left to reach is bare.
		var next: int = entry["next"]
		_count.text = "%d/%d" % [count, next] if next > 0 else str(count)

		var inactive := tier < 0
		modulate.a = 0.5 if inactive else 1.0
		_name.add_theme_color_override("font_color",
			UITheme.MUTED if inactive else UITheme.INK)
		add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("0a1721"), _tier_color, 4))


# =============================================================================
#  Cargo Hold — loose items, and the forge chart
# =============================================================================

class HoldPanel extends VBoxContainer:
	signal item_hovered(item_id: StringName, at: Vector2)
	signal item_unhovered()
	signal forge_chart_requested()

	var _grid: Container = null
	var _compact: bool = false
	## Items that arrived since the panel was last looked at, drawn with a flash.
	var _fresh: Dictionary = {}

	func _init() -> void:
		_compact = Layout.compact()
		add_theme_constant_override("separation", 4)

		if _compact:
			# One row: chips on the left, the forge chart button pinned on the
			# right. The heading goes — the button names the panel well enough.
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			add_child(row)

			var scroll := ScrollContainer.new()
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.custom_minimum_size = Vector2(0, Layout.item_chip().y)
			var strip := HBoxContainer.new()
			strip.add_theme_constant_override("separation", 4)
			scroll.add_child(strip)
			row.add_child(scroll)
			row.add_child(_chart_button())
			_grid = strip
			return

		var header := HBoxContainer.new()
		header.add_child(UITheme.heading("Cargo Hold"))
		header.add_child(UITheme.spacer())
		header.add_child(_chart_button())
		add_child(header)

		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		add_child(flow)
		_grid = flow

	func _chart_button() -> Button:
		var chart := UITheme.button("Forge chart", UITheme.FONT_TINY)
		chart.tooltip_text = "Every component pairing and what it makes"
		chart.pressed.connect(func(): forge_chart_requested.emit())
		return chart

	func _ready() -> void:
		Events.board_changed.connect(refresh)
		Events.item_gained.connect(_on_item_gained)
		refresh()

	func _on_item_gained(item_id: StringName, _source: StringName) -> void:
		_fresh[item_id] = Time.get_ticks_msec()
		refresh()

	func refresh() -> void:
		_forget_stale()
		for child in _grid.get_children():
			child.queue_free()

		if GameState.player.items.is_empty():
			if _compact:
				return       # the strip just stays empty
			_grid.add_child(UITheme.label("Empty hold.", UITheme.FONT_TINY, Color("4d6373")))
			return

		for item_id in GameState.player.items:
			var chip := ItemChip.new()
			chip.show_item(item_id)
			chip.fresh_since = _fresh.get(item_id, 0)
			chip.hovered.connect(func(at): item_hovered.emit(item_id, at))
			chip.unhovered.connect(func(): item_unhovered.emit())
			_grid.add_child(chip)

	## Drops timestamps the flash has outlived.
	##
	## Without this the dictionary keeps an entry for every kind of item the player
	## has ever held, and each rebuilt chip inherits a long-expired timestamp — one
	## wasted repaint per chip per refresh, forever.
	func _forget_stale() -> void:
		var now := Time.get_ticks_msec()
		for item_id in _fresh.keys():
			if now - int(_fresh[item_id]) >= ItemChip.FRESH_MS:
				_fresh.erase(item_id)


## One draggable item in the hold.
class ItemChip extends Control:
	signal hovered(at: Vector2)
	signal unhovered()

	## How long a newly acquired item keeps its highlight, in milliseconds.
	const FRESH_MS := 6000.0

	var item: ItemDef = null
	var fresh_since: int = 0

	func _init() -> void:
		custom_minimum_size = Layout.item_chip()
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hovered.emit(global_position + Vector2(size.x, 0)))
		mouse_exited.connect(func(): unhovered.emit())
		set_process(true)

	func show_item(item_id: StringName) -> void:
		item = GameState.content.item_def(item_id)
		queue_redraw()

	## Only while the highlight is actually animating.
	##
	## `fresh_since > 0` on its own never becomes false, so every item the player
	## had ever picked up went on requesting a repaint every frame for the rest of
	## the run — a hold of a dozen items redrawing forever for a six-second flash.
	func _process(_delta: float) -> void:
		if fresh_since == 0:
			return
		queue_redraw()
		if Time.get_ticks_msec() - fresh_since >= FRESH_MS:
			# This repaint is the one that clears the pulse. Stop asking for more.
			fresh_since = 0

	func _get_drag_data(_at: Vector2) -> Variant:
		if item == null or GameState.phase != GameState.Phase.PLAN:
			return null
		var preview := ItemChip.new()
		preview.item = item
		set_drag_preview(preview)
		return { "kind": &"item", "id": item.id }

	func _draw() -> void:
		if item == null:
			return
		var border := UITheme.GOLD if not item.is_component else Color("2f5a72")
		draw_rect(Rect2(Vector2.ZERO, size), Color("11283a"))

		# A newly acquired item pulses for a few seconds. The playtest note was
		# that items simply appeared with no acknowledgement at all.
		var age := Time.get_ticks_msec() - fresh_since
		if fresh_since > 0 and age < FRESH_MS:
			var pulse := 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.005))
			draw_rect(Rect2(Vector2(-2, -2), size + Vector2(4, 4)),
				Color(border.r, border.g, border.b, pulse), false, 2.0)

		draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.5)
		var font := UITheme.emoji_font()
		var glyph_size := roundi(size.y * 0.53)
		var width := font.get_string_size(item.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size).x
		draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.5 + glyph_size * 0.37),
			item.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size)


# =============================================================================
#  The Fleet — rival captains, and the running log
# =============================================================================

class FleetPanel extends VBoxContainer:
	signal captain_hovered(captain: Captain, at: Vector2)
	signal captain_unhovered()

	var _rows: VBoxContainer = null
	var _log: VBoxContainer = null

	func _init() -> void:
		add_theme_constant_override("separation", 4)
		add_child(UITheme.heading("The Fleet"))

		_rows = VBoxContainer.new()
		_rows.add_theme_constant_override("separation", 2)
		add_child(_rows)

		add_child(UITheme.heading("Log"))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_log = VBoxContainer.new()
		_log.add_theme_constant_override("separation", 2)
		_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_log)
		add_child(scroll)

	func _ready() -> void:
		Events.round_resolved.connect(func(_w, _d, _o): refresh())
		Events.phase_changed.connect(func(_p): refresh())
		Events.logged.connect(_on_logged)
		refresh()

	func refresh() -> void:
		for child in _rows.get_children():
			child.queue_free()

		var captains := GameState.everyone()
		captains.sort_custom(func(a, b):
			if a.alive != b.alive:
				return a.alive
			return a.hp > b.hp)

		for captain in captains:
			var row := CaptainRow.new()
			row.show_captain(captain)
			if captain.is_bot:
				row.hovered.connect(func(at): captain_hovered.emit(captain, at))
				row.unhovered.connect(func(): captain_unhovered.emit())
			_rows.add_child(row)

	func _on_logged(text: String, style: StringName) -> void:
		var line := UITheme.label(text, UITheme.FONT_TINY, UITheme.log_color(style))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_log.add_child(line)
		_log.move_child(line, 0)
		while _log.get_child_count() > 40:
			_log.get_child(_log.get_child_count() - 1).queue_free()


class CaptainRow extends PanelContainer:
	signal hovered(at: Vector2)
	signal unhovered()

	var _icon: Label = null
	var _name: Label = null
	var _level: Label = null
	var _hp: Label = null
	var _health_fraction: float = 1.0
	var _is_you: bool = false
	var _is_dead: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		add_child(row)

		_icon = Label.new()
		_icon.add_theme_font_override("font", UITheme.emoji_font())
		_icon.add_theme_font_size_override("font_size", 13)
		row.add_child(_icon)

		_name = UITheme.label("", UITheme.FONT_TINY, UITheme.INK)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.clip_text = true
		row.add_child(_name)

		_level = UITheme.label("", UITheme.FONT_TINY, UITheme.MUTED)
		row.add_child(_level)
		_hp = UITheme.label("", UITheme.FONT_SMALL, Color("ff8a95"))
		row.add_child(_hp)

		mouse_entered.connect(func(): hovered.emit(global_position))
		mouse_exited.connect(func(): unhovered.emit())

	func show_captain(captain: Captain) -> void:
		_icon.text = captain.icon
		_name.text = captain.display_name
		_level.text = "L%d" % captain.level
		_hp.text = str(maxi(0, captain.hp))
		_health_fraction = clampf(float(captain.hp) / 100.0, 0.0, 1.0)
		_is_you = not captain.is_bot
		_is_dead = not captain.alive
		modulate.a = 0.4 if _is_dead else 1.0
		add_theme_stylebox_override("panel", UITheme.panel_style(
			Color("1a1509") if _is_you else Color("0a1721"),
			UITheme.GOLD if _is_you else Color("142a38"), 4))
		queue_redraw()

	func _draw() -> void:
		# A health bar behind the row, so the standings read at a glance.
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * _health_fraction, size.y)),
			Color(UITheme.BLOOD.r, UITheme.BLOOD.g, UITheme.BLOOD.b, 0.13))
