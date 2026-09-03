class_name SeaDef
extends Resource

## A sea state: the weather one round of a stage is fought in.
##
## Once per stage the run draws one of these, and it lands on a fixed round —
## `GameState.SEA_ROUND` — so a captain always knows which round of the stage
## the sea will have an opinion about, and can build toward it. It is announced
## at the top of that round's planning phase, which is the whole point: the
## player gets the planning phase to answer it.
##
## Pure data. The behaviour lives in scripts/core/sea/<id>.gd, found by
## `ScriptDir` and keyed by the `id()` it reports, exactly as a trait's is.
## Nothing here may name an autoload — see the note at the top of
## champion_def.gd.

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: String = ""

## The line the round opens with. This is the thing the player actually reads,
## so it says what the sea is doing rather than what the numbers are.
@export_multiline var herald: String = ""

## What it does, for the almanac and the forecast. `{key}` tokens are filled
## from `values`.
@export_multiline var description: String = ""

## The first stage this can be drawn on. Stage 1 never draws at all — it is
## monsters and the armoury, and those rounds stay calm water.
@export var earliest_stage: int = 2

## Whether the board should mark the cells this sea will touch. A sea that marks
## nothing is still telegraphed by its herald line; a sea that shoves units
## around specific hexes is not, and an unmarked one of those is a dice roll
## rather than a decision.
@export var marks_cells: bool = false

## Whether standing in a marked cell is where you *want* to be. The board draws
## a boon and a hazard differently, because "get out of these hexes" and "get
## into these hexes" cannot look the same.
@export var boon: bool = false

## What the board paints the marked hexes. Carried here rather than picked by
## the renderer, because the sea is the thing with an identity: rogue waves are
## foam, a red tide is blood, a following sea is the green of a fair wind.
@export var mark_color: Color = Color("7fe3ff")

## Flat numbers read by the sea's script. No tiers — a sea has one strength.
@export var values: Dictionary = {}


func value(key: StringName, fallback: float = 0.0) -> float:
	if not values.has(key):
		return fallback
	return float(values[key])


## The description with its `{key}` tokens filled in.
##
## Not `Content.format_description`: that reads an array per key, one entry per
## tier, and a sea has no tiers. Keeping the values flat is worth a six-line
## formatter — stored as one-entry arrays they would read as "2 / " everywhere
## a number appears.
func text() -> String:
	var out := description
	for key in values:
		out = out.replace("{%s}" % key, "[b]%s[/b]" % _num(float(values[key])))
	return out


static func _num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return ("%.2f" % value).trim_suffix("0")
