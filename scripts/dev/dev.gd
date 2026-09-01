extends Node

## **DEV BUILD ONLY. This whole folder comes out before release.**
##
## Two things live here: a log of everything that happens during a playtest, and
## the dev menu that makes a scenario reachable without playing to it.
##
## Removing it is three deletions, and there is deliberately no fourth:
##
##   1. delete `scripts/dev/`
##   2. delete `tests/test_dev.gd`
##   3. delete the `Dev=` line from `[autoload]` in `project.godot`
##
## **No game code references any of this.** The menu attaches itself to the scene
## tree root instead of being built by `Main`, and the log listens on the `Events`
## bus instead of being called from anywhere. So deleting the folder cannot break
## a compile, and cannot leave half a hook behind — which is what happens to a dev
## tool welded into `main.gd`, and why those ship by accident.
##
## Two things switch it off short of deleting it. `ENABLED` below is the kill
## switch. And it stands down entirely under a `--script` target, because every
## tool in `tools/` is one: `screenshot.gd` asserts against panel heights and taps
## at measured coordinates, and a floating DEV button over the corner of that is a
## tool failing for a reason that has nothing to do with the game.
##
## What gets recorded: every signal on the `Events` bus, a snapshot of the fleet
## at the moment each fight starts, and window rotations — worth having because
## crossing a layout breakpoint rebuilds the HUD, and several bugs have only ever
## appeared on the far side of one. What does not: `Events.plan_timer`, which
## fires thirty times a second and says nothing either time.

## The kill switch. False here and nothing below runs, the menu never appears,
## and no log is kept.
const ENABLED := true

## Lines held in memory for COPY LOG and DOWNLOAD LOG. A long run is a few
## thousand; this cap only exists so a session left running overnight cannot eat
## the heap. Oldest go first, and the drop is recorded in the log itself, so a
## truncated log always says that it is one.
const MAX_LINES := 20000

## Desktop only. On the web `user://` is browser storage the player cannot reach,
## which is what the download button in the menu is for.
const LOG_DIR := "user://playtests"

var lines := PackedStringArray()

## Where the log is being written, or "" on the web and under a tool.
var log_path := ""

var _file: FileAccess = null
var _started_ms := 0
var _recording := false
var _dropped := 0
var _booted := false

## How many children the root has before the game is added: this autoload and the
## three before it. Dev is registered last, so at its own _ready() that is all
## of them.
var _autoloads := 0
var _last_window := Vector2i.ZERO
var _last_fleet := ""


func _ready() -> void:
	if not ENABLED:
		set_process(false)
		return

	_started_ms = Time.get_ticks_msec()
	_autoloads = get_tree().root.get_child_count()
	# Headless is the test suite and the balance tools. Nothing there is a
	# playtest, and a log file per test run is litter.
	_recording = DisplayServer.get_name() != "headless"
	if not _recording:
		set_process(false)
		return

	_subscribe()


## True when something in `tools/` is driving rather than a player.
##
## Every one of them is a `--script` target. `screenshot.gd` in particular
## asserts against panel heights and taps at measured coordinates, and a DEV
## button floating over the corner of that is a tool failing for a reason that
## has nothing to do with the game.
##
## `-- --dev-ui` opts back in, which is how the menu gets looked at in all three
## layouts: it is a phone-sized panel like every other, and the only way to know
## it fits on a 390-point screen is to render it on one.
func driven_by_a_tool() -> bool:
	if OS.get_cmdline_user_args().has("--dev-ui"):
		return false
	return OS.get_cmdline_args().has("--script")


func _process(_delta: float) -> void:
	if not _booted:
		# The game does not exist during an autoload's `_ready()`, and both the
		# header and the menu want it: the header records the layout the run
		# opened in, and the menu needs something to sit on top of.
		#
		# The wait is for the root to gain a child that is not an autoload,
		# rather than for `current_scene`, which is only set for a scene the
		# engine loaded itself. A tool that instantiates `main.tscn` and adds it
		# by hand leaves `current_scene` null forever, and the menu would then
		# never appear in the one place it can be looked at on a phone-sized
		# screen. Adding a node runs its `_ready()` there and then, so by the
		# time the count moves, `Main` has already applied the layout.
		if get_tree().root.get_child_count() <= _autoloads:
			return
		_booted = true
		_boot()
		return

	# The same poll `Main` uses, for the same reason: a browser canvas resize
	# fires no signal. A rotation earns a line because it rebuilds the HUD, and
	# more than one bug has only ever appeared on the far side of that.
	var size := get_window().size
	if size != _last_window:
		_last_window = size
		_record_view()


func _boot() -> void:
	_open_file()

	record(&"RUN", "Blacktide Tactics, %s" % Time.get_datetime_string_from_system(false, true))
	record(&"RUN", "%s, Godot %s" % [OS.get_name(),
		Engine.get_version_info().get("string", "?")])
	if log_path != "":
		record(&"RUN", "log: %s" % ProjectSettings.globalize_path(log_path))

	# The opening state, recorded rather than replayed. `GameState.start_game()`
	# runs inside its own `_ready()`, which is before this autoload's, so the
	# events it emitted are already gone. Nothing is lost by that: what those
	# events would have said is exactly the state the run opens in, written here.
	record(&"ROUND", "%d-%d %s" % [GameState.stage, GameState.round_number,
		GameState.round_type()])
	record(&"GOLD", "%d at the start" % GameState.player.gold)
	record(&"SHOP", ", ".join(_names(GameState.shop)))
	_record_view()

	if not driven_by_a_tool():
		get_tree().root.add_child(DevMenu.new())


func _record_view() -> void:
	_last_window = get_window().size
	var shape := "wide"
	if Layout.compact():
		shape = "compact-short" if Layout.short() else "compact"
	record(&"VIEW", "%dx%d device, %dx%d css, %s" % [_last_window.x, _last_window.y,
		int(Layout.css_size.x), int(Layout.css_size.y), shape])


# =============================================================================
#  Writing
# =============================================================================

## Adds one line. `tag` is the short column the log gets grepped by.
func record(tag: StringName, text_: String) -> void:
	if not _recording:
		return

	var ms := Time.get_ticks_msec() - _started_ms
	var line := "[%02d:%04.1f] %-6s %s" % [ms / 60000, fmod(ms / 1000.0, 60.0),
		String(tag), text_]

	lines.append(line)
	if lines.size() > MAX_LINES:
		lines.remove_at(0)
		_dropped += 1
		# Said once, as it starts, rather than on every line from then on.
		if _dropped == 1:
			lines.append("[  ..   ] TRIM   past %d lines; the oldest are being dropped"
				% MAX_LINES)

	if _file == null:
		return
	_file.store_line(line)
	# Flushed every line rather than in batches. The part of a playtest log worth
	# having is almost always the last few lines before whatever went wrong, and
	# buffering those is buffering exactly the ones a crash would take with it.
	_file.flush()


func _open_file() -> void:
	# The web has no filesystem the player can reach, so there is nothing useful
	# to open. There the log lives in memory and leaves through the menu buttons.
	if OS.has_feature("web"):
		return

	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var stamp := Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace("-", "").replace(":", "").replace("T", "_")
	var path := "%s/playtest_%s.log" % [LOG_DIR, stamp]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Dev: could not open %s, logging to memory only" % path)
		return
	_file = file
	log_path = path


## The whole log as one string, for the clipboard and the download.
func text() -> String:
	return "\n".join(lines)


func copy_to_clipboard() -> void:
	DisplayServer.clipboard_set(text())


## Hands the log to the browser as a file. The desktop already has one on disk.
func download() -> void:
	if not OS.has_feature("web"):
		return
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "")
	JavaScriptBridge.download_buffer(text().to_utf8_buffer(),
		"playtest_%s.log" % stamp, "text/plain")


# =============================================================================
#  Listening
# =============================================================================

func _subscribe() -> void:
	Events.phase_changed.connect(_on_phase_changed)
	Events.board_changed.connect(_on_board_changed)

	Events.round_began.connect(func(stage: int, round_number: int) -> void:
		record(&"ROUND", "%d-%d %s" % [stage, round_number,
			String(GameState.round_type())]))
	Events.round_resolved.connect(func(won: bool, damage: int, opponent: String) -> void:
		record(&"RESULT", "%s vs %s%s" % ["won" if won else "lost", opponent,
			"" if damage == 0 else ", -%d hull" % damage]))
	Events.game_over.connect(func(place: int) -> void:
		record(&"OVER", "finished %s at %d-%d" % [GameState.ordinal(place),
			GameState.stage, GameState.round_number]))

	Events.plan_time_warning.connect(func(seconds: float) -> void:
		record(&"CLOCK", "%.0fs left" % seconds))

	Events.gold_changed.connect(func(gold: int, delta: int) -> void:
		record(&"GOLD", "%+d to %d" % [delta, gold]))
	Events.level_changed.connect(func(level: int, xp: int, needed: int) -> void:
		record(&"LEVEL", "%d (%d/%d xp)" % [level, xp, needed]))
	Events.health_changed.connect(func(hp: int, delta: int) -> void:
		record(&"HULL", "%+d to %d" % [delta, hp]))
	Events.shop_rolled.connect(func(ids: Array) -> void:
		record(&"SHOP", ", ".join(_names(ids))))
	Events.shop_locked_changed.connect(func(locked: bool) -> void:
		record(&"SHOP", "locked" if locked else "unlocked"))

	Events.unit_bought.connect(func(id: StringName) -> void:
		record(&"BUY", _name(id)))
	Events.unit_sold.connect(func(id: StringName, value: int) -> void:
		record(&"SELL", "%s for %d" % [_name(id), value]))
	Events.unit_upgraded.connect(func(id: StringName, star: int) -> void:
		record(&"STAR", "%s to %d-star" % [_name(id), star]))

	Events.item_gained.connect(func(id: StringName, source: StringName) -> void:
		record(&"ITEM", "%s from %s" % [_item_name(id), String(source)]))
	Events.item_equipped.connect(func(id: StringName, uid: int) -> void:
		record(&"EQUIP", "%s on %s" % [_item_name(id), _unit_name(uid)]))
	Events.item_forged.connect(func(id: StringName, uid: int) -> void:
		record(&"FORGE", "%s on %s" % [_item_name(id), _unit_name(uid)]))

	# What the player was told, which is most of what a playtest is for. A notice
	# is the game refusing something, and a pile of the same refusal is a rule
	# that is not being communicated rather than a player who keeps forgetting.
	Events.notice.connect(func(text_: String, style: StringName) -> void:
		record(&"NOTE", "%s%s" % [text_, "" if style == &"" else " (%s)" % style]))
	Events.logged.connect(func(text_: String, _style: StringName) -> void:
		record(&"LOG", text_))


func _on_phase_changed(phase: int) -> void:
	var names := ["PLAN", "COMBAT", "RESULT", "ARMOURY", "OVER"]
	record(&"PHASE", names[phase] if phase < names.size() else str(phase))

	# The fleet as it stood when the fight started is the most useful line in the
	# log: it is the decision the player actually made, and everything the result
	# says afterwards is a consequence of it.
	if phase == GameState.Phase.COMBAT:
		record(&"FIELD", _fleet_summary())
		record(&"TRAITS", _trait_summary())


## Only when it has actually changed. `board_changed` fires on every drag,
## including the ones that put a pirate back where it was picked up from.
func _on_board_changed() -> void:
	var summary := _fleet_summary()
	if summary == _last_fleet:
		return
	_last_fleet = summary
	record(&"BOARD", summary)


# =============================================================================
#  Naming things
# =============================================================================

func _fleet_summary() -> String:
	if GameState.board.is_empty():
		return "(nothing fielded)"
	var parts := PackedStringArray()
	for u in GameState.board:
		var text_ := u.champion.display_name
		if u.star > 1:
			text_ += "*%d" % u.star
		if not u.items.is_empty():
			text_ += " [%s]" % ", ".join(_item_names(u.items))
		parts.append("%s @%d,%d" % [text_, u.cell.x, u.cell.y])
	return " | ".join(parts)


func _trait_summary() -> String:
	var parts := PackedStringArray()
	for entry in GameState.board_traits():
		if int(entry.get("tier", 0)) <= 0:
			continue
		var def: TraitDef = entry.get("def")
		parts.append("%s %d" % [def.display_name, int(entry.get("count", 0))])
	return "(none active)" if parts.is_empty() else ", ".join(parts)


func _name(id: StringName) -> String:
	var def: ChampionDef = GameState.content.champion(id)
	return String(id) if def == null else def.display_name


func _names(ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		out.append(_name(id))
	return out


func _item_name(id: StringName) -> String:
	var def: ItemDef = GameState.content.item_def(id)
	return String(id) if def == null else def.display_name


func _item_names(ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		out.append(_item_name(id))
	return out


func _unit_name(uid: int) -> String:
	for u in GameState.owned_units():
		if u.uid == uid:
			return u.champion.display_name + ("" if u.star == 1 else "*%d" % u.star)
	return "unit %d" % uid
