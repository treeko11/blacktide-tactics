extends Node

## Loads the champion, trait and item definitions and pairs each with its
## behaviour script.
##
## Definitions are .tres under data/ — balance is a file edit. Behaviour is one
## .gd per thing under scripts/core/{abilities,traits,items}/, discovered by
## ScriptDir and keyed by the id each reports. Nothing enumerates either list.
##
## The pairing is checked both ways at startup, and each direction fails
## differently. A def with no behaviour script is a silent no-op in the middle
## of a fight, which looks exactly like a balance problem. A script with no def
## never runs at all: it is a finished feature nobody can reach, and it looks
## like nothing whatsoever.

const CHAMPION_DIR := "res://data/champions"
const TRAIT_DIR := "res://data/traits"
const ITEM_DIR := "res://data/items"
const SEA_DIR := "res://data/sea"

const ABILITY_DIR := "res://scripts/core/abilities"
const TRAIT_SCRIPT_DIR := "res://scripts/core/traits"
const ITEM_SCRIPT_DIR := "res://scripts/core/items"
const SEA_SCRIPT_DIR := "res://scripts/core/sea"

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
var _capstones: Array[ItemDef] = []
var _recipes: Dictionary = {}        ## "blade+lens" -> item id
var _tiers: Dictionary = {}          ## item id -> 1 component, 2 forged, 3 capstone
var _seas: Dictionary = {}           ## id -> SeaDef
var _sea_list: Array[SeaDef] = []

var _abilities: Dictionary = {}
var _trait_effects: Dictionary = {}
var _item_effects: Dictionary = {}
var _sea_effects: Dictionary = {}


func _ready() -> void:
	_load_definitions()
	_abilities = ScriptDir.load_all(ABILITY_DIR, Ability)
	_trait_effects = ScriptDir.load_all(TRAIT_SCRIPT_DIR, TraitEffect)
	_item_effects = ScriptDir.load_all(ITEM_SCRIPT_DIR, ItemEffect)
	_sea_effects = ScriptDir.load_all(SEA_SCRIPT_DIR, SeaEffect)
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
			_recipes[item.key()] = item.id

	for def in _load_dir(SEA_DIR):
		var sea_def: SeaDef = def
		_seas[sea_def.id] = sea_def
		_sea_list.append(sea_def)

	_sort_item_tiers()


## Splits the forged items into tier 2 and tier 3, which is derived from the
## recipe rather than declared on the resource.
##
## A tier is a fact about what an item is *made of*, so a field for it would be a
## second copy of something the recipe already says, and the copy is the one that
## goes stale the first time a recipe is retuned. This runs after every def is
## loaded because a capstone's recipe names two forged items, and the file it
## names may not have been read when its own file was.
func _sort_item_tiers() -> void:
	for id in _items:
		_tiers[id] = _resolve_tier(id, {})
	for item in _items.values():
		if item.is_component:
			continue
		if _tiers.get(item.id, 2) >= 3:
			_capstones.append(item)
		else:
			_forged.append(item)
	_forged.sort_custom(func(a, b): return String(a.id) < String(b.id))
	_capstones.sort_custom(func(a, b): return String(a.id) < String(b.id))


## One more than the deeper of the two things it is forged from.
##
## `seen` breaks a recipe cycle rather than recursing until the stack gives out:
## a pair of items each listing the other is an authoring mistake, and the shape
## it should take is a startup error, not a hang.
func _resolve_tier(id: StringName, seen: Dictionary) -> int:
	var item: ItemDef = _items.get(id)
	if item == null:
		return 0
	if item.is_component:
		return 1
	if item.recipe.size() != 2:
		return 2
	if seen.has(id):
		push_error("Content: item '%s' is in a recipe cycle" % id)
		return 2
	seen[id] = true
	var deepest := 1
	for part in item.recipe:
		deepest = maxi(deepest, _resolve_tier(part, seen))
	seen.erase(id)
	return deepest + 1


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
	for sea_def in _sea_list:
		if not _sea_effects.has(sea_def.id):
			push_error("Content: sea '%s' has no effect script" % sea_def.id)

	# ...and the same question asked backwards, which was the half nobody asked.
	# A def with no script has always been loud. A *script* with no def was
	# silent in both places it could have been caught: nothing here looked, and
	# every content test walks the definitions, so a behaviour file with no
	# resource beside it is dead code the suite cannot see. Four fully written
	# sea effects sat in the tree exactly like that, never rolled, never listed
	# in the almanac, with a green suite over the top of them.
	_verify_orphans(_abilities, _champions, "ability")
	_verify_orphans(_trait_effects, _traits, "trait")
	_verify_orphans(_item_effects, _items, "item")
	_verify_orphans(_sea_effects, _seas, "sea")

	var expected := _components.size() * (_components.size() + 1) / 2
	if _forged.size() != expected:
		push_warning("Content: %d components should forge %d items, found %d"
			% [_components.size(), expected, _forged.size()])

	# A capstone is two *finished* items. One naming a component would load
	# happily, sort itself into tier 2 and quietly become a sixteenth forged
	# item — a recipe the forge chart would draw in the wrong grid.
	for item in _capstones:
		for part in item.recipe:
			if item_tier(part) != 2:
				push_error("Content: capstone '%s' is forged from '%s', which is tier %d"
					% [item.id, part, item_tier(part)])


## Behaviour scripts with nothing to attach to.
##
## `defs` is keyed by the same id the script reports — a champion id for an
## ability, the thing's own id for the other three.
func _verify_orphans(scripts: Dictionary, defs: Dictionary, kind: String) -> void:
	for id in scripts:
		if not defs.has(id):
			push_error("Content: %s script '%s' has no definition" % [kind, id])


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


func capstones() -> Array[ItemDef]:
	return _capstones


func is_component(id: StringName) -> bool:
	return item_tier(id) == 1


func is_capstone(id: StringName) -> bool:
	return item_tier(id) >= 3


## 1 for a component, 2 for an item forged from two of them, 3 for a capstone
## forged from two finished items. 0 for an id nothing knows.
func item_tier(id: StringName) -> int:
	return _tiers.get(id, 0)


## The item two others forge into, or "" if they do not pair.
##
## Tier is not a parameter: the recipe table is keyed by the pair of ids and does
## not care which rung they are on, so one lookup answers both "two components
## make a finished item" and "two finished items make a capstone".
func forge(a: StringName, b: StringName) -> StringName:
	return _recipes.get(ItemDef.recipe_key(a, b), &"")


## Every forge an item can take part in: [{ "with", "makes" }, ...].
##
## This is what the forge chart reads. A player holding two components could not
## previously tell what they made without trying it, which is a bad way to learn
## that you just welded your carry's slots shut — and the same is truer one rung
## up, where the two things being spent are finished items.
##
## Partners are looked for at the item's own tier, because that is the only place
## they can be: a recipe is two things of one tier making one of the next.
func forges_using(item_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other in _peers(item_id):
		var result := forge(item_id, other.id)
		if result != &"":
			out.append({ "with": other.id, "makes": result })
	return out


func _peers(item_id: StringName) -> Array[ItemDef]:
	match item_tier(item_id):
		1: return _components
		2: return _forged
	return []


# --- Item slots --------------------------------------------------------------
#
# The rule lives here, in one function, rather than on RosterUnit — a unit knows
# what it is carrying but not what tier any of it is, and a `can_take_item()`
# that answered only the easy half of the question was a half-truth every caller
# would have believed. RosterUnit deliberately has no such method now.

## Capstones in a loadout.
func capstone_count(items: Array[StringName]) -> int:
	var n := 0
	for id in items:
		if is_capstone(id):
			n += 1
	return n


## How many items a unit carrying `items` may hold in total.
##
## Three, until the second capstone: a capstone is worth about two finished
## items, and the price of the second one is the slot it stands in front of.
func capacity(items: Array[StringName]) -> int:
	if capstone_count(items) >= RosterUnit.MAX_CAPSTONES:
		return RosterUnit.MAX_ITEMS - 1
	return RosterUnit.MAX_ITEMS


func has_room(unit: RosterUnit) -> bool:
	return unit != null and unit.items.size() < capacity(unit.items)


## What dropping `item_id` on a unit holding `items` would do, without doing it.
##
## The one place the drop is decided. `preview_equip` shows the answer and
## `equip_item` acts on it, so the panel that says "this forges Ironclad
## Cutlass" and the code that forges it cannot come apart — they are the same
## call. Returns:
##   allowed  bool          whether the drop lands at all
##   items    Array         the loadout afterwards
##   forges   StringName    what was made, or "" for a plain equip
##   with     StringName    the held item it was made with
##   reason   String        why not, when not
func plan_equip(item_id: StringName, items: Array[StringName]) -> Dictionary:
	var no := func(why: String) -> Dictionary:
		return { "allowed": false, "items": items, "forges": &"", "with": &"", "reason": why }
	if item_def(item_id) == null:
		return no.call("No such item")

	# A capstone is the top of the tree and pairs with nothing, so it only ever
	# takes a slot. Everything below it looks for a partner first, because
	# forging costs no slot and is almost always what the player meant.
	if not is_capstone(item_id):
		for i in items.size():
			var forged: StringName = forge(item_id, items[i])
			if forged == &"":
				continue
			var after := items.duplicate()
			after[i] = forged
			if capstone_count(after) > RosterUnit.MAX_CAPSTONES:
				return no.call("Already carrying two greater items")
			if after.size() > capacity(after):
				# Only reachable forging a second capstone onto a unit that is
				# also holding a third item: the forge frees no slot, and the
				# second capstone takes the one that item is standing in.
				return no.call("A second greater item leaves no room for the third slot")
			return { "allowed": true, "items": after, "forges": forged,
				"with": items[i], "reason": "" }

	var appended := items.duplicate()
	appended.append(item_id)
	if capstone_count(appended) > RosterUnit.MAX_CAPSTONES:
		return no.call("Already carrying two greater items")
	if appended.size() > capacity(appended):
		if capstone_count(appended) >= RosterUnit.MAX_CAPSTONES:
			return no.call("Two greater items fill that pirate")
		return no.call("Carrying three items")
	return { "allowed": true, "items": appended, "forges": &"", "with": &"", "reason": "" }


# --- Behaviour ---------------------------------------------------------------

func ability(champion_id: StringName) -> Ability:
	return _abilities.get(champion_id)


func trait_effect(trait_id: StringName) -> TraitEffect:
	return _trait_effects.get(trait_id)


func sea(id: StringName) -> SeaDef:
	return _seas.get(id)


## Every sea state, in load order. The almanac lists them; nothing else should
## need the whole set — a round has one.
func seas() -> Array[SeaDef]:
	return _sea_list


func sea_effect(sea_id: StringName) -> SeaEffect:
	return _sea_effects.get(sea_id)


func item_effect(item_id: StringName) -> ItemEffect:
	return _item_effects.get(item_id)


# --- Text --------------------------------------------------------------------

## Fills `{key}` tokens in a description from a values dictionary.
##
## With no star, every star's value is shown ("160 / 240 / 400") so a shop card
## tells you what the champion becomes. With a star, only that one, emphasised.
##
## `scaling` is an ability's `scaling()` map, and marks each number with the stat
## that drives it — the reason it is a parameter rather than something read here
## is that traits and items come through this function too, and neither has a
## caster to scale off. Passing nothing leaves every number bare, which is what
## those want.
##
## The mark goes on the *number*, not on the ability, because four abilities are
## hybrids: Corvane, Finn, Hookjaw and Selka each read one figure off attack
## damage and another off ability power in the same sentence, and a single line
## underneath saying "scales with both" cannot say which is which.
static func format_description(text: String, values: Dictionary, star: int = 0,
		scaling: Dictionary = {}) -> String:
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
		replacement += scaling_tag(scaling.get(key, &""))
		out = out.replace("{%s}" % key, replacement)
	return out


## The coloured mark that goes after a number, or "" for one that scales off
## nothing. An unknown stat is also "": a mark nobody can decode is worse than
## no mark, and the legend below the description only lists stats it knows.
static func scaling_tag(stat: StringName) -> String:
	if not Ability.SCALING.has(stat):
		return ""
	var mark: Dictionary = Ability.SCALING[stat]
	return "[color=#%s]%s[/color]" % [mark["colour"], mark["tag"]]


static func _num(value: Variant) -> String:
	var f := float(value)
	return str(roundi(f)) if is_equal_approx(f, roundf(f)) else ("%.2f" % f).trim_suffix("0")
