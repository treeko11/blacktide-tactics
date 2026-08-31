class_name RosterUnit
extends RefCounted

## A pirate somebody owns, between fights.
##
## Distinct from SimUnit, which is the same pirate *inside* a battle with all its
## combat state. This one only knows what it is, how upgraded it is, what it is
## carrying and where it stands. A fight is built from these and throws its own
## copies away afterwards, which is why a battle can never corrupt a roster.
##
## Shared by the player and the seven bots, so a bot holding items works through
## exactly the same code the player's do.

## Sentinel for a unit that is on the bench rather than the board.
const BENCHED := Vector2i(-1, -1)

const MAX_ITEMS := 3

static var _next_uid: int = 1

var uid: int = 0
var champion: ChampionDef = null
var star: int = 1
var items: Array[StringName] = []
var cell: Vector2i = BENCHED


func _init(champion_def: ChampionDef = null, unit_star: int = 1) -> void:
	uid = _next_uid
	_next_uid += 1
	champion = champion_def
	star = unit_star


func id() -> StringName:
	return champion.id if champion != null else &""


func on_board() -> bool:
	return cell != BENCHED


func can_take_item() -> bool:
	return items.size() < MAX_ITEMS


## Gold returned for selling: the champion's cost, tripling per star.
func sell_value() -> int:
	return champion.sell_value(star) if champion != null else 0


## What a fight needs to know about this unit.
func to_entry() -> Dictionary:
	return {
		"champion": champion,
		"star": star,
		"items": items.duplicate(),
		"cell": cell,
	}


## How strong this is, roughly, for a bot deciding what to field.
func power() -> float:
	if champion == null:
		return 0.0
	return champion.cost * pow(3.0, star - 1) * 10.0
