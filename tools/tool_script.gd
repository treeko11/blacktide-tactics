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
var _setup_done := false
var _ran := false


func _process(_delta: float) -> bool:
	if _ran and not manual_quit:
		return true

	if not _setup_done:
		_setup_done = true
		setup()

	if _frame < startup_frames:
		_frame += 1
		return false

	if not _ran:
		_ran = true
		run()
		if not manual_quit:
			finish()
	return false


func finish() -> void:
	quit(exit_code)


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
