class_name ScriptDir
extends RefCounted

## Scans a folder of scripts, instantiates each one, and keys the results by the
## `id()` each reports.
##
## This is what makes abilities, traits and item effects "add a file and nothing
## else". A hand-maintained register of 44 champion abilities is exactly the kind
## of list that goes stale the first time someone adds a pirate in a hurry.
##
## `.remap` handling matters in exported builds, where `foo.gd` ships as
## `foo.gd.remap`. Trimming the suffix and loading the original path is what
## Godot expects.

## Loads every script in `dir`, returning { id: instance }.
##
## `expected` is an optional class the instances must be, so a stray file in the
## folder fails loudly at load rather than silently at cast time.
static func load_all(dir_path: String, expected: Variant = null) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("ScriptDir: no directory at %s" % dir_path)
		return out

	var names := dir.get_files()
	names.sort()
	for file in names:
		var script_name := file.trim_suffix(".remap")
		if not script_name.ends_with(".gd"):
			continue
		var path := dir_path.path_join(script_name)
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			push_error("ScriptDir: %s failed to compile" % path)
			continue

		var instance: Variant = script.new()
		if expected != null and not is_instance_of(instance, expected):
			push_error("ScriptDir: %s is not the expected type" % path)
			continue

		var id: StringName = instance.id()
		if id == &"":
			push_error("ScriptDir: %s reports an empty id()" % path)
			continue
		if out.has(id):
			push_error("ScriptDir: duplicate id '%s' from %s" % [id, path])
			continue
		out[id] = instance

	return out
