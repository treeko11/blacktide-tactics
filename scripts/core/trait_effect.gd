class_name TraitEffect
extends RefCounted

## The bonus a trait grants once it reaches a breakpoint.
##
## One file per trait in scripts/core/traits/, reporting the trait's id. Applied
## once at the start of a fight, after items, so a percentage bonus sees the
## stats an item just added.
##
## `context` carries:
##   def      TraitDef being applied
##   team     every unit on the side, holder or not
##   holders  only the units that actually have the trait
##   tier     index into the def's breakpoints
##   count    distinct champions sharing the trait
##   team_id  0 or 1

func id() -> StringName:
	return &""


func apply(_sim: Sim, _context: Dictionary) -> void:
	pass


## One trait number at the active tier.
func v(context: Dictionary, key: StringName) -> float:
	var def: TraitDef = context["def"]
	return def.value(key, context["tier"])
