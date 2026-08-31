extends TraitEffect

## Tidecaller — the tide mends what steel breaks.
##
## The overheal-into-shield cap is what keeps this from being worthless on a full
## fleet: healing a unit at full health still builds something. The sim does the
## pouring in `_tick_tide_regen`.

func id() -> StringName:
	return &"tidecaller"


func apply(_sim: Sim, context: Dictionary) -> void:
	var per_second := v(context, &"hps") / 100.0
	var cap := v(context, &"cap") / 100.0
	for u in context["team"]:
		u.regen = { "pct": per_second, "cap": cap }
