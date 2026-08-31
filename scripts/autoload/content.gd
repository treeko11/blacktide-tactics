extends Node

## Loads the champion, trait and item definitions and pairs each with its
## behaviour script.
##
## Definitions are .tres under data/ — balance is a file edit. Behaviour is one
## .gd per thing under scripts/core/{abilities,traits,items}/, discovered by
## ScriptDir and keyed by the id each reports. Nothing enumerates either list.
##
## A def with no matching behaviour script is a loud failure at startup, not a
## silent no-op in the middle of a fight. That has to be loud: an ability that
## quietly does nothing looks exactly like a balance problem.

const CHAMPION_DIR := "res://data/champions"
const TRAIT_DIR := "res://data/traits"
const ITEM_DIR := "res://data/items"

const ABILITY_DIR := "res://scripts/core/abilities"
const TRAIT_SCRIPT_DIR := "res://scripts/core/traits"
const ITEM_SCRIPT_DIR := "res://scripts/core/items"

## How many copies of each cost exist in the shared pool, across all eight
## captains. Scarcity is the reason two players cannot both force the same
## three-star carry.
const POOL_SIZE := { 1: 29, 2: 22, 3: 18, 4: 12, 5: 10 }

## Card border colours by cost, used everywhere a cost is shown.
const COST_COLORS := {
	0: Color("6b7a86"), 1: Color("9aa7b4"), 2: Color("3fbf7f"),
	3: Color("4a9dff"), 4: Color("c46bff"), 5: Color("ffb32e"),
}

var _champions: Dictionary = {}      ## id -> ChampionDef
var _champion_list: Array[ChampionDef] = []
var _shop_champions: Array[ChampionDef] = []
var _traits: Dictionary = {}         ## id -> TraitDef
var _trait_list: Array[TraitDef] = []
var _items: Dictionary = {}          ## id -> ItemDef
var _components: Array[ItemDef] = []
var _forged: Array[ItemDef] = []
var _recipes: Dictionary = {}        ## "blade+lens" -> item id

var _abilities: Dictionary = {}
var _trait_effects: Dictionary = {}
var _item_effects: Dictionary = {}


func _ready() -> void:
	_load_definitions()
	_abilities = ScriptDir.load_all(ABILITY_DIR, Ability)
	_trait_effects = ScriptDir.load_all(TRAIT_SCRIPT_DIR, TraitEffect)
	_item_effects = ScriptDir.load_all(ITEM_SCRIPT_DIR, ItemEffect)
	_verify()


func _load_definitions() -> void:
	for def in _load_dir(CHAMPION_DIR):
		var champion: ChampionDef = def
		_champions[champion.id] = champion
		_champion_list.append(champion)
		if champion.cost > 0:
			_shop_champions.append(champion)

	for def in _load_dir(TRAIT_DIR):
		var trait_def: TraitDef = def
		_traits[trait_def.id] = trait_def
		_trait_list.append(trait_def)

	for def in _load_dir(ITEM_DIR):
		var item: ItemDef = def
		_items[item.id] = item
		if item.is_component:
			_components.append(item)
		else:
			_forged.append(item)
			_recipes[item.key()] = item.id


func _load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Content: no directory at %s" % path)
		return out
	var files := dir.get_files()
	files.sort()
	for file in files:
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res: Resource = load(path.path_join(name))
		if res == null:
			push_error("Content: failed to load %s" % name)
			continue
		out.append(res)
	return out


## Every def must have a behaviour script and vice versa. Champions that cannot
## cast are exempt: monsters have no ability.
func _verify() -> void:
	for champion in _champion_list:
		if champion.casts() and not _abilities.has(champion.id):
			push_error("Content: champion '%s' casts but has no ability script" % champion.id)
	for trait_def in _trait_list:
		if not _trait_effects.has(trait_def.id):
			push_error("Content: trait '%s' has no effect script" % trait_def.id)
	for id in _items:
		if not _item_effects.has(id):
			push_error("Content: item '%s' has no effect script" % id)

	var expected := _components.size() * (_components.size() + 1) / 2
	if _forged.size() != expected:
		push_warning("Content: %d components should forge %d items, found %d"
			% [_components.size(), expected, _forged.size()])


# --- Champions ---------------------------------------------------------------

func champion(id: StringName) -> ChampionDef:
	return _champions.get(id)


func champions() -> Array[ChampionDef]:
	return _champion_list


## Only the ones that can appear in a shop — excludes the cost-0 monsters.
func shop_champions() -> Array[ChampionDef]:
	return _shop_champions


func champions_of_cost(cost: int) -> Array[ChampionDef]:
	var out: Array[ChampionDef] = []
	for c in _shop_champions:
		if c.cost == cost:
			out.append(c)
	return out


func pool_size(cost: int) -> int:
	return POOL_SIZE.get(cost, 0)


func cost_color(cost: int) -> Color:
	return COST_COLORS.get(cost, COST_COLORS[1])


# --- Traits ------------------------------------------------------------------

func trait_def(id: StringName) -> TraitDef:
	return _traits.get(id)


func traits() -> Array[TraitDef]:
	return _trait_list


func trait_ids_of_kind(kind: TraitDef.Kind) -> Array[StringName]:
	var out: Array[StringName] = []
	for t in _trait_list:
		if t.kind == kind:
			out.append(t.id)
	return out


# --- Items -------------------------------------------------------------------

func item_def(id: StringName) -> ItemDef:
	return _items.get(id)


func components() -> Array[ItemDef]:
	return _components


func forged_items() -> Array[ItemDef]:
	return _forged


func is_component(id: StringName) -> bool:
	var item := item_def(id)
	return item != null and item.is_component


## The item two components forge into, or "" if they do not pair.
func forge(a: StringName, b: StringName) -> StringName:
	return _recipes.get(ItemDef.recipe_key(a, b), &"")


## Every forge a component can take part in: [{ "with", "makes" }, ...].
##
## This is what the forge chart reads. A player holding two components could not
## previously tell what they made without trying it, which is a bad way to learn
## that you just welded your carry's slots shut.
func forges_using(component_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other in _components:
		var result := forge(component_id, other.id)
		if result != &"":
			out.append({ "with": other.id, "makes": result })
	return out


# --- Behaviour ---------------------------------------------------------------

func ability(champion_id: StringName) -> Ability:
	return _abilities.get(champion_id)


func trait_effect(trait_id: StringName) -> TraitEffect:
	return _trait_effects.get(trait_id)


func item_effect(item_id: StringName) -> ItemEffect:
	return _item_effects.get(item_id)


# --- Text --------------------------------------------------------------------

## Fills `{key}` tokens in a description from a values dictionary.
##
## With no star, every star's value is shown ("160 / 240 / 400") so a shop card
## tells you what the champion becomes. With a star, only that one, emphasised.
static func format_description(text: String, values: Dictionary, star: int = 0) -> String:
	var out := text
	for key in values:
		var arr: Array = values[key]
		if arr.is_empty():
			continue
		var replacement := ""
		if star > 0:
			replacement = "[b]%s[/b]" % _num(arr[clampi(star - 1, 0, arr.size() - 1)])
		else:
			var parts := PackedStringArray()
			for value in arr:
				parts.append(_num(value))
			replacement = "[b]%s[/b]" % " / ".join(parts)
		out = out.replace("{%s}" % key, replacement)
	return out


static func _num(value: Variant) -> String:
	var f := float(value)
	return str(roundi(f)) if is_equal_approx(f, roundf(f)) else ("%.2f" % f).trim_suffix("0")
