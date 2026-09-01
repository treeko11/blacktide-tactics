class_name Captain
extends RefCounted

## One of the eight players in the lobby — the human, or one of the seven bots.
##
## Holds only what every captain has: identity, economy, and how the last round
## went. The roster lives in the subclass or in GameState, because the player
## arranges a board and a bench while a bot only keeps a pile of units and works
## out a formation when asked.

## XP needed to reach the next level, indexed by current level.
const XP_TABLE := { 1: 2, 2: 2, 3: 6, 4: 10, 5: 20, 6: 36, 7: 56, 8: 80, 9: 1 << 30 }
const MAX_LEVEL := 9

## The full wage, paid from round 2-2 onwards. Earlier rounds pay less — see
## passive_income().
const BASE_INCOME := 5
## One gold per ten banked, to this ceiling. The whole reason to save.
const MAX_INTEREST := 5
## Paid on top for beating another captain. Monster rounds pay salvage instead.
const PVP_WIN_GOLD := 1

var display_name: String = ""
var icon: String = ""
var is_bot: bool = false

var hp: int = 100
var gold: int = 2
var level: int = 1
var xp: int = 0

## Positive for a win streak, negative for a loss streak. Both pay.
var streak: int = 0
var last_result: int = 0
var alive: bool = true
## Finishing position, set when eliminated. 1 is the winner.
var place: int = 0

## Components and forged items not currently on a unit.
var items: Array[StringName] = []


func _init(captain_name: String = "", captain_icon: String = "") -> void:
	display_name = captain_name
	icon = captain_icon


func add_xp(amount: int) -> void:
	xp += amount
	while level < MAX_LEVEL and xp >= XP_TABLE[level]:
		xp -= XP_TABLE[level]
		level += 1
	if level >= MAX_LEVEL:
		xp = mini(xp, XP_TABLE[MAX_LEVEL - 1])


func xp_needed() -> int:
	return XP_TABLE[level]


func is_max_level() -> bool:
	return level >= MAX_LEVEL


## Board slots available. Levelling is the only way to field more pirates.
func board_capacity() -> int:
	return level


## The wage for the round being entered, before interest and streaks.
##
## It ramps: 2 across the opening rounds, 3 for the last round of stage 1, 4 for
## 2-1, and the full 5 from 2-2 on. A run that pays 5 a round from the start can
## afford every shop it sees, so none of the early decisions cost anything —
## whether to reroll, to level, or to save is only a question while gold is
## scarce. Stage 1 round 1 never draws income; the run opens there.
func passive_income(stage: int, round_number: int) -> int:
	if stage == 1:
		return 3 if round_number >= 4 else 2
	if stage == 2 and round_number == 1:
		return 4
	return BASE_INCOME


## Round income: the wage, interest on savings, and a streak bonus.
##
## Interest is worked out on what is banked now, before the wage lands, so a
## captain cannot bank 95 and be paid interest on the 100 the same payment makes.
##
## Losing pays the same streak bonus as winning. A captain being beaten every
## round is meant to be able to fund the rebuild that gets them back in.
func round_income(stage: int, round_number: int) -> int:
	var income := passive_income(stage, round_number)
	income += mini(MAX_INTEREST, gold / 10)
	income += streak_bonus()
	return income


func streak_bonus() -> int:
	var run := absi(streak)
	if run >= 6:
		return 3
	if run >= 5:
		return 2
	if run >= 3:
		return 1
	return 0


## Records a fight result and extends or breaks the streak.
func record_result(won: bool, drawn: bool = false) -> void:
	if drawn:
		last_result = 0
		return
	if won:
		last_result = 1
		streak = streak + 1 if streak >= 0 else 1
	else:
		last_result = -1
		streak = streak - 1 if streak <= 0 else -1


func streak_label() -> String:
	if streak > 0:
		return "W%d" % streak
	if streak < 0:
		return "L%d" % absi(streak)
	return "–"
