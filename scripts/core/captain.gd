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

## Gold per round before interest and streaks.
const BASE_INCOME := 5
## One gold per ten banked, to this ceiling. The whole reason to save.
const MAX_INTEREST := 5

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


## Round income: a flat wage, interest on savings, and a streak bonus.
##
## Losing pays the same streak bonus as winning. A captain being beaten every
## round is meant to be able to fund the rebuild that gets them back in.
func round_income() -> int:
	var income := BASE_INCOME
	income += mini(MAX_INTEREST, gold / 10)
	income += streak_bonus()
	return income


func streak_bonus() -> int:
	var run := absi(streak)
	if run >= 5:
		return 3
	if run >= 4:
		return 2
	if run >= 2:
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
