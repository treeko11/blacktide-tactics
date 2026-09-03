class_name SeaEffect
extends RefCounted

## What a sea state does to a fight.
##
## One file per sea in scripts/core/sea/, reporting the sea's id. Applied once
## when a fight is built, *after* items and traits, so a cap this imposes is a
## real cap rather than something a trait can out-scale.
##
## `context` carries:
##   def     SeaDef being applied
##   cells   the hexes it touches, already decided
##
## **The cells are decided outside the fight and handed in.** They are drawn once
## when the stage rolls its sea and stored on `GameState`, because the board has
## to show the player which hexes will be hit *during planning*, before any fight
## exists — and the hexes it shows have to be the same ones the fight uses. A sea
## that picked its own lanes inside `Sim` would mark one set on the board and
## sweep another, seven different ways, in the seven fights of that round.
##
## Cells are in board coordinates and are never mirrored: a lane runs the whole
## height of the board and crosses both halves, which is what keeps the weather
## the same weather for both captains.

func id() -> StringName:
	return &""


## The hexes this sea touches, drawn once per stage.
##
## `rng` is the run's own generator, so a seeded run gets the same weather in the
## same places. Returning nothing is normal — fog touches the whole board.
func cells(_def: SeaDef, _rng: RandomNumberGenerator) -> Array[Vector2i]:
	return []


func apply(_sim: Sim, _context: Dictionary) -> void:
	pass


## One of the sea's numbers.
func v(context: Dictionary, key: StringName, fallback: float = 0.0) -> float:
	var def: SeaDef = context["def"]
	return def.value(key, fallback)


## True when `cell` is one of the hexes this sea is touching.
func touches(context: Dictionary, cell: Vector2i) -> bool:
	return cell in (context["cells"] as Array[Vector2i])
