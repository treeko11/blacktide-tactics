extends SeaEffect

## Fog. Nobody can see far enough to shoot far, so every attack range on the
## board is capped.
##
## Marks no cells — it is the whole board — but it is the sea that moves a
## backline the furthest, because a gunner capped at two hexes has to stand
## where a gunner would rather not.
##
## Applied after items and traits, so it is a real cap. A range item bought in
## answer to it is wasted gold, which is the intended cost of not reading the
## herald.


func id() -> StringName:
	return &"fog"


func apply(sim: Sim, context: Dictionary) -> void:
	var cap := maxi(1, int(v(context, &"range", 2.0)))
	for u in sim.units:
		u.attack_range = mini(u.attack_range, cap)
