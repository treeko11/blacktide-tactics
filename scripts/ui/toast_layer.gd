class_name ToastLayer
extends VBoxContainer

## Transient messages: loot arriving, and refusals.
##
## Two separate gaps from the playtest close here.
##
## **Items arriving said nothing.** Salvage and armoury pickups went straight
## into the hold with no acknowledgement, so you learned what you had won by
## noticing the hold had grown. A toast names the item and spells out what it
## does, which is also the moment you are most likely to read it.
##
## **Refusals said nothing either.** "Not enough gold" and "Deck is full" were
## computed by the old build and then dropped on the floor, so a click that could
## not work looked identical to a click that was ignored.

const HOLD_SECONDS := 4.5
const FADE_SECONDS := 0.6
const MAX_VISIBLE := 4


## How wide a toast is allowed to be.
##
## One number, because the strip and the toasts inside it have to agree: the
## strip was fitted to the screen and each toast asked for a flat 300, so on a
## narrow phone the toasts were wider than the column holding them and hung off
## the edge.
static func width() -> float:
	return minf(320.0, maxf(180.0, Layout.css_size.x - 24.0))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)

	Events.item_gained.connect(_on_item_gained)
	Events.item_forged.connect(_on_item_forged)
	Events.notice.connect(_on_notice)
	Events.unit_upgraded.connect(_on_unit_upgraded)


func _on_item_gained(item_id: StringName, source: StringName) -> void:
	# A sale is the player putting an item back themselves; they know.
	if source == &"sale":
		return
	var item: ItemDef = GameState.content.item_def(item_id)
	if item == null:
		return
	var heading := "SALVAGED" if source == &"salvage" else "FROM THE ARMOURY"
	_push(item.icon, "%s\n%s" % [item.display_name, item.description], heading,
		UITheme.GOLD if not item.is_component else UITheme.FOAM)


func _on_item_forged(item_id: StringName, _unit_uid: int) -> void:
	var item: ItemDef = GameState.content.item_def(item_id)
	if item == null:
		return
	_push(item.icon, "%s\n%s" % [item.display_name, item.description], "FORGED",
		UITheme.GOLD_BRIGHT)


func _on_unit_upgraded(champion_id: StringName, star: int) -> void:
	var champion: ChampionDef = GameState.content.champion(champion_id)
	if champion == null:
		return
	_push(champion.icon, champion.display_name, "%s UPGRADE" % UITheme.STAR.repeat(star),
		UITheme.GOLD_BRIGHT)


func _on_notice(text: String, _style: StringName) -> void:
	_push("⚠", text, "", UITheme.WARNING)


func _push(icon: String, body: String, heading: String, accent: Color) -> void:
	# Detaching before freeing is what makes this terminate; `trim_children` is
	# the same rule written so that it cannot stop being true.
	UITheme.trim_children(self, MAX_VISIBLE - 1, true)

	var toast := Toast.new()
	toast.build(icon, body, heading, accent)
	add_child(toast)
	toast.start(HOLD_SECONDS, FADE_SECONDS)


# =============================================================================

class Toast extends PanelContainer:
	func build(icon: String, body: String, heading: String, accent: Color) -> void:
		custom_minimum_size = Vector2(ToastLayer.width(), 0)
		add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("0d2231"), accent, 7))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		add_child(row)

		var glyph := Label.new()
		glyph.add_theme_font_override("font", UITheme.emoji_font())
		glyph.add_theme_font_size_override("font_size", 26)
		glyph.text = icon
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(glyph)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if heading != "":
			column.add_child(UITheme.label(heading, UITheme.FONT_TINY, accent))
		var text := UITheme.label(body, UITheme.FONT_SMALL, UITheme.INK)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(text)
		row.add_child(column)

		_make_transparent(self)

	## A toast is decoration, and decoration must never take a click.
	##
	## `mouse_filter` is per node, so setting it on the panel says nothing about
	## the containers inside it — and a bare `Container` defaults to STOP, unlike a
	## `Label`. So every toast was an invisible five-second hit-test blocker over
	## whatever it happened to cover: the cargo hold on a sideways phone, where
	## holding an item stopped opening the inspector, and the right third of the
	## board on a desktop, where a pirate could not be dropped for five seconds
	## after any pickup. It reads as the game ignoring you, which is exactly what
	## the toast was added to stop.
	##
	## Applied to the whole subtree once it is built, rather than to each container
	## as it is made, so a row added here later cannot reintroduce the bug by being
	## forgotten. `test_hud.gd` walks the layer and fails anything still STOP.
	func _make_transparent(control: Control) -> void:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in control.get_children():
			if child is Control:
				_make_transparent(child)

	func start(hold: float, fade: float) -> void:
		modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 1.0, 0.18)
		tween.tween_interval(hold)
		tween.tween_property(self, "modulate:a", 0.0, fade)
		tween.tween_callback(queue_free)
