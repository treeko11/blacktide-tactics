extends ItemEffect

## The Butcher's Bill - the Bloodletter's snowball with the Grapeshot burn under
## it, so the item that wants kills also carries the thing that finishes the
## targets flat damage cannot chew through.

func id() -> StringName:
	return &"butchers_bill"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ad += 48.0
	u.attack_speed *= 1.45

	var on_attack := func(unit: SimUnit, target: SimUnit) -> void:
		if target != null and target.alive:
			sim.apply_burn(target, 0.02, 5.0, unit, 0.50)

	var on_kill := func(unit: SimUnit, _victim: SimUnit) -> void:
		grant(unit, &"ad", 15.0)
		sim.proc_text(unit, "+15 AD")

	u.hooks_on_attack.append(on_attack)
	u.hooks_on_kill.append(on_kill)
