extends Ability

## Hymn of the Deep — the ability power is permanent and fleet-wide, which makes
## a second Meredine cast worth more than the first.

func id() -> StringName:
	return &"meredine"


func scaling() -> Dictionary:
	return { &"heal": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var heal := scaled(s, &"heal")
	var power := v(s, &"ap")
	for a in sim.living_allies(s.team):
		sim.heal(s, a, heal)
		a.ability_power += power
		sim.fx(&"pop", a, null, Color("b6a2ff"))
