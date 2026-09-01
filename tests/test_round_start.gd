extends TestCase

## The run holds at the line until the player says go.
##
## A run used to begin with its 32-second planning clock already running, behind
## the almanac Main opens over it. A new player read the rules and came out to a
## shop that had closed and a fight they never seated anyone for. Now the clock
## does not start until the almanac is closed or SET SAIL is pressed.
##
## The gate is one flag read in one place, which is exactly the kind of thing
## that gets refactored out from under a tool: `playthrough.gd` and
## `creep_balance.gd` play whole runs through this loop and have nobody to wait
## for, so the last test here is the one that keeps them from stalling forever on
## round 1-1.
##
## The clock is advanced by calling `_process` directly, because the runner is
## synchronous and cannot wait for frames. That is the same door the engine uses.


func after_each() -> void:
	# Leave a released run behind: these tests can end holding, mid-fight, or
	# with `instant` set, and everything after them assumes an ordinary run.
	var game := state()
	game.instant = false
	game.start_game()
	game.begin_run()


func test_a_new_run_holds_its_clock() -> void:
	var game := state()
	game.instant = false
	game.start_game()

	assert_true(game.awaiting_start, "a new run did not hold at the line")
	assert_eq(game.phase, game.Phase.PLAN, "the run should still be planning")

	var full: float = game.plan_timer
	for i in 10:
		game._process(0.5)

	assert_eq(game.plan_timer, full, "five seconds ran off a clock that was held")
	assert_eq(game.phase, game.Phase.PLAN, "the held run started a fight on its own")


func test_closing_the_briefing_starts_the_clock() -> void:
	var game := state()
	game.instant = false
	game.start_game()
	var full: float = game.plan_timer

	# What Main calls when the almanac is closed.
	game.begin_run()
	assert_false(game.awaiting_start, "the run was still holding after begin_run()")

	game._process(0.5)
	assert_lt(game.plan_timer, full, "the clock did not start when the run was released")


func test_set_sail_starts_a_held_run() -> void:
	var game := state()
	game.instant = false
	game.start_game()
	assert_true(game.awaiting_start, "a new run did not hold at the line")

	# SET SAIL sets the clock to zero. Against a clock that is not running, that
	# is a fight that never starts and a button that does nothing.
	game.start_combat_now()
	assert_false(game.awaiting_start, "SET SAIL left the run holding")
	assert_eq(game.phase, game.Phase.PLAN, "start_combat_now only sets the clock")

	game._process(1.0 / 60.0)
	assert_eq(game.phase, game.Phase.COMBAT, "SET SAIL never started the fight")


func test_a_tool_run_is_never_held() -> void:
	var game := state()
	game.instant = true
	game.start_game()

	assert_false(game.awaiting_start,
		"playthrough.gd and creep_balance.gd would stall on round 1-1 forever")
