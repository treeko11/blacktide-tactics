extends ItemEffect

## The Bloodletter — a snowball. Every kill makes the next one easier.
##
## Unbounded on purpose: it is the reward for putting the item on a unit that can
## actually finish fights, and it does nothing at all on one that cannot.

func id() -> StringName:
	return &"bloodletter"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ad += 45.0

	var on_kill := func(unit: SimUnit, _victim: SimUnit) -> void:
		unit.ad += 10.0
		sim.proc_text(unit, "+10 AD")

	u.hooks_on_kill.append(on_kill)
