extends SceneTree

## Headless test runner.
##
##   godot --headless --path <project> --script res://tools/run_tests.gd
##
## Discovers every res://tests/test_*.gd extending TestCase, runs each `test_*`
## method, and exits non-zero if anything failed so CI and shell chaining work.
##
## Arguments after `--`:
##   <substring>   run only files whose path contains it
##   -v, --verbose list every test rather than a per-file summary
##
## Output is one line per *file* by default. A passing test tells you nothing the
## exit code did not; failures are always printed in full.
##
## Tests run on the first _process frame rather than in _initialize, because
## autoload `_ready()` is deferred until after initialisation. Running in
## _initialize would test against half-constructed singletons.

const TEST_DIR := "res://tests"

var _has_run := false
var _verbose := false
var _total := 0
var _passed := 0
var _failed := 0
var _assertions := 0
var _failure_lines: Array[String] = []


func _process(_delta: float) -> bool:
	if _has_run:
		return true
	_has_run = true

	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "-v" or arg == "--verbose":
			_verbose = true
		elif not arg.begins_with("-"):
			filter = arg

	print("")
	if filter != "":
		print("running tests matching '%s'" % filter)
		print("")

	for path in _discover():
		if filter != "" and not path.contains(filter):
			continue
		_run_file(path)

	_report()
	quit(1 if _failed > 0 else 0)
	return true


func _discover() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("run_tests: no directory at %s" % TEST_DIR)
		return out
	for file in dir.get_files():
		var script_name := file.trim_suffix(".remap")
		if script_name.begins_with("test_") and script_name.ends_with(".gd"):
			out.append(TEST_DIR.path_join(script_name))
	out.sort()
	return out


func _run_file(path: String) -> void:
	var file_name := path.get_file()

	# A test file that will not compile has to fail loudly. Skipping it with a
	# warning means a syntax error silently removes a whole suite from the run and
	# still reports green.
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_fail_whole_file(file_name, "failed to compile")
		return

	var instance: Object = script.new()
	if instance == null:
		_fail_whole_file(file_name, "could not be instantiated")
		return
	if not (instance is TestCase):
		_fail_whole_file(file_name, "does not extend TestCase")
		return

	var methods := _test_methods(script)
	if methods.is_empty():
		# test_case.gd is the base class, not a suite, and legitimately has none.
		# Any *other* empty file is a silent hole — most likely a mistyped method
		# name, which would remove a file's worth of coverage without a word.
		if file_name == "test_case.gd":
			return
		_fail_whole_file(file_name,
			"has no test_* methods — check for a mistyped method name")
		return

	var test: TestCase = instance
	var file_total := 0
	var file_failed := 0

	for method in methods:
		_total += 1
		file_total += 1
		test.failures.clear()
		test._begin(method)

		test.before_each()
		test.call(method)
		# Probes are dropped before after_each, which is where fixtures get freed.
		test._cleanup_probes()
		test._dispose_battles()
		test.after_each()

		# A test that asserted nothing did not pass — it is either a stub, or a
		# runtime error aborted it before its first check. GDScript logs such an
		# error and carries on, so "no failures recorded" is not "succeeded".
		if test.assertion_count == 0 and test.failures.is_empty():
			test.failures.append(
				"%s: made no assertions — it was probably aborted by a runtime error"
				% method)

		_assertions += test.assertion_count
		test.assertion_count = 0

		if test.failures.is_empty():
			_passed += 1
			if _verbose:
				print("  ok    %s :: %s" % [file_name, method])
		else:
			_failed += 1
			file_failed += 1
			print("  FAIL  %s :: %s" % [file_name, method])
			for f in test.failures:
				_failure_lines.append("%s :: %s" % [file_name, f])

	if not _verbose:
		_print_file_summary(file_name, file_total, file_failed)


func _fail_whole_file(file_name: String, reason: String) -> void:
	_total += 1
	_failed += 1
	print("  FAIL  %s :: %s" % [file_name, reason])
	_failure_lines.append("%s: %s — the whole file was skipped" % [file_name, reason])


func _print_file_summary(file_name: String, total: int, failed: int) -> void:
	var status := "%d/%d" % [total - failed, total]
	var marker := "  " if failed == 0 else "! "
	print("%s%-28s %s" % [marker, file_name, status])


## Reads method names off the script rather than the instance, so the TestCase
## helpers are never mistaken for tests.
func _test_methods(script: GDScript) -> PackedStringArray:
	var out := PackedStringArray()
	for m in script.get_script_method_list():
		var method_name: String = m["name"]
		if method_name.begins_with("test_"):
			out.append(method_name)
	out.sort()
	return out


func _report() -> void:
	print("")
	if not _failure_lines.is_empty():
		print("failures:")
		for line in _failure_lines:
			print("  - %s" % line)
		print("")
	print("%d tests, %d passed, %d failed, %d assertions" % [
		_total, _passed, _failed, _assertions
	])
	print("")
