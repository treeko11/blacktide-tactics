extends ItemEffect

## Coral Aegis — front-loaded. The shield only covers the opening exchange, which
## is when a squishy caster is most likely to be focused down before casting once.

func id() -> StringName:
	return &"coral_aegis"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 30.0
	u.armor += 25.0
	u.magic_resist += 25.0
	sim.add_shield(u, 350.0, 10.0)
