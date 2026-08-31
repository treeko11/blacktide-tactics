extends ItemEffect

## Abyssal Prism — the flat ability power item. No proc, no condition: the
## benchmark every other caster item is measured against.

func id() -> StringName:
	return &"abyssal_prism"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ability_power += 80.0
