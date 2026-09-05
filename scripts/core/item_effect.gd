class_name ItemEffect
extends RefCounted

## What an item does to the unit carrying it.
##
## One file per item in scripts/core/items/, reporting the item's id. Applied
## once at the start of a fight, before traits.
##
## An item that does something *during* the fight registers a hook on the unit
## rather than asking to be ticked — `unit.hooks_on_attack.append(...)` and
## friends. Anything a hook needs to remember between calls goes in
## `unit.scratch`, keyed by the item id, so no item needs a field on SimUnit.

func id() -> StringName:
	return &""


func apply(_sim: Sim, _unit: SimUnit) -> void:
	pass


## Per-unit scratch value for this item, created from `initial` on first use.
func scratch(unit: SimUnit, initial: Variant = 0) -> Variant:
	if not unit.scratch.has(id()):
		unit.scratch[id()] = initial
	return unit.scratch[id()]


func set_scratch(unit: SimUnit, value: Variant) -> void:
	unit.scratch[id()] = value

# =============================================================================
#  Permanent growth
# =============================================================================

## Where every item's gathered bonuses live: `item_id -> { stat -> amount }`.
##
## One scratch key for all of them, keyed by item inside it, because two copies
## of a snowball on one pirate have to report separately - and because the two
## bounded items already spend their own `id()` slot on a stack count.
const GATHERED := &"gathered"

## Stats a growing item can grant, and how each is added.
const ADDITIVE := {
	&"ad": "ad", &"ap": "ability_power",
	&"armor": "armor", &"mr": "magic_resist",
}


## Grant a permanent bonus and record it, so the inspector can say how much this
## item has actually gathered.
##
## The recording goes through the same call as the mutation deliberately. Six
## items snowball, and a total kept beside a bare `unit.ad += 10.0` is a second
## copy of that number - the copy that goes stale the first time anybody retunes
## the item and edits only the line that does something.
##
## Fight-scoped, like the growth itself: items are applied fresh in `Sim._init`
## every round, so nothing here survives the bell.
func grant(unit: SimUnit, stat: StringName, amount: float) -> void:
	if not ADDITIVE.has(stat):
		push_error("ItemEffect.grant: %s cannot grant %s" % [id(), stat])
		return
	var field: String = ADDITIVE[stat]
	unit.set(field, unit.get(field) + amount)
	var book := _book(unit)
	book[stat] = float(book.get(stat, 0.0)) + amount


## The same, for attack speed, which is granted as a multiplier.
##
## So what it has gathered is a multiplier too: 1.07 twice is 1.145 and not
## "14%". It is recorded uncapped, because `ATTACK_SPEED_CAP` is applied where
## attack speed is read rather than where it is granted - the same reason
## `add_buff` does not clamp.
func grant_attack_speed(unit: SimUnit, factor: float) -> void:
	unit.attack_speed *= factor
	var book := _book(unit)
	book[&"as"] = float(book.get(&"as", 1.0)) * factor


## What `item_id` has gathered on this unit: `stat -> amount`, and empty for an
## item that grows nothing or has not grown yet. Static, because the reader is
## the tooltip and it has an item id rather than an effect.
static func gathered(unit: SimUnit, item_id: StringName) -> Dictionary:
	var all: Dictionary = unit.scratch.get(GATHERED, {})
	return all.get(item_id, {})


func _book(unit: SimUnit) -> Dictionary:
	if not unit.scratch.has(GATHERED):
		unit.scratch[GATHERED] = {}
	var all: Dictionary = unit.scratch[GATHERED]
	if not all.has(id()):
		all[id()] = {}
	return all[id()]
