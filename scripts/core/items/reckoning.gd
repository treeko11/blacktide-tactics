extends ItemEffect

## Corsair's Reckoning — the hybrid. Omnivamp heals off ability damage too, so
## this is the item that keeps a caster-bruiser alive rather than a pure carry.

func id() -> StringName:
	return &"reckoning"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ad += 20.0
	u.ability_power += 20.0
	u.omnivamp += 0.25
