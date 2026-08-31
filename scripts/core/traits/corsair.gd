extends TraitEffect

## Corsair — plunder fuels the crew.
##
## The whole team gets the attack damage; Corsairs themselves get it twice, which
## is the shape most origins here use: a reason to field the trait, and a bigger
## reason to field the units that carry it.

func id() -> StringName:
	return &"corsair"


func apply(_sim: Sim, context: Dictionary) -> void:
	var team_ad := v(context, &"teamAd") / 100.0
	var crit := v(context, &"crit") / 100.0
	for u in context["team"]:
		u.ad *= 1.0 + team_ad
	for u in context["holders"]:
		u.ad *= 1.0 + team_ad
		u.crit += crit
