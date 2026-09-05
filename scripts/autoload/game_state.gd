extends Node

## The run: economy, the shared champion pool, the shop, the round loop, and the
## seven rival captains.
##
## Everything the HUD needs to know is announced on `Events` rather than read out
## of here by polling, so the presentation layer can be replaced without this file
## changing. The battle itself lives in Sim; this owns when one starts and what
## its result costs.
##
## `_process` only accumulates real time and calls `Sim.step()` some number of
## times. The simulation itself advances strictly in fixed TICK increments — the
## frame rate and the speed multiplier decide *how many* steps happen, never how
## big one is, so a fight at 4x resolves identically to the same fight at 1x.

enum Phase { PLAN, COMBAT, RESULT, ARMOURY, OVER }

const SHOP_SIZE := 5
const BENCH_SIZE := 9
const PLAN_SECONDS := 32.0

## How long is left when the shop warns it is closing.
##
## The old build put the round clock in the top bar, diagonally opposite the shop
## the player spends the planning phase staring at, and never said anything when
## it ran low. Rounds ended mid-purchase.
const WARNING_SECONDS := 8.0

## Ticks given to each unwatched fight per frame while the player watches theirs.
##
## Six fights resolved in one go is up to 7,600 ticks in a single frame: a third
## of a second of a still window on a desktop by stage 5, and several times that
## in a browser, where it reads as the game having crashed. A fight the player is
## watching lasts hundreds of frames, and this is the work of the round spread
## across them — eight ticks each is enough to finish every one of them inside
## four seconds of a fight, and costs a fraction of a millisecond a frame.
const UNWATCHED_STEPS_PER_FRAME := 8

## How long the result banner holds before the next planning phase.
const RESULT_SECONDS := 2.6
const POST_COMBAT_SECONDS := 1.3

## Shop odds by level: the chance of each cost appearing in a slot.
const SHOP_ODDS := {
	1: [100, 0, 0, 0, 0],
	2: [100, 0, 0, 0, 0],
	3: [75, 25, 0, 0, 0],
	4: [55, 30, 15, 0, 0],
	5: [45, 33, 20, 2, 0],
	6: [30, 40, 25, 5, 0],
	7: [19, 30, 35, 15, 1],
	8: [17, 24, 32, 24, 3],
	9: [10, 18, 25, 35, 12],
}

## Hull lost for losing a round, by stage. Rises steeply — a bad stage 6 ends runs.
const STAGE_DAMAGE := [0, 0, 2, 3, 5, 7, 9, 11, 14]

## What the two shop buttons cost. The HUD reads these rather than carrying its
## own copies — a price shown on a button and charged somewhere else drifts.
## The round of every stage that is fought in weather.
##
## Fixed rather than rolled, so a captain always knows which round the sea will
## have an opinion about and can build toward it — the whole payoff of one sea a
## stage instead of one every round. Stage 1 lands on the armoury and stages 2
## on land on a captain fight, which is deliberate: monster rounds are a floor
## anything on the board should clear, and a fog bank over 3-3 turns that floor
## into a scripted loss.
const SEA_ROUND := 4

const REROLL_COST := 2
const XP_COST := 4
const XP_PER_PURCHASE := 4
const XP_PER_ROUND := 2

var content: Node = null
var rng := RandomNumberGenerator.new()

var phase: Phase = Phase.PLAN
var stage: int = 1
var round_number: int = 1
var plan_timer: float = PLAN_SECONDS
var speed: int = 1

var player: Captain = null
var bots: Array[Bot] = []

## The player's fielded pirates and their bench. The bench is fixed length with
## nulls for empty slots, so a slot index is stable while dragging.
var board: Array[RosterUnit] = []
var bench: Array[RosterUnit] = []

var shop: Array[StringName] = []
var shop_locked: bool = false

## Remaining copies of each champion, shared by all eight captains.
var pool: Dictionary = {}

var sim: Sim = null

## The six fights nobody watches, stepped alongside the one that is.
##
## Each entry is { "sim": Sim, "a": Bot, "b": Bot }, with `b` null on a monster
## round. They are opened when the player's fight starts and read when it ends.
var _bot_fights: Array = []

## Whether this fight's overtime has been announced yet. One line per fight.
var _overtime_announced: bool = false

## The last fight's meter rows and how long it ran, kept after the sim is thrown
## away. The player reads the DPS meter in the aftermath and through the planning
## phase that follows, and by then `_advance_round` has disposed the battle those
## numbers came from. See `battle_stats()`.
var _battle_stats: Array[Dictionary] = []
var _battle_time: float = 0.0

var opponent_name: String = ""
var opponent_icon: String = ""
var opponent_bot: Bot = null
var _last_opponent_index: int = -1

## The sea state drawn for this stage, and the hexes it will touch. Drawn once
## when the stage opens rather than when the round arrives, so the forecast can
## name it several rounds out. Empty when the stage drew nothing.
var sea_id: StringName = &""
var sea_cells: Array[Vector2i] = []

## The order the remaining seas will arrive in, next one at the back.
##
## A bag rather than a weighted draw each stage. Drawing independently, a seven
## stage run could be fog three times and never once show a following sea — and
## a player who has met one sea and not the others has not met the system, they
## have met that sea. Dealing a shuffled hand means every sea is seen before any
## repeats, and the order is still different every run.
var _sea_bag: Array[StringName] = []

var armoury_offer: Array[StringName] = []
var log_lines: Array[Dictionary] = []

## Skips the pauses that exist only so the player can read a banner.
##
## Set by tools/playthrough.gd, which plays a whole run through the real round
## loop and has no interest in watching the aftermath screen for three seconds a
## round. Nothing else should touch it.
var instant: bool = false

## True while the opening planning phase is holding at the line.
##
## A run used to begin with its 32-second clock already running, behind the
## almanac that opens over it — so the first round of a new player's first game
## was spent reading the rules and the shop closed on them. The clock now starts
## when they say so: closing the almanac, or pressing SET SAIL. Only the *first*
## planning phase of a run waits; the almanac opened mid-round is a reference,
## not a timeout, and the clock keeps running behind it.
##
## `instant` runs are the tools, which have nobody to wait for.
var awaiting_start: bool = false

var _warned_this_round: bool = false
var _sim_accumulator: float = 0.0
var _post_combat: float = 0.0
var _result_timer: float = 0.0


func _ready() -> void:
	content = get_node(^"/root/Content")
	rng.randomize()
	start_game()


# =============================================================================
#  Setting up a run
# =============================================================================

func start_game() -> void:
	_dispose_sim()
	stage = 1
	round_number = 1
	shop_locked = false
	log_lines.clear()
	speed = 1

	pool.clear()
	for champion in content.shop_champions():
		pool[champion.id] = content.pool_size(champion.cost)

	player = Captain.new("You", "🧭")
	board.clear()
	bench.clear()
	bench.resize(BENCH_SIZE)

	bots = Bot.make_lobby(7, content, rng)
	_sea_bag.clear()
	_roll_sea()

	shop.clear()
	_battle_stats.clear()
	_battle_time = 0.0
	refresh_shop(true)
	log_line("The fleet sets out. Eight captains, one horizon.", &"")
	awaiting_start = not instant
	Events.run_hold_changed.emit(awaiting_start)
	_begin_planning()


func everyone() -> Array[Captain]:
	var out: Array[Captain] = [player]
	for b in bots:
		out.append(b)
	return out


func alive_captains() -> Array[Captain]:
	var out: Array[Captain] = []
	for c in everyone():
		if c.alive:
			out.append(c)
	return out


func log_line(text: String, style: StringName = &"") -> void:
	log_lines.push_front({ "text": text, "style": style })
	if log_lines.size() > 60:
		log_lines.pop_back()
	Events.logged.emit(text, style)


## A transient message in front of the player. The old build computed these and
## then never displayed one, so "Not enough gold" looked like the click was
## simply ignored.
func notify(text: String, style: StringName = &"warn") -> void:
	Events.notice.emit(text, style)


# =============================================================================
#  The shared champion pool
# =============================================================================

func take_from_pool(champion_id: StringName) -> bool:
	if pool.get(champion_id, 0) <= 0:
		return false
	pool[champion_id] -= 1
	return true


## Returns copies to the pool. A two-star is three copies, a three-star is nine.
func return_to_pool(champion_id: StringName, star: int = 1) -> void:
	if not pool.has(champion_id):
		return
	pool[champion_id] += int(pow(3, star - 1))


func return_to_pool_many(champion_ids: Array) -> void:
	for id in champion_ids:
		if id != &"":
			return_to_pool(id, 1)


func copies_left(champion_id: StringName) -> int:
	return pool.get(champion_id, 0)


func _available_of_cost(cost: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for champion in content.champions_of_cost(cost):
		if pool.get(champion.id, 0) > 0:
			out.append(champion.id)
	return out


## Draws five cards, removing them from the shared pool.
##
## Champions are weighted by how many copies remain, so a champion half the lobby
## is already holding genuinely stops showing up.
func roll_shop(level: int) -> Array[StringName]:
	var odds: Array = SHOP_ODDS[clampi(level, 1, 9)]
	var out: Array[StringName] = []

	for i in SHOP_SIZE:
		var picked := &""
		for attempt in 8:
			var cost := _weighted_cost(odds)
			var available := _available_of_cost(cost)
			if available.is_empty():
				continue
			picked = _weighted_champion(available)
			break
		if picked == &"":
			# Nothing at the rolled cost anywhere: take whatever is left.
			for cost in range(1, 6):
				var available := _available_of_cost(cost)
				if not available.is_empty():
					picked = available[rng.randi_range(0, available.size() - 1)]
					break
		if picked != &"":
			pool[picked] -= 1
			out.append(picked)

	return out


func _weighted_cost(odds: Array) -> int:
	var total := 0
	for w in odds:
		total += w
	var roll := rng.randi_range(1, maxi(1, total))
	for i in odds.size():
		roll -= odds[i]
		if roll <= 0:
			return i + 1
	return 1


func _weighted_champion(candidates: Array[StringName]) -> StringName:
	var total := 0
	for id in candidates:
		total += pool[id]
	var roll := rng.randi_range(1, maxi(1, total))
	for id in candidates:
		roll -= pool[id]
		if roll <= 0:
			return id
	return candidates[0]


## Rolls a new shop, handing the old cards back first.
func refresh_shop(free: bool = false) -> void:
	if not free and player.gold < REROLL_COST:
		notify("Not enough gold to refresh")
		return
	if not free:
		spend_gold(REROLL_COST)
	return_to_pool_many(shop)
	shop = roll_shop(player.level)
	Events.shop_rolled.emit(shop.duplicate())


func reroll() -> bool:
	if phase != Phase.PLAN:
		return false
	if player.gold < REROLL_COST:
		notify("Not enough gold to refresh")
		return false
	refresh_shop()
	return true


func set_shop_locked(locked: bool) -> void:
	shop_locked = locked
	Events.shop_locked_changed.emit(locked)


## The one door to the battle speed.
##
## It used to be a bare field, assigned from four places: the top bar's own
## buttons, the 1/2/4 keys, and the dev menu twice. Only the first of those told
## the buttons anything, so tapping 4 ran the fight at 4x under a bar still
## reading 1x — the same "state the HUD shows but GameState owns" trap the mute
## button and the shop lock each have a setter and a signal to avoid.
func set_speed(value: int) -> void:
	if speed == value:
		return
	speed = value
	Events.speed_changed.emit(value)


func buy_xp() -> bool:
	if phase != Phase.PLAN:
		return false
	if player.is_max_level():
		notify("Already at the highest level")
		return false
	if player.gold < XP_COST:
		notify("Not enough gold for XP")
		return false
	spend_gold(XP_COST)
	player.add_xp(XP_PER_PURCHASE)
	Events.level_changed.emit(player.level, player.xp, player.xp_needed())
	return true


# =============================================================================
#  Gold and health
# =============================================================================

func spend_gold(amount: int) -> void:
	player.gold -= amount
	Events.gold_changed.emit(player.gold, -amount)


func gain_gold(amount: int) -> void:
	player.gold += amount
	Events.gold_changed.emit(player.gold, amount)


func lose_health(amount: int) -> void:
	player.hp -= amount
	Events.health_changed.emit(maxi(0, player.hp), -amount)


# =============================================================================
#  The player's roster
# =============================================================================

func owned_units() -> Array[RosterUnit]:
	var out: Array[RosterUnit] = []
	out.append_array(board)
	for u in bench:
		if u != null:
			out.append(u)
	return out


func first_free_bench_slot() -> int:
	return bench.find(null)


func unit_at(cell: Vector2i) -> RosterUnit:
	for u in board:
		if u.cell == cell:
			return u
	return null


## Star-1 copies of a champion already owned. Drives the shop's duplicate badge.
func copies_owned(champion_id: StringName) -> int:
	var n := 0
	for u in owned_units():
		if u.id() == champion_id and u.star == 1:
			n += 1
	return n


## Every copy of a champion on the board or the bench, at any star, and the
## highest star among them.
##
## Distinct from `copies_owned`, which counts only the star-1 copies a purchase
## could merge with. A two-star pirate does not bring a shop card closer to a
## star-up, but it is still the answer to "is this one mine?" — and that question
## is the one the player is actually asking of a shop.
func fleet_copies(champion_id: StringName) -> Dictionary:
	var count := 0
	var best := 0
	for u in owned_units():
		if u.id() == champion_id:
			count += 1
			best = maxi(best, u.star)
	return { "count": count, "best_star": best }


## What the shop card for a slot should say about the player's own fleet.
##
## Spotting that a card completes an upgrade was previously a matter of counting
## your own bench mid-timer, which is exactly the thing a player misses and then
## finds a fourth copy of two rounds later.
func shop_slot_info(index: int) -> Dictionary:
	if index < 0 or index >= shop.size():
		return {}
	var champion_id := shop[index]
	if champion_id == &"":
		return {}
	var owned := copies_owned(champion_id)
	var fleet := fleet_copies(champion_id)
	var copies_in_shop := 0
	for i in shop.size():
		if shop[i] == champion_id:
			copies_in_shop += 1
	return {
		"champion_id": champion_id,
		"owned": owned,
		"fleet_count": fleet["count"],
		"fleet_star": fleet["best_star"],
		"completes_upgrade": owned >= 2,
		# Two in the shop and one already yours is the same star-up as owning
		# two, it just costs twice — worth shouting about while both cards are
		# still on the counter.
		"pair_completes_upgrade": owned == 1 and copies_in_shop >= 2,
		"copies_in_shop": copies_in_shop,
		"duplicate_in_shop": copies_in_shop >= 2,
	}


func buy(index: int) -> bool:
	if phase != Phase.PLAN:
		return false
	if index < 0 or index >= shop.size():
		return false
	var champion_id := shop[index]
	if champion_id == &"":
		return false

	var champion: ChampionDef = content.champion(champion_id)
	if player.gold < champion.cost:
		notify("Not enough gold")
		return false

	# There must be room, unless the purchase immediately merges away.
	var slot := first_free_bench_slot()
	var copies := copies_owned(champion_id)
	if slot < 0 and copies < 2:
		notify("Deck is full")
		return false

	spend_gold(champion.cost)
	shop[index] = &""

	var unit := RosterUnit.new(champion, 1)
	if slot >= 0:
		bench[slot] = unit
	else:
		bench.append(unit)     # transient overflow, resolved by the merge below

	Events.unit_bought.emit(champion_id)
	_check_upgrades()
	if bench.size() > BENCH_SIZE:
		bench.resize(BENCH_SIZE)
	Events.board_changed.emit()
	return true


func sell(unit: RosterUnit) -> bool:
	if phase != Phase.PLAN or unit == null:
		return false
	var value := unit.sell_value()
	gain_gold(value)
	return_to_pool(unit.id(), unit.star)
	for item_id in unit.items:
		player.items.append(item_id)
		Events.item_gained.emit(item_id, &"sale")
	_remove_unit(unit)
	Events.unit_sold.emit(unit.id(), value)
	Events.board_changed.emit()
	return true


func _remove_unit(unit: RosterUnit) -> void:
	var slot := bench.find(unit)
	if slot >= 0:
		bench[slot] = null
		return
	board.erase(unit)


## Merges any three matching copies into the next star, repeatedly.
func _check_upgrades() -> void:
	var merged := true
	while merged:
		merged = false
		for star in [1, 2]:
			var groups: Dictionary = {}
			for u in owned_units():
				if u.star != star:
					continue
				if not groups.has(u.id()):
					groups[u.id()] = []
				groups[u.id()].append(u)

			for champion_id in groups:
				var group: Array = groups[champion_id]
				if group.size() < 3:
					continue
				_merge_three(group.slice(0, 3), star)
				merged = true
				break
			if merged:
				break


func _merge_three(three: Array, star: int) -> void:
	# Keep the board seat if any of the three was fielded, so an upgrade never
	# silently benches the unit you had positioned.
	var seat := RosterUnit.BENCHED
	var carried: Array[StringName] = []
	for u in three:
		if u.on_board() and seat == RosterUnit.BENCHED:
			seat = u.cell
		carried.append_array(u.items)
	for u in three:
		_remove_unit(u)

	var upgraded := RosterUnit.new(three[0].champion, star + 1)
	# Every item the three copies were carrying goes back through plan_equip —
	# the same call a drop makes — rather than being counted into free slots.
	#
	# Two bugs lived in the counting version. It never forged, so a star-up that
	# gathered a Buccaneer's Edge from one copy and a Rapier from another left
	# both worn side by side, and they could never be combined afterwards:
	# forging only ever happens at the moment an item is equipped, and both were
	# already on. And an earlier version took the first three in hand order,
	# which could hand the upgrade two capstones *and* a third item — the one
	# loadout the slot rule exists to forbid, arriving by a door equip_item
	# never sees. One call answers both, because it is the only thing that
	# decides a loadout.
	#
	# Capstones are still offered first, because they pair with nothing and what
	# fits is settled by how many of them there are.
	carried.sort_custom(func(a, b):
		return content.item_tier(a) > content.item_tier(b))
	for id in carried:
		# content is a Node, so this is a Variant until it is typed.
		var plan: Dictionary = content.plan_equip(id, upgraded.items)
		if plan["allowed"]:
			upgraded.items.assign(plan["items"])
			var forged: StringName = plan["forges"]
			if forged != &"":
				var made: ItemDef = content.item_def(forged)
				log_line("Forged %s" % made.display_name, &"good")
				Events.item_forged.emit(forged, upgraded.uid)
			continue
		player.items.append(id)
		Events.item_gained.emit(id, &"sale")

	if seat != RosterUnit.BENCHED:
		upgraded.cell = seat
		board.append(upgraded)
	else:
		var slot := first_free_bench_slot()
		if slot >= 0:
			bench[slot] = upgraded
		else:
			bench.append(upgraded)

	log_line("%s %s!" % [UITheme.STAR.repeat(2) if star == 1 else UITheme.STAR.repeat(3), upgraded.champion.display_name], &"good")
	Events.unit_upgraded.emit(upgraded.id(), upgraded.star)


## Moves a unit to a board cell, swapping with whatever is there.
func move_to_board(unit: RosterUnit, cell: Vector2i) -> bool:
	if phase != Phase.PLAN or not Hex.is_player_half(cell):
		return false
	var occupant := unit_at(cell)
	if occupant == unit:
		return false

	var from_bench := not unit.on_board()
	if from_bench and occupant == null and board.size() >= player.board_capacity():
		notify("Crew is at capacity")
		return false

	if from_bench:
		var slot := bench.find(unit)
		# A unit that is neither on the board nor on the bench is not a unit the
		# player can be dragging. Godot indexes an Array from the end for a
		# negative index, so a missed find() would blank bench slot 9 and lose
		# whoever was standing in it — silently, and nowhere near here.
		if slot < 0:
			return false
		bench[slot] = null
		if occupant != null:
			board.erase(occupant)
			occupant.cell = RosterUnit.BENCHED
			bench[slot] = occupant
		unit.cell = cell
		board.append(unit)
	else:
		if occupant != null:
			occupant.cell = unit.cell
		unit.cell = cell

	Events.board_changed.emit()
	return true


## Moves a unit into a bench slot, swapping with whatever is there.
func move_to_bench(unit: RosterUnit, slot: int) -> bool:
	if phase != Phase.PLAN or slot < 0 or slot >= BENCH_SIZE:
		return false
	var occupant := bench[slot]
	if occupant == unit:
		return false

	if unit.on_board():
		board.erase(unit)
		if occupant != null:
			board.append(occupant)
			occupant.cell = unit.cell
		unit.cell = RosterUnit.BENCHED
		bench[slot] = unit
	else:
		var from := bench.find(unit)
		if from < 0:
			return false        # see move_to_board: a negative index writes to the end
		bench[from] = occupant
		bench[slot] = unit

	Events.board_changed.emit()
	return true


# =============================================================================
#  Items
# =============================================================================

func give_item(item_id: StringName, source: StringName = &"salvage") -> void:
	player.items.append(item_id)
	Events.item_gained.emit(item_id, source)


## What dropping `item_id` on `unit` would do, without doing it.
##
## The UI uses this to say "this forges Ironclad Cutlass" *before* the drop
## rather than after, because equipping is irreversible and a component welded
## onto the wrong unit is gone for the rest of the run.
func preview_equip(item_id: StringName, unit: RosterUnit) -> Dictionary:
	if unit == null or item_id == &"":
		return { "allowed": false, "reason": "" }
	return content.plan_equip(item_id, unit.items)


func equip_item(item_id: StringName, unit: RosterUnit) -> bool:
	if phase != Phase.PLAN:
		return false
	var index := player.items.find(item_id)
	if index < 0 or unit == null:
		return false

	# The same call the preview showed, so what the drag promised and what the
	# drop does cannot come apart.
	var plan: Dictionary = content.plan_equip(item_id, unit.items)
	if not plan["allowed"]:
		notify(plan["reason"])
		return false

	unit.items.assign(plan["items"])
	player.items.remove_at(index)

	var forged: StringName = plan["forges"]
	if forged != &"":
		var made: ItemDef = content.item_def(forged)
		if content.is_capstone(forged):
			log_line("Forged %s, a greater item." % made.display_name, &"good")
		else:
			log_line("Forged %s" % made.display_name, &"good")
		Events.item_forged.emit(forged, unit.uid)
	else:
		Events.item_equipped.emit(item_id, unit.uid)
	Events.board_changed.emit()
	return true


# =============================================================================
#  Traits
# =============================================================================

## Active and near-active traits on the player's board, strongest first.
##
## Counts *distinct champions*, not bodies: three copies of one pirate is a
## star-up, never a trait.
func board_traits() -> Array[Dictionary]:
	var seen: Dictionary = {}
	for u in board:
		for trait_id in u.champion.traits:
			if not seen.has(trait_id):
				seen[trait_id] = {}
			seen[trait_id][u.id()] = true

	var out: Array[Dictionary] = []
	for trait_id in seen:
		var def: TraitDef = content.trait_def(trait_id)
		if def == null:
			continue
		var count: int = seen[trait_id].size()
		out.append({
			"id": trait_id,
			"def": def,
			"count": count,
			"tier": def.tier_for(count),
			"next": def.next_breakpoint(count),
		})

	out.sort_custom(func(a, b):
		if a["tier"] != b["tier"]:
			return a["tier"] > b["tier"]
		if a["count"] != b["count"]:
			return a["count"] > b["count"]
		return String(a["id"]) < String(b["id"]))
	return out


# =============================================================================
#  The round loop
# =============================================================================

func rounds_this_stage() -> int:
	return 4 if stage == 1 else 6


## What a round is: a monster wave, the armoury, or another captain.
##
## Takes a round rather than always reading the current one, because the sea has
## to know what `SEA_ROUND` will be several rounds before it gets there — in
## stage 1 that round is the armoury, which is why stage 1 never forecasts
## weather it is not going to get.
func round_type(at_round: int = -1) -> StringName:
	var n := round_number if at_round < 0 else at_round
	if stage == 1:
		return &"pve" if n <= 3 else &"armoury"
	if n == 3:
		return &"pve"
	if n == 6:
		return &"armoury"
	return &"pvp"


# --- the sea -----------------------------------------------------------------

## Takes this stage's weather off the bag, and draws the hexes it will touch.
##
## Both come out of the run's own generator, so a seeded run gets the same seas
## in the same order in the same lanes. The cells are drawn *now*, not when the
## fight is built, because the board has to show the player the same hexes the
## fight will use — and there are seven fights that round, all of which have to
## agree.
func _roll_sea() -> void:
	var previous := sea_id
	sea_id = &""
	sea_cells = []

	if _sea_bag.is_empty():
		_refill_sea_bag(previous)
	if _sea_bag.is_empty():
		return

	sea_id = _sea_bag.pop_back()
	var def: SeaDef = content.sea(sea_id)
	var effect: Variant = content.sea_effect(sea_id)
	if def != null and effect != null:
		sea_cells = effect.cells(def, rng)


## Shuffles every sea the run has reached into a fresh bag.
##
## A sea gated to a later stage joins at the next refill rather than the moment
## it becomes legal, which is a whole cycle of drift at worst and not worth the
## bookkeeping to avoid.
##
## `previous` is the sea the last bag ended on. Without the swap at the end, a
## refill can hand out the same weather twice running across the seam — the one
## thing a bag exists to stop, arriving at the only place it is not looking.
func _refill_sea_bag(previous: StringName) -> void:
	_sea_bag.clear()
	for def in content.seas():
		if def.earliest_stage <= stage:
			_sea_bag.append(def.id)

	for i in range(_sea_bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := _sea_bag[i]
		_sea_bag[i] = _sea_bag[j]
		_sea_bag[j] = swap

	# Dealt off the back, so the last entry is the next one out.
	if _sea_bag.size() > 1 and _sea_bag[-1] == previous:
		var last := _sea_bag[-1]
		_sea_bag[-1] = _sea_bag[0]
		_sea_bag[0] = last


## Rounds until the weather arrives: 0 on the round being fought in it, and -1
## when this stage has none coming.
##
## A sea only lands on a captain fight. The armoury has no fight to affect, and
## a monster round is the floor the whole balance rests on — so a stage whose
## `SEA_ROUND` is either of those has no weather, and never says it has.
func rounds_until_sea() -> int:
	if sea_id == &"" or round_number > SEA_ROUND:
		return -1
	if round_type(SEA_ROUND) != &"pvp":
		return -1
	return SEA_ROUND - round_number


## Whether the round being played is the one fought in weather.
func sea_active() -> bool:
	return rounds_until_sea() == 0


func sea_def() -> SeaDef:
	return content.sea(sea_id) if sea_id != &"" else null


## The sea a fight built this round should be given. Empty on every other round.
func _sea_for_fight() -> StringName:
	return sea_id if sea_active() else &""


func _set_phase(next: Phase) -> void:
	phase = next
	Events.phase_changed.emit(next)


func _begin_planning() -> void:
	plan_timer = PLAN_SECONDS
	_warned_this_round = false
	if round_type() == &"armoury":
		_open_armoury()
		return
	_set_phase(Phase.PLAN)
	Events.round_began.emit(stage, round_number)

	# Announced after the phase, so the board is already up to be marked, and
	# after `round_began`, so the herald is the last line in the log rather than
	# the first thing the new round scrolls away.
	var away := rounds_until_sea()
	Events.sea_changed.emit(sea_id if away >= 0 else &"", away)
	if away == 0:
		var def := sea_def()
		log_line(def.herald, &"good" if def.boon else &"bad")
		# The herald says what the sea is doing; this says what that costs. Two
		# lines because the flavour is what gets read and the numbers are what
		# gets acted on, and one line carrying both is read as neither.
		log_line(def.text().replace("[b]", "").replace("[/b]", ""), &"")
		notify("%s  %s" % [def.icon, def.display_name.to_upper()],
			&"good" if def.boon else &"warn")


## Starts the run's clock, if it is still holding at the line.
##
## Called by whatever the player did to say they are ready — closing the opening
## almanac, or pressing SET SAIL, which starts the fight through the call below
## and would otherwise set a clock that was not running.
func begin_run() -> void:
	if not awaiting_start:
		return
	awaiting_start = false
	Events.run_hold_changed.emit(false)


## Ends the planning phase early.
func start_combat_now() -> void:
	begin_run()
	if phase == Phase.PLAN:
		plan_timer = 0.0


func _process(delta: float) -> void:
	match phase:
		Phase.PLAN:
			_tick_planning(delta)
		Phase.COMBAT:
			_tick_combat(delta)
		Phase.RESULT:
			_result_timer -= delta
			if _result_timer <= 0.0:
				_advance_round()
		_:
			pass


func _tick_planning(delta: float) -> void:
	if awaiting_start:
		return
	plan_timer -= delta
	Events.plan_timer.emit(maxf(0.0, plan_timer), clampf(plan_timer / PLAN_SECONDS, 0.0, 1.0))

	if not _warned_this_round and plan_timer <= WARNING_SECONDS:
		_warned_this_round = true
		Events.plan_time_warning.emit(plan_timer)

	if plan_timer <= 0.0:
		_start_combat()


func _tick_combat(delta: float) -> void:
	if sim == null:
		return
	_step_bot_fights()
	if not sim.done:
		_sim_accumulator += delta * speed
		var steps := 0
		# The cap stops a long frame from resolving the whole battle at once.
		while _sim_accumulator >= Sim.TICK and steps < 40 and not sim.done:
			sim.step()
			_sim_accumulator -= Sim.TICK
			steps += 1
		_announce_overtime()
		if sim.done:
			_post_combat = 0.0 if instant else POST_COMBAT_SECONDS
		return

	_post_combat -= delta
	if _post_combat <= 0.0:
		_resolve_combat()


## Says once, on the tick the watched fight crosses into overtime.
##
## Watched here rather than announced from inside `Sim`, because the sim never
## touches the bus and six of the seven fights a round have nobody to announce
## anything to. The flag is cleared by `_start_combat`, not by the phase, so a
## HUD rebuilt mid-fight cannot re-announce a fight already in overtime.
func _announce_overtime() -> void:
	if _overtime_announced or sim.overtime() <= 0.0:
		return
	_overtime_announced = true
	log_line("The tide turns — quarter is spent, and every blow tells.", &"warn")
	Events.combat_overtime.emit()


# --- starting a fight --------------------------------------------------------

## Seats spare bench pirates in any empty crew slot, at the bell.
##
## A pirate bought and never dragged out of the deck does not fight, and the
## only thing that says so is a crew count nobody is reading with eight seconds
## on the clock — so a round was routinely fought a body down for no decision
## anybody made. It runs when the fight starts rather than when the round opens,
## which is the only place that catches a purchase made in the last seconds of
## planning, and it takes the deck in order: first off the bench, first seated.
##
## The seat matches the pirate the way `Bot.formation` does, melee forward and
## ranged behind, because a bombardier dropped into the front rank is a worse
## answer than the empty seat was. And it is **announced** — a board that
## rearranges itself with nothing on screen to say why is indistinguishable
## from a bug, which is the same rule the sea marks its water under.
func _field_spare_crew() -> void:
	var fielded: Array[String] = []
	for slot in BENCH_SIZE:
		if board.size() >= player.board_capacity():
			break
		var unit := bench[slot]
		if unit == null:
			continue
		var cell := _free_seat(unit)
		# Capacity says there is room and the half says there is not, which can
		# only mean the board is full: stop rather than walk the rest of the deck.
		if not Hex.on_board(cell):
			break
		bench[slot] = null
		unit.cell = cell
		board.append(unit)
		fielded.append(unit.champion.display_name)

	if fielded.is_empty():
		return

	Events.board_changed.emit()
	if fielded.size() == 1:
		log_line("The bosun sends %s up from the deck." % fielded[0], &"good")
		notify("%s JOINS THE LINE" % fielded[0].to_upper(), &"good")
	else:
		log_line("The bosun sends %s up from the deck." % ", ".join(fielded), &"good")
		notify("%d PIRATES JOIN THE LINE" % fielded.size(), &"good")


## The seat a pirate should take: its own rows first and the rest of the
## player's half after, each filled from the centre out. Off the board when
## there is no room left at all.
##
## On a weather round it steps around the marked water first. The whole premise
## of the sea is that the player gets the planning phase to answer it — and a
## pirate sent up at the bell has had no planning phase, so a bosun seating one
## in a wave lane is the game making that call on the player's behalf and then
## announcing it as help. Witchfire was the sharpest version: its hexes are the
## middle three columns of row 4, which is exactly the first three seats this
## fills, so every auto-fielded melee pirate landed in it.
##
## It only ever *avoids*. It does not go looking for a fair wind, because which
## pirate is worth standing in one is a positioning decision, and taking it here
## would mean overriding the melee-forward, ranged-back order — which is already
## the better answer for a crew nobody placed.
func _free_seat(unit: RosterUnit) -> Vector2i:
	var rows := [4, 5, 7, 6] if unit.champion.attack_range <= 1 else [7, 6, 4, 5]
	var seats := Hex.seats(rows)

	if _seats_avoid_the_sea():
		for cell in seats:
			if unit_at(cell) == null and not sea_cells.has(cell):
				return cell

	# Dry water first, but never a seat short: a board with nothing but marked
	# hexes left still fields the pirate. Sailing a body down is the worse of
	# the two, which is the whole reason this function exists.
	for cell in seats:
		if unit_at(cell) == null:
			return cell
	return Vector2i(-1, -1)


## Whether this round's weather is something to seat a spare pirate away from:
## being fought right now, marking specific hexes, and not a gift.
func _seats_avoid_the_sea() -> bool:
	if not sea_active():
		return false
	var def := sea_def()
	return def != null and def.marks_cells and not def.boon


func _start_combat() -> void:
	_sim_accumulator = 0.0
	_overtime_announced = false

	# Anything left on the deck with a seat going spare is sent up first, or it
	# is not in `board` when the fleet is read out of it below.
	_field_spare_crew()

	var kind := round_type()
	var enemy_board: Array = []
	opponent_bot = null

	if kind == &"pve":
		enemy_board = creep_wave()
		opponent_name = creep_wave_name()
		opponent_icon = "💀"
	else:
		var candidates: Array[Bot] = []
		for b in bots:
			if b.alive and b.index != _last_opponent_index:
				candidates.append(b)
		if candidates.is_empty():
			for b in bots:
				if b.alive:
					candidates.append(b)
		if candidates.is_empty():
			opponent_name = "A ghost ship"
			opponent_icon = "👻"
		else:
			opponent_bot = candidates[rng.randi_range(0, candidates.size() - 1)]
			_last_opponent_index = opponent_bot.index
			enemy_board = opponent_bot.formation()
			opponent_name = opponent_bot.display_name
			opponent_icon = opponent_bot.icon

	var my_board: Array = []
	for u in board:
		my_board.append(u.to_entry())

	_dispose_sim()
	sim = Sim.new(content, my_board, enemy_board, true, rng.randi(),
		_sea_for_fight(), sea_cells)

	# The rest of the lobby's fights are built now and stepped alongside this one.
	# They used to be run in one go the moment this fight ended, which by stage 5
	# was a third of a second of nothing responding, every round, on the frame the
	# player was waiting for a result.
	_open_bot_fights()

	# The phase is announced last, so anything listening for it finds the fight
	# already built rather than a null sim.
	_set_phase(Phase.COMBAT)


func _dispose_sim() -> void:
	if sim != null:
		sim.dispose()
		sim = null
	# The unwatched fights are the same web of RefCounted holding each other, and
	# there are six of them for every one of these.
	for fight in _bot_fights:
		fight["sim"].dispose()
	_bot_fights.clear()


# --- resolving it ------------------------------------------------------------

func _resolve_combat() -> void:
	# Read off the fight before anything else, because this is the last moment it
	# is guaranteed to exist: `_advance_round` disposes it, and the meter is still
	# on screen after that.
	_battle_stats = sim.stats()
	_battle_time = sim.time

	var won := sim.winner == Sim.Result.PLAYER_WIN
	var drawn := sim.winner == Sim.Result.DRAW
	var kind := round_type()
	var damage := 0

	if won:
		player.record_result(true)
		# A win over another captain pays a coin. A monster wave pays salvage
		# instead, which is worth more, so it does not also pay the coin.
		if kind == &"pve":
			_player_loot()
		else:
			gain_gold(Captain.PVP_WIN_GOLD)
		log_line("Victory over %s." % opponent_name, &"good")
	elif drawn:
		player.record_result(false, true)
		damage = maxi(1, stage_damage() / 2)
		lose_health(damage)
		log_line("The fight ends in a stalemate.", &"")
	else:
		player.record_result(false)
		damage = stage_damage()
		for u in sim.survivors(Sim.Team.ENEMY):
			damage += u.star + (1 if u.def.cost >= 4 else 0)
		lose_health(damage)
		log_line("Boarded by %s. –%d hull." % [opponent_name, damage], &"bad")

	if opponent_bot != null and not drawn:
		if won:
			opponent_bot.record_result(false)
			var bot_damage := stage_damage()
			for u in sim.survivors(Sim.Team.PLAYER):
				bot_damage += u.star + (1 if u.def.cost >= 4 else 0)
			opponent_bot.hp -= bot_damage
		else:
			opponent_bot.record_result(true)

	_close_bot_fights()
	_check_eliminations()

	Events.round_resolved.emit(won, damage, opponent_name)
	_set_phase(Phase.RESULT)
	_result_timer = 0.0 if instant else RESULT_SECONDS


## Per-combatant damage and healing for the fight on screen, or the last one
## fought. What the DPS meter reads.
##
## The live sim wins while there is one, so the meter follows a fight as it
## happens; the snapshot answers once the round has moved on.
func battle_stats() -> Array[Dictionary]:
	return sim.stats() if sim != null else _battle_stats


## Whether the fight on screen is in overtime. What the HUD reads back after a
## rebuild, when the signal that announced it has long since fired.
func in_overtime() -> bool:
	return phase == Phase.COMBAT and sim != null and sim.overtime() > 0.0


## How long that fight has been running, for the per-second figures.
func battle_duration() -> float:
	return sim.time if sim != null else _battle_time


func stage_damage() -> int:
	return STAGE_DAMAGE[mini(stage, STAGE_DAMAGE.size() - 1)]


func _player_loot() -> void:
	var components: Array = content.components()
	var count := 1 if stage == 1 else (1 if rng.randf() < 0.5 else 2)
	var names := PackedStringArray()
	for i in count:
		var item: ItemDef = components[rng.randi_range(0, components.size() - 1)]
		give_item(item.id, &"salvage")
		names.append(item.display_name)
	var gold := 2 + rng.randi_range(0, 2)
	gain_gold(gold)
	log_line("Salvage: %s and %d gold." % [", ".join(names), gold], &"good")


## Builds the six fights nobody watches, without running any of them.
##
## They are resolved headless, at no rendering cost, and now at no *frame* cost
## either: each is stepped a little at a time while the player watches their own.
##
## Who fights whom is decided here rather than at the end, which is the one thing
## that changed: the player's opponent is already known by now, and the bots do
## not act again between here and the result, so the matches are the same ones
## the old code would have made.
func _open_bot_fights() -> void:
	_bot_fights.clear()

	if round_type() == &"pve":
		for b in bots:
			if not b.alive:
				continue
			# A fresh wave each, rather than one array handed to seven sims. The
			# contents are identical either way; not sharing it is what keeps that
			# true if a sim ever takes the list apart as it seats it.
			_bot_fights.append({
				"sim": Sim.new(content, b.formation(), creep_wave(), false, rng.randi()),
				"a": b,
				"b": null,
			})
		return

	var pool_of_bots: Array[Bot] = []
	for b in bots:
		if b.alive and b != opponent_bot:
			pool_of_bots.append(b)
	# Shuffle so the same two do not meet every round.
	for i in range(pool_of_bots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool_of_bots[i]
		pool_of_bots[i] = pool_of_bots[j]
		pool_of_bots[j] = tmp

	while pool_of_bots.size() >= 2:
		var a: Bot = pool_of_bots.pop_back()
		var b: Bot = pool_of_bots.pop_back()
		# The same weather, in the same lanes, as the fight being watched. It is
		# the sea, so it cannot be only the player's. Bots cannot reposition for
		# it, which is a real edge to the player and one worth measuring rather
		# than assuming — see creep_balance.gd and the bot handicap.
		_bot_fights.append({
			"sim": Sim.new(content, a.formation(), b.formation(), false, rng.randi(),
				_sea_for_fight(), sea_cells),
			"a": a,
			"b": b,
		})

	# The odd one out sits the round out, as it always did.
	if pool_of_bots.size() == 1:
		pool_of_bots[0].last_result = 0


## A slice of each unwatched fight, once a frame, while the player watches theirs.
func _step_bot_fights() -> void:
	for fight in _bot_fights:
		var bot_sim: Sim = fight["sim"]
		if not bot_sim.done:
			bot_sim.advance(UNWATCHED_STEPS_PER_FRAME)


## Reads the results off, finishing anything still running.
##
## A fight that is not done by now is one the player's own ended before: a rout
## in four seconds leaves the rest half fought, and their results are needed on
## this frame. That remainder is the only part still paid for in one go, and it
## is a fraction of what the whole round used to cost here.
func _close_bot_fights() -> void:
	for fight in _bot_fights:
		var bot_sim: Sim = fight["sim"]
		if not bot_sim.done:
			bot_sim.run_to_end()

		var a: Bot = fight["a"]
		var b: Variant = fight["b"]

		if b == null:
			if bot_sim.winner == Sim.Result.PLAYER_WIN:
				a.record_result(true)
				a.gold += 1
			else:
				var d := stage_damage()
				for u in bot_sim.survivors(Sim.Team.ENEMY):
					d += u.star
				a.hp -= d
				a.record_result(false)
			continue

		var other: Bot = b
		if bot_sim.winner == Sim.Result.DRAW:
			a.hp -= 2
			other.hp -= 2
			a.record_result(false, true)
			other.record_result(false, true)
			continue

		var a_won := bot_sim.winner == Sim.Result.PLAYER_WIN
		var winner := a if a_won else other
		var loser := other if a_won else a
		var d := stage_damage()
		for u in bot_sim.survivors(Sim.Team.PLAYER if a_won else Sim.Team.ENEMY):
			d += u.star + (1 if u.def.cost >= 4 else 0)
		loser.hp -= d
		loser.record_result(false)
		winner.record_result(true)
		winner.gold += 1

	for fight in _bot_fights:
		fight["sim"].dispose()
	_bot_fights.clear()


func _check_eliminations() -> void:
	var dying: Array[Captain] = []
	for c in everyone():
		if c.alive and c.hp <= 0:
			dying.append(c)
	if dying.is_empty():
		return

	var survivors := 0
	for c in everyone():
		if c.alive and c.hp > 0:
			survivors += 1

	# The most battered sinks first, so the placements read in the right order.
	dying.sort_custom(func(a, b): return a.hp < b.hp)
	for i in dying.size():
		var c := dying[i]
		c.alive = false
		c.hp = 0
		c.place = survivors + dying.size() - i
		log_line("%s goes down with the ship — %s." % [c.display_name, ordinal(c.place)],
			&"" if c.is_bot else &"bad")


static func ordinal(n: int) -> String:
	var suffix := ["th", "st", "nd", "rd"]
	var v := n % 100
	if v >= 11 and v <= 13:
		return "%dth" % n
	return "%d%s" % [n, suffix[v % 10] if v % 10 < 4 else "th"]


# --- between rounds ----------------------------------------------------------

func _advance_round() -> void:
	_dispose_sim()
	opponent_bot = null

	if not player.alive or alive_captains().size() <= 1:
		_end_game()
		return

	var finished := round_type()

	round_number += 1
	if round_number > rounds_this_stage():
		round_number = 1
		stage += 1
		_roll_sea()

	var income := player.round_income(stage, round_number)
	gain_gold(income)
	player.add_xp(XP_PER_ROUND)
	Events.level_changed.emit(player.level, player.xp, player.xp_needed())

	for b in bots:
		if not b.alive:
			continue
		b.grant_loot(finished, self, rng)
		b.take_turn(self, finished)

	if not shop_locked:
		return_to_pool_many(shop)
		shop = roll_shop(player.level)
		Events.shop_rolled.emit(shop.duplicate())

	_begin_planning()


func _end_game() -> void:
	_set_phase(Phase.OVER)
	if player.place == 0:
		player.place = 1 if player.alive else alive_captains().size() + 1
	Events.game_over.emit(player.place)


# =============================================================================
#  The armoury
# =============================================================================

func _open_armoury() -> void:
	var forged: Array = content.forged_items()
	var indices: Array[int] = []
	for i in forged.size():
		indices.append(i)
	for i in range(indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := indices[i]
		indices[i] = indices[j]
		indices[j] = tmp

	armoury_offer.clear()
	for i in mini(3, indices.size()):
		armoury_offer.append(forged[indices[i]].id)

	if armoury_offer.is_empty():
		# Nothing to offer means a modal with no buttons, and it is the modal the
		# player cannot dismiss. Skip the stop entirely rather than stand on it.
		_advance_round()
		return

	gain_gold(2)

	# The offer is built before the phase is announced, exactly as _start_combat
	# builds the sim before announcing COMBAT. Announcing first handed Main an
	# armoury_offer that take_armoury_item had emptied on the previous stage, so
	# the modal opened with a title, a subtitle and no items to take — and it is
	# not dismissable, so the run stopped there.
	_set_phase(Phase.ARMOURY)


func take_armoury_item(item_id: StringName) -> void:
	if phase != Phase.ARMOURY:
		return
	give_item(item_id, &"armoury")
	log_line("Hauled %s from the armoury." % content.item_def(item_id).display_name, &"good")
	armoury_offer.clear()
	_advance_round()


# =============================================================================
#  Monster waves
# =============================================================================

const CREEP_SEATS := [
	Vector2i(3, 5), Vector2i(2, 5), Vector2i(4, 5), Vector2i(3, 4), Vector2i(1, 5),
	Vector2i(5, 5), Vector2i(2, 4), Vector2i(4, 4), Vector2i(3, 6),
]


## The wave for a stage and round. Defaults to the one being played.
##
## It takes them as arguments rather than reading the run because the almanac
## lists every wave in the game, and the alternative — winding `stage` forward
## and back to ask — is a mutation of the run to answer a question about it.
func creep_wave(at_stage: int = -1, at_round: int = -1) -> Array:
	var for_stage: int = stage if at_stage < 0 else at_stage
	var for_round: int = round_number if at_round < 0 else at_round
	var wave: Array = []
	var add := func(champion_id: StringName, star: int, count: int) -> void:
		for i in count:
			wave.append({ "id": champion_id, "star": star })

	match for_stage:
		1:
			# Round one is fought with a single pirate, because level 1 seats one.
			# Anything the lone unit cannot chew through on its own is a scripted
			# loss on the opening round of the game.
			if for_round == 1:
				add.call(&"rat", 1, 2)
			elif for_round == 2:
				add.call(&"rat", 1, 3)
			else:
				add.call(&"crab", 1, 1)
				add.call(&"rat", 1, 3)
		2:
			add.call(&"crab", 2, 2)
			add.call(&"gull", 2, 2)
		3:
			add.call(&"serpent", 2, 2)
			add.call(&"skiff", 2, 1)
			add.call(&"crab", 2, 2)
		4:
			add.call(&"golem", 1, 1)
			add.call(&"serpent", 2, 3)
		5:
			add.call(&"golem", 2, 2)
			add.call(&"skiff", 3, 2)
		6:
			add.call(&"elder", 1, 1)
			add.call(&"golem", 2, 2)
		_:
			add.call(&"elder", 2, 1)
			add.call(&"golem", 3, 2)
			add.call(&"serpent", 3, 2)

	var out: Array = []
	for i in mini(wave.size(), CREEP_SEATS.size()):
		out.append({
			"champion": content.champion(wave[i]["id"]),
			"star": wave[i]["star"],
			"items": [],
			"cell": CREEP_SEATS[i],
		})
	return out


func creep_wave_name(at_stage: int = -1) -> String:
	var for_stage: int = stage if at_stage < 0 else at_stage
	match for_stage:
		1: return "Bilge Vermin"
		2: return "Gull Flock"
		3: return "Reef Ambush"
		4: return "The Wreck"
		5: return "Drowned Armada"
		_: return "The Elder Deep"
