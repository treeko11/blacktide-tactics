extends TraitEffect

## Reaver — sustain, and a finisher.
##
## `execute_amp` is applied in Sim.damage to anything below half health, ability
## damage included. That is what makes Reavers the answer to a Tidecaller fleet
## that would otherwise heal back through the chip damage.

func id() -> StringName:
	return &"reaver"


func apply(_sim: Sim, context: Dictionary) -> void:
	var vamp := v(context, &"ov") / 100.0
	var bonus := v(context, &"bonus") / 100.0
	for u in context["holders"]:
		u.omnivamp += vamp
		u.execute_amp += bonus
