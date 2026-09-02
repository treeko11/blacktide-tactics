extends "res://tools/tool_script.gd"

## Stamps `ArtTable` into `data/champions/*.tres`.
##
##     Godot --headless --path . --script res://tools/assign_art.gd
##
## Deliberately **not** part of `generate_content.gd`, even though the generator
## writes the same files. The generator overwrites a champion whole, which throws
## away every number tuned in the inspector since the port; this loads each
## resource, sets three fields and saves it back, so balance survives. Re-running
## it is safe and idempotent.
##
## Add `--check` to report what would change without writing anything, which is
## what `test_art.gd` would do if a test could write to `res://` — it cannot, so
## the test asserts the .tres are already correct and this is what fixes them.

const CHAMPION_DIR := "res://data/champions"


func run() -> void:
	rule("Assigning champion art")
	var check := has_flag("check")
	var written := 0
	var missing: Array[String] = []

	var dir := DirAccess.open(CHAMPION_DIR)
	if dir == null:
		fail("Cannot open %s" % CHAMPION_DIR)
		return

	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var path := "%s/%s" % [CHAMPION_DIR, file_name]
		var def: ChampionDef = load(path)
		if def == null:
			fail("Cannot load %s" % path)
			continue

		if not ArtTable.ART.has(def.id):
			missing.append(String(def.id))

		var art := ArtTable.lookup(def.id)
		var body: StringName = art["body"]
		var tint := Color(art["tint"])
		var marks: Array[StringName] = []
		marks.assign(art["marks"])

		if def.art_body == body and def.art_tint == tint and def.art_marks == marks:
			continue

		written += 1
		print("  %-14s %-8s #%s %s" % [def.id, body, art["tint"],
			", ".join(art["marks"])])
		if check:
			continue

		def.art_body = body
		def.art_tint = tint
		def.art_marks = marks
		var err := ResourceSaver.save(def, path)
		if err != OK:
			fail("Could not save %s (%d)" % [path, err])

	# A champion the table has never heard of is the failure that matters: it is
	# playable, it is on the board, and it is a blue pirate with no hat.
	if not missing.is_empty():
		fail("Not in ArtTable: %s" % ", ".join(missing))

	print("")
	print("  %d of %d champions %s" % [written, ArtTable.ART.size(),
		"would change" if check else "updated"])
