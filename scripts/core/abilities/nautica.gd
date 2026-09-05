extends Ability

## Flagship Broadside — a huge area nuke plus fleet-wide stats. The stats are
## the half that wins long fights.
##
## They are a state the fleet is in for GRANT_TIME, refreshed by each cast, and
## this is the ability that most needed it. Three stats at once, on every ally,
## with no ceiling, on a champion who is herself Siren *and* Navigator and so
## supplies the mana engine that drives her own casting: with two mana items she
## banked +2,835 armour and +2,835 magic resist on every ally over one fight,
## against +105 for the same fleet with nothing equipped. That is not a strong
## five-cost, it is a loop — and it is a large part of why two such boards could
## not kill each other before the time limit.
##
## A duration on its own was not enough here, which is the whole reason
## `Sim.refresh_flat` exists: it caps a grant at `amount × casts inside the
## duration`, and with two mana items she casts about twice a second, so ten
## seconds still meant nineteen live stacks. Refreshed, the fleet gains the same
## sixty however often she casts, and the extra casts pay in nuke damage
## instead.

const GRANT_TIME := 10.0


func id() -> StringName:
	return &"nautica"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var cluster := sim.best_cluster(s.team, 2)
	if not cluster.is_empty():
		sim.fx_at(&"nova", cluster["pos"], Color("ffd27a"))
		var damage := scaled(s, &"dmg")
		for e in cluster["units"]:
			sim.damage(s, e, damage, &"magic")

	var resist := v(s, &"res")
	var power := v(s, &"ap")
	for a in sim.living_allies(s.team):
		sim.refresh_flat(a, &"armor", resist, GRANT_TIME, &"nautica")
		sim.refresh_flat(a, &"magic_resist", resist, GRANT_TIME, &"nautica")
		sim.refresh_flat(a, &"ability_power", power, GRANT_TIME, &"nautica")
		sim.fx(&"pop", a, null, Color("ffe9a8"))
