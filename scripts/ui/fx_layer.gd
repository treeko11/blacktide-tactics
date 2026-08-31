class_name FxLayer
extends Node2D

## Draws everything the battle does — projectiles, impacts, casts, damage
## numbers.
##
## The whole layer is one node that draws every live effect in a single `_draw`.
## Spawning a node per hit meant hundreds of allocations a second at 4x speed for
## things that live a fifth of a second; here an effect is a dictionary in an
## array and costs nothing to create or throw away.
##
## **Why there are so many shapes.** In the JavaScript build every ranged attack
## was the same thin line and every melee attack the same expanding ring, so a
## fight was unreadable — you could not tell a gunner's volley from a siren's
## cast, or which direction anything came from. Each archetype now has its own
## projectile and its own impact, every effect is oriented along the line between
## attacker and target, and hits throw sparks *away* from the blow. Direction and
## variety are the point; none of it changes a single number in the sim.

## Above this many live effects, only damage numbers are still accepted. Reached
## only at 4x with a full board, and dropping a spark nobody could follow anyway
## is better than dropping frames.
const MAX_EFFECTS := 400

## Pixels per second a projectile travels.
##
## Tuned down from a realistic speed until a shot was actually legible: at
## 1100 px/s a bullet crossed two hexes in five frames and the eye caught only
## the impact, which is the problem this whole layer exists to fix. A shot has to
## be visibly *travelling*, and from somewhere.
const PROJECTILE_SPEED := 700.0
const PROJECTILE_MIN_LIFE := 0.10
const PROJECTILE_MAX_LIFE := 0.34

## Battle speed multiplier, so effects keep pace with a fast-forwarded fight.
var speed: float = 1.0

## Resolves a unit uid to its current board position, so a shot can follow a
## target that is still walking. Set by BoardView; unset, projectiles simply fly
## to wherever the target was when they were fired.
var position_resolver: Callable = Callable()

var _effects: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font

## True while something is still painted. Without it the layer stops redrawing
## once the last effect expires and leaves that final frame on screen forever.
var _painted: bool = false


func _ready() -> void:
	set_process(true)


func clear() -> void:
	_effects.clear()
	queue_redraw()


## Takes one entry off a Sim's fx queue.
func add_effect(entry: Dictionary) -> void:
	var kind: StringName = entry.get("kind", &"")
	if _effects.size() >= MAX_EFFECTS and kind != &"text":
		return

	var at: Vector2 = entry.get("at", Vector2.ZERO)
	var from: Vector2 = entry.get("from", Vector2.INF)
	var has_source := from != Vector2.INF

	var effect := {
		"kind": kind,
		"at": at,
		"from": from if has_source else at,
		"has_source": has_source,
		"color": entry.get("color", Color.WHITE) as Color,
		"style": entry.get("style", &"") as StringName,
		"text": entry.get("text", "") as String,
		"age": 0.0,
		"life": 0.4,
		"angle": 0.0,
		"target_uid": entry.get("target_uid", 0),
	}

	if has_source:
		effect["angle"] = (at - from).angle()

	match kind:
		&"projectile":
			var distance: float = at.distance_to(effect["from"])
			effect["life"] = clampf(distance / PROJECTILE_SPEED,
				PROJECTILE_MIN_LIFE, PROJECTILE_MAX_LIFE)
		&"muzzle": effect["life"] = 0.16
		&"melee": effect["life"] = 0.26
		&"impact": effect["life"] = 0.28
		&"crit": effect["life"] = 0.36
		&"tracer": effect["life"] = 0.22
		&"chain": effect["life"] = 0.32
		&"beam": effect["life"] = 0.36
		&"bolt": effect["life"] = 0.36
		&"nova": effect["life"] = 0.55
		&"shock": effect["life"] = 0.45
		&"wave": effect["life"] = 0.6
		&"pop": effect["life"] = 0.3
		&"cast": effect["life"] = 0.35
		&"revive": effect["life"] = 0.6
		&"blink": effect["life"] = 0.3
		&"stun": effect["life"] = 0.9
		&"drain": effect["life"] = 0.45
		&"death": effect["life"] = 0.4
		&"text": effect["life"] = 0.95
		_: effect["life"] = 0.4

	_effects.append(effect)


func _process(delta: float) -> void:
	if _effects.is_empty():
		if _painted:
			_painted = false
			queue_redraw()
		return
	_painted = true
	# Effects age at battle speed, so a 4x fight does not leave a trail of stale
	# sparks hanging behind the units that made them.
	var step := delta * maxf(1.0, speed)
	var landed: Array[Dictionary] = []

	for i in range(_effects.size() - 1, -1, -1):
		var e := _effects[i]
		e["age"] += step
		if e["age"] < e["life"]:
			_track_target(e)
			continue
		# A projectile that has arrived becomes the impact it caused.
		if e["kind"] == &"projectile":
			landed.append(e)
		_effects.remove_at(i)

	for e in landed:
		_spawn_impact(e)

	queue_redraw()


## Keeps a shot pointed at where its target actually is now.
func _track_target(e: Dictionary) -> void:
	if e["kind"] != &"projectile" or int(e["target_uid"]) == 0:
		return
	if not position_resolver.is_valid():
		return
	var live: Variant = position_resolver.call(int(e["target_uid"]))
	if live == null:
		return
	e["at"] = live
	e["angle"] = ((live as Vector2) - (e["from"] as Vector2)).angle()


func _spawn_impact(projectile: Dictionary) -> void:
	if _effects.size() >= MAX_EFFECTS:
		return
	_effects.append({
		"kind": &"impact",
		"at": projectile["at"],
		"from": projectile["from"],
		"has_source": true,
		"color": projectile["color"],
		"style": projectile["style"],
		"text": "",
		"age": 0.0,
		"life": 0.28,
		"angle": projectile["angle"],
	})


# =============================================================================
#  Drawing
# =============================================================================

func _draw() -> void:
	for e in _effects:
		var t: float = clampf(e["age"] / e["life"], 0.0, 1.0)
		match e["kind"]:
			&"projectile": _draw_projectile(e, t)
			&"muzzle": _draw_muzzle(e, t)
			&"melee": _draw_melee(e, t)
			&"impact": _draw_impact(e, t)
			&"crit": _draw_crit(e, t)
			&"tracer": _draw_tracer(e, t)
			&"chain": _draw_chain(e, t)
			&"beam": _draw_beam(e, t)
			&"bolt": _draw_bolt(e, t)
			&"nova": _draw_nova(e, t)
			&"shock": _draw_shock(e, t)
			&"wave": _draw_wave(e, t)
			&"pop": _draw_pop(e, t)
			&"cast": _draw_cast(e, t)
			&"revive": _draw_revive(e, t)
			&"blink": _draw_blink(e, t)
			&"stun": _draw_stun(e, t)
			&"drain": _draw_drain(e, t)
			&"death": _draw_death(e, t)
			&"text": _draw_text(e, t)


func _fade(base: Color, alpha: float) -> Color:
	return Color(base.r, base.g, base.b, clampf(alpha, 0.0, 1.0))


# --- basic attacks -----------------------------------------------------------

## The travelling shot. Every archetype throws something different, and all of
## them point the way they are going.
func _draw_projectile(e: Dictionary, t: float) -> void:
	var pos: Vector2 = (e["from"] as Vector2).lerp(e["at"], t)
	var angle: float = e["angle"]
	var forward := Vector2.RIGHT.rotated(angle)
	var side := forward.orthogonal()
	var color: Color = e["color"]

	match e["style"]:
		&"bullet":
			# A hot streak with a bright head.
			draw_line(pos - forward * 16.0, pos, _fade(color, 0.85), 2.5)
			draw_circle(pos, 2.5, Color.WHITE)
		&"cannon":
			draw_circle(pos, 5.0, color)
			draw_circle(pos, 7.5, _fade(color, 0.25))
			# Smoke falling behind the ball.
			for i in 3:
				var back := pos - forward * (10.0 + i * 9.0)
				draw_circle(back, 4.0 - i, _fade(Color("6b6055"), 0.35 - i * 0.1))
		&"bolt":
			# A crossbow bolt: shaft plus a head.
			draw_line(pos - forward * 14.0, pos, color, 2.0)
			var head := PackedVector2Array([
				pos + forward * 5.0, pos - forward * 3.0 + side * 3.5,
				pos - forward * 3.0 - side * 3.5])
			draw_colored_polygon(head, color)
		&"harpoon":
			# Spear head, barbs, and the rope paying out behind it.
			draw_line(pos - forward * 20.0, pos, color, 2.5)
			var tip := PackedVector2Array([
				pos + forward * 8.0, pos - forward * 4.0 + side * 5.0,
				pos - forward * 4.0 - side * 5.0])
			draw_colored_polygon(tip, color)
			var rope_start: Vector2 = e["from"]
			var rope := pos - forward * 20.0
			var span := rope_start.distance_to(rope)
			var links := int(span / 14.0)
			for i in links:
				var a := rope_start.lerp(rope, float(i) / maxf(1.0, links))
				var b := rope_start.lerp(rope, float(i + 0.5) / maxf(1.0, links))
				draw_line(a, b, _fade(color, 0.35), 1.5)
		&"orb":
			var pulse := 1.0 + sin(t * 22.0) * 0.15
			draw_circle(pos, 9.0 * pulse, _fade(color, 0.22))
			draw_circle(pos, 5.0 * pulse, color)
			draw_circle(pos, 2.0, Color.WHITE)
		&"spark":
			# A jagged arc rather than a straight line.
			var previous := pos - forward * 26.0
			for i in range(1, 5):
				var along := pos - forward * (26.0 - i * 6.5)
				var jitter := side * (sin(float(i) * 2.7 + t * 30.0) * 5.0)
				var point := along + jitter
				draw_line(previous, point, color, 2.0)
				previous = point
			draw_line(previous, pos, Color.WHITE, 2.0)
		_:
			# wisp, and anything unnamed: a soft trailing glow.
			for i in 4:
				var trail := pos - forward * (i * 7.0)
				draw_circle(trail, 6.0 - i * 1.2, _fade(color, 0.5 - i * 0.11))
			draw_circle(pos, 3.0, Color.WHITE)


## The flash at the barrel, so a shot reads as *fired* rather than as appearing
## out of nowhere halfway across the board.
##
## This is the one effect where the two positions are the other way round: the
## sim reports the muzzle *on the shooter*, with the target as its source, so the
## cone is aimed from `at` toward `from`.
func _draw_muzzle(e: Dictionary, t: float) -> void:
	if not e["has_source"]:
		return
	var alpha := 1.0 - t
	var origin: Vector2 = e["at"]
	var forward: Vector2 = ((e["from"] as Vector2) - origin).normalized()
	var side := forward.orthogonal()
	var reach := 20.0 * (1.0 - t * 0.4)
	var cone := PackedVector2Array([
		origin + forward * 6.0,
		origin + forward * reach + side * (reach * 0.42),
		origin + forward * reach - side * (reach * 0.42),
	])
	draw_colored_polygon(cone, _fade(e["color"], alpha * 0.75))
	draw_circle(origin + forward * 8.0, 4.0 * alpha, _fade(Color.WHITE, alpha))


## Melee: an arc swung *through* the target, oriented from the attacker.
func _draw_melee(e: Dictionary, t: float) -> void:
	var target: Vector2 = e["at"]
	var angle: float = e["angle"]
	var forward := Vector2.RIGHT.rotated(angle)
	var alpha := 1.0 - t
	var color: Color = e["color"]
	# Sit the swing just short of the target, on the attacker's side.
	var centre := target - forward * 10.0

	match e["style"]:
		&"crush":
			# A heavy landing: a wedge plus an expanding shockwave.
			var reach := 26.0
			var wedge := PackedVector2Array([
				centre - forward * 10.0,
				centre + forward * reach + forward.orthogonal() * 14.0,
				centre + forward * reach - forward.orthogonal() * 14.0,
			])
			draw_colored_polygon(wedge, _fade(color, alpha * 0.5))
			draw_arc(target, 12.0 + t * 30.0, 0.0, TAU, 24,
				_fade(color, alpha * 0.8), 3.0)
		&"claw":
			# Three parallel rakes, sweeping as they fade.
			var sweep := -0.6 + t * 1.2
			for i in 3:
				var offset := forward.orthogonal() * ((i - 1) * 9.0)
				draw_arc(centre + offset, 18.0, angle - 0.9 + sweep, angle + 0.5 + sweep,
					10, _fade(color, alpha), 2.5)
		&"spectral":
			var sweep := -0.5 + t * 1.0
			draw_arc(centre, 22.0, angle - 1.1 + sweep, angle + 1.1 + sweep, 16,
				_fade(color, alpha * 0.9), 5.0)
			draw_arc(centre, 15.0, angle - 0.8 + sweep, angle + 0.8 + sweep, 12,
				_fade(Color.WHITE, alpha * 0.5), 2.0)
		_:
			# A clean cutlass arc.
			var sweep := -0.8 + t * 1.6
			draw_arc(centre, 21.0, angle - 1.0 + sweep, angle + 0.6 + sweep, 14,
				_fade(Color.WHITE, alpha), 3.5)
			draw_arc(centre, 21.0, angle - 1.0 + sweep, angle + 0.3 + sweep, 12,
				_fade(color, alpha * 0.7), 1.5)

	if e["style"] != &"crush":
		_draw_sparks(target, angle, t, color, 4)


## Where a shot lands: a flash, and sparks thrown on *through* the target.
func _draw_impact(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	draw_circle(e["at"], 9.0 * (1.0 - t) + 2.0, _fade(Color.WHITE, alpha * 0.75))
	draw_circle(e["at"], 15.0 * t + 3.0, _fade(e["color"], alpha * 0.35))
	_draw_sparks(e["at"], e["angle"], t, e["color"], 5)


## A fan of sparks continuing along the direction of the blow.
func _draw_sparks(at: Vector2, angle: float, t: float, color: Color, count: int) -> void:
	var alpha := 1.0 - t
	for i in count:
		var spread := (float(i) / maxf(1.0, count - 1.0) - 0.5) * 1.5
		var direction := Vector2.RIGHT.rotated(angle + spread)
		var near := at + direction * (6.0 + t * 14.0)
		var far := at + direction * (12.0 + t * 26.0)
		draw_line(near, far, _fade(color, alpha * 0.9), 2.0 * alpha + 0.5)


## A crit gets a starburst, so a big number has a reason on screen.
func _draw_crit(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	var reach := 10.0 + t * 22.0
	for i in 8:
		var direction := Vector2.RIGHT.rotated(TAU * float(i) / 8.0 + t * 0.6)
		draw_line(e["at"] + direction * (reach * 0.4), e["at"] + direction * reach,
			_fade(e["color"], alpha), 2.5)
	draw_arc(e["at"], reach * 0.75, 0.0, TAU, 20, _fade(Color.WHITE, alpha * 0.5), 1.5)


# --- ability lines -----------------------------------------------------------

func _draw_tracer(e: Dictionary, t: float) -> void:
	if not e["has_source"]:
		return
	var alpha := 1.0 - t
	draw_line(e["from"], e["at"], _fade(e["color"], alpha), 2.0)
	draw_circle(e["at"], 4.0 * alpha, _fade(Color.WHITE, alpha))


## A chain reads as links rather than a line, so a pull is obviously a pull.
func _draw_chain(e: Dictionary, t: float) -> void:
	if not e["has_source"]:
		return
	var alpha := 1.0 - t
	var from: Vector2 = e["from"]
	var to: Vector2 = e["at"]
	var links := maxi(3, int(from.distance_to(to) / 12.0))
	for i in links:
		var a := from.lerp(to, float(i) / links)
		var b := from.lerp(to, (float(i) + 0.55) / links)
		draw_line(a, b, _fade(e["color"], alpha), 3.0)
	draw_circle(to, 5.0 * alpha, _fade(e["color"], alpha))


## A beam is a bright core inside a wide glow.
func _draw_beam(e: Dictionary, t: float) -> void:
	if not e["has_source"]:
		return
	var alpha := 1.0 - t
	draw_line(e["from"], e["at"], _fade(e["color"], alpha * 0.3), 14.0)
	draw_line(e["from"], e["at"], _fade(e["color"], alpha * 0.7), 6.0)
	draw_line(e["from"], e["at"], _fade(Color.WHITE, alpha), 2.0)


## Lightning: a jagged fall from above, or a jagged arc from a source.
func _draw_bolt(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	var to: Vector2 = e["at"]
	var from: Vector2 = e["from"] if e["has_source"] else to + Vector2(0, -110)
	var segments := 6
	var normal := (to - from).normalized().orthogonal()
	var previous := from
	for i in range(1, segments + 1):
		var point := from.lerp(to, float(i) / segments)
		if i < segments:
			point += normal * (sin(float(i) * 3.1 + to.x) * 9.0)
		draw_line(previous, point, _fade(e["color"], alpha), 3.0)
		draw_line(previous, point, _fade(Color.WHITE, alpha * 0.7), 1.2)
		previous = point
	draw_circle(to, 10.0 * alpha, _fade(e["color"], alpha * 0.4))


# --- ability bursts ----------------------------------------------------------

## A double ring, for the big area abilities.
func _draw_nova(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	draw_arc(e["at"], 10.0 + t * 96.0, 0.0, TAU, 40, _fade(e["color"], alpha), 5.0)
	draw_arc(e["at"], 4.0 + t * 62.0, 0.0, TAU, 32, _fade(Color.WHITE, alpha * 0.55), 2.0)


## A ring with spikes, for the close-range slams.
func _draw_shock(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	var radius := 8.0 + t * 66.0
	draw_arc(e["at"], radius, 0.0, TAU, 32, _fade(e["color"], alpha), 3.5)
	for i in 10:
		var direction := Vector2.RIGHT.rotated(TAU * float(i) / 10.0)
		draw_line(e["at"] + direction * radius * 0.82, e["at"] + direction * (radius + 9.0),
			_fade(e["color"], alpha * 0.8), 2.0)


## Three staggered ripples travelling outward.
func _draw_wave(e: Dictionary, t: float) -> void:
	for i in 3:
		var offset := t - i * 0.16
		if offset <= 0.0:
			continue
		var alpha := (1.0 - offset) * 0.9
		draw_arc(e["at"], 6.0 + offset * 108.0, 0.0, TAU, 36,
			_fade(e["color"], alpha), 4.0 - i)


## A small quick flash, for buffs and heals landing on an ally.
func _draw_pop(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	draw_arc(e["at"], 6.0 + t * 26.0, 0.0, TAU, 20, _fade(e["color"], alpha), 2.5)
	draw_circle(e["at"], 5.0 * alpha, _fade(e["color"], alpha * 0.6))


## Mana full: a ring pulled *inward*, the opposite of everything else, so a cast
## winding up never reads as a cast going off.
func _draw_cast(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t * 0.4
	draw_arc(e["at"], 42.0 * (1.0 - t) + 8.0, 0.0, TAU, 28, _fade(e["color"], alpha), 3.0)
	for i in 6:
		var direction := Vector2.RIGHT.rotated(TAU * float(i) / 6.0 - t * 2.0)
		var distance := 42.0 * (1.0 - t) + 8.0
		draw_circle(e["at"] + direction * distance, 2.5, _fade(Color.WHITE, alpha))


func _draw_revive(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t
	draw_arc(e["at"], 8.0 + t * 40.0, 0.0, TAU, 24, _fade(e["color"], alpha), 3.0)
	for i in 6:
		var lift := Vector2(sin(float(i) * 2.3) * 16.0, -t * 46.0 - i * 4.0)
		draw_circle(e["at"] + lift, 3.0 * alpha, _fade(e["color"], alpha))


func _draw_blink(e: Dictionary, t: float) -> void:
	var alpha := (1.0 - t) * 0.7
	for i in 3:
		draw_arc(e["at"], 10.0 + i * 8.0 + t * 12.0, 0.0, TAU, 18,
			_fade(e["color"], alpha - i * 0.15), 2.0)


## Stars orbiting overhead, held for the length of the stun's own animation.
func _draw_stun(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - t * t
	var above: Vector2 = e["at"] + Vector2(0, -34)
	for i in 3:
		var spin := t * 9.0 + TAU * float(i) / 3.0
		var point := above + Vector2(cos(spin) * 15.0, sin(spin) * 5.0)
		draw_circle(point, 3.5, _fade(e["color"], alpha))


## Motes pulled from the target back to whoever is draining them.
func _draw_drain(e: Dictionary, t: float) -> void:
	if not e["has_source"]:
		return
	var alpha := 1.0 - t
	for i in 4:
		var offset := fposmod(t + float(i) * 0.25, 1.0)
		var point: Vector2 = (e["at"] as Vector2).lerp(e["from"], offset)
		draw_circle(point, 4.0 * (1.0 - offset) + 1.0, _fade(e["color"], alpha))


func _draw_death(e: Dictionary, t: float) -> void:
	var alpha := (1.0 - t) * 0.6
	draw_circle(e["at"], 10.0 + t * 20.0, _fade(e["color"], alpha))


# --- damage numbers ----------------------------------------------------------

func _draw_text(e: Dictionary, t: float) -> void:
	var alpha := 1.0
	if t < 0.12:
		alpha = t / 0.12          # a quick fade in stops numbers popping
	elif t > 0.6:
		alpha = 1.0 - (t - 0.6) / 0.4

	var rise := -18.0 - t * 30.0
	var size := UITheme.FONT_BODY
	var color := UITheme.DMG_PHYSICAL

	match e["style"]:
		&"magic": color = UITheme.DMG_MAGIC
		&"true": color = UITheme.DMG_TRUE
		&"crit":
			color = UITheme.DMG_CRIT
			size = UITheme.FONT_TITLE
		&"heal": color = UITheme.HEAL
		&"miss":
			color = UITheme.MISS
			size = UITheme.FONT_SMALL
		&"execute":
			color = Color("ff5f7a")
			size = UITheme.FONT_TITLE
		&"proc":
			color = UITheme.PROC
			size = UITheme.FONT_SMALL

	var text: String = e["text"]
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at: Vector2 = e["at"] + Vector2(-width * 0.5, rise)

	# Drawn twice: a dark copy behind keeps numbers legible over a bright effect.
	draw_string(_font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		_fade(Color.BLACK, alpha * 0.8))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _fade(color, alpha))
