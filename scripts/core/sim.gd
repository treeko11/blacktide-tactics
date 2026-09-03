class_name Sim
extends RefCounted

## The battle simulation.
##
## Fixed timestep, no engine ties, no nodes. `step()` advances exactly one tick
## and nothing else moves the clock — the renderer accumulates real time and
## calls it, so 1x and 4x speed produce the identical fight and a headless bot
## match costs nothing to run. Every round resolves six of those alongside the
## one the player watches.
##
## The renderer learns what happened by draining `fx_queue`. The sim never
## touches the scene tree, so anything here can be tested by stepping it and
## reading the numbers back.
##
## Randomness comes from `rng`, seeded per fight, so a reported battle can be
## replayed exactly by reusing the seed.

const TICK := 1.0 / 30.0
const TIME_LIMIT := 42.0

## Overtime: the pressure that makes a fight end.
##
## Nothing else in the sim forces a resolution, so a fight that neither side can
## close ran to `TIME_LIMIT` and was handed to whoever had more health left — a
## result nobody watched happen. Measured over even boards, one fight in six
## ended that way, and one in three once both sides were three-star, because the
## star curve grows health (x3.24) faster than it grows ability damage (x2.67):
## the longer a run goes, the harder its fights are to finish.
##
## From `OVERTIME_START` every hit lands harder and every heal lands softer,
## reaching full effect at `OVERTIME_FULL`. It is symmetric, so it decides
## nothing — it removes the stalemate and leaves the better board winning.
const OVERTIME_START := 14.0
const OVERTIME_FULL := 28.0
const OVERTIME_DAMAGE := 1.5   ## +150% damage at full ramp
const OVERTIME_HEAL_CUT := 0.9 ## -90% healing and shielding at full ramp
const BASE_CRIT := 0.25
const BASE_CRIT_DAMAGE := 1.4
const MOVE_TIME := 0.34   ## seconds to cross one hex
const CAST_TIME := 0.22
const ATTACK_SPEED_CAP := 5.0

## Mana gained from landing an attack, and the cap on mana gained from one hit.
const MANA_PER_ATTACK := 10.0
const MANA_FROM_DAMAGE_CAP := 42.5

## Floating healing numbers are coalesced per unit.
##
## Every regeneration in the game — Hull of the Deep, the Tidecaller tide, the
## Navy's recovery — pays out through `heal()` once per tick, thirty times a
## second. One popup per call meant a 4,500 HP three-star under Tidecaller
## reporting "+6" thirty times a second on one hex: the same healing, drawn as
## noise, and unreadable next to the damage numbers it is racing. Worse, it was
## silent below 1 HP a tick, so whether regeneration was visible at all was a
## fact about the healed unit's max health rather than about the healing.
##
## So a heal big enough to read on its own shows at once, and anything smaller
## is banked until it is worth a number or the window is up — a trickle reports
## itself around once a second, at the figure it actually healed for.
const HEAL_POPUP_FRACTION := 0.02 ## a heal worth this much of max HP shows at once
const HEAL_POPUP_MIN := 8.0       ## ...but never a lower bar than this
const HEAL_POPUP_WINDOW := 0.8    ## seconds a banked trickle waits to be shown

enum Team { PLAYER = 0, ENEMY = 1 }
enum Result { DRAW = -1, PLAYER_WIN = 0, ENEMY_WIN = 1 }

## How each archetype presents its basic attack. The renderer turns these into
## muzzle flashes, projectiles and directional impacts; the sim only names one.
##
## This exists because every attack looking identical — a line for ranged, a ring
## for melee — made fights unreadable. You could not tell a gunner volley from a
## siren's cast without reading the health bars.
const ATTACK_STYLES := {
	&"bullet":   { "color": Color("ffd9a0"), "ranged": true },
	&"cannon":   { "color": Color("ffb15c"), "ranged": true },
	&"bolt":     { "color": Color("cfe8ff"), "ranged": true },
	&"harpoon":  { "color": Color("b6ffce"), "ranged": true },
	&"orb":      { "color": Color("9ec6ff"), "ranged": true },
	&"spark":    { "color": Color("8fd4ff"), "ranged": true },
	&"wisp":     { "color": Color("c9a2ff"), "ranged": true },
	&"slash":    { "color": Color("ffffff"), "ranged": false },
	&"crush":    { "color": Color("ffc98a"), "ranged": false },
	&"claw":     { "color": Color("ff9db0"), "ranged": false },
	&"spectral": { "color": Color("c9a2ff"), "ranged": false },
}

## Monsters have no traits to derive a style from, so they name one directly.
const CREEP_STYLES := {
	&"rat": &"claw", &"crab": &"crush", &"gull": &"orb", &"serpent": &"claw",
	&"skiff": &"wisp", &"golem": &"crush", &"elder": &"orb",
}

var content: Node = null
var render: bool = false
var rng := RandomNumberGenerator.new()

var time: float = 0.0
var done: bool = false
var winner: int = Result.DRAW

var units: Array[SimUnit] = []
var teams: Array = [[], []]
## Active traits per team: { "id": StringName, "count": int, "tier": int }
var active_traits: Array = [[], []]

## The sea state this fight is being fought in, and the hexes it touches. Empty
## for every round that is not the stage's one weather round. The cells are
## handed in rather than drawn here — see `SeaEffect` for why.
var sea_id: StringName = &""
var sea_cells: Array[Vector2i] = []

## Effects the renderer has not drawn yet.
var fx_queue: Array[Dictionary] = []

## Cell key -> SimUnit, so occupancy is a lookup rather than a scan.
var _occupied: Dictionary = {}
## { "at": float, "call": Callable } — one-shot delayed callbacks.
var _events: Array[Dictionary] = []
## { "next": float, "interval": float, "call": Callable } — repeating ones.
var _timers: Array[Dictionary] = []
var _next_uid: int = 1


## `board_a` and `board_b` are arrays of { "champion", "star", "items", "cell" }.
## Team B's formation is mirrored onto the top half here, so both sides author
## their board in the same coordinates.
func _init(content_node: Node, board_a: Array, board_b: Array,
		should_render: bool = false, seed_value: int = 0,
		sea: StringName = &"", sea_hexes: Array[Vector2i] = []) -> void:
	content = content_node
	render = should_render
	sea_id = sea
	sea_cells = sea_hexes
	rng.seed = seed_value if seed_value != 0 else randi()

	for entry in board_a:
		_spawn(entry, Team.PLAYER, false)
	for entry in board_b:
		_spawn(entry, Team.ENEMY, true)

	for u in units:
		_occupied[Hex.key(u.cell)] = u

	# Items before traits, so a trait's percentage bonus applies to the stats an
	# item just added rather than to the bare champion.
	for u in units:
		for item_id in u.items:
			var effect: Variant = content.item_effect(item_id)
			if effect != null:
				effect.apply(self, u)

	for t in 2:
		_apply_traits(t)

	# The weather goes on last, so a cap it imposes is a real cap rather than
	# something a trait bonus can be stacked over the top of.
	_apply_sea()

	for u in units:
		u.attack_speed = minf(u.attack_speed, ATTACK_SPEED_CAP)
		u.hp = u.max_hp
		u.recalc_shield()


func _spawn(entry: Dictionary, team: int, mirrored: bool) -> void:
	var def: ChampionDef = entry.get("champion")
	if def == null:
		var champ_id: StringName = entry.get("champion_id", &"")
		def = content.champion(champ_id)
	if def == null:
		return

	var u := SimUnit.new()
	u.uid = _next_uid
	_next_uid += 1
	u.def = def
	u.star = entry.get("star", 1)
	u.team = team
	u.items.assign(entry.get("items", []))

	var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
	u.cell = Hex.mirror(cell) if mirrored else cell
	u.home = u.cell
	u.pos = Hex.to_pixel(u.cell)

	var stats := def.stats_at(u.star)
	u.max_hp = stats["max_hp"]
	u.hp = u.max_hp
	u.ad = stats["ad"]
	u.attack_speed = stats["attack_speed"]
	u.armor = stats["armor"]
	u.magic_resist = stats["magic_resist"]
	u.attack_range = stats["attack_range"]
	u.mana = stats["mana_start"]
	u.max_mana = stats["mana_max"]
	u.crit = BASE_CRIT
	u.crit_damage = BASE_CRIT_DAMAGE

	units.append(u)
	teams[team].append(u)


# --- Traits ------------------------------------------------------------------

## Counts *distinct champions* per trait, not bodies, then runs the effect script
## for every trait that reached a breakpoint.
func _apply_traits(team_id: int) -> void:
	var seen: Dictionary = {}
	for u in teams[team_id]:
		for trait_id in u.def.traits:
			if not seen.has(trait_id):
				seen[trait_id] = {}
			seen[trait_id][u.def.id] = true

	for trait_id in seen:
		var count: int = seen[trait_id].size()
		var def: TraitDef = content.trait_def(trait_id)
		if def == null:
			continue
		var tier := def.tier_for(count)
		if tier < 0:
			continue

		var holders: Array[SimUnit] = []
		for u in teams[team_id]:
			if u.def.has_trait(trait_id):
				holders.append(u)

		active_traits[team_id].append({ "id": trait_id, "count": count, "tier": tier })

		var effect: Variant = content.trait_effect(trait_id)
		if effect != null:
			effect.apply(self, {
				"def": def, "team": teams[team_id], "holders": holders,
				"tier": tier, "count": count, "team_id": team_id,
			})


## Hands the round's sea state its fight, if there is one.
func _apply_sea() -> void:
	if sea_id == &"":
		return
	var def: Variant = content.sea(sea_id)
	var effect: Variant = content.sea_effect(sea_id)
	if def == null or effect == null:
		push_error("Sim: no sea '%s'" % sea_id)
		return
	effect.apply(self, { "def": def, "cells": sea_cells })


func traits_of(team_id: int) -> Array:
	return active_traits[team_id]


# --- Queries -----------------------------------------------------------------

func distance(a: SimUnit, b: SimUnit) -> int:
	return Hex.distance(a.cell, b.cell)


func living_allies(team_id: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for u in teams[team_id]:
		if u.alive:
			out.append(u)
	return out


func living_enemies(team_id: int) -> Array[SimUnit]:
	return living_allies(1 - team_id)


func enemies_near(origin: SimUnit, radius: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for u in living_enemies(origin.team):
		if u != origin and Hex.distance(u.cell, origin.cell) <= radius:
			out.append(u)
	return out


## Enemies of `team_id` within `radius` of a cell.
##
## Separate from `enemies_near` because an ability that splashes around its
## *target* is asking about the caster's enemies, not the target's — and the
## target's enemies are the caster's own fleet. Getting that backwards silently
## turns a nuke into a friendly-fire incident.
func enemies_near_cell(team_id: int, cell: Vector2i, radius: int,
		exclude: SimUnit = null) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for u in living_enemies(team_id):
		if u != exclude and Hex.distance(u.cell, cell) <= radius:
			out.append(u)
	return out


func allies_near(origin: SimUnit, radius: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for u in living_allies(origin.team):
		if Hex.distance(u.cell, origin.cell) <= radius:
			out.append(u)
	return out


func nearest_enemies(u: SimUnit, count: int) -> Array[SimUnit]:
	var foes := living_enemies(u.team)
	foes.sort_custom(func(a, b): return distance(u, a) < distance(u, b))
	return foes.slice(0, count)


func lowest_enemy(team_id: int) -> SimUnit:
	var best: SimUnit = null
	for u in living_enemies(team_id):
		if best == null or u.hp < best.hp:
			best = u
	return best


func lowest_ally(team_id: int) -> SimUnit:
	var best: SimUnit = null
	for u in living_allies(team_id):
		if best == null or u.health_fraction() < best.health_fraction():
			best = u
	return best


func farthest_enemy(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	for f in living_enemies(u.team):
		if best == null or distance(u, f) > distance(u, best):
			best = f
	return best


## The unit's current target, reacquiring if it died.
func pick_target(u: SimUnit) -> SimUnit:
	if u.target != null and u.target.alive:
		return u.target
	return acquire(u)


## The cell covering the most enemies, for abilities that want a good landing
## spot rather than a target. Returns {} when there is nobody left to hit.
func best_cluster(team_id: int, radius: int) -> Dictionary:
	var foes := living_enemies(team_id)
	if foes.is_empty():
		return {}
	var best: Dictionary = {}
	var best_count := -1
	for r in Hex.ROWS:
		for c in Hex.COLS:
			var cell := Vector2i(c, r)
			var caught: Array[SimUnit] = []
			for f in foes:
				if Hex.distance(f.cell, cell) <= radius:
					caught.append(f)
			if caught.size() > best_count:
				best_count = caught.size()
				best = { "cell": cell, "pos": Hex.to_pixel(cell), "units": caught }
	return best if best_count > 0 else {}


## Enemies inside a rectangle from `src` through `target`, `length` hexes long.
func line_targets(src: SimUnit, target: SimUnit, length: float) -> Array[SimUnit]:
	var delta := target.pos - src.pos
	var dir := delta.normalized() if delta.length() > 0.001 else Vector2.RIGHT
	var max_d := length * Hex.HEX_W
	var out: Array[SimUnit] = []
	for e in living_enemies(src.team):
		var rel := e.pos - src.pos
		var along := rel.dot(dir)
		if along < 0.0 or along > max_d:
			continue
		if absf(rel.cross(dir)) < Hex.HEX_W * 0.62:
			out.append(e)
	return out


# --- Board occupancy ---------------------------------------------------------

func cell_free(cell: Vector2i) -> bool:
	return Hex.on_board(cell) and not _occupied.has(Hex.key(cell))


func unit_at(cell: Vector2i) -> SimUnit:
	return _occupied.get(Hex.key(cell))


## Teleports a unit, keeping occupancy and pixel position in step.
func place(u: SimUnit, cell: Vector2i) -> void:
	_occupied.erase(Hex.key(u.cell))
	u.cell = cell
	_occupied[Hex.key(cell)] = u
	u.pos = Hex.to_pixel(cell)
	u.is_moving = false


## Nearest free cell to `cell`, optionally breaking ties toward another unit.
func free_cell_near(cell: Vector2i, prefer: SimUnit = null) -> Vector2i:
	if cell_free(cell):
		return cell
	var best := Vector2i(-1, -1)
	var best_score := INF
	for r in Hex.ROWS:
		for c in Hex.COLS:
			var candidate := Vector2i(c, r)
			if not cell_free(candidate):
				continue
			var score := float(Hex.distance(candidate, cell) * 10)
			if prefer != null:
				score += Hex.distance(candidate, prefer.cell)
			if score < best_score:
				best_score = score
				best = candidate
	return best


## A free cell beside `around`, preferring the side nearest `toward`.
func adjacent_free(around: SimUnit, toward: SimUnit = null) -> Vector2i:
	var options: Array[Vector2i] = []
	for n in Hex.neighbours(around.cell):
		if cell_free(n):
			options.append(n)
	if options.is_empty():
		return Vector2i(-1, -1)
	if toward == null:
		return options[0]
	options.sort_custom(func(a, b):
		return Hex.distance(a, toward.cell) < Hex.distance(b, toward.cell))
	return options[0]


## Blink `u` next to `target`.
func blink_near(u: SimUnit, target: SimUnit) -> void:
	var cell := adjacent_free(target, u)
	if cell.x >= 0:
		place(u, cell)
		fx(&"blink", u, null, Color.WHITE)


## Drag `target` next to `anchor`.
func pull_to(anchor: SimUnit, target: SimUnit) -> void:
	var cell := adjacent_free(anchor, target)
	if cell.x >= 0:
		place(target, cell)


# --- Scheduling --------------------------------------------------------------

## Runs `call` once, `seconds` from now, in sim time.
func delay(seconds: float, callback: Callable) -> void:
	_events.append({ "at": time + seconds, "call": callback })


func add_timer(first: float, interval: float, callback: Callable) -> void:
	_timers.append({ "next": time + first, "interval": interval, "call": callback })


# --- Effects the renderer draws ----------------------------------------------

## Queues a visual. Skipped entirely when the fight is headless, which is most
## of them — six bot fights resolve every round and none is ever seen.
func fx(kind: StringName, at: SimUnit, from: SimUnit = null,
		color: Color = Color.WHITE, extra: Dictionary = {}) -> void:
	if not render or at == null:
		return
	var entry := {
		"kind": kind,
		"at": at.pos,
		"from": from.pos if from != null else Vector2.INF,
		"color": color,
	}
	for k in extra:
		entry[k] = extra[k]
	fx_queue.append(entry)


## Queues a visual at a raw board position rather than on a unit.
func fx_at(kind: StringName, at: Vector2, color: Color = Color.WHITE,
		extra: Dictionary = {}) -> void:
	if not render:
		return
	var entry := { "kind": kind, "at": at, "from": Vector2.INF, "color": color }
	for k in extra:
		entry[k] = extra[k]
	fx_queue.append(entry)


func float_text(u: SimUnit, text: String, style: StringName = &"") -> void:
	if not render:
		return
	fx_queue.append({ "kind": &"text", "at": u.pos, "text": text, "style": style })


## Short label above a unit announcing an item or trait proc. Item effects were
## invisible in play — the numbers changed and nothing said why.
func proc_text(u: SimUnit, text: String) -> void:
	float_text(u, text, &"proc")


func attack_style_for(def: ChampionDef) -> StringName:
	if CREEP_STYLES.has(def.id):
		return CREEP_STYLES[def.id]
	if def.attack_range > 1:
		if def.has_trait(&"gunner"): return &"bullet"
		if def.has_trait(&"harpooner"): return &"harpoon"
		if def.has_trait(&"stormborn"): return &"spark"
		if def.has_trait(&"ghost"): return &"wisp"
		if def.has_trait(&"siren") or def.has_trait(&"tidecaller"): return &"orb"
		if def.has_trait(&"bosun") or def.has_trait(&"leviathan"): return &"cannon"
		return &"bolt"
	if def.has_trait(&"bosun") or def.has_trait(&"leviathan"): return &"crush"
	if def.has_trait(&"ghost"): return &"spectral"
	if def.has_trait(&"reaver") or def.has_trait(&"harpooner"): return &"claw"
	return &"slash"


# --- Buffs and statuses ------------------------------------------------------

func add_shield(u: SimUnit, amount: float, duration: float) -> void:
	if not u.alive:
		return
	# Shielding is healing by another name as far as a stalemate is concerned.
	var amt := amount * (1.0 - OVERTIME_HEAL_CUT * overtime())
	u.shields.append({ "amount": amt, "time": duration, "tide": false })
	u.recalc_shield()


## Multiplies a stat for a duration.
##
## The value is not clamped here. The attack-speed cap is applied where attack
## speed is *used*, so removing the buff always restores the original number
## exactly — clamping on the way in loses the difference and leaves the unit
## permanently slower than it started.
func add_buff(u: SimUnit, stat: StringName, mult: float, duration: float) -> void:
	u.set(stat, u.get(stat) * mult)
	u.buffs.append({ "stat": stat, "mult": mult, "time": duration })


func add_flat(u: SimUnit, stat: StringName, amount: float, duration: float) -> void:
	u.set(stat, u.get(stat) + amount)
	u.flats.append({ "stat": stat, "amount": amount, "time": duration })


func add_max_hp(u: SimUnit, amount: float) -> void:
	u.max_hp += amount
	u.hp += amount


func add_temp_omnivamp(u: SimUnit, value: float, duration: float) -> void:
	u.temp_omnivamp = value
	u.temp_omnivamp_time = duration


func stun(u: SimUnit, duration: float) -> void:
	if not u.alive:
		return
	u.stun_time = maxf(u.stun_time, duration)
	fx(&"stun", u, null, Color("ffe07a"))


func apply_shred(u: SimUnit, pct: float, duration: float) -> void:
	u.rend = maxf(u.rend, pct)
	u.rend_time = maxf(u.rend_time, duration)


func apply_shred_mr(u: SimUnit, pct: float, duration: float) -> void:
	u.shred_mr = maxf(u.shred_mr, pct)
	u.shred_mr_time = maxf(u.shred_mr_time, duration)


## Burns do not stack — a fresh application replaces the old one, along with the
## healing cut that rides with it.
func apply_burn(u: SimUnit, pct_per_second: float, duration: float, source: SimUnit) -> void:
	u.burns = [{ "pct": pct_per_second, "time": duration, "tick": 1.0, "source": source }]
	u.heal_cut = 0.33
	u.heal_cut_time = duration


func heal_over_time(u: SimUnit, amount: float, duration: float) -> void:
	u.regen_queue.append({ "amount": amount, "time": duration })


func grant_revive(team_id: int, pct: float, duration: float) -> void:
	for u in teams[team_id]:
		u.revive = { "pct": pct, "used": false, "until": time + duration }


# --- Damage and healing ------------------------------------------------------

## The one place damage is applied. Returns the amount actually dealt.
##
## Order is: amplifiers, crit, resistances, flat reduction, then shields before
## health. Mana is gained from being hit, scaled off both the pre- and
## post-mitigation figure, so a tank behind armour still charges its ability.
func damage(src: SimUnit, target: SimUnit, amount: float, type: StringName,
		options: Dictionary = {}) -> float:
	if target == null or not target.alive or amount <= 0.0:
		return 0.0

	var amt := amount * (1.0 + OVERTIME_DAMAGE * overtime())
	if src != null:
		amt *= 1.0 + src.damage_amp
		if src.execute_amp > 0.0 and target.health_fraction() < 0.5:
			amt *= 1.0 + src.execute_amp

	var is_crit := false
	var can_crit: bool = options.get("is_attack", false) or options.get("can_crit", false)
	if src != null and can_crit and rng.randf() < src.crit:
		is_crit = true
		amt *= src.crit_damage
		fx(&"crit", target, src, Color("ff9d5c"))

	var pre := amt
	var pen: float = options.get("penetration", 0.0)
	if type == &"physical":
		var res: float = target.armor * (1.0 - target.rend) * (1.0 - pen)
		amt *= 100.0 / (100.0 + maxf(0.0, res))
	elif type == &"magic":
		var res: float = target.magic_resist * (1.0 - target.shred_mr) * (1.0 - pen)
		amt *= 100.0 / (100.0 + maxf(0.0, res))
	amt *= 1.0 - target.damage_reduction
	amt = maxf(0.0, amt)

	# Shields soak first, oldest first.
	var remaining := amt
	while remaining > 0.0 and not target.shields.is_empty():
		var s: Dictionary = target.shields[0]
		var used: float = minf(s["amount"], remaining)
		s["amount"] -= used
		remaining -= used
		if s["amount"] <= 0.001:
			target.shields.pop_front()
	target.recalc_shield()
	target.hp -= remaining

	if src != null:
		src.damage_dealt += amt
	target.damage_taken += amt

	var style := &"damage"
	if type == &"magic":
		style = &"magic"
	elif type == &"true":
		style = &"true"
	elif is_crit:
		style = &"crit"
	float_text(target, "%d%s" % [roundi(amt), "!" if is_crit else ""], style)

	target.gain_mana(minf(MANA_FROM_DAMAGE_CAP, pre * 0.01 + amt * 0.07))

	for hook in target.hooks_on_damaged:
		hook.call(target, amt, src)

	if src != null and src.alive:
		var vamp := src.omnivamp + src.temp_omnivamp
		if vamp > 0.0:
			heal(src, src, amt * vamp)

	if target.hp <= 0.0:
		if src != null:
			for hook in src.hooks_on_kill:
				hook.call(src, target)
		kill(target, src)

	return amt


## Straight to zero, ignoring shields — the Leviathan devour finisher.
func execute(src: SimUnit, target: SimUnit) -> void:
	if not target.alive:
		return
	# Counted for the meter as the effective health it removed. Without this the
	# one ability that deletes a full-health tank reads as having done nothing.
	var removed := maxf(0.0, target.hp) + target.shield
	if src != null:
		src.damage_dealt += removed
	target.damage_taken += removed
	target.hp = 0.0
	target.shields.clear()
	target.shield = 0.0
	float_text(target, "DEVOURED", &"execute")
	if src != null:
		for hook in src.hooks_on_kill:
			hook.call(src, target)
	kill(target, src)


func heal(src: SimUnit, target: SimUnit, amount: float) -> float:
	if target == null or not target.alive or amount <= 0.0:
		return 0.0
	var amt := amount * (1.0 - OVERTIME_HEAL_CUT * overtime())
	if target.heal_cut_time > 0.0:
		amt *= 1.0 - target.heal_cut
	var before := target.hp
	target.hp = minf(target.max_hp, target.hp + amt)
	var done_amount := target.hp - before
	if src != null:
		src.healing_done += done_amount
	_bank_heal_popup(target, done_amount)
	return done_amount


## Banks healing towards one floating number rather than drawing a number per
## heal. See `HEAL_POPUP_FRACTION` for why. A heal that carries its own weight
## shows immediately and takes whatever was banked with it.
##
## Nothing in the fight reads any of this, and it is only banked while the sim
## is being rendered — so the six fights a round that nobody watches pay for it
## exactly what they pay for `fx()`, which is nothing.
func _bank_heal_popup(u: SimUnit, amount: float) -> void:
	if not render or amount <= 0.0:
		return
	u.heal_popup += amount
	if u.heal_popup >= maxf(HEAL_POPUP_MIN, u.max_hp * HEAL_POPUP_FRACTION):
		_show_heal_popup(u)


## Draws what is banked, if it is worth a number. Healing that does not yet
## round to 1 keeps its bank and restarts the clock instead of being thrown
## away — a slow trickle should arrive late, not never.
func _show_heal_popup(u: SimUnit) -> void:
	u.heal_popup_time = 0.0
	var shown := roundi(u.heal_popup)
	if shown < 1:
		return
	u.heal_popup = 0.0
	float_text(u, "+%d" % shown, &"heal")


func kill(u: SimUnit, src: SimUnit = null) -> void:
	if not u.alive:
		return
	u.alive = false
	u.hp = 0.0
	u.shields.clear()
	u.shield = 0.0
	u.is_moving = false
	u.target = null
	_occupied.erase(Hex.key(u.cell))
	fx(&"death", u, null, Color("20303c"))

	for hook in u.hooks_on_death:
		hook.call(u, src)

	if u.revive.is_empty() or u.revive.get("used", false):
		return
	if u.revive.has("until") and time > u.revive["until"]:
		return
	u.revive["used"] = true
	u.pending_revive = true
	var pct: float = u.revive["pct"]
	delay(1.5, func(): respawn(u, pct))


func respawn(u: SimUnit, pct: float) -> void:
	u.pending_revive = false
	var cell := free_cell_near(u.home)
	if cell.x < 0:
		return
	u.alive = true
	u.hp = maxf(1.0, u.max_hp * pct)
	u.mana = 0.0
	u.stun_time = 0.0
	u.casting = 0.0
	u.attack_timer = 0.0
	u.burns.clear()
	u.rend = 0.0
	u.shred_mr = 0.0
	place(u, cell)
	fx(&"revive", u, null, Color("8fffc0"))
	float_text(u, "RISEN", &"heal")


## Brings back the most valuable fallen ally.
func revive_best(team_id: int, pct: float) -> void:
	var dead: Array[SimUnit] = []
	for u in teams[team_id]:
		if not u.alive and not u.pending_revive:
			dead.append(u)
	if dead.is_empty():
		return
	dead.sort_custom(func(a, b):
		return a.def.cost * a.star > b.def.cost * b.star)
	var u: SimUnit = dead[0]
	u.pending_revive = true
	respawn(u, pct)


# --- Movement ----------------------------------------------------------------

## Nearest living enemy, health breaking ties.
func acquire(u: SimUnit) -> SimUnit:
	var foes := living_enemies(u.team)
	if foes.is_empty():
		u.target = null
		return null
	var best: SimUnit = null
	var best_score := INF
	for f in foes:
		var score := distance(u, f) * 100.0 + f.hp / 1000.0
		if score < best_score:
			best_score = score
			best = f
	u.target = best
	return best


## First step of a breadth-first path toward a target, stopping as soon as the
## unit would be in range rather than walking all the way onto it.
##
## Returns (-1, -1) when boxed in.
func step_toward(u: SimUnit, target: SimUnit) -> Vector2i:
	var goal_key := Hex.key(target.cell)
	var came_from: Dictionary = { Hex.key(u.cell): Vector2i(-1, -1) }
	var queue: Array[Vector2i] = [u.cell]
	var found := Vector2i(-1, -1)

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current != u.cell and Hex.distance(current, target.cell) <= u.attack_range:
			found = current
			break
		for n in Hex.neighbours(current):
			var k := Hex.key(n)
			if came_from.has(k):
				continue
			# The goal's own cell is walkable in the search so a path exists even
			# when the target is the thing blocking it.
			if k != goal_key and _occupied.has(k):
				continue
			came_from[k] = current
			queue.append(n)

	if found.x < 0:
		# Boxed in: take whichever neighbour closes the gap most.
		var options: Array[Vector2i] = []
		for n in Hex.neighbours(u.cell):
			if cell_free(n):
				options.append(n)
		if options.is_empty():
			return Vector2i(-1, -1)
		options.sort_custom(func(a, b):
			return Hex.distance(a, target.cell) < Hex.distance(b, target.cell))
		return options[0]

	# Walk the path back to the step adjacent to where we started.
	var cursor := found
	while true:
		var prev: Vector2i = came_from[Hex.key(cursor)]
		if prev.x < 0:
			return Vector2i(-1, -1)
		if prev == u.cell:
			return cursor
		cursor = prev
	return Vector2i(-1, -1)


## Begins a move.
##
## The unit's cell is committed *immediately*, along with its occupancy entry —
## only the pixel position lags behind and eases across. Leaving `cell` on the
## origin until the slide finished meant a unit was registered at its destination
## while still reporting the cell it came from, and `kill()` and `place()` both
## erase occupancy by `cell`: a unit that died mid-step therefore freed whichever
## cell it had left (evicting whoever had since moved in) and left its own
## destination blocked by a corpse for the rest of the fight.
func start_move(u: SimUnit, cell: Vector2i) -> void:
	if not cell_free(cell):
		return
	_occupied.erase(Hex.key(u.cell))
	_occupied[Hex.key(cell)] = u
	u.move_from = u.pos          # from wherever it actually is, not from the grid
	u.move_to = Hex.to_pixel(cell)
	u.cell = cell
	u.move_t = 0.0
	u.move_duration = MOVE_TIME
	u.is_moving = true


# --- Main loop ---------------------------------------------------------------

## How far into overtime this fight is: 0.0 before it starts, 1.0 at full ramp.
func overtime() -> float:
	if time <= OVERTIME_START:
		return 0.0
	return clampf((time - OVERTIME_START) / (OVERTIME_FULL - OVERTIME_START), 0.0, 1.0)


## Advances exactly one tick. The only thing that moves the clock.
func step() -> void:
	if done:
		return
	time += TICK

	if not _events.is_empty():
		var ready: Array[Dictionary] = []
		var pending: Array[Dictionary] = []
		for e in _events:
			if e["at"] <= time:
				ready.append(e)
			else:
				pending.append(e)
		_events = pending
		for e in ready:
			e["call"].call()

	for t in _timers:
		while t["next"] <= time:
			t["call"].call()
			t["next"] += t["interval"]

	for u in units:
		if u.alive:
			_tick_statuses(u, TICK)
	for u in units:
		if u.alive:
			_tick_unit(u, TICK)

	_check_end()


func _check_end() -> void:
	var a_alive := false
	var b_alive := false
	for u in teams[Team.PLAYER]:
		if u.alive or u.pending_revive:
			a_alive = true
			break
	for u in teams[Team.ENEMY]:
		if u.alive or u.pending_revive:
			b_alive = true
			break

	if a_alive and b_alive and time < TIME_LIMIT:
		return

	done = true
	if a_alive and not b_alive:
		winner = Result.PLAYER_WIN
	elif b_alive and not a_alive:
		winner = Result.ENEMY_WIN
	elif not a_alive and not b_alive:
		winner = Result.DRAW
	else:
		# Timed out with both sides standing: most health left wins.
		var sa := team_score(Team.PLAYER)
		var sb := team_score(Team.ENEMY)
		winner = Result.PLAYER_WIN if sa > sb else (Result.ENEMY_WIN if sb > sa else Result.DRAW)


## Survivors weighted by how healthy they are, for timeout tie-breaks.
func team_score(team_id: int) -> float:
	var score := 0.0
	for u in teams[team_id]:
		if u.alive:
			score += u.health_fraction() + 0.5
	return score


func _tick_statuses(u: SimUnit, dt: float) -> void:
	if u.stun_time > 0.0:
		u.stun_time -= dt
	if u.rend_time > 0.0:
		u.rend_time -= dt
		if u.rend_time <= 0.0:
			u.rend = 0.0
	if u.shred_mr_time > 0.0:
		u.shred_mr_time -= dt
		if u.shred_mr_time <= 0.0:
			u.shred_mr = 0.0
	if u.heal_cut_time > 0.0:
		u.heal_cut_time -= dt
	if u.temp_omnivamp_time > 0.0:
		u.temp_omnivamp_time -= dt
		if u.temp_omnivamp_time <= 0.0:
			u.temp_omnivamp = 0.0

	for i in range(u.shields.size() - 1, -1, -1):
		u.shields[i]["time"] -= dt
		if u.shields[i]["time"] <= 0.0:
			u.shields.remove_at(i)
	u.recalc_shield()

	for i in range(u.buffs.size() - 1, -1, -1):
		u.buffs[i]["time"] -= dt
		if u.buffs[i]["time"] <= 0.0:
			var b: Dictionary = u.buffs[i]
			u.set(b["stat"], u.get(b["stat"]) / b["mult"])
			u.buffs.remove_at(i)

	for i in range(u.flats.size() - 1, -1, -1):
		u.flats[i]["time"] -= dt
		if u.flats[i]["time"] <= 0.0:
			var f: Dictionary = u.flats[i]
			u.set(f["stat"], u.get(f["stat"]) - f["amount"])
			u.flats.remove_at(i)

	for i in range(u.burns.size() - 1, -1, -1):
		var burn: Dictionary = u.burns[i]
		burn["time"] -= dt
		burn["tick"] -= dt
		if burn["tick"] <= 0.0:
			burn["tick"] = 1.0
			damage(burn["source"], u, u.max_hp * burn["pct"], &"true")
		if burn["time"] <= 0.0:
			u.burns.remove_at(i)

	for i in range(u.regen_queue.size() - 1, -1, -1):
		var r: Dictionary = u.regen_queue[i]
		if r["time"] <= 0.0:
			u.regen_queue.remove_at(i)
			continue
		var give: float = r["amount"] * (dt / r["time"])
		heal(u, u, minf(r["amount"], give))
		r["amount"] -= give
		r["time"] -= dt
		if r["time"] <= 0.0 or r["amount"] <= 0.0:
			u.regen_queue.remove_at(i)

	if u.item_regen > 0.0:
		heal(u, u, u.max_hp * u.item_regen * dt)

	_tick_tide_regen(u, dt)

	if u.mana_regen > 0.0 and u.casting <= 0.0:
		u.gain_mana(u.mana_regen * dt)

	# Last, so a tick's own regeneration is part of the number it flushes.
	if render and u.heal_popup > 0.0:
		u.heal_popup_time += dt
		if u.heal_popup_time >= HEAL_POPUP_WINDOW:
			_show_heal_popup(u)


## Tidecaller regeneration: heals, and pours the overflow into a capped shield
## rather than wasting it on a unit already at full health.
func _tick_tide_regen(u: SimUnit, dt: float) -> void:
	if u.regen.is_empty():
		return
	var amount: float = u.max_hp * u.regen["pct"] * dt
	var missing: float = u.max_hp - u.hp
	var spent: float = minf(amount, missing)
	heal(u, u, spent)

	# Overflow is the part the unit had no room for, measured against what the
	# regen offered rather than against what the heal actually landed. Those are
	# the same number until overtime cuts healing — and taking it off the landed
	# amount would then pour the cut straight into the shield, leaving the one
	# trait that heals through a stalemate *stronger* in the phase that exists to
	# break it. The shield pays the same cut the heal did.
	var overflow := (amount - spent) * (1.0 - OVERTIME_HEAL_CUT * overtime())
	if overflow <= 0.0:
		return

	var cap: float = u.max_hp * u.regen["cap"]
	var current := 0.0
	var tide_shield: Dictionary = {}
	for s in u.shields:
		if s.get("tide", false):
			tide_shield = s
			current += s["amount"]
	if current >= cap:
		return
	if tide_shield.is_empty():
		tide_shield = { "amount": 0.0, "time": 999.0, "tide": true }
		u.shields.append(tide_shield)
	tide_shield["amount"] = minf(cap, tide_shield["amount"] + overflow)
	u.recalc_shield()


func _tick_unit(u: SimUnit, dt: float) -> void:
	if u.is_moving:
		u.move_t += dt
		var k := minf(1.0, u.move_t / u.move_duration)
		u.pos = u.move_from.lerp(u.move_to, k)
		if k >= 1.0:
			u.is_moving = false
		return

	if u.stun_time > 0.0:
		return

	if u.casting > 0.0:
		u.casting -= dt
		if u.casting <= 0.0:
			u.casting = 0.0
			u.mana = 0.0
			var ability: Variant = content.ability(u.def.id)
			if ability != null:
				ability.cast(self, u)
			for hook in u.hooks_on_cast:
				hook.call(u)
		return

	if u.casts() and u.mana >= u.max_mana:
		u.casting = CAST_TIME
		fx(&"cast", u, null, Color("7fe3ff"))
		return

	var target := pick_target(u)
	if target == null:
		return

	if distance(u, target) <= u.attack_range:
		u.attack_timer -= dt
		if u.attack_timer <= 0.0:
			u.attack_timer = 1.0 / minf(u.attack_speed, ATTACK_SPEED_CAP)
			attack(u, target)
		return

	var cell := step_toward(u, target)
	if cell.x >= 0:
		start_move(u, cell)
	else:
		u.attack_timer = maxf(u.attack_timer - dt, 0.0)
		acquire(u)


func attack(u: SimUnit, target: SimUnit) -> void:
	var style := attack_style_for(u.def)
	var spec: Dictionary = ATTACK_STYLES[style]
	if spec["ranged"]:
		fx(&"muzzle", u, target, spec["color"], { "style": style })
		# The target's uid lets the renderer follow it while the shot is in the
		# air. Damage lands the moment the shot is fired, so the projectile is
		# cosmetic catch-up — and one that arrives where the target used to be
		# standing reads as a miss that somehow still hurt.
		fx(&"projectile", target, u, spec["color"],
			{ "style": style, "target_uid": target.uid })
	else:
		fx(&"melee", target, u, spec["color"], { "style": style })

	if target.dodge > 0.0 and rng.randf() < target.dodge:
		float_text(target, "dodge", &"miss")
	else:
		damage(u, target, u.ad, &"physical", { "is_attack": true })

	u.gain_mana(MANA_PER_ATTACK)
	for hook in u.hooks_on_attack:
		hook.call(u, target)


## Advances at most `max_steps` ticks, stopping early if the fight ends. Returns
## true once it has.
##
## The unwatched fights use this rather than running in one go. Six of them
## resolved inside a single frame is a third of a second of the game not
## responding on a desktop, and several times that in a browser — for work
## nobody is looking at, during a fight the player *is* looking at, which has
## hundreds of frames to spare.
func advance(max_steps: int) -> bool:
	var n := 0
	while not done and n < max_steps:
		step()
		n += 1
	return done


## Runs the whole fight immediately. The tools use it, and so does the last
## moment before a result is needed from a fight still part way through.
func run_to_end() -> int:
	advance(int(TIME_LIMIT / TICK) + 10)
	done = true
	return winner


func survivors(team_id: int) -> Array[SimUnit]:
	return living_allies(team_id)


## What every combatant did with the fight, for the DPS meter.
##
## Plain values rather than the SimUnits themselves, on purpose. The meter has to
## keep reading after the round advances, and `dispose()` nulls every `def` and
## clears every reference the moment it does — a snapshot holding units would
## either read back blanks or pin a finished battle in memory, which is the leak
## `dispose()` exists to prevent.
func stats() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for u in units:
		rows.append({
			"uid": u.uid,
			"name": u.display_name(),
			"icon": u.def.icon if u.def != null else "",
			"cost": u.def.cost if u.def != null else 0,
			"team": u.team,
			"star": u.star,
			"alive": u.alive,
			"dealt": u.damage_dealt,
			"taken": u.damage_taken,
			"healed": u.healing_done,
		})
	return rows


## Breaks the reference cycles a finished fight is holding, so it can be freed.
##
## Three things here are cyclic, and GDScript's RefCounted has no cycle
## collector: a unit's `target` points at another unit, every item and trait hook
## is a lambda that captured the unit it was installed on, and a pending delayed
## callback captures both the caster and the sim.
##
## Seven fights resolve every round — one watched, six headless — so without this
## a long game leaks every unit of every battle it ever ran. Call it once the
## result has been read; the sim is not usable afterwards.
func dispose() -> void:
	for u in units:
		u.target = null
		u.hooks_on_attack.clear()
		u.hooks_on_damaged.clear()
		u.hooks_on_cast.clear()
		u.hooks_on_kill.clear()
		u.hooks_on_death.clear()
		u.burns.clear()      # each burn holds its source
		u.revive.clear()
		u.scratch.clear()
		u.def = null
	_events.clear()          # each pending event captured the caster
	_timers.clear()
	_occupied.clear()
	fx_queue.clear()
	units.clear()
	teams = [[], []]
	active_traits = [[], []]
