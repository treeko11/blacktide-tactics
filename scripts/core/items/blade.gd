extends ItemEffect

## Corsair's Blade — a component. Flat stats and nothing else; the interesting behaviour
## only appears once two of these are forged together.

func id() -> StringName:
	return &"blade"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ad += 10.0
