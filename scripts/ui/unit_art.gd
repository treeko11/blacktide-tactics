class_name UnitArt
extends RefCounted

## Draws a pirate. Every unit on the board is built here out of polygons.
##
## **Why shapes and not sprites.** The game has no artist and no image asset of
## any kind. A drawn figure costs nothing to ship, renders identically at the
## 21-point hex a phone gives it and the 87-point one a desktop does, and — the
## part that matters — arrives already in pieces, so an arm can swing without
## anybody drawing a second frame of it.
##
## **Thirteen bodies, not fifty-one.** A champion names one of `BODIES`, a tint and
## a couple of `MARKS`, and that is its whole appearance. At the size a unit is
## actually seen, a bespoke silhouette per champion would be detail nobody can
## resolve; a family plus a colour plus one signature accessory is what reads at
## a glance, and it keeps adding a pirate a `.tres` edit rather than an art job.
##
## Nothing here holds state, touches the scene tree or names an autoload: it is a
## pile of static functions drawing into whatever CanvasItem it is handed, so the
## board, the bench, a shop card and the almanac all show the same figure.
##
## Coordinates are figure space — origin at the unit's board position, y up is
## negative, feet on the ground plate at `GROUND`. A body is about 44 tall and 34
## wide, which is the footprint the circle it replaced had.

## Every archetype. A champion naming anything else falls back to `pirate`, so a
## typo in a `.tres` is a plain-looking pirate rather than an invisible unit.
const BODIES: Array[StringName] = [
	&"pirate",   ## human, cutlass
	&"gunner",   ## human, firearm
	&"officer",  ## human, Royal Navy: long-tailed uniform, boards, bicorn
	&"siren",    ## mermaid
	&"ship",     ## hull, mast, sail
	&"shark",    ## finned swimmer, in profile
	&"serpent",  ## coiled, turns to face its aim
	&"kraken",   ## mantle and tentacles
	&"crab",     ## shell and claws
	&"ghost",    ## tattered wraith
	&"bird",     ## gull
	&"golem",    ## stone hulk
	&"brute",    ## low four-legged vermin
]

## Signature accessories. An unknown mark is ignored rather than failing, for the
## same reason as an unknown body.
const MARKS: Array[StringName] = [
	&"tricorn", &"bicorn", &"bandana", &"crown", &"eyepatch", &"beard",
	&"hook", &"harpoon", &"musket", &"spyglass", &"parrot", &"plume",
	&"epaulette", &"anchor", &"keg", &"storm", &"lantern", &"tattered",
	&"dual", &"horns", &"tide", &"rope",
]

## Bodies drawn from above, which rotate to point along their aim.
const TURNS_TO_AIM: Array[StringName] = [&"serpent", &"bird"]
## Bodies drawn from the side, which flip to face their aim.
const MIRRORS_TO_AIM: Array[StringName] = [&"brute", &"shark"]

## Everything below is authored at a size that left a figure adrift in the middle
## of its hex. Rather than move ninety numbers, the whole figure is scaled once —
## the ground plate is drawn before this applies, so the disc keeps the footprint
## the hex was built around.
const FIGURE_SCALE := 1.14

const GROUND := 17.0    ## y of the ground plate a figure stands on
const REACH := 13.0     ## how far a weapon hand travels from the shoulder

const SKIN := Color("d8a476")
const SKIN_DROWNED := Color("9fc0b4")
const METAL := Color("c2d2dc")
const WOOD := Color("6d4a30")
const WOOD_DARK := Color("46301f")


## One frame of a unit's animation. Every field is 0-1 and decays in the view;
## nothing here reaches back into the sim, which is what keeps a fight at 4x
## identical to the same fight at 1x whether or not anybody is watching it.
class Pose:
	extends RefCounted

	## Seconds, for idle motion. Given a per-unit offset by the view so a board
	## of eighteen does not breathe in lockstep.
	var clock: float = 0.0
	## Unit vector toward whatever this unit is pointed at. The board is played
	## up the screen, so this is usually vertical — which is exactly why a figure
	## faces the viewer and *leans* at its target rather than turning to face it.
	var aim: Vector2 = Vector2(0.0, -1.0)
	## 1 the instant an attack fires, decaying to 0.
	var swing: float = 0.0
	## Ranged attacks kick back; melee attacks lunge forward.
	var ranged: bool = false
	## 1 the instant health drops, decaying to 0. Flinch plus a white flash.
	var recoil: float = 0.0
	## 1 while an ability is being channelled.
	var cast: float = 0.0
	## 0 alive, 1 fully sunk.
	var dead: float = 0.0
	## 1 while walking between hexes.
	var moving: float = 0.0
	var stunned: bool = false
	var alpha: float = 1.0
	## Whether to draw the plate the figure stands on. On the board it is the
	## only thing carrying the team and the cost, so it is never off there; in a
	## 24-point list row it is a flat ellipse under a figure barely taller than
	## it, and reads as a pair of cart wheels.
	var grounded: bool = true
	## How much fine detail is worth drawing, from the scale the board is at.
	## A phone draws a unit into a 21-point hex, where a belt buckle, a row of
	## teeth and a parrot are three draw calls each producing one indistinct
	## pixel. Silhouette and outline survive at every size and are never gated;
	## trim is.
	var detail: float = 1.0


## The colours a body draws with, derived from one authored tint so a champion is
## a single colour in its `.tres` rather than a paint scheme. The flash, the
## drain and the fade are folded in here rather than at every call site, because
## a body that forgets one of them is a body that does not react to being hit.
static func palette(tint: Color, pose: Pose) -> Dictionary:
	var flash: float = clampf(pose.recoil * 0.75, 0.0, 0.75)
	var alpha: float = pose.alpha * (1.0 - pose.dead * 0.7)
	var drab: float = 0.55 if pose.stunned else 0.0

	var out := {
		"main": tint,
		"dark": tint.darkened(0.45),
		"deep": tint.darkened(0.68),
		"light": tint.lightened(0.32),
		"skin": SKIN,
		"drowned": SKIN_DROWNED,
		"metal": METAL,
		"wood": WOOD,
		"wood_dark": WOOD_DARK,
		"ink": Color("0a141c"),
		"bone": Color("e6e2d2"),
	}
	for key in out:
		var c: Color = out[key]
		if drab > 0.0:
			var grey: float = c.get_luminance()
			c = c.lerp(Color(grey, grey, grey * 1.05), drab)
		c = c.lerp(Color.WHITE, flash)
		c.a = alpha
		out[key] = c
	return out


# --- the one entry point -----------------------------------------------------

## Draws a whole unit into `ci`, ground plate first. The caller's transform is
## left exactly as it was found, because everything drawn afterwards — health
## bars, stars, item pips — is laid out in unpolluted board space.
static func draw_unit(ci: CanvasItem, body: StringName, tint: Color,
		marks: Array, pose: Pose, team_color: Color,
		rim_color: Color = Color.TRANSPARENT) -> void:
	_detail = pose.detail
	_draw_ground(ci, pose, team_color,
		team_color if rim_color.a == 0.0 else rim_color)

	var pal := palette(tint, pose)
	var aim: Vector2 = pose.aim.normalized()
	if aim.length() < 0.01:
		aim = Vector2(0.0, -1.0)

	# Lunge on a melee swing, kick back on a ranged one, flinch away from a hit,
	# and settle back to standing as each decays.
	var thrust: float = pose.swing * (-6.0 if pose.ranged else 9.0)
	var offset: Vector2 = aim * thrust - aim * pose.recoil * 4.0
	var bob: float = sin(pose.clock * 2.2) * 1.1
	if pose.moving > 0.0:
		bob += sin(pose.clock * 11.0) * 1.6 * pose.moving
	offset.y += bob + pose.dead * 9.0

	var tilt: float = pose.dead * 0.55 + pose.recoil * 0.1
	var squash := Vector2(
		FIGURE_SCALE * (1.0 + pose.recoil * 0.12),
		FIGURE_SCALE * (1.0 - pose.recoil * 0.12))

	# Three ways a body can be pointed at its target, and which one applies is a
	# property of the shape rather than a choice. A swimmer or a bird is drawn
	# from above and simply turns; a rat is drawn from the side and flips; a
	# figure standing on two legs faces the viewer and only leans, because a
	# board played up the screen would otherwise spend the fight in profile
	# facing away from you.
	if TURNS_TO_AIM.has(body):
		tilt += aim.angle() + PI * 0.5
	elif MIRRORS_TO_AIM.has(body) and aim.x < 0.0:
		squash.x = -squash.x

	ci.draw_set_transform(offset, tilt, squash)

	if pose.cast > 0.0:
		_draw_cast_glow(ci, pose)

	match body:
		&"gunner": _body_gunner(ci, pal, pose, aim, marks)
		&"officer": _body_officer(ci, pal, pose, aim, marks)
		&"siren": _body_siren(ci, pal, pose, aim, marks)
		&"ship": _body_ship(ci, pal, pose, aim, marks)
		&"shark": _body_shark(ci, pal, pose, aim, marks)
		&"serpent": _body_serpent(ci, pal, pose, aim, marks)
		&"kraken": _body_kraken(ci, pal, pose, aim, marks)
		&"crab": _body_crab(ci, pal, pose, aim, marks)
		&"ghost": _body_ghost(ci, pal, pose, aim, marks)
		&"bird": _body_bird(ci, pal, pose, aim, marks)
		&"golem": _body_golem(ci, pal, pose, aim, marks)
		&"brute": _body_brute(ci, pal, pose, aim, marks)
		_: _body_pirate(ci, pal, pose, aim, marks)

	if marks.has(&"tide"):
		_mark_tide(ci, pal, pose)
	if marks.has(&"storm"):
		_mark_storm(ci, pal, pose)

	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The disc a figure stands on, and the only thing on the board still carrying
## the two facts the old circular body carried: `team_color` fills it, so a
## glance says whose fleet this is, and `rim_color` outlines it, so a glance
## still says what the pirate cost. The figures keep their own colours, which is
## why neither could stay on the figure.
static func _draw_ground(ci: CanvasItem, pose: Pose, team_color: Color,
		rim_color: Color) -> void:
	var alive: float = 1.0 - pose.dead
	if alive <= 0.01 or not pose.grounded:
		return
	var centre := Vector2(0.0, GROUND)

	var shade := Color(0.0, 0.05, 0.09, 0.4 * alive * pose.alpha)
	ci.draw_colored_polygon(_ellipse(centre + Vector2(0.0, 1.5), 16.0, 5.5), shade)

	var a: float = alive * pose.alpha
	ci.draw_colored_polygon(_ellipse(centre, 16.0, 5.5),
		Color(team_color.r, team_color.g, team_color.b, 0.2 * a))
	ci.draw_polyline(_closed(_ellipse(centre, 16.0, 5.5)),
		Color(rim_color.r, rim_color.g, rim_color.b, 0.75 * a), 1.6)

	# The wake exists only while something is moving through the water.
	if pose.moving > 0.0:
		var swell: float = 1.0 + sin(pose.clock * 8.0) * 0.12
		ci.draw_polyline(_closed(_ellipse(centre, 21.5 * swell, 7.2 * swell)),
			Color(0.78, 0.93, 1.0, 0.3 * pose.moving * pose.alpha), 1.5)


## A unit mid-cast is about to do the most important thing it does, so the ring
## the old circular body wore survives here rather than being lost with it.
static func _draw_cast_glow(ci: CanvasItem, pose: Pose) -> void:
	var pulse: float = 0.6 + sin(pose.clock * 9.0) * 0.4
	var glow := Color(0.5, 0.89, 1.0, 0.55 * pose.cast * pose.alpha)
	ci.draw_arc(Vector2(0.0, GROUND), 18.0 + pulse * 2.0, 0.0, TAU, 26, glow, 2.0)
	ci.draw_arc(Vector2.ZERO, 21.0, PI * 1.15, PI * 1.85, 16,
		Color(glow.r, glow.g, glow.b, glow.a * 0.6), 1.5)


# --- shape helpers -----------------------------------------------------------

## How small the current figure is, from the pose `draw_unit` was handed.
##
## A static rather than an argument on fifty call sites. It is written once at
## the top of every `draw_unit` and read only by `_shape` below, and drawing is
## single-threaded, so the value is always the one belonging to the figure being
## drawn. The alternative was threading `detail` through every body and every
## mark, which is a parameter nobody would read and everybody would forget.
static var _detail: float = 1.0

## Below this, outlines stop being drawn.
##
## The outline is what keeps a flat polygon from losing its silhouette on a dark
## board, so it is the last thing to go — but it is a second draw call for every
## shape in every figure, and at a 21-point hex on a phone it lands under a pixel
## wide and changes nothing anybody can see.
const OUTLINE_FLOOR := 0.45


## Fill plus a darker edge. Everything is drawn this way: a flat polygon on a
## dark board loses its silhouette, and one outline is what gives it back.
static func _shape(ci: CanvasItem, points: PackedVector2Array, fill: Color,
		line_width: float = 1.0) -> void:
	if points.size() < 3:
		return
	ci.draw_colored_polygon(points, fill)
	if _detail < OUTLINE_FLOOR:
		return
	var edge := fill.darkened(0.55)
	edge.a = fill.a
	ci.draw_polyline(_closed(points), edge, line_width)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out


static func _ellipse(centre: Vector2, rx: float, ry: float,
		segments: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		out.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## A tapering limb: a quad from `a` to `b`, `w0` wide at one end and `w1` at the
## other. Arms, legs, tails and tentacle segments are all this.
static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, w0: float, w1: float,
		fill: Color) -> void:
	var dir := b - a
	if dir.length() < 0.001:
		return
	var n := dir.normalized().orthogonal()
	_shape(ci, PackedVector2Array([a + n * w0, b + n * w1, b - n * w1, a - n * w0]), fill)


## A limb that curls: `bend` pushes the midpoint sideways, which is what turns a
## straight tentacle into one that coils. `STEPS` is a constant rather than an
## argument on purpose — a `for` bound inside a `_draw` should never be a number
## that arrived from somewhere else.
const CURL_STEPS := 6

static func _curl(ci: CanvasItem, a: Vector2, b: Vector2, bend: float,
		w0: float, w1: float, fill: Color) -> void:
	var straight := b - a
	var span := straight.length()
	if span < 0.001:
		return

	# A ribbon folds over itself on the inside of a bend once it is wider than
	# the curve is tight, and Godot answers a self-intersecting polygon with
	# "triangulation failed" every frame rather than with a wrong shape. Both
	# limits are clamped here rather than at each call site, because the values
	# that break it arrive from a sine — a siren's tail is fine at rest and folds
	# the moment she swims.
	bend = clampf(bend, -span * 0.35, span * 0.35)
	var widest: float = maxf(w0, w1)
	var room: float = span * 0.32
	if widest > room:
		var shrink: float = room / widest
		w0 *= shrink
		w1 *= shrink

	var control: Vector2 = (a + b) * 0.5 + straight.normalized().orthogonal() * bend
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var previous := a
	for i in CURL_STEPS + 1:
		var t: float = float(i) / float(CURL_STEPS)
		var p: Vector2 = a.lerp(control, t).lerp(control.lerp(b, t), t)
		var tangent: Vector2 = p - previous
		if tangent.length() < 0.001:
			tangent = straight
		previous = p
		var side: Vector2 = tangent.normalized().orthogonal() * lerpf(w0, w1, t)
		left.append(p + side)
		right.append(p - side)
	right.reverse()
	left.append_array(right)
	_shape(ci, left, fill)


## The weapon hand: at rest by the hip, thrown out along the aim as a swing
## peaks. Everything a figure holds hangs off this one position.
static func _hand(pose: Pose, aim: Vector2, rest: Vector2) -> Vector2:
	var out: float = pose.swing
	if pose.ranged:
		out = 0.55 + pose.swing * 0.25
	return rest + aim * REACH * out


# --- the bodies --------------------------------------------------------------
#
# Each one draws back to front: whatever is behind the torso, then the torso,
# then whatever is in front of it. They share `_human` where they can, because a
# pirate and a gunner differ by exactly one thing — what is in the hand.

## Shoulders, hips and the ground, shared by everything that stands on two legs.
const SHOULDER_L := Vector2(-8.0, -7.0)
const SHOULDER_R := Vector2(8.0, -7.0)
const HEAD := Vector2(0.0, -16.5)
const HEAD_R := 5.5


static func _body_pirate(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var hand := _hand(pose, aim, Vector2(8.5, -2.0))
	_human(ci, pal, pose, aim, marks, hand)
	if marks.has(&"harpoon"):
		_weapon_harpoon(ci, pal, hand, aim)
	elif marks.has(&"anchor"):
		_weapon_anchor(ci, pal, hand, aim)
	else:
		_weapon_cutlass(ci, pal, hand, aim)
		if marks.has(&"dual"):
			_weapon_cutlass(ci, pal, Vector2(-8.5, -1.0) - aim * 4.0, -aim)


static func _body_gunner(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var rest := Vector2(7.0, -4.0)
	var hand: Vector2 = rest + aim * REACH * (0.62 + pose.swing * 0.2)
	_human(ci, pal, pose, aim, marks, hand)
	if marks.has(&"spyglass"):
		_weapon_spyglass(ci, pal, hand, aim)
	elif marks.has(&"musket"):
		_weapon_gun(ci, pal, pose, hand, aim, 17.0)
	else:
		_weapon_gun(ci, pal, pose, hand, aim, 10.0)


## The Royal Navy. Not a re-hatted gunner: it is `_human` in uniform, which is a
## different outline — squared shoulders, a narrow waist and a coat flared into
## tails past the knee, against the corsair's round-shouldered jacket ending at
## the hip. The hat is the least of it, deliberately. A bicorn against a tricorn
## is a couple of pixels of difference at the 21-point hex a phone gives a unit,
## so the faction the whole board is built around was, in practice, unmarked.
##
## It carries every weapon rather than only a gun, because the Navy runs from
## Marlowe at range 4 to Old Anchor Ned swinging an anchor at range 1, and an
## officer is a rank rather than an attack style.
static func _body_officer(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var hand := _hand(pose, aim, Vector2(8.5, -2.0))
	if marks.has(&"musket") or marks.has(&"spyglass"):
		hand = Vector2(7.0, -4.0) + aim * REACH * (0.62 + pose.swing * 0.2)
	_human(ci, pal, pose, aim, marks, hand, true)
	if marks.has(&"spyglass"):
		_weapon_spyglass(ci, pal, hand, aim)
	elif marks.has(&"musket"):
		_weapon_gun(ci, pal, pose, hand, aim, 17.0)
	elif marks.has(&"anchor"):
		_weapon_anchor(ci, pal, hand, aim)
	else:
		_weapon_cutlass(ci, pal, hand, aim)


## Legs, coat, arms and head. `hand` is where the weapon arm ends; everything
## a champion actually holds is drawn by its caller, after this, so the weapon
## is in front of the body and the arm behind it.
##
## `uniform` is the Royal Navy. It is not a paint job: the coat grows tails past
## the knee, the shoulders square off into boards, and the default hat becomes a
## bicorn. All three are changes to the **outline**, which is the only thing that
## survives a 21-point hex on a phone — a hat brim there is two pixels, which is
## why "Navy wears a bicorn, Corsairs wear a tricorn" told nobody anything.
static func _human(ci: CanvasItem, pal: Dictionary, pose: Pose, aim: Vector2,
		marks: Array, hand: Vector2, uniform: bool = false) -> void:
	var stride: float = sin(pose.clock * 11.0) * 3.0 * pose.moving
	var skin: Color = pal["drowned"] if marks.has(&"tattered") else pal["skin"]

	# Legs and boots.
	_limb(ci, Vector2(-4.0, 3.0), Vector2(-5.0 - stride, 14.0), 3.0, 2.4, pal["deep"])
	_limb(ci, Vector2(4.0, 3.0), Vector2(5.0 + stride, 14.0), 3.0, 2.4, pal["deep"])
	_shape(ci, PackedVector2Array([Vector2(-8.0 - stride, 13.0), Vector2(-2.5 - stride, 13.0),
		Vector2(-2.5 - stride, 17.0), Vector2(-8.5 - stride, 17.0)]), pal["wood_dark"])
	_shape(ci, PackedVector2Array([Vector2(2.5 + stride, 13.0), Vector2(8.0 + stride, 13.0),
		Vector2(8.5 + stride, 17.0), Vector2(2.5 + stride, 17.0)]), pal["wood_dark"])

	# The back arm, behind the coat.
	_limb(ci, SHOULDER_L, Vector2(-10.0, 3.0), 2.6, 2.0, pal["dark"])
	if marks.has(&"hook"):
		_mark_hook(ci, pal, Vector2(-10.5, 4.0))
	if marks.has(&"lantern"):
		_mark_lantern(ci, pal, pose, Vector2(-11.0, 5.0))
	if marks.has(&"keg"):
		_mark_keg(ci, pal, Vector2(-13.0, 6.0))

	# Coat. A uniform is walked as one simple ring — down the right tail, up into
	# the split at the centre, down the left tail — so the notch between the
	# tails is concave but never crossed. Every number in it is a constant, which
	# is the other half of why it cannot fold: nothing here arrives from a sine.
	var braid := Color("e8b44a", pal["main"].a)
	if uniform:
		_shape(ci, PackedVector2Array([Vector2(-8.5, -9.5), Vector2(8.5, -9.5),
			Vector2(10.0, 2.0), Vector2(12.0, 15.0), Vector2(4.0, 14.0),
			Vector2(0.0, 7.0), Vector2(-4.0, 14.0), Vector2(-12.0, 15.0),
			Vector2(-10.0, 2.0)]), pal["main"])
		# Shoulder boards, never gated: they are what squares off the top of the
		# silhouette, and a silhouette is what a phone still has.
		for side in [-1.0, 1.0]:
			_shape(ci, PackedVector2Array([Vector2(6.0 * side, -10.5),
				Vector2(12.5 * side, -9.5), Vector2(12.0 * side, -6.0),
				Vector2(6.0 * side, -7.0)]), braid)
	else:
		_shape(ci, PackedVector2Array([Vector2(-8.5, -9.0), Vector2(8.5, -9.0), Vector2(10.5, 4.0),
			Vector2(8.0, 7.0), Vector2(-8.0, 7.0), Vector2(-10.5, 4.0)]), pal["main"])
	if pose.detail > 0.45:
		var placket: Color = braid if uniform else pal["light"]
		_shape(ci, PackedVector2Array([Vector2(-2.6, -9.0), Vector2(2.6, -9.0), Vector2(2.0, 6.0),
			Vector2(-2.0, 6.0)]), placket)
		_shape(ci, PackedVector2Array([Vector2(-10.0, 1.5), Vector2(10.0, 1.5), Vector2(10.4, 4.5),
			Vector2(-10.4, 4.5)]), pal["wood_dark"])
		ci.draw_rect(Rect2(-2.0, 1.8, 4.0, 2.8), pal["metal"])

	# Over the coat, under the weapon arm below and under whatever the body
	# draws after this — which is how the anchor ends up in front of it.
	if marks.has(&"rope"):
		_mark_rope(ci, pal, pose)

	# Head and neck.
	_shape(ci, PackedVector2Array([Vector2(-2.5, -12.0), Vector2(2.5, -12.0), Vector2(2.5, -8.5),
		Vector2(-2.5, -8.5)]), skin)
	_shape(ci, _ellipse(HEAD, HEAD_R, HEAD_R + 0.4, 14), skin)
	if pose.detail > 0.5 and not marks.has(&"eyepatch"):
		ci.draw_circle(HEAD + Vector2(-2.2, -0.8), 0.9, pal["ink"])
	if pose.detail > 0.5:
		ci.draw_circle(HEAD + Vector2(2.2, -0.8), 0.9, pal["ink"])

	# The weapon arm, in front of the coat so a swing reads as coming forward.
	_limb(ci, SHOULDER_R, hand, 2.6, 2.0, pal["dark"])

	_draw_head_marks(ci, pal, pose, marks, uniform)


## Hats, hair and everything else worn. Split out because every humanoid body
## wants all of it and none of them want it in a different order.
static func _draw_head_marks(ci: CanvasItem, pal: Dictionary, pose: Pose,
		marks: Array, uniform: bool = false) -> void:
	if marks.has(&"beard"):
		_shape(ci, PackedVector2Array([Vector2(-5.0, -15.0), Vector2(5.0, -15.0), Vector2(4.0, -8.0),
			Vector2(0.0, -5.0), Vector2(-4.0, -8.0)]), pal["deep"])
	if marks.has(&"eyepatch") and pose.detail > 0.4:
		ci.draw_line(HEAD + Vector2(-6.0, -3.5), HEAD + Vector2(5.0, -1.0),
			pal["ink"], 1.2)
		ci.draw_rect(Rect2(HEAD.x - 4.2, HEAD.y - 2.6, 3.6, 3.2), pal["ink"])
	if marks.has(&"epaulette") and pose.detail > 0.45:
		for side in [-1.0, 1.0]:
			_shape(ci, PackedVector2Array([Vector2(6.5 * side, -9.5), Vector2(11.5 * side, -8.5),
				Vector2(11.0 * side, -5.5), Vector2(6.5 * side, -6.5)]),
				Color("e8b44a", pal["main"].a))
	if marks.has(&"parrot") and pose.detail > 0.55:
		_mark_parrot(ci, pal, pose)

	if marks.has(&"crown"):
		_mark_crown(ci, pal)
	elif marks.has(&"bicorn"):
		_hat_bicorn(ci, pal, pose)
	elif marks.has(&"bandana"):
		_shape(ci, PackedVector2Array([Vector2(-6.2, -21.5), Vector2(6.2, -21.5), Vector2(6.4, -17.5),
			Vector2(-6.4, -17.5)]), pal["main"])
		_limb(ci, Vector2(-6.0, -19.0), Vector2(-12.0, -14.0 + sin(pose.clock * 4.0) * 1.5),
			2.4, 1.0, pal["main"])
	elif marks.has(&"horns"):
		for side in [-1.0, 1.0]:
			_curl(ci, Vector2(4.5 * side, -20.0), Vector2(11.0 * side, -27.0),
				3.0 * side, 2.2, 0.5, pal["bone"])
	elif uniform:
		# An officer's default, the other way round from everyone else's.
		_hat_bicorn(ci, pal, pose)
	elif not marks.has(&"tattered"):
		# A tricorn is the default headwear: a pirate without a hat reads as a
		# civilian, and every body here is in somebody's fleet.
		_shape(ci, PackedVector2Array([Vector2(-11.0, -20.0), Vector2(-4.5, -22.5), Vector2(0.0, -23.5),
			Vector2(4.5, -22.5), Vector2(11.0, -20.0), Vector2(0.0, -17.5)]), pal["deep"])
		_shape(ci, PackedVector2Array([Vector2(-5.0, -21.0), Vector2(-3.5, -26.0), Vector2(3.5, -26.0),
			Vector2(5.0, -21.0)]), pal["deep"])

	if marks.has(&"plume"):
		_curl(ci, Vector2(5.0, -22.0), Vector2(14.0, -29.0), 3.5, 2.4, 0.4, pal["light"])


## Wide and flat, worn across. The one hat whose brim reaches past the shoulders,
## which is what makes it survive being shrunk.
static func _hat_bicorn(ci: CanvasItem, pal: Dictionary, pose: Pose) -> void:
	_shape(ci, PackedVector2Array([Vector2(-12.0, -20.0), Vector2(-4.0, -27.5), Vector2(4.0, -27.5),
		Vector2(12.0, -20.0), Vector2(0.0, -18.0)]), pal["deep"])
	if pose.detail > 0.45:
		ci.draw_line(Vector2(-6.0, -22.0), Vector2(6.0, -22.0),
			Color("e8b44a", pal["main"].a), 1.2)


static func _body_siren(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var sway: float = sin(pose.clock * 2.6) * 3.5 + pose.moving * sin(pose.clock * 9.0) * 3.0

	# Hair first, behind everything.
	_curl(ci, Vector2(-1.0, -21.0), Vector2(-12.0, 1.0), 5.0, 6.0, 1.5, pal["dark"])
	_curl(ci, Vector2(1.0, -21.0), Vector2(11.0, -1.0), -4.0, 5.5, 1.5, pal["dark"])

	# Tail, curling away and finishing in a fluke.
	var tail_end := Vector2(sway, 12.0)
	_curl(ci, Vector2(0.0, 0.0), tail_end, sway * 0.6, 6.0, 2.5, pal["main"])
	_shape(ci, PackedVector2Array([tail_end, tail_end + Vector2(-9.0 + sway * 0.3, 7.0),
		tail_end + Vector2(-3.0, 9.0), tail_end + Vector2(0.0, 5.0),
		tail_end + Vector2(3.0, 9.0), tail_end + Vector2(9.0 + sway * 0.3, 7.0)]),
		pal["light"])
	if pose.detail > 0.5:
		for i in 3:
			var y: float = 1.0 + i * 3.5
			ci.draw_arc(Vector2(sway * (y / 14.0), y), 4.0 - i * 0.6, PI * 0.15,
				PI * 0.85, 8, pal["deep"], 1.0)

	var skin: Color = pal["skin"].lerp(pal["light"], 0.35)
	skin.a = pal["skin"].a
	_shape(ci, PackedVector2Array([Vector2(-5.5, -11.0), Vector2(5.5, -11.0), Vector2(5.0, 1.0),
		Vector2(-5.0, 1.0)]), skin)
	_shape(ci, PackedVector2Array([Vector2(-5.5, -11.0), Vector2(5.5, -11.0), Vector2(5.0, -6.0),
		Vector2(-5.0, -6.0)]), pal["main"])

	# Arms raised: a siren's whole ability is that she is singing.
	var lift: float = 1.0 + pose.cast * 0.6
	_limb(ci, Vector2(-5.0, -9.0), Vector2(-11.0, -18.0 * lift), 2.4, 1.8, skin)
	var hand: Vector2 = Vector2(5.0, -9.0) + aim * REACH * (0.5 + pose.swing * 0.35)
	_limb(ci, Vector2(5.0, -9.0), hand, 2.4, 1.8, skin)
	if pose.cast > 0.0:
		ci.draw_circle(hand, 2.5 + sin(pose.clock * 12.0), Color(0.6, 0.92, 1.0,
			0.7 * pose.cast * pose.alpha))

	_shape(ci, _ellipse(HEAD, HEAD_R, HEAD_R + 0.4, 14), skin)
	if pose.detail > 0.5:
		ci.draw_circle(HEAD + Vector2(-2.2, -0.8), 0.9, pal["ink"])
		ci.draw_circle(HEAD + Vector2(2.2, -0.8), 0.9, pal["ink"])
	# A fringe, so the head is not a bare disc above all that hair.
	_shape(ci, PackedVector2Array([Vector2(-6.0, -18.0), Vector2(6.0, -18.0), Vector2(5.0, -20.0),
		Vector2(-5.0, -20.0)]), pal["dark"])
	if marks.has(&"crown"):
		_mark_crown(ci, pal)


static func _body_ship(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var roll: float = sin(pose.clock * 1.6) * 1.5
	var billow: float = 0.82 + sin(pose.clock * 1.3) * 0.18
	var ragged: bool = marks.has(&"tattered")
	var canvas: Color = pal["deep"] if ragged else pal["bone"]

	# Mast and rigging, behind the sail.
	_limb(ci, Vector2(0.0, 4.0), Vector2(roll * 0.5, -27.0), 1.7, 1.2, pal["wood_dark"])
	if pose.detail > 0.5:
		ci.draw_line(Vector2(roll * 0.5, -25.0), Vector2(-11.0, 2.0), pal["wood_dark"], 0.8)
		ci.draw_line(Vector2(roll * 0.5, -25.0), Vector2(11.0, 2.0), pal["wood_dark"], 0.8)

	# Sail, bellying away from the mast.
	var sail := PackedVector2Array([Vector2(roll * 0.5, -24.0), Vector2(7.0 * billow, -19.0),
		Vector2(13.0 * billow, -12.0), Vector2(7.0 * billow, -6.0), Vector2(0.0, -4.0)])
	if ragged:
		sail = PackedVector2Array([Vector2(roll * 0.5, -24.0), Vector2(7.0 * billow, -19.0),
			Vector2(9.0 * billow, -14.0), Vector2(12.0 * billow, -12.0),
			Vector2(8.0 * billow, -10.0), Vector2(10.0 * billow, -6.0),
			Vector2(5.0 * billow, -7.0), Vector2(0.0, -4.0)])
	_shape(ci, sail, canvas)
	if pose.detail > 0.5:
		ci.draw_line(Vector2(4.0 * billow, -21.0), Vector2(4.0 * billow, -5.0),
			canvas.darkened(0.3), 0.8)

	# Flag.
	var flag_wave: float = sin(pose.clock * 5.0) * 2.0
	_shape(ci, PackedVector2Array([Vector2(roll * 0.5, -27.0), Vector2(9.0, -25.0 + flag_wave),
		Vector2(roll * 0.5, -22.5)]), pal["main"])

	# Hull.
	_shape(ci, PackedVector2Array([Vector2(-16.0, 3.0), Vector2(16.0, 3.0), Vector2(12.0, 14.0),
		Vector2(-12.0, 14.0)]), pal["wood"])
	_shape(ci, PackedVector2Array([Vector2(-15.0, 5.0), Vector2(15.0, 5.0), Vector2(14.4, 8.5),
		Vector2(-14.4, 8.5)]), pal["main"])
	if pose.detail > 0.45:
		for i in 3:
			ci.draw_rect(Rect2(-7.5 + i * 6.0, 9.5, 3.0, 3.0), pal["ink"])
	# Bow foam, on whichever side the ship is pointed.
	var foam := Color(0.8, 0.94, 1.0, (0.3 + pose.moving * 0.4) * pal["main"].a)
	ci.draw_arc(Vector2(aim.x * 13.0, 12.0), 6.0, PI, TAU, 10, foam, 1.6)


static func _body_shark(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	# In profile, snout to the right, turned round by `MIRRORS_TO_AIM`.
	#
	# It was drawn from above first, to match the board being played up the
	# screen — and a shark from above is a spindle with two fins, which at forty
	# pixels is a leaf. The silhouette everyone already knows is the side one, so
	# the body faces across the board and only the lean points at the target.
	var thrash: float = sin(pose.clock * 4.0) * (1.5 + pose.moving * 3.0)

	# Caudal fin, in two triangles rather than one arrowhead: a concave quad
	# built from an animated number is how a polygon folds over itself.
	var root := Vector2(-13.0, 0.0)
	_shape(ci, PackedVector2Array([root, Vector2(-25.0, -10.0 + thrash), Vector2(-19.0, 1.0)]),
		pal["dark"])
	_shape(ci, PackedVector2Array([root, Vector2(-19.0, 1.0), Vector2(-24.0, 11.0 + thrash)]),
		pal["dark"])
	# Far pectoral, behind the body.
	_shape(ci, PackedVector2Array([Vector2(2.0, 3.0), Vector2(-4.0, 12.0), Vector2(6.0, 5.0)]),
		pal["deep"])

	_shape(ci, PackedVector2Array([Vector2(-15.0, -2.0), Vector2(-6.0, -8.0), Vector2(4.0, -9.0),
		Vector2(13.0, -6.0), Vector2(19.0, -1.0), Vector2(13.0, 4.0),
		Vector2(2.0, 7.0), Vector2(-8.0, 6.0), Vector2(-15.0, 2.0)]), pal["main"])
	# Pale underside, which is half of what says shark. A band, so its upper edge
	# is walked left to right and its lower edge right to left and the two can
	# never cross — written the other way round it crossed itself under the jaw
	# and Godot refused to triangulate it, once per frame.
	_shape(ci, PackedVector2Array([Vector2(-13.0, 1.0), Vector2(-5.0, 4.0), Vector2(5.0, 4.6),
		Vector2(14.0, 1.8), Vector2(13.0, 4.0), Vector2(2.0, 7.0),
		Vector2(-8.0, 6.0), Vector2(-14.0, 2.5)]), pal["light"])

	# Before the fins, so the strap passes under them rather than over.
	if marks.has(&"rope"):
		_mark_rope_girth(ci, pal, pose)

	_shape(ci, PackedVector2Array([Vector2(-1.0, -8.5), Vector2(4.0, -19.0), Vector2(7.0, -7.5)]),
		pal["dark"])
	_shape(ci, PackedVector2Array([Vector2(7.0, 4.0), Vector2(4.0, 14.0), Vector2(13.0, 5.5)]),
		pal["dark"])

	if pose.detail > 0.45:
		for i in 3:
			ci.draw_line(Vector2(7.0 - i * 2.2, -5.0), Vector2(6.0 - i * 2.2, 2.0),
				pal["deep"], 0.9)
		ci.draw_circle(Vector2(14.0, -3.0), 1.2, pal["ink"])
		# The jaw, hinged open as it strikes.
		var gape: float = 1.5 + pose.swing * 4.0
		_shape(ci, PackedVector2Array([Vector2(19.0, -1.0), Vector2(9.0, 1.0),
			Vector2(9.5, 1.0 + gape), Vector2(18.0, 0.5 + gape * 0.4)]), pal["ink"])
		for i in 4:
			ci.draw_circle(Vector2(11.0 + i * 2.2, 1.4), 0.7, pal["bone"])
	if marks.has(&"hook"):
		_mark_hook(ci, pal, Vector2(17.0, 3.0))


static func _body_serpent(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	# One tapering ribbon down the screen, wriggling. Built as two edges walked
	# in opposite directions so it closes into a single polygon.
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var speed: float = 3.0 + pose.moving * 3.0
	for i in 9:
		var t: float = float(i) / 8.0
		var y: float = -14.0 + t * 32.0
		var x: float = sin(pose.clock * speed + t * 5.0) * (2.0 + t * 5.0)
		var w: float = lerpf(6.0, 1.2, t)
		left.append(Vector2(x - w, y))
		right.append(Vector2(x + w, y))
	right.reverse()
	left.append_array(right)
	_shape(ci, left, pal["main"])

	var head_x: float = sin(pose.clock * speed) * 2.0
	_shape(ci, _ellipse(Vector2(head_x, -16.0), 6.0, 7.0, 14), pal["light"])
	if pose.detail > 0.45:
		ci.draw_circle(Vector2(head_x - 2.4, -18.0), 1.1, pal["ink"])
		ci.draw_circle(Vector2(head_x + 2.4, -18.0), 1.1, pal["ink"])
		var tongue: float = 3.0 + pose.swing * 5.0
		ci.draw_line(Vector2(head_x, -21.0), Vector2(head_x, -21.0 - tongue),
			Color("d8455e", pal["main"].a), 1.2)
	if marks.has(&"horns"):
		for side in [-1.0, 1.0]:
			_curl(ci, Vector2(3.5 * side, -20.0), Vector2(9.0 * side, -26.0),
				2.5 * side, 1.8, 0.4, pal["bone"])


static func _body_kraken(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	# Tentacles first, so the mantle sits over the top of where they join.
	for i in 6:
		var t: float = float(i) / 5.0
		var x0: float = lerpf(-9.0, 9.0, t)
		var reach: float = 1.0 + pose.swing * 0.5
		var end := Vector2(x0 * 2.0 * reach, 14.0 + sin(pose.clock * 3.0 + i) * 2.0)
		var bend: float = sin(pose.clock * 2.5 + i * 1.7) * 6.0
		_curl(ci, Vector2(x0 * 0.7, -1.0), end, bend, 3.4, 0.9,
			pal["dark"] if i % 2 == 0 else pal["main"])

	_shape(ci, PackedVector2Array([Vector2(-13.0, -1.0), Vector2(-10.0, -13.0), Vector2(0.0, -19.0),
		Vector2(10.0, -13.0), Vector2(13.0, -1.0), Vector2(0.0, 3.0)]), pal["main"])
	if pose.detail > 0.4:
		for side in [-1.0, 1.0]:
			ci.draw_circle(Vector2(5.0 * side, -8.0), 3.2, pal["bone"])
			ci.draw_circle(Vector2(5.0 * side + aim.x * 1.0, -8.0 + aim.y * 0.8), 1.6,
				pal["ink"])
	if pose.detail > 0.55:
		_shape(ci, PackedVector2Array([Vector2(-2.5, 1.0), Vector2(2.5, 1.0), Vector2(0.0, 5.0)]),
			pal["ink"])
	if marks.has(&"crown"):
		_mark_crown(ci, pal)


static func _body_crab(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var scuttle: float = sin(pose.clock * 9.0) * 2.0 * pose.moving
	for side in [-1.0, 1.0]:
		for i in 3:
			_limb(ci, Vector2(11.0 * side, 1.0 + i * 2.5),
				Vector2((15.0 + i * 1.5) * side, 13.0 + scuttle * side), 1.6, 1.0,
				pal["deep"])

	# Claws, which open as the crab winds up and snap shut as it strikes.
	var open: float = 2.5 + (1.0 - pose.swing) * 2.5
	for side in [-1.0, 1.0]:
		var root := Vector2(12.0 * side, -1.0)
		var tip: Vector2 = root + Vector2(7.0 * side, -5.0) + aim * pose.swing * 4.0
		_limb(ci, root, tip, 3.2, 2.6, pal["main"])
		_shape(ci, PackedVector2Array([tip, tip + Vector2(6.0 * side, -open), tip + Vector2(9.0 * side, 0.0)]),
			pal["light"])
		_shape(ci, PackedVector2Array([tip, tip + Vector2(6.0 * side, open), tip + Vector2(9.0 * side, 0.5)]),
			pal["light"])

	_shape(ci, PackedVector2Array([Vector2(-15.0, 4.0), Vector2(-12.0, -5.0), Vector2(-6.0, -9.5),
		Vector2(6.0, -9.5), Vector2(12.0, -5.0), Vector2(15.0, 4.0), Vector2(10.0, 10.0),
		Vector2(-10.0, 10.0)]), pal["main"])
	if pose.detail > 0.45:
		ci.draw_arc(Vector2(0.0, 1.0), 8.0, PI * 1.15, PI * 1.85, 12, pal["light"], 1.4)
		for side in [-1.0, 1.0]:
			_limb(ci, Vector2(4.0 * side, -8.0), Vector2(5.0 * side, -14.0), 1.2, 1.2,
				pal["dark"])
			ci.draw_circle(Vector2(5.0 * side, -14.5), 1.8, pal["bone"])
			ci.draw_circle(Vector2(5.0 * side, -14.5), 0.9, pal["ink"])


static func _body_ghost(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	# A wraith has no feet, so it drifts rather than standing. What makes it read
	# as a wraith rather than as a blob with eyes is the hollow: a dark hood with
	# two lights inside it, where a face should be.
	var drift: float = sin(pose.clock * 1.8) * 2.0
	var sheet: Color = pal["main"]
	sheet.a *= 0.72
	var sleeve: Color = pal["dark"]
	sleeve.a *= 0.85

	for side in [-1.0, 1.0]:
		var reach := Vector2(15.0 * side, 7.0 + drift)
		if side > 0.0:
			reach += aim * REACH * pose.swing
		_curl(ci, Vector2(7.0 * side, -6.0 + drift), reach, 3.5 * side, 3.4, 0.8,
			sleeve)

	# The robe: shoulders, a hood peak, then a hem torn into spikes. Walked as
	# one ring — down the left, across the hem right to left, back up the right.
	var robe: Array = [
		Vector2(-10.0, -5.0 + drift), Vector2(-8.0, -16.0 + drift),
		Vector2(0.0, -23.0 + drift), Vector2(8.0, -16.0 + drift),
		Vector2(10.0, -5.0 + drift), Vector2(13.0, 7.0 + drift),
	]
	for i in 9:
		var t: float = 1.0 - float(i) / 8.0
		var x: float = lerpf(-13.0, 13.0, t)
		var hem: float = 15.0 + drift + sin(pose.clock * 4.0 + float(i) * 1.9) * 2.0
		robe.append(Vector2(x, hem + (5.5 if i % 2 == 0 else -3.5)))
	robe.append(Vector2(-13.0, 7.0 + drift))
	_shape(ci, PackedVector2Array(robe), sheet)
	if marks.has(&"rope"):
		_mark_rope(ci, pal, pose, Vector2(0.0, drift))

	var hollow: Color = pal["ink"]
	hollow.a = pal["main"].a * 0.9
	_shape(ci, _ellipse(Vector2(0.0, -13.0 + drift), 6.0, 7.5, 12), hollow)

	var glow := Color(0.66, 0.97, 1.0, 0.95 * pal["main"].a)
	for side in [-1.0, 1.0]:
		ci.draw_circle(Vector2(2.7 * side, -14.0 + drift), 1.5, glow)
		if pose.detail > 0.5:
			ci.draw_circle(Vector2(2.7 * side, -14.0 + drift), 2.8,
				Color(glow.r, glow.g, glow.b, 0.22 * pal["main"].a))

	if marks.has(&"hook"):
		_mark_hook(ci, pal, Vector2(-14.0, 7.0 + drift))
	if marks.has(&"beard"):
		_shape(ci, PackedVector2Array([Vector2(-4.5, -8.0 + drift), Vector2(4.5, -8.0 + drift),
			Vector2(2.5, 1.0 + drift), Vector2(0.0, 4.0 + drift),
			Vector2(-2.5, 1.0 + drift)]), sheet)
	if marks.has(&"crown"):
		_mark_crown(ci, pal)
	if marks.has(&"horns"):
		for side in [-1.0, 1.0]:
			_curl(ci, Vector2(6.5 * side, -18.0 + drift),
				Vector2(13.0 * side, -26.0 + drift), 3.0 * side, 2.2, 0.4, pal["bone"])


static func _body_bird(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	# From above, wings beating. The span shortening on the upstroke is the whole
	# illusion of a flap in a flat drawing.
	var flap: float = 0.55 + absf(sin(pose.clock * 7.0)) * 0.45
	for side in [-1.0, 1.0]:
		_curl(ci, Vector2(3.0 * side, -4.0), Vector2(19.0 * side * flap, 6.0),
			-5.0 * side, 5.0, 1.2, pal["main"])
		if pose.detail > 0.5:
			_curl(ci, Vector2(3.0 * side, -4.0), Vector2(15.0 * side * flap, 5.0),
				-4.0 * side, 2.0, 0.6, pal["light"])

	_shape(ci, PackedVector2Array([Vector2(-6.0, 12.0), Vector2(0.0, 16.0), Vector2(6.0, 12.0),
		Vector2(0.0, 8.0)]), pal["dark"])
	_shape(ci, _ellipse(Vector2(0.0, 0.0), 5.5, 11.0, 14), pal["light"])
	_shape(ci, _ellipse(Vector2(0.0, -11.0), 4.2, 4.6, 12), pal["main"])
	_shape(ci, PackedVector2Array([Vector2(-1.8, -14.0), Vector2(1.8, -14.0),
		Vector2(0.0, -20.0 - pose.swing * 3.0)]), Color("e8b44a", pal["main"].a))
	if pose.detail > 0.5:
		ci.draw_circle(Vector2(-2.0, -12.5), 0.9, pal["ink"])
		ci.draw_circle(Vector2(2.0, -12.5), 0.9, pal["ink"])


static func _body_golem(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	var stride: float = sin(pose.clock * 8.0) * 2.0 * pose.moving
	_shape(ci, PackedVector2Array([Vector2(-9.0 - stride, 8.0), Vector2(-2.0 - stride, 8.0),
		Vector2(-2.5 - stride, 17.0), Vector2(-9.5 - stride, 17.0)]), pal["deep"])
	_shape(ci, PackedVector2Array([Vector2(2.0 + stride, 8.0), Vector2(9.0 + stride, 8.0),
		Vector2(9.5 + stride, 17.0), Vector2(2.5 + stride, 17.0)]), pal["deep"])

	_limb(ci, Vector2(-12.0, -6.0), Vector2(-15.0, 6.0), 4.2, 3.6, pal["dark"])
	var fist: Vector2 = Vector2(13.0, -4.0) + aim * REACH * pose.swing
	_limb(ci, Vector2(12.0, -6.0), fist, 4.2, 3.6, pal["dark"])
	ci.draw_circle(fist, 4.6, pal["dark"])

	_shape(ci, PackedVector2Array([Vector2(-12.0, -9.0), Vector2(12.0, -9.0), Vector2(10.0, 11.0),
		Vector2(-10.0, 11.0)]), pal["main"])
	_shape(ci, PackedVector2Array([Vector2(-7.0, -22.0), Vector2(7.0, -22.0), Vector2(6.0, -10.0),
		Vector2(-6.0, -10.0)]), pal["main"])
	if pose.detail > 0.45:
		ci.draw_line(Vector2(-6.0, -4.0), Vector2(-1.0, 2.0), pal["deep"], 1.2)
		ci.draw_line(Vector2(-1.0, 2.0), Vector2(4.0, -1.0), pal["deep"], 1.2)
		ci.draw_line(Vector2(4.0, 4.0), Vector2(8.0, 9.0), pal["deep"], 1.2)
		var lit: float = 0.55 + pose.cast * 0.45
		ci.draw_rect(Rect2(-4.5, -18.0, 9.0, 2.6),
			Color(1.0, 0.72, 0.35, lit * pal["main"].a))
	if marks.has(&"crown"):
		_mark_crown(ci, pal)


static func _body_brute(ci: CanvasItem, pal: Dictionary, pose: Pose,
		aim: Vector2, marks: Array) -> void:
	# Side on, nose to the right; `MIRRORS_TO_AIM` turns the whole thing around
	# when its target is the other way.
	var stride: float = sin(pose.clock * 12.0) * 2.5 * maxf(pose.moving, 0.25)
	_curl(ci, Vector2(-9.0, 4.0), Vector2(-22.0, 6.0 + sin(pose.clock * 4.0) * 4.0),
		3.0, 1.8, 0.4, pal["dark"])
	for i in 4:
		var x: float = -7.0 + i * 5.0
		var swing: float = stride if i % 2 == 0 else -stride
		_limb(ci, Vector2(x, 5.0), Vector2(x + swing, 16.0), 2.0, 1.4, pal["deep"])

	_shape(ci, PackedVector2Array([Vector2(-11.0, 1.0), Vector2(-5.0, -7.0), Vector2(6.0, -7.0),
		Vector2(12.0, 0.0), Vector2(10.0, 9.0), Vector2(-9.0, 9.0)]), pal["main"])
	_shape(ci, _ellipse(Vector2(12.0, -2.0), 6.0, 5.5, 12), pal["light"])
	_shape(ci, PackedVector2Array([Vector2(15.0, -4.0), Vector2(22.0 + pose.swing * 3.0, 0.0),
		Vector2(15.0, 2.5)]), pal["light"])
	_shape(ci, _ellipse(Vector2(8.0, -8.0), 3.2, 3.2, 10), pal["dark"])
	if pose.detail > 0.45:
		ci.draw_circle(Vector2(13.0, -3.5), 1.1, pal["ink"])
		_shape(ci, PackedVector2Array([Vector2(18.0, 1.0), Vector2(20.0, 1.0), Vector2(19.0, 4.5)]),
			pal["bone"])


# --- the things a body holds or wears ----------------------------------------

static func _weapon_cutlass(ci: CanvasItem, pal: Dictionary, hand: Vector2,
		aim: Vector2) -> void:
	ci.draw_circle(hand, 2.2, pal["wood_dark"])
	_curl(ci, hand, hand + aim * 16.0, 3.5, 2.0, 0.4, pal["metal"])


static func _weapon_harpoon(ci: CanvasItem, pal: Dictionary, hand: Vector2,
		aim: Vector2) -> void:
	_limb(ci, hand - aim * 5.0, hand + aim * 14.0, 1.3, 1.0, pal["wood"])
	var tip: Vector2 = hand + aim * 20.0
	_shape(ci, PackedVector2Array([tip, tip - aim * 6.0 + aim.orthogonal() * 3.0,
		tip - aim * 6.0 - aim.orthogonal() * 3.0]), pal["metal"])


static func _weapon_anchor(ci: CanvasItem, pal: Dictionary, hand: Vector2,
		aim: Vector2) -> void:
	# Shank down from the hand, stock across it, and two flukes curling back —
	# drawn as flukes rather than as an arc, because an arc wide enough to read
	# at this size closes into a ring and the anchor becomes a letter.
	var head: Vector2 = hand + aim * 11.0
	var across := aim.orthogonal()
	_limb(ci, hand - aim * 2.0, head, 1.5, 1.3, pal["metal"])
	ci.draw_line(hand + aim * 2.5 - across * 4.5, hand + aim * 2.5 + across * 4.5,
		pal["metal"], 1.8)
	# Triangles, not quads. A four-point fluke drawn from an animated `aim` can
	# fold over itself, and Godot answers a self-intersecting polygon with
	# "triangulation failed" every frame rather than with a wrong shape.
	for side in [-1.0, 1.0]:
		_shape(ci, PackedVector2Array([head + aim * 1.0, head + across * 6.5 * side,
			head + across * 3.0 * side - aim * 5.0]), pal["metal"])
	ci.draw_arc(hand - aim * 4.0, 2.2, 0.0, TAU, 8, pal["metal"], 1.2)


static func _weapon_gun(ci: CanvasItem, pal: Dictionary, pose: Pose, hand: Vector2,
		aim: Vector2, length: float) -> void:
	# A stock as long as the barrel, and a lock between them. A bare pale line is
	# a sword; what says firearm at this size is the wooden half.
	var across := aim.orthogonal()
	_shape(ci, PackedVector2Array([hand - aim * 8.0 - across * 1.4, hand + aim * 4.0 - across * 2.2,
		hand + aim * 4.0 + across * 2.2, hand - aim * 6.0 + across * 3.2]), pal["wood"])
	ci.draw_circle(hand + aim * 3.0, 1.8, pal["metal"])
	_limb(ci, hand + aim * 2.0, hand + aim * length, 1.5, 1.2, pal["metal"])
	if pose.swing > 0.35:
		# The muzzle flash the fx layer draws is at the target's end of the shot;
		# this is the other end, and without it a volley has no source.
		var flash := Color(1.0, 0.86, 0.5, (pose.swing - 0.35) * 1.4 * pal["main"].a)
		ci.draw_circle(hand + aim * (length + 1.5), 3.0 + pose.swing * 2.0, flash)


static func _weapon_spyglass(ci: CanvasItem, pal: Dictionary, hand: Vector2,
		aim: Vector2) -> void:
	_limb(ci, hand, hand + aim * 9.0, 2.4, 1.8, pal["wood"])
	_limb(ci, hand + aim * 9.0, hand + aim * 15.0, 1.9, 1.5, Color("e8b44a",
		pal["main"].a))


static func _mark_hook(ci: CanvasItem, pal: Dictionary, at: Vector2) -> void:
	ci.draw_arc(at + Vector2(0.0, 2.0), 3.6, PI * 0.85, TAU, 10, pal["metal"], 2.0)


static func _mark_crown(ci: CanvasItem, pal: Dictionary) -> void:
	var gold := Color("f0c85c", pal["main"].a)
	_shape(ci, PackedVector2Array([Vector2(-7.0, -20.0), Vector2(-7.0, -27.0), Vector2(-3.5, -23.5),
		Vector2(0.0, -28.5), Vector2(3.5, -23.5), Vector2(7.0, -27.0),
		Vector2(7.0, -20.0)]), gold)


static func _mark_parrot(ci: CanvasItem, pal: Dictionary, pose: Pose) -> void:
	var perch := Vector2(-10.5, -12.0)
	var body := Color("3fbf6a", pal["main"].a)
	_shape(ci, _ellipse(perch, 3.0, 4.0, 10), body)
	_shape(ci, _ellipse(perch + Vector2(-0.5, -4.5), 2.4, 2.4, 8), body)
	_shape(ci, PackedVector2Array([perch + Vector2(-2.5, -5.0), perch + Vector2(-6.0, -3.8),
		perch + Vector2(-2.5, -2.8)]), Color("e8b44a", pal["main"].a))
	_limb(ci, perch + Vector2(1.5, 2.0), perch + Vector2(5.0, 6.0 +
		sin(pose.clock * 3.0)), 1.6, 0.5, Color("d8455e", pal["main"].a))


static func _mark_lantern(ci: CanvasItem, pal: Dictionary, pose: Pose,
		at: Vector2) -> void:
	var swing: float = sin(pose.clock * 2.4) * 1.5
	var box := at + Vector2(swing, 5.0)
	ci.draw_line(at, box, pal["metal"], 0.9)
	var lit: float = 0.65 + sin(pose.clock * 6.0) * 0.2
	_shape(ci, PackedVector2Array([box + Vector2(-2.6, 0.0), box + Vector2(2.6, 0.0),
		box + Vector2(2.2, 4.6), box + Vector2(-2.2, 4.6)]),
		Color(1.0, 0.82, 0.42, lit * pal["main"].a))


static func _mark_keg(ci: CanvasItem, pal: Dictionary, at: Vector2) -> void:
	_shape(ci, PackedVector2Array([at + Vector2(-4.0, -4.5), at + Vector2(4.0, -4.5),
		at + Vector2(5.0, 0.0), at + Vector2(4.0, 4.5), at + Vector2(-4.0, 4.5),
		at + Vector2(-5.0, 0.0)]), pal["wood"])
	ci.draw_line(at + Vector2(-4.6, -1.6), at + Vector2(4.6, -1.6), pal["metal"], 1.0)
	ci.draw_line(at + Vector2(-4.6, 1.6), at + Vector2(4.6, 1.6), pal["metal"], 1.0)


## Tidecaller, and the other half of why `storm` is drawn out here rather than by
## a body: Calypso and Thalassa are both, so the two have to be able to land on
## one figure. The storm crackles at the upper corners; this takes the bottom of
## the figure, and the two never meet.
##
## **It is a change to the outline rather than a badge, and that is the point.**
## Seven smaller marks were tried first and every one failed the same way: at the
## 43-point hex a phone gives a unit there is no room for a symbol. A wave glyph
## on the brow read as ski goggles, a pool inside the cost rim and two swells at
## the ankles were too quiet to find, a crest either side of the body read as
## wings, a curling wave read as a tentacle, and a scallop shell needed a
## hand-placed position per body and still landed mid-flank on the shark.
## Silhouette is the one channel this project has actually proved survives that
## size - it is why the `officer` reads - so the mark is a Tidecaller standing in
## water rather than wearing a picture of it.
##
## Translucent on purpose. The cost rim `_draw_ground` puts under every unit, the
## boots, and a siren's tail all have to stay legible through it; the first pass
## at 0.88 buried all three.
static func _mark_tide(ci: CanvasItem, pal: Dictionary, pose: Pose) -> void:
	var alpha: float = pal["main"].a
	if alpha <= 0.02:
		return
	var crest := PackedVector2Array()
	for i in 13:
		crest.append(Vector2(lerpf(-16.5, 16.5, float(i) / 12.0),
			9.0 + sin(float(i) * 1.15 + pose.clock * 2.0) * 2.2))
	# Walked across the crest left to right and back along a floor well below the
	# lowest any crest can dip, so a ring whose top edge comes out of a sine can
	# never close on itself. Same rule as the shark's underside band.
	var poly := PackedVector2Array(crest)
	poly.append(Vector2(16.5, 18.5))
	poly.append(Vector2(-16.5, 18.5))
	_shape(ci, poly, Color(0.19, 0.75, 0.74, 0.55 * alpha))
	# The foam is what actually does the reading, so it is never detail-gated.
	ci.draw_polyline(crest, Color(0.82, 1.0, 0.96, 0.95 * alpha), 1.5)


## Bosun — a coil of rope worn as a bandolier.
##
## **Drawn by each body rather than by `draw_unit`, and that is the whole point
## of it.** `storm` and `tide` are drawn after the body dispatch because they are
## weather and belong on top of everything; a bandolier is worn, so it sits over
## the coat and *under* the arm that swings and under whatever the champion is
## holding. Old Anchor Ned's anchor passes in front of it. A strap painted on top
## of the finished figure is a sticker, not a thing the pirate is wearing.
##
## Diagonal is most of why it reads at a 43-point hex: it is the one direction
## nothing else in the game uses, so it cannot be taken for the belt, the tide's
## crest or the storm's bolts, which are all horizontal or vertical.
##
## `offset` exists for the wraith, whose whole body drifts on the clock — a
## bandolier that ignored the drift would swim about on the robe.
static func _mark_rope(ci: CanvasItem, pal: Dictionary, pose: Pose,
		offset: Vector2 = Vector2.ZERO) -> void:
	var alpha: float = pal["main"].a
	if alpha <= 0.02:
		return
	var hemp := Color(0.82, 0.72, 0.48, 0.97 * alpha)
	var shade := Color(0.46, 0.38, 0.24, 0.9 * alpha)
	var top: Vector2 = Vector2(9.0, -11.0) + offset
	var hip: Vector2 = Vector2(-7.5, 4.5) + offset
	_limb(ci, top, hip, 2.5, 2.2, hemp)
	ci.draw_arc(hip + Vector2(-1.8, 1.8), 3.0, 0.0, TAU, 12, hemp, 1.7)
	if pose.detail > 0.45:
		for i in 4:
			var at: Vector2 = top.lerp(hip, 0.18 + float(i) * 0.22)
			ci.draw_line(at + Vector2(-1.2, -1.0), at + Vector2(1.2, 1.0), shade, 0.8)


## The same rope on a body with no shoulder to sling it over. A shark wears it
## round the girth, under the fins, the way a working animal wears a harness.
## The sash was tried here first and a diagonal band across a fish drawn in
## profile is a loaf strapped to it: the shark's long axis is horizontal, so the
## one direction that reads as "worn" on a standing figure reads as cargo here.
static func _mark_rope_girth(ci: CanvasItem, pal: Dictionary, pose: Pose) -> void:
	var alpha: float = pal["main"].a
	if alpha <= 0.02:
		return
	var hemp := Color(0.82, 0.72, 0.48, 0.97 * alpha)
	var shade := Color(0.46, 0.38, 0.24, 0.9 * alpha)
	var top := Vector2(4.5, -8.0)
	var belly := Vector2(2.0, 6.6)
	_limb(ci, top, belly, 2.4, 2.2, hemp)
	if pose.detail > 0.45:
		for i in 4:
			var at: Vector2 = top.lerp(belly, 0.15 + float(i) * 0.23)
			ci.draw_line(at + Vector2(-1.3, -0.8), at + Vector2(1.3, 0.8), shade, 0.8)
		ci.draw_circle(Vector2(3.7, -1.6), 1.5, shade)


## Drawn outside the body dispatch, so a storm crackles over a siren, a gunner
## and a serpent alike without any of them knowing about it.
static func _mark_storm(ci: CanvasItem, pal: Dictionary, pose: Pose) -> void:
	if pose.detail < 0.4:
		return
	var flicker: float = absf(sin(pose.clock * 3.7))
	var bright := Color(0.66, 0.9, 1.0, (0.35 + flicker * 0.55) * pal["main"].a)
	for side in [-1.0, 1.0]:
		var top := Vector2(9.0 * side, -26.0)
		ci.draw_polyline(PackedVector2Array([top, top + Vector2(-2.0 * side, 3.5),
			top + Vector2(1.5 * side, 4.0), top + Vector2(-1.0 * side, 8.0)]),
			bright, 1.4)
