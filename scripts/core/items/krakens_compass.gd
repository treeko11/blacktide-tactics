extends ItemEffect

## Kraken's Compass — pure cast frequency. On a champion with an expensive
## ability this is worth more than any raw stat item.

func id() -> StringName:
	return &"krakens_compass"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ability_power += 15.0
	u.gain_mana(30.0)

	var on_cast := func(unit: SimUnit) -> void:
		unit.gain_mana(30.0)

	u.hooks_on_cast.append(on_cast)
