extends TraitEffect

## Leviathan — things older than ships.
##
## Only three breakpoints and they start at two, because there are few Leviathans
## in the pool and they are expensive. Flat health plus flat damage reduction is
## deliberately the bluntest bonus in the game: it is the wall other comps have to
## get through.

func id() -> StringName:
	return &"leviathan"


func apply(sim: Sim, context: Dictionary) -> void:
	var bonus_hp := v(context, &"hp")
	var reduction := v(context, &"dr") / 100.0
	for u in context["holders"]:
		sim.add_max_hp(u, bonus_hp)
		u.damage_reduction += reduction
