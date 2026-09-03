extends Ability

## The Locker Opens — board-wide damage, and a window in which the whole fleet
## comes back once.
##
## The revive it grants carries an expiry, unlike the Ghost Fleet trait's, so the
## sim's kill path can tell a windowed second life from a permanent one.

func id() -> StringName:
	return &"davy"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var damage := scaled(s, &"dmg")
	for e in sim.living_enemies(s.team):
		sim.fx(&"drain", e, s, Color("8f6bff"))
		sim.damage(s, e, damage, &"magic")
	sim.grant_revive(s.team, v(s, &"rev") / 100.0, v(s, &"dur"))
