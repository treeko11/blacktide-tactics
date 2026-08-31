extends ItemEffect

## Powder Keg — a component. Flat stats and nothing else; the interesting behaviour
## only appears once two of these are forged together.

func id() -> StringName:
	return &"keg"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.attack_speed *= 1.12
