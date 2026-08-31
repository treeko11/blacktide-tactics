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
