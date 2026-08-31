extends TraitEffect

## Bosun — health for the crew, more for the Bosuns.
##
## The team bonus is zero at the first breakpoint, which is why it is guarded:
## adding nothing is free but the intent reads better stated.

func id() -> StringName:
	return &"bosun"


func apply(sim: Sim, context: Dictionary) -> void:
	var own_hp := v(context, &"hp")
	var team_hp := v(context, &"team")
	if team_hp > 0.0:
		for u in context["team"]:
			sim.add_max_hp(u, team_hp)
	for u in context["holders"]:
		sim.add_max_hp(u, own_hp)
