extends ItemEffect

## Siren's Locket — grows as it casts, and the mana refund shortens the gap
## between the casts that grow it.
##
## The growth expires. It used to last the fight, which made the item worth
## whatever the fight's length happened to be: measured at +86 ability power
## banked on an ordinary caster over seventeen seconds, against a printed +25.
## A stack that runs out instead plateaus at about `STACK_AP` times however many
## casts fit in `STACK_TIME` — bigger per cast than before, and bounded.

const STACK_AP := 18.0
const STACK_TIME := 8.0


func id() -> StringName:
	return &"sirens_locket"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 25.0
	u.gain_mana(20.0)

	var on_cast := func(unit: SimUnit) -> void:
		unit.gain_mana(20.0)
		grant_temporary(sim, unit, &"ap", STACK_AP, STACK_TIME)
		sim.proc_text(unit, "+%d AP" % int(STACK_AP))

	u.hooks_on_cast.append(on_cast)
