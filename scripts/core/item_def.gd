class_name ItemDef
extends Resource

## A component, or a forged item made from two of them.
##
## Five components combine into every one of the fifteen pairs, so a component is
## never a dead end — that is the property the forge chart in the UI is there to
## make obvious, because a player who cannot see it hoards components instead of
## building anything.
##
## Pure data. The effect lives in scripts/core/items/<id>.gd. Nothing here may
## name an autoload — see the note at the top of champion_def.gd.

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: String = ""
@export_multiline var description: String = ""

## True for the five raw components. Forged items have a `recipe` instead.
@export var is_component: bool = false

## The two component ids this is forged from. Empty for components themselves.
@export var recipe: Array[StringName] = []


## Recipe key for a pair of components, order-independent: "blade+lens".
static func recipe_key(a: StringName, b: StringName) -> StringName:
	var pair := [String(a), String(b)]
	pair.sort()
	return StringName("%s+%s" % pair)


func key() -> StringName:
	if recipe.size() != 2:
		return &""
	return recipe_key(recipe[0], recipe[1])
