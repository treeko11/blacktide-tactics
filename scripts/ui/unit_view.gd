class_name UnitView
extends Node2D

## One pirate on the board or the bench.
##
## Draws itself rather than assembling a subtree of Sprites and ProgressBars: a
## unit is a circle, two bars, a few pips and an icon, and drawing it directly
## keeps a board of eighteen down to eighteen nodes.
##
## It reads either a RosterUnit (between fights) or a SimUnit (during one), which
## is why `bind_roster` and `bind_sim` both exist. Nothing here writes back to
## either — the view is downstream of the state, always.

const BODY_RADIUS := 23.0
const BAR_WIDTH := 52.0
const BAR_HEIGHT := 5.0

var champion: ChampionDef = null
var star: int = 1
var items: Array[StringName] = []
var is_enemy: bool = false

## Set while a fight is running; null between them.
var sim_unit: SimUnit = null

## Between fights there are no bars to draw and no mana to show.
var show_bars: bool = false
## Highlight ring, used for the unit under the cursor and the drag source.
var highlighted: bool = false

var _content: Node = null


func _ready() -> void:
	_content = get_node_or_null(^"/root/Content")


func bind_roster(unit: RosterUnit) -> void:
	champion = unit.champion
	star = unit.star
	items = unit.items
	sim_unit = null
	show_bars = false
	queue_redraw()


func bind_sim(unit: SimUnit) -> void:
	champion = unit.def
	star = unit.star
	items = unit.items
	sim_unit = unit
	is_enemy = unit.team == Sim.Team.ENEMY
	show_bars = true
	queue_redraw()


## Called every frame during a fight, so the bars and position track the sim.
func follow_sim() -> void:
	if sim_unit == null:
		return
	position = sim_unit.pos
	queue_redraw()


func _draw() -> void:
	if champion == null:
		return
	if sim_unit != null and not sim_unit.alive:
		_draw_body(0.25)
		return

	_draw_body(1.0)
	if show_bars:
		_draw_bars()
	_draw_stars()
	_draw_items()


func _draw_body(alpha: float) -> void:
	var border := UITheme.cost_color(champion.cost)
	if is_enemy:
		# Tint the enemy fleet so a glance tells you whose half a unit is on even
		# when both sides are running the same champion.
		border = border.lerp(Color("ff8a8a"), 0.45)

	var fill_top := Color("2a4b60") if not is_enemy else Color("5a2a34")
	var fill := fill_top.lerp(Color("0d1d28"), 0.5)
	fill.a = alpha
	draw_circle(Vector2.ZERO, BODY_RADIUS, fill)

	var casting := sim_unit != null and sim_unit.casting > 0.0
	if casting:
		# A unit mid-cast is about to do the most important thing it does.
		draw_arc(Vector2.ZERO, BODY_RADIUS + 4.0, 0.0, TAU, 28, UITheme.FOAM, 3.0)
		draw_arc(Vector2.ZERO, BODY_RADIUS + 8.0, 0.0, TAU, 28,
			Color(UITheme.FOAM.r, UITheme.FOAM.g, UITheme.FOAM.b, 0.35), 2.0)
	if highlighted:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 3.0, 0.0, TAU, 28, UITheme.GOLD_BRIGHT, 2.0)

	draw_arc(Vector2.ZERO, BODY_RADIUS, 0.0, TAU, 32,
		Color(border.r, border.g, border.b, alpha), 2.5)

	var font := UITheme.emoji_font()
	var size := 26
	var width := font.get_string_size(champion.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var modulate_color := Color(1, 1, 1, alpha)
	if sim_unit != null and sim_unit.stun_time > 0.0:
		modulate_color = Color(0.6, 0.6, 0.65, alpha)
	draw_string(font, Vector2(-width * 0.5, size * 0.38), champion.icon,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, modulate_color)


func _draw_bars() -> void:
	if sim_unit == null:
		return
	var top := BODY_RADIUS + 6.0
	var left := -BAR_WIDTH * 0.5

	# Health, with any shield laid over the top of it in a lighter colour.
	var track := Rect2(left, top, BAR_WIDTH, BAR_HEIGHT)
	draw_rect(track, Color("0a0f14"))
	var health := UITheme.HP_THEIRS if is_enemy else UITheme.HP_MINE
	draw_rect(Rect2(left, top, BAR_WIDTH * sim_unit.health_fraction(), BAR_HEIGHT), health)

	if sim_unit.shield > 0.0:
		var shield_fraction := clampf(sim_unit.shield / sim_unit.max_hp, 0.0, 1.0)
		draw_rect(Rect2(left, top, BAR_WIDTH * shield_fraction, BAR_HEIGHT),
			Color(UITheme.SHIELD.r, UITheme.SHIELD.g, UITheme.SHIELD.b, 0.85))
	draw_rect(track, Color(0, 0, 0, 0.6), false, 1.0)

	if sim_unit.casts():
		var mana_top := top + BAR_HEIGHT + 1.0
		var mana_track := Rect2(left, mana_top, BAR_WIDTH, 4.0)
		draw_rect(mana_track, Color("0a0f14"))
		draw_rect(Rect2(left, mana_top, BAR_WIDTH * sim_unit.mana_fraction(), 4.0),
			UITheme.MANA)
		draw_rect(mana_track, Color(0, 0, 0, 0.6), false, 1.0)


func _draw_stars() -> void:
	if star <= 1:
		return
	var font := UITheme.ui_font()
	var text := "★".repeat(star)
	var size := 13 if star < 3 else 15
	var color := UITheme.GOLD_BRIGHT if star < 3 else Color("ffe9a8")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(-width * 0.5, -BODY_RADIUS - 6.0)
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(0, 0, 0, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Item pips under the body, so what a unit is carrying is visible on the board
## rather than only inside a tooltip.
func _draw_items() -> void:
	if items.is_empty() or _content == null:
		return
	var font := UITheme.emoji_font()
	var size := 12
	var spacing := 15.0
	var start := -(items.size() - 1) * spacing * 0.5
	var y := BODY_RADIUS + (17.0 if show_bars else 4.0)

	for i in items.size():
		var item: ItemDef = _content.item_def(items[i])
		if item == null:
			continue
		var centre := Vector2(start + i * spacing, y)
		var forged := not item.is_component
		draw_rect(Rect2(centre - Vector2(7, 7), Vector2(14, 14)), Color("0e2130"))
		draw_rect(Rect2(centre - Vector2(7, 7), Vector2(14, 14)),
			UITheme.GOLD if forged else Color("2f5a72"), false, 1.0)
		var width := font.get_string_size(item.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, centre + Vector2(-width * 0.5, size * 0.36), item.icon,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size)
