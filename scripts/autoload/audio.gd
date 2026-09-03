extends Node

## Sound.
##
## One bank of cues with two feeds. Everything the run *announces* comes off the
## `Events` bus, so the shop still does not know a speaker exists — buying a
## pirate makes a coin sound because `unit_bought` fired, not because `ShopBar`
## asked for one. Everything a *fight* does comes through `FxLayer`, the one node
## that draws every effect, because that is already the exact boundary this game
## needs: seven fights resolve every round and six are never rendered, so those
## six are silent for free. Sound fed from `Sim` instead would play six invisible
## battles over the top of the one being watched.
##
## Cues are data. `BANK` is the whole design — which file, how loud, how far the
## pitch may wander, and how often it may repeat — so making the cannons quieter
## or swapping a sound for a better one is an edit to a dictionary rather than to
## any code. Several cues name more than one file and pick between them, which
## with a little pitch wander is what stops eighteen pirates attacking from
## sounding like one sample stuttering.
##
## Loudness is two numbers on purpose. A cue's `db` is where it sits *against the
## other cues*, and `MASTER_DB` is where the game sits against everything else
## the player has open — so turning the game down is one edit rather than fifty,
## and it cannot quietly undo the mix. `GROUP_GAPS` is the same split applied to
## density: a per-cue gap keeps one sound from stuttering, a group gap keeps a
## whole board of them from arriving together.
##
## **The sounds are CC0** from Kenney (kenney.nl) — see `audio/CREDITS.md`. They
## were chosen by what each file is *named*: a pack's "confirmation" and "error"
## carry their meaning in the name, where a melody's mood cannot be read off a
## filename at all. That is why nothing here is a jingle.
##
## Sound stands down where there is nobody to hear it. Headless is the test
## suite, `playthrough.gd` and `creep_balance.gd`, and none of those is a
## listener.

const DIR := "res://audio/"

## Enough voices for a busy exchange without a fight becoming a wall. When they
## are all busy the oldest is taken, so a new sound is never dropped in favour of
## one already half played.
const VOICES := 12

const SETTINGS := "user://settings.cfg"

## How loud the game is, over the top of everything below.
##
## `BANK` is a *mix*: each cue's `db` says how loud that sound is next to the
## others, which is a different question from how loud the game is next to
## whatever else the player has open. Tuning the first by editing fifty numbers
## loses the second, so the master trim is its own knob — turn the game down
## here, and the balance struck below survives it.
const MASTER_DB := -9.0

## Everything a fight does, throttled together rather than cue by cue.
##
## A per-cue gap keeps one sound from stuttering; it does nothing about
## *eighteen* pirates, because a board with four attack styles on it is four
## separate throttles all firing at once. Eighteen units attacking at 4x is
## upwards of fifty swings a second, and a twelve-voice pool asked for fifty
## sounds a second spends the fight stealing voices from itself — which is what
## a wall of noise actually is. One shared floor across every attack turns that
## into a patter of distinct hits, and the sounds that carry information — a
## death, an ability, a crit — are deliberately *outside* it, so they still cut
## through the swings rather than queueing behind them.
const GROUP_GAPS := {
	&"swing": 0.085,
}

## Every cue in the game.
##
##   files  one or more names in `audio/`; one is picked at random
##   db     volume, relative to the file's own level and to every other cue.
##          `MASTER_DB` is added on top of it
##   pitch  the range the playback rate may wander in — variation, and for a few
##          cues (the cannon) the whole reason the file sounds like what it is
##   gap    the shortest time between two plays of this cue, in seconds. A fight
##          at 4x fires attacks faster than a sound can finish, and without this
##          the result is mush rather than a battle
##   group  a gap shared with every other cue naming it, from `GROUP_GAPS`. Both
##          gaps apply: the cue's own, and its group's
const BANK := {
	# --- the shop and the economy
	&"buy":       { "files": ["handleCoins.ogg"],    "db": -7.0,  "pitch": Vector2(0.98, 1.04) },
	&"sell":      { "files": ["chips-handle-2.ogg"], "db": -9.0,  "pitch": Vector2(0.98, 1.04) },
	&"lock":      { "files": ["switch_004.ogg"],     "db": -12.0, "pitch": Vector2(1.0, 1.0) },
	# Four XP a purchase, so this is the most-played cue in the shop by a wide
	# margin. It is a tick under the coins, not a second sound beside them.
	&"xp":        { "files": ["tick_002.ogg"],       "db": -15.0, "pitch": Vector2(0.98, 1.06), "gap": 0.06 },
	&"level_up":  { "files": ["select_005.ogg"],     "db": -8.0,  "pitch": Vector2(1.0, 1.0) },
	&"star_up":   { "files": ["confirmation_004.ogg"], "db": -6.0, "pitch": Vector2(1.0, 1.0) },
	# A buzzer is the harshest noise in the pack and it fires on every refusal —
	# a mistimed click on a locked shop used to buzz twice a second. Quiet, and
	# rationed: the toast is the message, this only points at it.
	&"denied":    { "files": ["error_004.ogg"],      "db": -14.0, "pitch": Vector2(1.0, 1.0), "gap": 0.7 },

	# --- items
	&"item":      { "files": ["metalLatch.ogg"],     "db": -8.0,  "pitch": Vector2(0.97, 1.03) },
	&"equip":     { "files": ["beltHandle1.ogg"],    "db": -9.0,  "pitch": Vector2(0.97, 1.05) },
	&"forge":     { "files": ["impactMetal_heavy_000.ogg", "impactMetal_heavy_001.ogg"],
	                                                 "db": -8.0,  "pitch": Vector2(0.9, 1.0) },

	# --- the round loop
	&"round":     { "files": ["open_004.ogg"],       "db": -11.0, "pitch": Vector2(1.0, 1.0) },
	&"warning":   { "files": ["bong_001.ogg"],       "db": -10.0, "pitch": Vector2(1.0, 1.0) },
	&"combat":    { "files": ["impactBell_heavy_002.ogg"], "db": -8.0, "pitch": Vector2(0.9, 0.9) },
	&"armoury":   { "files": ["creak1.ogg"],         "db": -8.0,  "pitch": Vector2(0.95, 1.0) },
	&"won":       { "files": ["confirmation_002.ogg"], "db": -6.0, "pitch": Vector2(1.0, 1.0) },
	&"lost":      { "files": ["error_008.ogg"],      "db": -8.0,  "pitch": Vector2(1.0, 1.0) },
	&"hull":      { "files": ["impactWood_heavy_001.ogg"], "db": -7.0, "pitch": Vector2(0.85, 0.95) },

	# --- a fight: ranged attacks, one cue per style
	#
	# The pitch is doing real work here. There is no cannon in a CC0 interface
	# pack, but a heavy metal impact dropped half an octave is a cannon — and the
	# same file at its own pitch is the anvil the forge uses.
	#
	# Every one of these is in the `swing` group. A single attack is background:
	# what the player is reading is the board, and the swings are its texture, so
	# they sit well under the round's own announcements.
	&"shot":         { "files": ["impactMetal_light_001.ogg", "impactMetal_light_002.ogg"],
	                                                 "db": -20.0, "pitch": Vector2(1.1, 1.3), "gap": 0.09, "group": &"swing" },
	&"shot_cannon":  { "files": ["impactMetal_heavy_000.ogg", "impactMetal_heavy_001.ogg"],
	                                                 "db": -16.0, "pitch": Vector2(0.5, 0.62), "gap": 0.1, "group": &"swing" },
	&"shot_bullet":  { "files": ["impactMetal_light_001.ogg", "impactMetal_light_002.ogg"],
	                                                 "db": -20.0, "pitch": Vector2(1.15, 1.35), "gap": 0.09, "group": &"swing" },
	&"shot_harpoon": { "files": ["drawKnife2.ogg"],  "db": -18.0, "pitch": Vector2(0.95, 1.1), "gap": 0.1, "group": &"swing" },
	&"shot_bolt":    { "files": ["pluck_002.ogg"],   "db": -20.0, "pitch": Vector2(0.9, 1.15), "gap": 0.09, "group": &"swing" },
	&"shot_spark":   { "files": ["pluck_002.ogg"],   "db": -20.0, "pitch": Vector2(1.15, 1.4), "gap": 0.09, "group": &"swing" },
	&"shot_orb":     { "files": ["glass_005.ogg"],   "db": -20.0, "pitch": Vector2(0.95, 1.15), "gap": 0.1, "group": &"swing" },
	&"shot_wisp":    { "files": ["glass_005.ogg"],   "db": -20.0, "pitch": Vector2(0.7, 0.85), "gap": 0.1, "group": &"swing" },

	# --- a fight: melee
	&"melee":          { "files": ["knifeSlice.ogg", "knifeSlice2.ogg"],
	                                                 "db": -18.0, "pitch": Vector2(0.95, 1.1), "gap": 0.09, "group": &"swing" },
	&"melee_slash":    { "files": ["knifeSlice.ogg", "knifeSlice2.ogg"],
	                                                 "db": -18.0, "pitch": Vector2(0.95, 1.1), "gap": 0.09, "group": &"swing" },
	&"melee_claw":     { "files": ["knifeSlice2.ogg"], "db": -18.0, "pitch": Vector2(1.1, 1.3), "gap": 0.09, "group": &"swing" },
	&"melee_crush":    { "files": ["impactPlank_medium_000.ogg", "impactPlank_medium_001.ogg"],
	                                                 "db": -16.0, "pitch": Vector2(0.8, 0.95), "gap": 0.09, "group": &"swing" },
	&"melee_spectral": { "files": ["glass_005.ogg"], "db": -20.0, "pitch": Vector2(0.6, 0.75), "gap": 0.1, "group": &"swing" },

	# --- a fight: everything that is not an attack
	#
	# Outside the `swing` group on purpose. These four are the ones carrying
	# information — something died, something cast, something hit hard — and a
	# fight in which they queue behind the swings is a fight that reports nothing.
	&"crit":      { "files": ["impactPlate_heavy_000.ogg"], "db": -13.0, "pitch": Vector2(0.95, 1.1), "gap": 0.13 },
	&"death":     { "files": ["dropLeather.ogg"],    "db": -11.0, "pitch": Vector2(0.85, 1.0), "gap": 0.1 },
	&"cast":      { "files": ["maximize_006.ogg"],   "db": -15.0, "pitch": Vector2(0.95, 1.1), "gap": 0.12 },
	&"nova":      { "files": ["impactMetal_heavy_000.ogg"], "db": -12.0, "pitch": Vector2(0.65, 0.75), "gap": 0.14 },
}

## What a drawn effect sounds like.
##
## Only the kinds worth hearing are here. An ability that draws a `cast`, a
## `nova` and four `tracer`s is one thing happening, and sounding all six is the
## same mistake a node per hit was: the tracers, chains and beams that decorate a
## cast are silent, and the cast is not.
const FX_CUES := {
	&"muzzle": &"shot",
	&"melee": &"melee",
	&"crit": &"crit",
	&"death": &"death",
	&"cast": &"cast",
	&"nova": &"nova",
}

var muted: bool = false

## What has actually been heard, by cue, and how many sounds have played at all.
##
## Not bookkeeping for its own sake: sound is the system that looks perfect while
## producing nothing, exactly like a DPS meter rendering honest zeros. A missing
## file, a signal that stopped firing, a feed wired to the wrong place — all of
## them are silence, and silence is also what most of a game sounds like. These
## two are what `screenshot.gd --sfx` asserts against, because the suite is
## headless and can only ever check the bank.
var plays: int = 0
var cues_played: Dictionary = {}

## False where there is nobody listening — headless, which is every tool that
## resolves fights by the thousand.
var _enabled: bool = false

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _started: Array[float] = []
var _last_played: Dictionary = {}
var _last_group: Dictionary = {}
var _rng := RandomNumberGenerator.new()

## The level the last `level_changed` reported, so a level-up can be told from
## the four XP a purchase buys. The signal carries both, and only the numbers say
## which one it was.
var _level: int = 1


func _ready() -> void:
	_rng.randomize()
	_enabled = DisplayServer.get_name() != "headless"
	_load_settings()

	# Connected even where nothing can be heard. A signal named wrongly in here is
	# a cue that simply never plays, and `connect()` is the one thing that says
	# so — standing the wiring down headless would mean the only run that checks
	# everything is the only run that never looks.
	_connect_bus()
	if not _enabled:
		return

	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Master"
		add_child(voice)
		_voices.append(voice)
		_started.append(-1000.0)


# =============================================================================
#  Playing
# =============================================================================

## Plays a cue by name. An unknown name is ignored rather than fatal: a cue is a
## garnish, and a typo in one should not take a round down with it. `test_audio`
## is what catches the typo instead.
func play(cue: StringName) -> void:
	if not _enabled or muted:
		return
	var spec: Dictionary = BANK.get(cue, {})
	if spec.is_empty():
		return

	var now := float(Time.get_ticks_msec()) / 1000.0
	var gap: float = spec.get("gap", 0.0)
	if gap > 0.0 and now - float(_last_played.get(cue, -1000.0)) < gap:
		return

	# The cue's own gap stops one sound stuttering; its group's stops a whole
	# board of them arriving at once. Both are checked before either is recorded,
	# or a cue refused by its group would still push the other one forward and
	# silence itself twice over.
	var group: StringName = spec.get("group", &"")
	if group != &"":
		var group_gap: float = GROUP_GAPS.get(group, 0.0)
		if group_gap > 0.0 and now - float(_last_group.get(group, -1000.0)) < group_gap:
			return
		_last_group[group] = now
	_last_played[cue] = now

	var files: Array = spec["files"]
	var stream := _stream(files[_rng.randi_range(0, files.size() - 1)])
	if stream == null:
		return

	var index := _claim_voice(now)
	var voice := _voices[index]
	var pitch: Vector2 = spec.get("pitch", Vector2.ONE)
	voice.stream = stream
	voice.volume_db = float(spec.get("db", -6.0)) + MASTER_DB
	voice.pitch_scale = _rng.randf_range(pitch.x, pitch.y)
	voice.play()

	plays += 1
	cues_played[cue] = int(cues_played.get(cue, 0)) + 1


## What a drawn effect sounds like. Called by `FxLayer` as it takes an entry off
## the queue, which is the point where "this fight is being watched" is already
## known — the six fights nobody sees never reach it.
func fx(kind: StringName, style: StringName = &"") -> void:
	var cue: StringName = FX_CUES.get(kind, &"")
	if cue == &"":
		return
	# An attack's style is a different sound, not a variation of one: a cannon
	# and a cutlass have nothing in common. A style with no entry of its own falls
	# back to the generic cue, so one added later is plain rather than silent.
	if style != &"":
		var styled := StringName("%s_%s" % [cue, style])
		if BANK.has(styled):
			cue = styled
	play(cue)


## The oldest voice, when every one of them is busy. Taking the oldest is the
## right way round: the sound that has been playing longest is the one already
## half heard, and the new one is the thing that just happened.
func _claim_voice(now: float) -> int:
	var oldest := 0
	for i in _voices.size():
		if not _voices[i].playing:
			_started[i] = now
			return i
		if _started[i] < _started[oldest]:
			oldest = i
	_started[oldest] = now
	return oldest


func _stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var stream: AudioStream = load(DIR + file) as AudioStream
	_streams[file] = stream
	return stream


# =============================================================================
#  Muting
# =============================================================================

## Sound off. Kept in `user://settings.cfg` so it survives the tab being closed —
## a player who turned the sound off did not mean "until you next open me".
func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	if muted:
		for voice in _voices:
			voice.stop()
	_save_settings()
	Events.sound_muted_changed.emit(muted)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS) != OK:
		return
	muted = bool(config.get_value("audio", "muted", false))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS)


# =============================================================================
#  The bus
# =============================================================================

func _connect_bus() -> void:
	Events.unit_bought.connect(func(_id): play(&"buy"))
	Events.unit_sold.connect(func(_id, _value): play(&"sell"))
	Events.unit_upgraded.connect(func(_id, _star): play(&"star_up"))
	Events.shop_locked_changed.connect(func(_locked): play(&"lock"))
	Events.level_changed.connect(_on_level_changed)

	Events.item_gained.connect(func(_id, _source): play(&"item"))
	Events.item_equipped.connect(func(_id, _uid): play(&"equip"))
	Events.item_forged.connect(func(_id, _uid): play(&"forge"))

	Events.round_began.connect(func(_stage, _number): play(&"round"))
	Events.plan_time_warning.connect(func(_left): play(&"warning"))
	Events.phase_changed.connect(_on_phase_changed)
	Events.round_resolved.connect(func(won, _damage, _name): play(&"won" if won else &"lost"))
	Events.health_changed.connect(_on_health_changed)

	# Most notices are the game refusing something — no gold, no room, wrong
	# phase — and hearing that is faster than reading it. But `notify` carries a
	# style precisely because not all of them are: the weather round announces a
	# following sea through the same call, and buzzing at the player for a boon
	# tells them the opposite of what happened. Only a refusal buzzes.
	Events.notice.connect(_on_notice)


func _on_notice(_text: String, style: StringName) -> void:
	if style == &"good":
		return
	play(&"denied")


func _on_level_changed(level: int, _xp: int, _needed: int) -> void:
	if level > _level:
		play(&"level_up")
	else:
		play(&"xp")
	_level = level


func _on_phase_changed(phase: int) -> void:
	match phase:
		GameState.Phase.COMBAT:
			play(&"combat")
		GameState.Phase.ARMOURY:
			play(&"armoury")
		GameState.Phase.PLAN:
			# A new run resets the level this tracks. Without it, restarting after
			# a run that reached level 8 plays a level-up for the first XP of the
			# next one, and never plays another.
			if GameState.stage == 1 and GameState.round_number == 1:
				_level = 1


func _on_health_changed(_hp: int, delta: int) -> void:
	if delta < 0:
		play(&"hull")
