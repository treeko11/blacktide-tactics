extends TraitEffect

## Siren — songs that drown men.
##
## Sirens do not stack the team bonus on top of their own: they are given the
## difference, so the listed number is what they end up with rather than a figure
## you have to add up yourself.

func id() -> StringName:
	return &"siren"


func apply(_sim: Sim, context: Dictionary) -> void:
	var team_ap := v(context, &"teamAp")
	var own_ap := v(context, &"ap")
	var refund := v(context, &"mana")

	var on_cast := func(unit: SimUnit) -> void:
		unit.gain_mana(refund)

	for u in context["team"]:
		u.ability_power += team_ap
	for u in context["holders"]:
		u.ability_power += own_ap - team_ap
		u.hooks_on_cast.append(on_cast)
