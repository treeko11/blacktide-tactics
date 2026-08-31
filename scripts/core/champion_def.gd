class_name ChampionDef
extends Resource

## One buyable pirate. Pure data — balance lives here, behaviour lives in
## scripts/core/abilities/<id>.gd, which Content pairs up by id at load.
##
## Nothing in this file may name an autoload. It is compiled as a dependency of
## tools/generate_content.gd, which is a `--script` target where the autoload
## globals do not exist yet, and naming one there fails the whole generator to
## compile. (Learned the same way Incrementile learned it, with MissionDef.)

## Health multiplies by this per star, attack damage by the other. Ability
## numbers do not scale — they are listed explicitly per star in `ability_values`,
## because a flat multiplier makes every three-star ability the same shape.
const HP_PER_STAR := 1.8
const AD_PER_STAR := 1.55

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: String = ""

## 1-5 for shop champions. Monsters are cost 0 and never enter the shop.
@export var cost: int = 1

## Origin and class ids, matched against TraitDef.id.
@export var traits: Array[StringName] = []

@export_group("Base stats")
@export var hp: float = 500.0
@export var ad: float = 50.0
@export var attack_speed: float = 0.65
@export var armor: float = 25.0
@export var magic_resist: float = 25.0
@export var attack_range: int = 1
@export var mana_start: float = 0.0
@export var mana_max: float = 0.0

@export_group("Ability")
@export var ability_name: String = ""
## Description text. `{key}` tokens are filled from `ability_values` — showing all
## three star values when no star is given, and bolding just the one when it is.
@export_multiline var ability_desc: String = ""
## Named arrays of three values, one per star. Read by the ability script.
@export var ability_values: Dictionary = {}


func has_trait(trait_id: StringName) -> bool:
	return traits.has(trait_id)


func casts() -> bool:
	return mana_max > 0.0


## Star-scaled stat block. Star is 1-3.
func stats_at(star: int) -> Dictionary:
	var hp_mul: float = pow(HP_PER_STAR, star - 1)
	var ad_mul: float = pow(AD_PER_STAR, star - 1)
	return {
		"max_hp": roundf(hp * hp_mul),
		"ad": roundf(ad * ad_mul),
		"attack_speed": attack_speed,
		"armor": armor,
		"magic_resist": magic_resist,
		"attack_range": attack_range,
		"mana_start": mana_start,
		"mana_max": mana_max,
	}


## One ability number at a star, e.g. `value(&"dmg", 2)`.
func value(key: StringName, star: int) -> float:
	if not ability_values.has(key):
		return 0.0
	var arr: Array = ability_values[key]
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(star - 1, 0, arr.size() - 1)])


## Gold returned for selling a copy at this star: cost x3 per star up.
func sell_value(star: int) -> int:
	return cost * int(pow(3, star - 1))
