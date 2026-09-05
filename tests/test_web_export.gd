extends TestCase

## The export output must not become an export input.
##
## `web/` holds the built web game, and three of the files in it are PNGs. With
## nothing telling the engine otherwise it imports those as ordinary resources,
## and the *next* export packs them into `index.pck` — the build carrying a copy
## of its own last output forward, every time, growing quietly. Nothing about
## that throws, nothing about it shows in a screenshot, and the game plays
## perfectly with the stowaways aboard.
##
## `web/.gdignore` is the whole fix, and deleting it looks harmless. This is what
## says otherwise. `js/` and `css/` carry one for the same reason.

const WEB_DIR := "res://web"


func test_web_folder_is_hidden_from_the_engine() -> void:
	assert_true(FileAccess.file_exists(WEB_DIR + "/.gdignore"),
		"web/.gdignore is missing — the next export will pack the last one's icons")


## The symptom, rather than the cause: an import file beside the build means the
## engine scanned the folder anyway, whatever the reason.
func test_nothing_in_the_web_build_was_imported() -> void:
	var imported: Array[String] = []
	for file in DirAccess.get_files_at(WEB_DIR):
		if file.ends_with(".import"):
			imported.append(file)
	assert_eq(imported, [] as Array[String],
		"the engine imported part of the web build as a resource")
