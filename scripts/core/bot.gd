class_name Bot
extends Captain

## One of the seven rival captains.
##
## Bots buy from the *same* shared champion pool the player does, so a bot
## forcing a three-star carry genuinely takes those copies off the board. That is
## the whole reason the pool is shared, and it is why a bot's shopping happens
## through GameState rather than against a private list.
##
## Nothing here names an autoload: the state object is passed in. Core scripts
## that name `GameState` become uncompilable inside a `--script` target, which is
## the trap documented at the top of tools/tool_script.gd.
##
## **Bots hold and forge items.** In the JavaScript build they were handed one
## random finished item per stage and never combined anything, which made the
## items system look broken from the outside — the player could not see the AI
## using items because it essentially was not. They now draw the same loot on the
## same rounds and equip it by the same rules.

const NAMES := [
	["Captain Mordecai", "💀"], ["Redsail Yara", "🏴"], ["Old Man Fathom", "🐙"],
	["Widow Calder", "🗡"], ["Bosun Krell", "💪"], ["The Gull", "🐦"],
	["Saltbeard Ossy", "🍺"], ["Lady Undertow", "🌊"], ["Ironhook Vance", "🪝"],
	["Squid-Eye Pell", "🦑"], ["Cannonade Rue", "🔫"], ["Ghostwake Tam", "👻"],
]

enum Personality { ECON, AGGRO, BALANCED, REROLL }

## How far bots push their level by stage. Kept a little behind a good human,
## who can read the shop and react to it.
const LEVEL_BY_STAGE := { 1: 3, 2: 4, 3: 5, 4: 6, 5: 7, 6: 8, 7: 8, 8: 9 }

## Bench depth beyond the board, before a bot starts selling its worst.
const BENCH_DEPTH := 9

var index: int = 0
var units: Array[RosterUnit] = []
var personality: Personality = Personality.BALANCED
## The origin and class this bot is chasing, which biases everything it buys.
var chasing: Array[StringName] = []


func _init(bot_index: int = 0, bot_name: String = "", bot_icon: String = "") -> void:
	super(bot_name, bot_icon)
	index = bot_index
	is_bot = true


## Picks a comp identity to chase. Done here rather than in _init so the bot can
## be built before Content is available.
func choose_comp(content_node: Node, rng: RandomNumberGenerator) -> void:
	var origins: Array = content_node.trait_ids_of_kind(TraitDef.Kind.ORIGIN)
	var classes: Array = content_node.trait_ids_of_kind(TraitDef.Kind.CLASS)
	chasing = [
		origins[rng.randi_range(0, origins.size() - 1)],
		classes[rng.randi_range(0, classes.size() - 1)],
	]
	personality = Personality.values()[rng.randi_range(0, Personality.size() - 1)]


func target_level(stage: int) -> int:
	var wanted: int = LEVEL_BY_STAGE.get(mini(8, stage), MAX_LEVEL)
	if personality == Personality.AGGRO:
		wanted = mini(MAX_LEVEL, wanted + 1)
	elif personality == Personality.REROLL:
		wanted = maxi(3, wanted - 1)
	return wanted


## Gold a bot will not spend, so an economy bot actually banks interest.
func reserve(stage: int) -> int:
	match personality:
		Personality.ECON:
			return 30 if stage < 5 else 10
		Personality.BALANCED:
			return 20 if stage < 4 else 0
		_:
			return 0


# --- The round's turn --------------------------------------------------------

## Income, levelling, shopping, merging, and itemising, in that order.
func take_turn(state: Node) -> void:
	if not alive:
		return
	var stage: int = state.stage

	var income := round_income()
	if last_result > 0:
		income += 1
	# Handicap. Bots cannot read a shop or plan two rounds ahead, so they are paid
	# to keep pace. Worth re-measuring now they also use items.
	income += maxi(0, stage - 2)
	gold += income
	add_xp(2)

	var guard := 0
	while level < target_level(stage) and gold >= 4 + reserve(stage) and guard < 20:
		gold -= 4
		add_xp(4)
		guard += 1

	var rolls := 1
	if personality == Personality.REROLL and gold > 40:
		rolls = 4
	if gold > 55:
		rolls += 2
	for r in rolls:
		if r > 0:
			if gold < 2 + reserve(stage):
				break
			gold -= 2
		_shop(state)

	_merge(state)
	equip_items(state)


func _shop(state: Node) -> void:
	# roll_shop has already taken these cards out of the shared pool, so anything
	# not bought must be handed back or the pool bleeds away.
	var offers: Array = state.roll_shop(level)
	offers.sort_custom(func(a, b): return _score(a, state) > _score(b, state))

	var unsold: Array[StringName] = []
	var stage: int = state.stage
	for champion_id in offers:
		var champion: ChampionDef = state.content.champion(champion_id)
		var too_poor := gold < champion.cost
		var saving_up := (gold - champion.cost) < reserve(stage) and units.size() >= level
		var junk := _score(champion_id, state) < 25.0 and units.size() >= level + 3
		var full := units.size() >= level + BENCH_DEPTH
		if too_poor or saving_up or junk or full:
			unsold.append(champion_id)
			continue
		gold -= champion.cost
		units.append(RosterUnit.new(champion, 1))

	state.return_to_pool_many(unsold)


## How much this bot wants a champion: cost, whether it fits the comp it is
## chasing, and how close it already is to an upgrade.
func _score(champion_id: StringName, state: Node) -> float:
	var champion: ChampionDef = state.content.champion(champion_id)
	if champion == null:
		return 0.0
	var score := champion.cost * 10.0
	for trait_id in champion.traits:
		if chasing.has(trait_id):
			score += 22.0
	var copies := 0
	for u in units:
		if u.id() == champion_id and u.star == 1:
			copies += 1
	if copies == 1:
		score += 18.0
	elif copies >= 2:
		score += 45.0     # one away from a star-up, take it over almost anything
	return score


## Merges three of a kind, then sells down to the bench limit.
func _merge(state: Node) -> void:
	for star in [1, 2]:
		var merged := true
		while merged:
			merged = false
			var groups: Dictionary = {}
			for u in units:
				if u.star != star:
					continue
				if not groups.has(u.id()):
					groups[u.id()] = []
				groups[u.id()].append(u)

			for champion_id in groups:
				var group: Array = groups[champion_id]
				if group.size() < 3:
					continue
				var three := group.slice(0, 3)
				var carried: Array[StringName] = []
				for u in three:
					carried.append_array(u.items)
					units.erase(u)
				var upgraded := RosterUnit.new(three[0].champion, star + 1)
				upgraded.items.assign(carried.slice(0, RosterUnit.MAX_ITEMS))
				units.append(upgraded)
				# Anything that would not fit goes back in the hold.
				items.append_array(carried.slice(RosterUnit.MAX_ITEMS))
				merged = true
				break

	if units.size() > level + BENCH_DEPTH:
		units.sort_custom(func(a, b): return _keep_score(a) > _keep_score(b))
		var cut := units.slice(level + BENCH_DEPTH)
		units = units.slice(0, level + BENCH_DEPTH)
		for u in cut:
			items.append_array(u.items)
			state.return_to_pool(u.id(), u.star)


func _keep_score(u: RosterUnit) -> float:
	var score := u.power()
	for trait_id in u.champion.traits:
		if chasing.has(trait_id):
			score += 8.0
	return score


# --- Items -------------------------------------------------------------------

## Loot for finishing the same round types the player loots on.
func grant_loot(round_type: StringName, state: Node, rng: RandomNumberGenerator) -> void:
	if not alive:
		return
	var content_node: Node = state.content
	if round_type == &"pve":
		var components: Array = content_node.components()
		var count: int = 1 if int(state.stage) == 1 else (1 if rng.randf() < 0.5 else 2)
		for i in count:
			items.append(components[rng.randi_range(0, components.size() - 1)].id)
	elif round_type == &"armoury":
		var forged: Array = content_node.forged_items()
		items.append(forged[rng.randi_range(0, forged.size() - 1)].id)


## Hands everything in the hold to whichever fielded unit wants it most,
## forging components together on the way.
func equip_items(state: Node) -> void:
	var carries := board_units()
	if carries.is_empty():
		return
	var content_node: Node = state.content

	var remaining: Array[StringName] = []
	for item_id in items:
		var holder := _best_holder(carries, item_id, content_node)
		if holder == null:
			remaining.append(item_id)
			continue
		_give(holder, item_id, content_node)
	items = remaining


## Prefers a unit that can forge this component with something it already holds,
## then simply the strongest unit with a free slot.
func _best_holder(carries: Array[RosterUnit], item_id: StringName,
		content_node: Node) -> RosterUnit:
	if content_node.is_component(item_id):
		for u in carries:
			for held in u.items:
				if content_node.forge(item_id, held) != &"":
					return u
	for u in carries:
		if u.can_take_item():
			return u
	return null


func _give(holder: RosterUnit, item_id: StringName, content_node: Node) -> void:
	if content_node.is_component(item_id):
		for i in holder.items.size():
			var forged: StringName = content_node.forge(item_id, holder.items[i])
			if forged != &"":
				holder.items[i] = forged
				return
	if holder.can_take_item():
		holder.items.append(item_id)
	else:
		items.append(item_id)


# --- Fielding ----------------------------------------------------------------

## The units this bot would put on the board: its strongest, up to its level.
func board_units() -> Array[RosterUnit]:
	var ordered := units.duplicate()
	ordered.sort_custom(func(a, b): return _keep_score(a) > _keep_score(b))
	var out: Array[RosterUnit] = []
	out.assign(ordered.slice(0, board_capacity()))
	return out


## A formation in the bot's own half: melee on the front rows, ranged behind.
func formation() -> Array:
	var melee: Array[RosterUnit] = []
	var ranged: Array[RosterUnit] = []
	for u in board_units():
		if u.champion.attack_range <= 1:
			melee.append(u)
		else:
			ranged.append(u)

	var front := _seats([4, 5])
	var back := _seats([7, 6])
	var out: Array = []
	var f := 0
	var b := 0

	for u in melee:
		var cell := Vector2i(-1, -1)
		if f < front.size():
			cell = front[f]
			f += 1
		elif b < back.size():
			cell = back[b]
			b += 1
		else:
			break
		out.append(_entry(u, cell))

	for u in ranged:
		var cell := Vector2i(-1, -1)
		if b < back.size():
			cell = back[b]
			b += 1
		elif f < front.size():
			cell = front[f]
			f += 1
		else:
			break
		out.append(_entry(u, cell))

	return out


## Seats filled from the middle outward, so a small board still meets in the
## centre rather than hugging one flank.
func _seats(rows: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in rows:
		for col in [3, 2, 4, 1, 5, 0, 6]:
			out.append(Vector2i(col, row))
	return out


func _entry(u: RosterUnit, cell: Vector2i) -> Dictionary:
	return {
		"champion": u.champion,
		"star": u.star,
		"items": u.items.duplicate(),
		"cell": cell,
	}


## Active traits on this bot's fielded board, for the scouting tooltip.
func trait_summary(content_node: Node) -> Array[Dictionary]:
	var seen: Dictionary = {}
	for u in board_units():
		for trait_id in u.champion.traits:
			if not seen.has(trait_id):
				seen[trait_id] = {}
			seen[trait_id][u.id()] = true

	var out: Array[Dictionary] = []
	for trait_id in seen:
		var def: TraitDef = content_node.trait_def(trait_id)
		if def == null:
			continue
		var count: int = seen[trait_id].size()
		var tier := def.tier_for(count)
		if tier < 0:
			continue
		out.append({ "id": trait_id, "count": count, "tier": tier })
	out.sort_custom(func(a, b):
		return a["tier"] > b["tier"] or (a["tier"] == b["tier"] and a["count"] > b["count"]))
	return out


## Builds the seven rivals with distinct names.
static func make_lobby(count: int, content_node: Node,
		rng: RandomNumberGenerator) -> Array[Bot]:
	var pool := NAMES.duplicate()
	# Fisher-Yates through the sim's own generator, so a seeded game is repeatable.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	var out: Array[Bot] = []
	for i in mini(count, pool.size()):
		var bot := Bot.new(i + 1, pool[i][0], pool[i][1])
		bot.choose_comp(content_node, rng)
		out.append(bot)
	return out
