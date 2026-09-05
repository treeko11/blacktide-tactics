extends ItemEffect

## The Red Tally - the Bloodletter's snowball and the Rapier's, on one carry.
##
## Both parents were unbounded and so is this, which is the point of putting them
## together: nothing here caps, and ATTACK_SPEED_CAP does its work where attack
## speed is read rather than where it is granted.

func id() -> StringName:
	return &"red_tally"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ad += 70.0

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		unit.attack_speed *= 1.07

	var on_kill := func(unit: SimUnit, _victim: SimUnit) -> void:
		unit.ad += 15.0
		unit.attack_speed *= 1.15
		sim.proc_text(unit, "+15 AD")

	u.hooks_on_attack.append(on_attack)
	u.hooks_on_kill.append(on_kill)
