class_name SimUnit
extends RefCounted

## One combatant inside a battle.
##
## A RefCounted, not a Node. Nothing in a fight ever enters the scene tree — the
## renderer reads this and draws it. That is what lets the same simulation run
## headless for the six bot-vs-bot fights that resolve every round, at no
## rendering cost, and it is why a battle can be replayed or fast-forwarded
## without the visuals having any say in the outcome.
##
## Base ability power is 100 and `power()` divides by it, so an ability written
## as `600 * unit.power()` deals 600 at no bonus AP and scales from there.

const BASE_AP := 100.0

var uid: int = 0
var def: ChampionDef = null
var star: int = 1
var team: int = 0

var cell: Vector2i = Vector2i.ZERO
var home: Vector2i = Vector2i.ZERO
var pos: Vector2 = Vector2.ZERO

var max_hp: float = 0.0
var hp: float = 0.0
var shield: float = 0.0
## Each entry is { "amount": float, "time": float, "tide": bool }.
var shields: Array[Dictionary] = []

var mana: float = 0.0
var max_mana: float = 0.0
var mana_regen: float = 0.0

var ad: float = 0.0
var ability_power: float = BASE_AP
var armor: float = 0.0
var magic_resist: float = 0.0
var attack_speed: float = 0.65
var attack_range: int = 1

var crit: float = 0.0
var crit_damage: float = 1.4
var omnivamp: float = 0.0
var damage_reduction: float = 0.0
var damage_amp: float = 0.0
var dodge: float = 0.0
var execute_amp: float = 0.0
var item_regen: float = 0.0

var items: Array[StringName] = []

var alive: bool = true
var target: SimUnit = null
var attack_timer: float = 0.0
var casting: float = 0.0
var stun_time: float = 0.0

var is_moving: bool = false
var move_from: Vector2 = Vector2.ZERO
var move_to: Vector2 = Vector2.ZERO
var move_t: float = 0.0
var move_duration: float = 0.0

## Armor shred and magic-resist shred, each with their own remaining duration.
var rend: float = 0.0
var rend_time: float = 0.0
var shred_mr: float = 0.0
var shred_mr_time: float = 0.0

var heal_cut: float = 0.0
var heal_cut_time: float = 0.0
var temp_omnivamp: float = 0.0
var temp_omnivamp_time: float = 0.0

## { "pct": float, "time": float, "tick": float, "source": SimUnit }
var burns: Array[Dictionary] = []
## { "stat": StringName, "mult": float, "time": float }
var buffs: Array[Dictionary] = []
## { "stat": StringName, "amount": float, "time": float }
var flats: Array[Dictionary] = []
## { "amount": float, "time": float } — healing paid out over a duration.
var regen_queue: Array[Dictionary] = []
## { "pct": float, "cap": float } — the Tidecaller overheal-into-shield effect.
var regen: Dictionary = {}
## { "pct": float, "used": bool, "until": float }
var revive: Dictionary = {}
var pending_revive: bool = false

## Per-item scratch space, so an item effect can keep a counter without every
## item's bookkeeping becoming a field on this class.
var scratch: Dictionary = {}

var hooks_on_attack: Array[Callable] = []
var hooks_on_damaged: Array[Callable] = []
var hooks_on_cast: Array[Callable] = []
var hooks_on_kill: Array[Callable] = []
var hooks_on_death: Array[Callable] = []

var damage_dealt: float = 0.0
var healing_done: float = 0.0


## Ability power as a multiplier: 1.0 at base, 1.8 with +80 AP.
func power() -> float:
	return ability_power / BASE_AP


func health_fraction() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)


func mana_fraction() -> float:
	return 0.0 if max_mana <= 0.0 else clampf(mana / max_mana, 0.0, 1.0)


func casts() -> bool:
	return max_mana > 0.0


func gain_mana(amount: float) -> void:
	if max_mana <= 0.0 or casting > 0.0:
		return
	mana = minf(max_mana, mana + amount)


func recalc_shield() -> void:
	var total := 0.0
	for s in shields:
		total += s["amount"]
	shield = total


## Sell value follows the champion's cost, tripling per star.
func sell_value() -> int:
	return def.sell_value(star) if def != null else 0


func display_name() -> String:
	return def.display_name if def != null else "?"
