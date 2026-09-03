extends SeaEffect

## The doldrums. No wind, no swell, and nothing charges.
##
## Every ability on the board needs more mana before it will fire, so a comp
## built around one big cast arrives late to a fight that may already be over.
##
## Marks nothing, because it is the whole ocean — like the fog, the answer is a
## comp rather than a place to stand. It is deliberately the opposite lever to
## the fog: fog moves a backline, this one moves a *shopping list*, and a captain
## who has spent the stage on a single five-cost carry is the one it costs.
##
## Applied after items and traits, so a mana item bought in answer to it still
## helps — it shortens the bar, and this lengthens it.


func id() -> StringName:
	return &"doldrums"


func apply(sim: Sim, context: Dictionary) -> void:
	var extra := 1.0 + v(context, &"mana", 35.0) / 100.0
	for u in sim.units:
		# A champion with no ability has no bar to lengthen. Multiplying zero
		# would be harmless and would also quietly claim it had been affected.
		if u.max_mana <= 0.0:
			continue
		u.max_mana *= extra
