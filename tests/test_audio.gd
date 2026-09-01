extends TestCase

## Sound is the system that fails silently by definition.
##
## A missing file, a renamed one, a cue nothing ever asks for, a style spelled
## wrongly in the bank — every one of those is *quiet*, which is also what
## working sound is most of the time. Nothing in a screenshot shows it and
## nothing in a playthrough reports it, so the assertions are on the bank itself:
## that every cue names a file that loads, that every file shipped is used, and
## that every attack style in the sim has the cue the bank claims to give it.
##
## What is *not* testable here is playback. The suite is headless, `Audio` builds
## no voices there and `play()` returns immediately, so a test that called it
## would assert nothing. That is the trade for not loading thirty-one streams on
## every test run; the wiring itself is still exercised, because `_connect_bus`
## runs headless and a signal named wrongly errors there.


func test_every_cue_names_files_that_load() -> void:
	var broken := PackedStringArray()
	for cue in Audio.BANK:
		var files: Array = Audio.BANK[cue]["files"]
		assert_gt(files.size(), 0, "cue '%s' names no file at all" % cue)
		for file in files:
			var path: String = Audio.DIR + file
			if not ResourceLoader.exists(path):
				broken.append("%s -> %s" % [cue, file])
				continue
			var stream := load(path) as AudioStream
			if stream == null:
				broken.append("%s -> %s (not an AudioStream)" % [cue, file])

	assert_true(broken.is_empty(),
		"these cues are silent because their file is gone: %s" % ", ".join(broken))


## The other direction: a file in `audio/` that no cue plays is dead weight in
## the export, and the web build pays for every byte of it.
func test_every_shipped_sound_is_used() -> void:
	var used := {}
	for cue in Audio.BANK:
		for file in Audio.BANK[cue]["files"]:
			used[file] = true

	var orphans := PackedStringArray()
	for file in DirAccess.get_files_at(Audio.DIR):
		# Godot hands a `.import` sidecar back for every asset it has imported.
		if not file.ends_with(".ogg") and not file.ends_with(".wav"):
			continue
		if not used.has(file):
			orphans.append(file)

	assert_true(orphans.is_empty(),
		"shipped but never played: %s" % ", ".join(orphans))


## Every attack style the sim can fire has a cue of its own.
##
## The fallback in `Audio.fx` means a style with no entry still makes *a* sound,
## which is the failure this catches: a typo in a bank key, or a style added to
## `Sim.ATTACK_STYLES` later, both come out as every pirate of that kind sounding
## like the generic one. Silent-adjacent, and nothing else would ever report it.
func test_every_attack_style_has_its_own_cue() -> void:
	var missing := PackedStringArray()
	for style in Sim.ATTACK_STYLES:
		var spec: Dictionary = Sim.ATTACK_STYLES[style]
		var cue := StringName("%s_%s" % ["shot" if spec["ranged"] else "melee", style])
		if not Audio.BANK.has(cue):
			missing.append(String(cue))

	assert_true(missing.is_empty(),
		"these would fall back to the generic attack sound: %s" % ", ".join(missing))


## The two feeds have to agree. `FX_CUES` maps what the renderer draws onto what
## the bank plays, and a name on the wrong side of that map is a drawn effect
## with no sound.
func test_the_effect_map_only_names_real_cues() -> void:
	var broken := PackedStringArray()
	for kind in Audio.FX_CUES:
		var cue: StringName = Audio.FX_CUES[kind]
		if not Audio.BANK.has(cue):
			broken.append("%s -> %s" % [kind, cue])

	assert_true(broken.is_empty(),
		"drawn but never heard: %s" % ", ".join(broken))
	assert_true(Audio.FX_CUES.has(&"death"),
		"a pirate dying is the one thing in a fight that has to be audible")


## An unknown cue is ignored rather than fatal. Sound is a garnish, and a typo in
## one must not be able to take a round down with it.
func test_an_unknown_cue_is_harmless() -> void:
	Audio.play(&"no_such_cue")
	assert_false(Audio.BANK.has(&"no_such_cue"), "the test's own cue name got real")
