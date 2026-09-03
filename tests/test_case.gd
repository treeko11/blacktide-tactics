class_name TestCase
extends RefCounted

## Base class for tests. Deliberately tiny: a third-party framework is another
## dependency to keep current, and the runner is under 200 lines.
##
## Write a test by extending this, putting each check in a method named `test_*`,
## and using the assert helpers. The runner discovers everything in res://tests.
##
## A limit worth knowing about: **the harness cannot detect a test that aborts
## part-way through.** A GDScript runtime error logs and abandons the method, and
## execution returns to the runner as if the test had finished. The runner catches
## the case where *nothing* was asserted, but a test that asserts once and then
## aborts still reports green. Test through public APIs; a test reaching into
## another object's internals is one refactor away from passing without checking
## anything.
##
## **This file must never name an autoload directly.** It is compiled as a
## dependency of run_tests.gd, a `--script` target, where the autoload globals do
## not exist — naming `Content` here fails the whole run to compile. Use the
## accessors below. Test *files* are loaded later and can name them normally.

var failures: Array[String] = []
var assertion_count: int = 0

var _current: String = ""
var _probes: Array = []

## Sims built by battle(), torn down after each test.
var _battles: Array[Sim] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Runs after every test, even a failing one, before after_each.
func _dispose_battles() -> void:
	for sim in _battles:
		sim.dispose()
	_battles.clear()


func _begin(method: String) -> void:
	_current = method


func _fail(message: String) -> void:
	failures.append("%s: %s" % [_current, message])


# --- Autoloads, fetched at runtime -------------------------------------------

func content() -> Node:
	return Engine.get_main_loop().root.get_node(^"Content")


func state() -> Node:
	return Engine.get_main_loop().root.get_node(^"GameState")


func events() -> Node:
	return Engine.get_main_loop().root.get_node(^"Events")


# --- Battle fixtures ---------------------------------------------------------

## One board entry, ready to hand to Sim.
func entry(champion_id: StringName, cell: Vector2i, star: int = 1,
		items: Array = []) -> Dictionary:
	return {
		"champion": content().champion(champion_id),
		"star": star,
		"items": items,
		"cell": cell,
	}


## A fight with a fixed seed, so a failure is reproducible.
##
## Every sim built this way is disposed after the test. A finished fight holds
## reference cycles that RefCounted cannot collect, and the runner reports leaked
## objects at exit — which would otherwise be noise every suite had to ignore.
func battle(board_a: Array, board_b: Array, seed_value: int = 12345,
		sea: StringName = &"", sea_hexes: Array[Vector2i] = []) -> Sim:
	var sim := Sim.new(content(), board_a, board_b, false, seed_value, sea, sea_hexes)
	_battles.append(sim)
	return sim


## Runs a battle for a number of seconds, or until it ends.
func run_for(sim: Sim, seconds: float) -> void:
	var ticks := int(seconds / Sim.TICK)
	for i in ticks:
		if sim.done:
			return
		sim.step()


# --- Signal probing ----------------------------------------------------------

## Watches a signal and returns an Array that gains one entry — itself an Array
## of the emitted arguments — per emission.
##
## Use this instead of assigning to a local from inside a handler lambda.
## GDScript lambdas capture by *value*, so `var seen := -1;
## sig.connect(func(v): seen = v)` leaves `seen` at -1 forever and the test
## silently passes or fails for the wrong reason. An Array is a reference, so
## appending to it does propagate.
func probe(sig: Signal, arity: int = 0) -> Array:
	var out: Array = []
	var cb: Callable
	match arity:
		0: cb = func(): out.append([])
		1: cb = func(a): out.append([a])
		2: cb = func(a, b): out.append([a, b])
		3: cb = func(a, b, c): out.append([a, b, c])
		4: cb = func(a, b, c, d): out.append([a, b, c, d])
		_:
			_fail("probe() does not support arity %d" % arity)
			return out
	sig.connect(cb)
	_probes.append([sig, cb])
	return out


func _cleanup_probes() -> void:
	for entry_pair in _probes:
		var sig: Signal = entry_pair[0]
		var cb: Callable = entry_pair[1]
		var owner := sig.get_object()
		if owner == null or not is_instance_valid(owner):
			continue
		if sig.is_connected(cb):
			sig.disconnect(cb)
	_probes.clear()


# --- Assertions --------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> void:
	assertion_count += 1
	if not condition:
		_fail(message if message != "" else "expected true, got false")


func assert_false(condition: bool, message: String = "") -> void:
	assertion_count += 1
	if condition:
		_fail(message if message != "" else "expected false, got true")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertion_count += 1
	if actual != expected:
		_fail("%sexpected %s, got %s" % [
			(message + " — ") if message != "" else "", str(expected), str(actual)
		])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertion_count += 1
	if actual == unexpected:
		_fail("%sexpected anything but %s" % [
			(message + " — ") if message != "" else "", str(unexpected)
		])


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.0001,
		message: String = "") -> void:
	assertion_count += 1
	if absf(actual - expected) > tolerance:
		_fail("%sexpected %f (+/- %f), got %f" % [
			(message + " — ") if message != "" else "", expected, tolerance, actual
		])


func assert_null(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value != null:
		_fail("%sexpected null, got %s" % [
			(message + " — ") if message != "" else "", str(value)
		])


func assert_not_null(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value == null:
		_fail(message if message != "" else "expected non-null, got null")


func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	assertion_count += 1
	if actual <= threshold:
		_fail("%sexpected greater than %f, got %f" % [
			(message + " — ") if message != "" else "", threshold, actual
		])


func assert_lt(actual: float, threshold: float, message: String = "") -> void:
	assertion_count += 1
	if actual >= threshold:
		_fail("%sexpected less than %f, got %f" % [
			(message + " — ") if message != "" else "", threshold, actual
		])


func fail(message: String) -> void:
	assertion_count += 1
	_fail(message)
