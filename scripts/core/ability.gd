class_name Ability
extends RefCounted

## What a champion does when its mana fills.
##
## One file per champion in scripts/core/abilities/, named after the champion and
## reporting the same id. Content scans the folder through ScriptDir and pairs
## each script with the ChampionDef sharing its id — nothing enumerates them, so
## adding a pirate is adding a .tres and a .gd and nothing else.
##
## Numbers live in the def's `ability_values`, not here. `v()` reads one at the
## caster's star, so a balance change is a data edit.

## Must match the ChampionDef id.
func id() -> StringName:
	return &""


## Called once when the cast finishes. `sim` is the battle, `self_unit` the caster.
func cast(_sim: Sim, _self_unit: SimUnit) -> void:
	pass


## One ability number at the caster's star.
func v(unit: SimUnit, key: StringName) -> float:
	return unit.def.value(key, unit.star)


## The same number scaled by the caster's ability power, which is what almost
## every damage and healing figure wants.
func scaled(unit: SimUnit, key: StringName) -> float:
	return unit.def.value(key, unit.star) * unit.power()
