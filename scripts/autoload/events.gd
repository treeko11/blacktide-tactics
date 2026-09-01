extends Node

## Cross-system signal bus.
##
## The shop does not know the HUD exists; it announces that gold changed and
## whatever cares listens. This is what keeps the round loop, the economy and the
## presentation from reaching into each other.
##
## Presentation signals are as first-class here as state ones. Several pieces of
## the first playtest's feedback — no feedback when an item arrives, no warning
## before the shop closes — were not missing *logic*, they were things the game
## already knew and never said out loud. Anything worth telling the player gets a
## signal, and the HUD decides how to show it.

# --- Round loop --------------------------------------------------------------

## PLAN, COMBAT, RESULT, ARMOURY, OVER — see GameState.Phase.
signal phase_changed(phase: int)
signal round_began(stage: int, round_number: int)
signal round_resolved(won: bool, damage: int, opponent_name: String)
signal game_over(place: int)

## Fires once per planning phase, when the shop is about to close. The clock was
## in the top bar, nowhere near the shop the player was actually looking at.
signal plan_time_warning(seconds_left: float)
signal plan_timer(seconds_left: float, fraction: float)

# --- Economy -----------------------------------------------------------------

signal gold_changed(gold: int, delta: int)
signal level_changed(level: int, xp: int, needed: int)
signal health_changed(hp: int, delta: int)
signal shop_rolled(champion_ids: Array)
signal shop_locked_changed(locked: bool)

# --- Roster ------------------------------------------------------------------

signal unit_bought(champion_id: StringName)
signal unit_sold(champion_id: StringName, value: int)
signal unit_upgraded(champion_id: StringName, star: int)
signal board_changed()

# --- Items -------------------------------------------------------------------

## Something landed in the cargo hold. `source` is "salvage", "armoury" or "sale".
signal item_gained(item_id: StringName, source: StringName)
signal item_equipped(item_id: StringName, unit_uid: int)
signal item_forged(item_id: StringName, unit_uid: int)

# --- Presentation ------------------------------------------------------------

## A line for the log panel. `style` is "", "good" or "bad".
signal logged(text: String, style: StringName)

## A transient message to put in front of the player — "Not enough gold", "Deck
## is full". The old build computed these and dropped them on the floor.
signal notice(text: String, style: StringName)

## The window crossed the breakpoint between the wide layout and the compact one
## — a phone rotating, or a desktop window dragged narrow. The HUD is rebuilt
## rather than resized: the two layouts are different arrangements of the same
## panels, not the same arrangement at two sizes. See scripts/ui/layout.gd.
signal layout_changed(compact: bool)
