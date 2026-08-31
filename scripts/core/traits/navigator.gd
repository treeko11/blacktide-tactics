extends TraitEffect

## Navigator — the whole fleet casts sooner, and more often.
##
## Starting mana plus regeneration is the strongest enabler in the game for the
## expensive casters, which is why it only has three breakpoints and the top one
## needs four distinct Navigators.

func id() -> StringName:
	return &"navigator"


func apply(_sim: Sim, context: Dictionary) -> void:
	var starting := v(context, &"start")
	var regen := v(context, &"reg")
	var haste := v(context, &"as") / 100.0

	for u in context["team"]:
		u.gain_mana(starting)
		u.mana_regen += regen
	for u in context["holders"]:
		u.attack_speed *= 1.0 + haste
