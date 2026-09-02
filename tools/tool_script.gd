extends SceneTree

## Base class for headless tool scripts.
##
## It exists to keep two traps in one place rather than in every tool:
##
## 1. **Autoload globals do not resolve at compile time in a `--script` target.**
##    Naming `Content` in a tool — or in anything the tool depends on — fails the
##    whole script to compile with "Identifier not found". The accessors at the
##    bottom fetch them by node path at *runtime*, where they exist.
##
## 2. **Autoload `_ready()` has not run during `_initialize()`.** It is deferred
##    to the first frame, so a tool doing its work in `_initialize()` sees empty
##    singletons. Everything here runs on a frame instead.
##
## Nothing in this file may name an autoload directly, for exactly the reason it
## documents — it is compiled as a dependency of every tool extending it.
##
## Write a tool like this:
##
##     extends "res://tools/tool_script.gd"
##
##     func run() -> void:
##         print(content().champions().size())

## Frames to let pass before run() is called. Anything needing the renderer to
## have drawn, or a scene to have settled, wants a few.
var startup_frames := 0

## Exit code handed back to the shell. Set it non-zero to fail a build.
var exit_code := 0

## Set true to keep the tool alive after run(); it must then call finish() itself.
var manual_quit := false

var _frame := 0
var _parked := false
var _pointer_home := Vector2i.ZERO
var _pointer_saved := false
var _setup_done := false
var _ran := false


func _process(_delta: float) -> bool:
	if _ran and not manual_quit:
		return true

	if not _setup_done:
		_setup_done = true
		_park_window()
		setup()

	if _frame < startup_frames:
		_frame += 1
		return false

	if not _ran:
		_ran = true
		# Again, because a tool that sized its own window in setup() moved it.
		_park_window()
		run()
		if not manual_quit:
			finish()
	return false


func finish() -> void:
	_restore_pointer()
	quit(exit_code)


## A scripted hover has to move the real pointer, so a windowed run borrows it.
##
## `Viewport.get_mouse_position()` on the *root* viewport reports where the
## pointer physically is rather than what was last parsed — measured, not
## assumed — and the inspector closes itself the moment that leaves its owner.
## So `screenshot.gd` warps for a hover and there is no way around it.
##
## What there is a way around is leaving it where the last hover put it. The
## person running the tool was in the middle of something.
func _remember_pointer() -> void:
	if _pointer_saved:
		return
	_pointer_saved = true
	_pointer_home = DisplayServer.mouse_get_position()


func _restore_pointer() -> void:
	if not _pointer_saved or DisplayServer.get_name() == "headless":
		return
	if DisplayServer.mouse_get_position() == _pointer_home:
		return
	# `warp_mouse` is relative to the window, and the window has been moved since
	# the position was taken, so the offset is read again here rather than kept.
	DisplayServer.warp_mouse(_pointer_home - DisplayServer.window_get_position())


# --- The window ---------------------------------------------------------------

## Puts a windowed tool on a monitor the person running it is not using.
##
## Three of these tools have to run *without* `--headless` — screenshot.gd,
## art_sheet.gd and a windowed soak — because a dummy renderer draws nothing and
## the whole point of them is what was drawn. So a run that takes a couple of
## minutes is a couple of minutes of game windows opening on top of whatever the
## person was reading, stealing focus as they go.
##
## The window still exists and still draws; it is just parked. The screen is the
## first one that is not the primary, or `GODOT_TOOL_SCREEN` — a machine with one
## monitor keeps the behaviour it had, since there is nowhere else to put it, and
## `GODOT_TOOL_SCREEN=-1` opts out.
##
## This runs on the first frame, so the window has already been created by then:
## it is a move, and a move is visible. Pass the *engine* flag `--screen 1`
## before `--script` to have it open there in the first place. They are different
## flags on purpose — that one belongs to Godot and takes a space, this is the
## fallback for every invocation that forgets it.
##
## NO_FOCUS is the other half: parking a window that then pulls focus back at
## every resize is not parking it. It only affects who the keyboard belongs to,
## and every one of these tools drives itself with `Input.parse_input_event`,
## which does not go through the window manager.
func _park_window() -> void:
	if DisplayServer.get_name() == "headless":
		return

	var wanted := -1
	var asked := OS.get_environment("GODOT_TOOL_SCREEN")
	if asked.is_valid_int():
		wanted = int(asked)
	else:
		var primary := DisplayServer.get_primary_screen()
		for i in DisplayServer.get_screen_count():
			if i != primary:
				wanted = i
				break
	if wanted < 0 or wanted >= DisplayServer.get_screen_count():
		return

	_remember_pointer()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	if DisplayServer.window_get_current_screen() != wanted:
		DisplayServer.window_set_current_screen(wanted)
		# Said out loud once: a window that has gone somewhere the person cannot
		# see it should say where, or a tool that opened nothing and a tool that
		# opened it on the other monitor look identical.
		if not _parked:
			print("  window parked on screen %d (GODOT_TOOL_SCREEN=-1 to keep it here)"
				% wanted)
	_parked = true


# --- Override these ----------------------------------------------------------

## Runs on the first frame, before any startup_frames elapse. Use it to build a
## scene the tool needs to look at.
func setup() -> void:
	pass


## The tool's actual work.
func run() -> void:
	pass


# --- Autoloads, resolved at runtime ------------------------------------------

func autoload(node_name: String) -> Node:
	return root.get_node_or_null(NodePath(node_name))


func events() -> Node: return autoload("Events")
func content() -> Node: return autoload("Content")
func state() -> Node: return autoload("GameState")


# --- Arguments ---------------------------------------------------------------

## Everything after `--` on the command line.
func args() -> PackedStringArray:
	return OS.get_cmdline_user_args()


## Value of `--name=value`, or the fallback.
func arg(arg_name: String, fallback: String = "") -> String:
	var prefix := "--%s=" % arg_name
	for a in args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


func has_flag(flag_name: String) -> bool:
	return args().has("--%s" % flag_name)


# --- Output ------------------------------------------------------------------

func rule(title: String) -> void:
	print("")
	print("=== %s " % title + "=".repeat(maxi(56 - title.length(), 0)))


func fail(message: String) -> void:
	push_error(message)
	print("  FAILED: %s" % message)
	exit_code = 1
