class_name TraitDef
extends Resource

## An Origin or a Class. Fielding enough *different* champions sharing a trait
## activates it at a breakpoint tier.
##
## Counting distinct champions rather than bodies is the rule that makes trait
## building interesting: three copies of one pirate is a star-up, not a trait.
##
## Pure data. The bonus itself lives in scripts/core/traits/<id>.gd. Nothing here
## may name an autoload — see the note at the top of champion_def.gd.

enum Kind { ORIGIN, CLASS }

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: String = ""
@export var kind: Kind = Kind.ORIGIN

## `{key}` tokens are filled from `values`.
@export_multiline var description: String = ""

## Champion counts that activate each tier, ascending, e.g. [2, 4, 6].
@export var breakpoints: Array[int] = []

## Named arrays, one entry per breakpoint. Read by the trait script.
@export var values: Dictionary = {}


## Index into `breakpoints` for a given count, or -1 when the trait is inactive.
func tier_for(count: int) -> int:
	var tier := -1
	for i in breakpoints.size():
		if count >= breakpoints[i]:
			tier = i
	return tier


## The next breakpoint above a count, or 0 when the trait is already maxed.
func next_breakpoint(count: int) -> int:
	for b in breakpoints:
		if b > count:
			return b
	return 0


func value(key: StringName, tier: int) -> float:
	if not values.has(key) or tier < 0:
		return 0.0
	var arr: Array = values[key]
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(tier, 0, arr.size() - 1)])


## Styling band for the manifest badge: bronze, silver, gold, then prismatic for
## a trait taken past its last listed breakpoint.
func tier_style(tier: int) -> StringName:
	if tier < 0:
		return &"off"
	if breakpoints.size() >= 4 and tier >= 3:
		return &"prism"
	match tier:
		0: return &"bronze"
		1: return &"silver"
		_: return &"gold"
	return &"gold"
