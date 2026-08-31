extends Ability

## Anchor Down — a pure defensive cast. The resistances are flat and timed, so
## they come back off cleanly when the eight seconds are up.

func id() -> StringName:
	return &"ned"


func cast(sim: Sim, s: SimUnit) -> void:
	var resist := v(s, &"res")
	sim.add_shield(s, scaled(s, &"shield"), 8.0)
	sim.add_flat(s, &"armor", resist, 8.0)
	sim.add_flat(s, &"magic_resist", resist, 8.0)
	sim.fx(&"pop", s, null, Color("9fb8d8"))
