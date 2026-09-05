extends ItemEffect

## Siren's Locket — grows permanently over a long fight, and the mana refund
## shortens the gap between casts that grow it.

func id() -> StringName:
	return &"sirens_locket"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 25.0
	u.gain_mana(20.0)

	var on_cast := func(unit: SimUnit) -> void:
		unit.gain_mana(20.0)
		grant(unit, &"ap", 10.0)
		sim.proc_text(unit, "+10 AP")

	u.hooks_on_cast.append(on_cast)
