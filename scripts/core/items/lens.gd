extends ItemEffect

## Sea-Glass Lens — a component. Flat stats and nothing else; the interesting behaviour
## only appears once two of these are forged together.

func id() -> StringName:
	return &"lens"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ability_power += 10.0
