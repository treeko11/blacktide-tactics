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

## The two stats an ability number can be driven by, and how each is marked.
##
## `tag` goes immediately after the number in a description, so it has to read as
## an annotation rather than as prose. An attack-damage number is *always* a
## percentage of the caster's attack — there is no other kind — so its mark
## carries the "%" and the descriptions no longer spell out "% Attack Damage"
## after every one. `name` is the long form the inspector's legend spells out.
##
## All Latin-1: the web export has no font for anything cleverer, and this text
## goes next to every damage figure in the game.
const SCALING := {
	&"ap": { "tag": " AP", "name": "Ability Power", "colour": "c9a2ff" },
	&"ad": { "tag": "% AD", "name": "Attack Damage", "colour": "ffb27a" },
}


## Must match the ChampionDef id.
func id() -> StringName:
	return &""


## Which of this ability's numbers are driven by which stat: `{ &"dmg": &"ap" }`.
##
## Declared in the ability rather than in the .tres because it is a fact about
## the code below and not a balance number. `scaled()` is what makes an entry
## true, so the declaration has to sit where somebody rewriting the cast will see
## it — a champion's .tres is edited to retune a number, which is exactly the
## edit that must *not* be able to change what the number scales off.
##
## A key left out scales off nothing, which is most of them: a stun duration, a
## shred percentage, a mana refund and a revive threshold are the same figure at
## any stat line. An ability with nothing to declare — Tuck — overrides nothing.
##
## `test_abilities.gd` proves every entry honest by casting the ability twice
## with the stat moved between casts, so a declaration that drifts away from the
## code fails the suite rather than quietly mislabelling a tooltip.
func scaling() -> Dictionary:
	return {}


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
