extends TestCase

## The manifest: every definition has behaviour, and every behaviour has a
## definition.
##
## `Content._verify` asks both questions at startup and pushes an error, which
## the test runner cannot see. These are the same questions asked where a red
## suite reports them, and the second direction is the one that needed a home:
## every other content test in this project walks the *definitions*, so a
## behaviour script with no resource beside it is invisible to all of them. Four
## finished sea effects sat in the tree exactly like that — never rolled, never
## listed in the almanac, with a green suite over the top.
##
## The four extension points are checked from a table rather than one test each,
## because a fifth one added and not listed here is the same drift arriving
## again, and a table is where it shows.


## Behaviour directories against the definitions each is keyed by.
##
## An ability is keyed by its *champion's* id, which is why the pairing is worth
## writing down rather than deriving from the folder name.
func _folders() -> Array:
	var c := content()
	return [
		{ "kind": "ability", "dir": c.ABILITY_DIR, "ids": _ids(c.champions()) },
		{ "kind": "trait", "dir": c.TRAIT_SCRIPT_DIR, "ids": _ids(c.traits()) },
		{ "kind": "item", "dir": c.ITEM_SCRIPT_DIR, "ids": _item_ids() },
		{ "kind": "sea", "dir": c.SEA_SCRIPT_DIR, "ids": _ids(c.seas()) },
	]


func _ids(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append(def.id)
	return out


func _item_ids() -> Array:
	var out: Array = []
	for item in content().components():
		out.append(item.id)
	for item in content().forged_items():
		out.append(item.id)
	return out


## Every id reported by a script in a behaviour folder.
##
## Loaded through `ScriptDir` rather than by reading filenames, because the id a
## script *reports* is the only thing `Content` keys it by — a file named
## `red_tide.gd` reporting `&"red_tid"` pairs with nothing, and a filename check
## would call that fine.
func _script_ids(dir_path: String) -> Array:
	return ScriptDir.load_all(dir_path).keys()


## Nothing in the game is defined and then left without behaviour.
##
## This is the direction that was already loud at startup. It is here as well
## because a `push_error` scrolls past in a tool run and fails nothing.
func test_every_definition_has_a_behaviour_script() -> void:
	for folder in _folders():
		var scripts: Array = _script_ids(folder["dir"])
		for id in folder["ids"]:
			# A champion that cannot cast has no ability, and is meant not to:
			# the monsters are the cost-0 half of the roster.
			if folder["kind"] == "ability" and not content().champion(id).casts():
				continue
			assert_true(scripts.has(id),
				"%s '%s' is defined but has no script in %s"
					% [folder["kind"], id, folder["dir"]])


## Nothing in the game is written and then left unreachable.
##
## The quiet direction. A script with no definition is never loaded into a
## fight, never rolled, never listed anywhere the player can reach, and throws
## nothing at any point — it is a finished feature that looks, from the outside,
## exactly like a feature nobody started.
func test_every_behaviour_script_has_a_definition() -> void:
	for folder in _folders():
		var defined: Array = folder["ids"]
		for id in _script_ids(folder["dir"]):
			assert_true(defined.has(id),
				"%s script '%s' in %s has no definition and can never run"
					% [folder["kind"], id, folder["dir"]])
