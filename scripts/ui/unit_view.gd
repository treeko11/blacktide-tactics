class_name UnitView
extends Node2D

## One pirate on the board or the bench.
##
## Draws itself rather than assembling a subtree of Sprites and ProgressBars: a
## unit is a figure, two bars, a few pips and some item boxes, and drawing it
## directly keeps a board of eighteen down to eighteen nodes. The figure itself
## comes from `UnitArt`, which is where every shape lives.
##
## It reads either a RosterUnit (between fights) or a SimUnit (during one), which
## is why `bind_roster` and `bind_sim` both exist. Nothing here writes back to
## either — the view is downstream of the state, always.
##
## **The animation is derived, not delivered.** The sim announces effects on
## `fx_queue`, and an entry there carries positions rather than a uid, so it
## cannot say *which unit* just swung. It does not need to: an attack is an
## attack timer that jumped back up, a wound is health that went down, a death is
## `alive` going false. Reading those every frame keeps the sim entirely ignorant
## of the fact that anything is being animated at all — which is the rule that
## lets six unwatched fights resolve for free, and lets the watched one resolve
## identically at 1x and at 4x.

## The old circular body's radius. Kept because it is the board's hit-test
## distance for "the cursor is on this pirate", which wants a stable disc and not
## the bounding box of a hat.
const BODY_RADIUS := 23.0
const BAR_WIDTH := 52.0
const BAR_HEIGHT := 5.0

## Seconds each reaction takes to decay, in battle time.
const SWING_TIME := 0.26
const RECOIL_TIME := 0.32
const DEATH_TIME := 0.7

## Between fights nothing is happening, so idle breathing is redrawn at a rate
## that looks continuous rather than at whatever the monitor runs at. Eighteen
## units redrawing a hundred polygons each is not free on a phone, and a planning
## phase is where the player is doing the reading.
const IDLE_FRAME := 1.0 / 24.0

var champion: ChampionDef = null
var star: int = 1
var items: Array[StringName] = []
var is_enemy: bool = false

## Set while a fight is running; null between them.
var sim_unit: SimUnit = null

## Between fights there are no bars to draw and no mana to show.
var show_bars: bool = false

## Battle speed multiplier, so a fight watched at 4x animates at 4x. Set by
## BoardView from the same number it hands the effects layer.
var anim_speed: float = 1.0

## The scale the board is drawn at, passed down so a unit squeezed into a
## 21-point hex on a phone stops paying for detail nobody can see.
var detail: float = 1.0

var _pose := UnitArt.Pose.new()
var _content: Node = null

## Last frame's values, which is the whole of the change detection.
var _last_attack_timer: float = 0.0
var _last_health: float = -1.0
var _idle_accum: float = 0.0


func _ready() -> void:
	_content = get_node_or_null(^"/root/Content")
	set_process(true)


func bind_roster(unit: RosterUnit) -> void:
	champion = unit.champion
	star = unit.star
	items = unit.items
	sim_unit = null
	show_bars = false
	_reset_pose(unit.uid)
	queue_redraw()


func bind_sim(unit: SimUnit) -> void:
	champion = unit.def
	star = unit.star
	items = unit.items
	sim_unit = unit
	is_enemy = unit.team == Sim.Team.ENEMY
	show_bars = true
	_reset_pose(unit.uid)
	_last_attack_timer = unit.attack_timer
	_last_health = unit.hp + unit.shield
	_pose.ranged = unit.attack_range > 1
	queue_redraw()


## A per-unit phase offset, so a board of eighteen does not breathe in lockstep.
## Taken from the uid rather than from a random number: it costs nothing, it is
## stable across a rebuild, and it keeps the renderer from touching an RNG at
## all, which is one less thing to have to argue is not affecting the sim.
func _reset_pose(uid: int) -> void:
	_pose = UnitArt.Pose.new()
	_pose.clock = float(uid % 97) * 0.19
	_pose.aim = Vector2.DOWN if is_enemy else Vector2.UP


## Called every frame during a fight, so the bars and position track the sim.
func follow_sim() -> void:
	if sim_unit == null:
		return
	position = sim_unit.pos
	queue_redraw()


func _process(delta: float) -> void:
	if champion == null:
		return
	var step: float = delta * (anim_speed if sim_unit != null else 1.0)
	_pose.clock += step
	_pose.swing = maxf(_pose.swing - step / SWING_TIME, 0.0)
	_pose.recoil = maxf(_pose.recoil - step / RECOIL_TIME, 0.0)

	if sim_unit != null:
		_read_sim(step)
		queue_redraw()
		return

	_idle_accum += delta
	if _idle_accum >= IDLE_FRAME:
		_idle_accum = 0.0
		queue_redraw()


## Everything the figure does, read off the unit's own state. No signal, no
## queue, no call from the sim.
func _read_sim(step: float) -> void:
	# The attack timer counts down and is reset upward the instant a shot is
	# fired, so it going *up* is the one unambiguous "this unit just attacked".
	if sim_unit.attack_timer > _last_attack_timer + 0.0001:
		_pose.swing = 1.0
	_last_attack_timer = sim_unit.attack_timer

	var health: float = sim_unit.hp + sim_unit.shield
	if _last_health >= 0.0 and health < _last_health - 0.01:
		_pose.recoil = 1.0
	_last_health = health

	_pose.cast = 1.0 if sim_unit.casting > 0.0 else 0.0
	_pose.moving = 1.0 if sim_unit.is_moving else 0.0
	_pose.stunned = sim_unit.stun_time > 0.0
	_pose.ranged = sim_unit.attack_range > 1
	if not sim_unit.alive:
		_pose.dead = minf(_pose.dead + step / DEATH_TIME, 1.0)
	_pose.aim = _aim()


## Where this unit is pointed. A live target if it has one, otherwise up the
## board at the fleet it is going to have to get through.
func _aim() -> Vector2:
	if sim_unit != null and sim_unit.target != null and sim_unit.target.alive:
		var to_target: Vector2 = sim_unit.target.pos - sim_unit.pos
		if to_target.length() > 0.5:
			return to_target.normalized()
	return Vector2.DOWN if is_enemy else Vector2.UP


func _draw() -> void:
	if champion == null:
		return

	_pose.detail = detail
	# The team colour fills the plate and the cost colour rims it, so a glance
	# still answers both "whose is that" and "how expensive was it" now that the
	# figure keeps its own colours instead of wearing them.
	var team: Color = UITheme.HP_THEIRS if is_enemy else UITheme.HP_MINE
	UnitArt.draw_unit(self, champion.art_body, champion.art_tint,
		champion.art_marks, _pose, team, UITheme.cost_color(champion.cost))

	var fade: float = 1.0 - _pose.dead
	if fade <= 0.05:
		return
	if show_bars and _pose.dead <= 0.0:
		_draw_bars()
	_draw_stars(fade)
	_draw_items(fade)


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


## Above the hat, not above the old circle: a figure is seven pixels taller than
## the body it replaced, and a star rating drawn into a tricorn is a smudge.
func _draw_stars(fade: float) -> void:
	if star <= 1:
		return
	var font := UITheme.ui_font()
	var text := UITheme.STAR.repeat(star)
	var size := 13 if star < 3 else 15
	var color := UITheme.GOLD_BRIGHT if star < 3 else Color("ffe9a8")
	color.a = fade
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(-width * 0.5, -34.0)
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(0, 0, 0, 0.9 * fade))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Item pips under the body, so what a unit is carrying is visible on the board
## rather than only inside a tooltip.
func _draw_items(fade: float) -> void:
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
		var tier: int = _content.item_tier(items[i])
		draw_rect(Rect2(centre - Vector2(7, 7), Vector2(14, 14)), Color(0.05, 0.13, 0.19, fade))
		var edge := UITheme.item_tier_color(tier)
		edge.a = fade
		# A greater item gets a heavier rim as well as its own colour: this is a
		# fourteen-pixel square on a phone, where a hue on its own is one pixel of
		# difference and the outline is what actually reads.
		draw_rect(Rect2(centre - Vector2(7, 7), Vector2(14, 14)), edge, false,
			2.0 if tier >= 3 else 1.0)
		var width := font.get_string_size(item.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, centre + Vector2(-width * 0.5, size * 0.36), item.icon,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, fade))
