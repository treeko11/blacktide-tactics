extends ItemEffect

## Hull of the Deep — health and steady regeneration. `item_regen` is ticked by
## the sim rather than by a hook, because it applies every frame rather than on
## an event.

func id() -> StringName:
	return &"hull_of_the_deep"


func apply(sim: Sim, u: SimUnit) -> void:
	sim.add_max_hp(u, 800.0)
	u.item_regen += 0.03
