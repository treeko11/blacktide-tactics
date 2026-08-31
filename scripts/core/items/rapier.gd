extends ItemEffect

## Rapier of the Reef — compounding attack speed with no stack limit.
##
## The cap that stops this running away is ATTACK_SPEED_CAP, applied where attack
## speed is *used* rather than where it is granted, so the buff bookkeeping stays
## reversible.

func id() -> StringName:
	return &"rapier"


func apply(_sim: Sim, u: SimUnit) -> void:
	u.ad += 18.0

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		unit.attack_speed *= 1.06

	u.hooks_on_attack.append(on_attack)
