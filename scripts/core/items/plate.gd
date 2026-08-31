extends ItemEffect

## Barnacle Plate — a component. Flat stats and nothing else; the interesting
## behaviour only appears once two of these are forged together.

func id() -> StringName:
	return &"plate"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.armor += 20.0
	u.magic_resist += 20.0
