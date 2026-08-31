extends ItemEffect

## Buccaneer's Edge — turns attack speed into cast frequency.

func id() -> StringName:
	return &"buccaneers_edge"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ad += 15.0
	u.gain_mana(15.0)

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		unit.gain_mana(6.0)

	u.hooks_on_attack.append(on_attack)
