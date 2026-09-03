extends Ability

## Rise, Drowned Ones — heals itself, raises the most valuable body on the floor,
## and crushes what is nearby. The revive picks by cost and star, so it brings
## back the carry rather than whatever died first.

func id() -> StringName:
	return &"barnacleking"


func scaling() -> Dictionary:
	return { &"dmg": &"ap", &"heal": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	sim.heal(s, s, scaled(s, &"heal"))
	sim.revive_best(s.team, v(s, &"rev") / 100.0)
	sim.fx(&"shock", s, null, Color("a2ffd0"))
	var damage := scaled(s, &"dmg")
	for e in sim.enemies_near(s, 2):
		sim.damage(s, e, damage, &"magic")
