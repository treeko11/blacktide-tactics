extends ItemEffect

## The Duellist's Warrant - the Edge's mana-on-hit and the Rapier's compounding
## attack speed, which feed each other: faster attacks are more mana, and the
## cast is what most carries are attacking towards.

func id() -> StringName:
	return &"duellists_warrant"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ad += 45.0
	u.gain_mana(20.0)

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		unit.gain_mana(8.0)
		unit.attack_speed *= 1.06

	u.hooks_on_attack.append(on_attack)
