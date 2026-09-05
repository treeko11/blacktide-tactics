extends Ability

## Hymn of the Deep — a fleet-wide heal and a fleet-wide power buff.
##
## The power is a state the fleet is in for GRANT_TIME, refreshed by each cast,
## rather than something every cast adds to. Granted for the rest of combat it
## compounded: every ally kept every cast's worth, so a fleet that could keep
## Meredine casting banked +805 ability power over one fight with no items on
## the board at all, and the ability was worth whatever the fight's length
## happened to be. Bigger per cast now, and it has a ceiling.
##
## Refreshed rather than stacked because a duration alone still leaves the cast
## *rate* in the number, and the mana items exist to raise exactly that — see
## `Sim.refresh_flat`, where that argument is made in full.

const GRANT_TIME := 10.0


func id() -> StringName:
	return &"meredine"


func scaling() -> Dictionary:
	return { &"heal": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var heal := scaled(s, &"heal")
	var power := v(s, &"ap")
	for a in sim.living_allies(s.team):
		sim.heal(s, a, heal)
		sim.refresh_flat(a, &"ability_power", power, GRANT_TIME, &"meredine")
		sim.fx(&"pop", a, null, Color("b6a2ff"))
