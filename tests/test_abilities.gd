extends TestCase

## Casts every champion ability once, in isolation, and proves it changed
## something.
##
## The isolation matters. A fight left running would change the board through
## ordinary attacks, and the test would pass whether or not the ability did
## anything at all. So:
##
##   - the caster's allies are *copies of the caster*, and the enemies are
##     monsters, so no trait reaches a breakpoint (traits count distinct
##     champions, and one champion three times still counts as one);
##   - every unit is stunned for the duration, so nobody attacks;
##   - the ability is invoked directly and the sim is then stepped only to flush
##     the delayed callbacks that multi-hit abilities schedule.
##
## What is left moving is the ability. If the board signature is unchanged after
## it fires, the ability did nothing — which is what a mistyped value key, an
## empty target query or a team mix-up all look like.

const STUN_DURATION := 60.0
const FLUSH_SECONDS := 6.0

## The scaling checks give the board room to move in both directions: enough
## health that no ability can overkill, and half of it missing so a heal has
## somewhere to land. An ability that saturates at both stat lines reports the
## same figure twice and reads as one that does not scale at all.
const SCALE_HP := 200000.0

## How far the stat is moved between the two casts. Large enough that a small
## share of the output moving still clears the float comparison.
const SCALE_FACTOR := 4.0

## Long enough for every staggered ability to finish — Calypso's hurricane is the
## slowest at 3.6s — and short enough that the six-second shields are still up.
const SCALE_FLUSH := 5.0


func test_every_ability_does_something() -> void:
	var silent: Array[String] = []
	var checked := 0

	for champion in content().champions():
		if not champion.casts():
			continue
		checked += 1
		if not _cast_changes_the_board(champion):
			silent.append(String(champion.id))

	assert_gt(checked, 40.0, "expected the full champion roster to be castable")
	assert_true(silent.is_empty(),
		"these abilities changed nothing when cast: %s" % ", ".join(silent))


func test_every_casting_champion_has_an_ability_script() -> void:
	var missing: Array[String] = []
	for champion in content().champions():
		if champion.casts() and content().ability(champion.id) == null:
			missing.append(String(champion.id))
	assert_true(missing.is_empty(), "no ability script for: %s" % ", ".join(missing))


## Ability text is written with {token} placeholders. One that never got a value
## reaches the player as a literal "{dmg}" on a tooltip.
func test_ability_descriptions_have_no_unfilled_tokens() -> void:
	var broken: Array[String] = []
	for champion in content().champions():
		if champion.ability_desc == "":
			continue
		var filled := Content.format_description(
			champion.ability_desc, champion.ability_values, 1)
		if filled.contains("{") or filled.contains("}"):
			broken.append("%s: %s" % [champion.id, filled])
	assert_true(broken.is_empty(), "unfilled ability tokens — %s" % "; ".join(broken))


## Every declared scaling key is a number the champion actually has.
##
## A key that is not in `ability_values` is a mark on nothing: the token never
## appears in the description, so no tag is ever drawn and the mistake is
## invisible. The reverse is fine and common — most keys scale off nothing.
func test_declared_scaling_keys_are_real_ability_values() -> void:
	var wrong: Array[String] = []
	var checked := 0
	for champion in content().champions():
		var ability: Ability = content().ability(champion.id)
		if ability == null:
			continue
		for key in ability.scaling():
			checked += 1
			if not champion.ability_values.has(key):
				wrong.append("%s has no {%s}" % [champion.id, key])
			if not Ability.SCALING.has(ability.scaling()[key]):
				wrong.append("%s marks {%s} with an unknown stat" % [champion.id, key])
	assert_gt(checked, 40.0, "expected the roster to declare some scaling")
	assert_true(wrong.is_empty(), "bad scaling declarations: %s" % ", ".join(wrong))


## What `scaling()` claims has to be what `cast()` does.
##
## Nothing about a declaration that has drifted from its own cast looks wrong.
## The ability still fires, the numbers still land, and the only broken thing is
## a mark on a tooltip promising that a figure grows with a stat which never
## touches it — a player builds around that and the board quietly does not
## change. It is the DPS meter problem in a new place: correct-looking output,
## produced by nothing.
##
## So this does not read the declaration against the source. It casts each
## ability twice with the stat moved in between and asks the fight which numbers
## actually came out different, then holds the declaration to that.
func test_declared_scaling_is_what_the_cast_actually_does() -> void:
	var wrong: Array[String] = []
	var checked := 0

	for champion in content().champions():
		if not champion.casts():
			continue
		var ability: Ability = content().ability(champion.id)
		if ability == null:
			continue
		var declared: Array = ability.scaling().values()
		for stat in [&"ad", &"ap"]:
			checked += 1
			var moved := not is_equal_approx(
				_cast_output(champion, ability, stat, 1.0),
				_cast_output(champion, ability, stat, SCALE_FACTOR))
			if moved and not declared.has(stat):
				wrong.append("%s scales off %s and does not declare it"
					% [champion.id, stat])
			elif not moved and declared.has(stat):
				wrong.append("%s declares %s and nothing moved when it changed"
					% [champion.id, stat])

	assert_gt(checked, 80.0, "expected two stats checked against every caster")
	assert_true(wrong.is_empty(), "scaling declarations disagree with the sim: %s"
		% "; ".join(wrong))


# --- helpers -----------------------------------------------------------------

func _cast_changes_the_board(champion: ChampionDef) -> bool:
	# Both sides sit on the front rank. The opponent's cells are *mirrored* into
	# the top half, so an enemy authored at row 4 ends up at row 3 — right next to
	# an ally on row 4. Seating them any further apart makes every proximity
	# ability legitimately find nothing, and the test then blames the ability for
	# a fixture that never put anything in range.
	var allies: Array = [
		entry(champion.id, Vector2i(3, 4), 2),
		entry(champion.id, Vector2i(2, 4), 2),
		entry(champion.id, Vector2i(4, 4), 2),
	]
	var foes: Array = [
		entry(&"rat", Vector2i(3, 4)),
		entry(&"rat", Vector2i(2, 4)),
		entry(&"rat", Vector2i(4, 4)),
		entry(&"rat", Vector2i(3, 5)),
	]
	var sim := battle(allies, foes)

	for u in sim.units:
		u.stun_time = STUN_DURATION

	var caster: SimUnit = sim.teams[Sim.Team.PLAYER][0]
	var before := _signature(sim)

	var ability: Ability = content().ability(champion.id)
	if ability == null:
		return false
	ability.cast(sim, caster)
	run_for(sim, FLUSH_SECONDS)

	return not is_equal_approx(before, _signature(sim))


## Everything an ability could plausibly move, in one number: health, shields,
## mana, the offensive and defensive stats, and position.
func _signature(sim: Sim) -> float:
	var total := 0.0
	for u in sim.units:
		total += u.hp + u.shield + u.mana
		total += u.ad + u.armor + u.magic_resist + u.ability_power
		total += u.attack_speed * 1000.0
		total += u.crit * 1000.0 + u.omnivamp * 1000.0 + u.damage_reduction * 1000.0
		total += u.rend * 100.0 + u.shred_mr * 100.0
		total += u.cell.x * 7.0 + u.cell.y * 13.0
		total += u.regen_queue.size() * 17.0
		total += (1.0 if u.alive else 0.0) * 31.0
		total += float(u.revive.size()) * 41.0
	return total


## Everything one cast put out: what the caster dealt, what it healed, and every
## shield standing at the end of it.
##
## Not `_signature`, which is built to notice *any* change and is therefore too
## coarse to compare two runs of the same ability at different stat lines — the
## positions and the alive flags in it are identical either way, and the health
## totals it sums are large enough that a real difference of a few hundred
## disappears inside `is_equal_approx`. These three numbers are the ones an
## ability's scaling can move, and nothing else contributes to them while every
## unit on the board is stunned.
func _cast_output(champion: ChampionDef, ability: Ability, stat: StringName,
		factor: float) -> float:
	var allies: Array = [
		entry(champion.id, Vector2i(3, 4), 2),
		entry(champion.id, Vector2i(2, 4), 2),
		entry(champion.id, Vector2i(4, 4), 2),
	]
	var foes: Array = [
		entry(&"rat", Vector2i(3, 4)),
		entry(&"rat", Vector2i(2, 4)),
		entry(&"rat", Vector2i(4, 4)),
		entry(&"rat", Vector2i(3, 5)),
	]
	var sim := battle(allies, foes)
	for u in sim.units:
		u.stun_time = STUN_DURATION
		u.max_hp = SCALE_HP
		u.hp = SCALE_HP * 0.5

	var caster: SimUnit = sim.teams[Sim.Team.PLAYER][0]
	if stat == &"ap":
		caster.ability_power *= factor
	else:
		caster.ad *= factor

	ability.cast(sim, caster)
	run_for(sim, SCALE_FLUSH)

	var total := caster.damage_dealt + caster.healing_done
	for u in sim.units:
		total += u.shield
	return total
