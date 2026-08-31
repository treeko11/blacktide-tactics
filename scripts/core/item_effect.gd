class_name ItemEffect
extends RefCounted

## What an item does to the unit carrying it.
##
## One file per item in scripts/core/items/, reporting the item's id. Applied
## once at the start of a fight, before traits.
##
## An item that does something *during* the fight registers a hook on the unit
## rather than asking to be ticked — `unit.hooks_on_attack.append(...)` and
## friends. Anything a hook needs to remember between calls goes in
## `unit.scratch`, keyed by the item id, so no item needs a field on SimUnit.

func id() -> StringName:
	return &""


func apply(_sim: Sim, _unit: SimUnit) -> void:
	pass


## Per-unit scratch value for this item, created from `initial` on first use.
func scratch(unit: SimUnit, initial: Variant = 0) -> Variant:
	if not unit.scratch.has(id()):
		unit.scratch[id()] = initial
	return unit.scratch[id()]


func set_scratch(unit: SimUnit, value: Variant) -> void:
	unit.scratch[id()] = value
