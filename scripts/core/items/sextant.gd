extends ItemEffect

## Brass Sextant — a component. Flat stats and nothing else; the interesting behaviour
## only appears once two of these are forged together.

func id() -> StringName:
	return &"sextant"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.gain_mana(15.0)
