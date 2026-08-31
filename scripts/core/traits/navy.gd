extends TraitEffect

## Royal Navy — discipline holds the line.
##
## The only trait with four breakpoints, and the recovery is paid out over three
## seconds rather than instantly, so it rewards a fleet that can survive the burst
## rather than one that simply out-heals it.

func id() -> StringName:
	return &"navy"


func apply(sim: Sim, context: Dictionary) -> void:
	var resist := v(context, &"res")
	var recover := v(context, &"heal") / 100.0

	var on_damaged := func(unit: SimUnit, amount: float, _source: SimUnit) -> void:
		sim.heal_over_time(unit, amount * recover, 3.0)

	for u in context["team"]:
		u.armor += resist
		u.magic_resist += resist
	for u in context["holders"]:
		u.armor += resist
		u.magic_resist += resist
		u.hooks_on_damaged.append(on_damaged)
