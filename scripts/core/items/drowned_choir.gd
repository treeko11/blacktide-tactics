extends ItemEffect

## The Drowned Choir - both mana engines at once. Fifty mana back on every cast
## is most of a second cast, which is what makes this the item that turns an
## ability into the unit's main output rather than its opener.
##
## Its growth expires, for the reason the Locket's does and harder: the refund
## that makes this item what it is also drives its own compounding, so a grant
## that lasted the fight grew faster the longer the fight ran. On a fleet that
## could keep it casting it measured furthest from even of any greater item in
## `capstone_balance.gd` — the only pairing at 100%.
##
## `STACK_AP` deliberately matches the Locket's rather than beating it. What
## makes this the better item is that it casts more often, so more of its stacks
## are live at once — the fifty mana back is the upgrade, not a bigger number per
## cast. Set above the Locket's it measured 100% against its own parents, which
## is the trap in the other direction: a greater item nobody would decline.

const STACK_AP := 18.0
const STACK_TIME := 8.0


func id() -> StringName:
	return &"drowned_choir"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 45.0
	u.gain_mana(50.0)

	var on_cast := func(unit: SimUnit) -> void:
		unit.gain_mana(50.0)
		grant_temporary(sim, unit, &"ap", STACK_AP, STACK_TIME)
		sim.proc_text(unit, "CHOIR")

	u.hooks_on_cast.append(on_cast)
