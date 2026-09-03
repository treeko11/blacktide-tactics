extends Ability

## Cutthroat — repeats itself on a kill, up to four times in a chain.
##
## The recursion is a bound method rather than a self-referencing lambda, which
## GDScript cannot express cleanly. The depth guard is what stops a Rook that is
## killing something every quarter-second from looping for the rest of the fight.

func id() -> StringName:
	return &"rook"


func scaling() -> Dictionary:
	return { &"dmg": &"ad" }


func cast(sim: Sim, s: SimUnit) -> void:
	_strike(sim, s, 0)


func _strike(sim: Sim, s: SimUnit, depth: int) -> void:
	if not s.alive or depth > 3:
		return
	var t := sim.lowest_enemy(s.team)
	if t == null:
		return
	sim.blink_near(s, t)
	sim.fx(&"slash", t, s, Color("ff5f8f"))
	sim.damage(s, t, s.ad * v(s, &"dmg") / 100.0, &"physical", { "can_crit": true })
	if not t.alive:
		sim.delay(0.25, _strike.bind(sim, s, depth + 1))
