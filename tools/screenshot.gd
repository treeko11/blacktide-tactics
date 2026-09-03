extends "res://tools/tool_script.gd"

## Loads the game, lets it settle, and writes a PNG.
##
##   godot --path . --script res://tools/screenshot.gd -- --out=shot.png
##
## Must run *without* `--headless`: there is nothing to capture if nothing was
## rendered.
##
## Arguments after `--`:
##   --out=<path>     where to write (default user://shot.png)
##   --phase=combat   skip the planning phase and photograph a fight instead
##   --frames=<n>     how many frames to let pass first
##   --gold=<n>       start the player with this much gold
##   --units=<ids>    comma-separated champion ids to field, e.g. lyra,kraken
##   --bench=<ids>    comma-separated champion ids to sit on the bench
##   --stars=<n>      what star the fielded crew is (default 2)
##   --size=<WxH>     resize the window first, e.g. --size=390x844 for a phone
##   --touch=yes|no   pretend the device does or does not have a touchscreen.
##                    A desktop reports none, and `Layout.short()` now asks — so
##                    a sideways *phone* is only reachable with --touch=yes
##   --hold=<what>    press and hold a "card", a "bench" slot, a "trait" badge,
##                    an "item" or a forge "chart"
##                    square, then photograph the inspector it opens
##   --rotate=<WxH>   resize again once the HUD is up, to prove it rebuilds
##   --measure        print how tall each block of the HUD ended up
##   --briefing       photograph the opening almanac, and assert the run is
##                    holding its clock behind it and starts when it closes
##   --sfx            fight a real round and assert sound actually came out of it
##   --almanac=<id>   open the almanac on one pirate's or one sea's entry and
##                    photograph it,
##                    asserting the entry drew its portrait
##   --sequence=buy   tap a card to buy it, and prove the inspector that opened
##                    on the way in is gone once the finger is off
##   --sequence=forge replay the reported lock-up: read the forge chart, close
##                    it, then try to buy from the shop
##   --live           hover a pirate mid-fight and prove the inspector keeps up
##                    with it without the cursor moving again
##   --shop=<ids>     comma-separated champion ids to seat in the shop
##   --sea=<id>       put the run on its weather round with that sea running,
##                    and assert the board marked the water and the top bar
##                    named it
##   --modal=dps      fight a real round, open the DPS meter, and assert all
##                    three tabs have numbers in them rather than empty frames
##   --tab=<which>    which DPS tab to photograph: dealt, taken or healed
##   --fight=no       open the DPS meter before a shot has been fired, to prove
##                    it says so and can still be closed

var _out := "user://shot.png"
var _scene: Node = null

## Where the last scripted hover put the pointer, so a failure can tell whether
## it is still there. -1 means nothing has hovered yet.
var _hover_home := Vector2(-1.0, -1.0)


func setup() -> void:
	_out = arg("out", _out)
	startup_frames = int(arg("frames", "40"))

	# Before the scene exists, so the HUD is built in the layout it will be shot
	# in rather than built wide and then rebuilt. The same goes for the touch
	# answer: `Layout.short()` reads it, so it has to be settled before the first
	# build or the sideways-phone shot is of a desktop's landscape HUD.
	var pretend := arg("touch")
	if pretend != "":
		Layout.touch_override = 1 if pretend == "yes" else 0

	var wanted := arg("size")
	if wanted != "":
		var parts := wanted.split("x")
		if parts.size() == 2:
			root.size = Vector2i(int(parts[0]), int(parts[1]))

	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func run() -> void:
	var game := state()
	if game == null:
		fail("no GameState")
		return

	manual_quit = true

	# The briefing is the first thing every run shows and the only screen with the
	# clock stopped behind it, so it is photographed before anything is dismissed.
	if has_flag("briefing"):
		await _briefing(game)
		finish()
		return

	_close_modals()

	# Closing the opening almanac is what starts a new run's clock. The wiring
	# that does it is in Main, where no unit test can see it, and a run still
	# holding here is a game that never begins — a frozen clock and a shop that
	# never closes, which reads as the round loop having stopped.
	if game.awaiting_start:
		fail("closing the almanac left the run holding at the line")

	if arg("speed") != "":
		game.speed = int(arg("speed"))
	if arg("gold") != "":
		game.player.gold = int(arg("gold"))

	var units := arg("units")
	if units != "":
		_field(game, units.split(","))

	var benched := arg("bench")
	if benched != "":
		_bench(game, benched.split(","))

	var counter := arg("shop")
	if counter != "":
		_stock_shop(game, counter.split(","))

	if arg("sea") != "":
		_set_sea(game, StringName(arg("sea")))
		await _frames(3)
		_check_sea(game)

	if arg("modal") != "":
		await _open_modal(arg("modal"), game)
		await _frames(3)
		_capture()
		finish()
		return

	if arg("almanac") != "":
		await _almanac_entry(arg("almanac"))
		_capture()
		finish()
		return

	if arg("sequence") != "":
		await _sequence(game, arg("sequence"))
		_capture()
		finish()
		return

	if has_flag("measure"):
		await _frames(6)
		_measure()
		_capture()
		finish()
		return

	if arg("rotate") != "":
		await _rotate(arg("rotate"))
		_capture()
		finish()
		return

	if arg("hold") != "":
		await _press_and_hold(game, arg("hold"))
		_capture()
		finish()
		return

	if has_flag("sfx"):
		await _listen_to_a_fight(game)
		finish()
		return

	if has_flag("live"):
		await _watch_a_fight(game)
		finish()
		return

	if arg("phase") == "combat":
		await _run_a_fight(game)
	else:
		await _frames(3)      # let the board rebuild after fielding a crew
		_capture()
	finish()


## Fields a named crew, so a screenshot can show a real board rather than an
## empty one.
func _field(game: Node, ids: PackedStringArray) -> void:
	game.player.level = maxi(game.player.level, ids.size())
	var seats := [
		Vector2i(3, 5), Vector2i(2, 5), Vector2i(4, 5), Vector2i(1, 5),
		Vector2i(5, 5), Vector2i(3, 7), Vector2i(2, 7), Vector2i(4, 7),
	]
	var star := int(arg("stars", "2"))
	for i in mini(ids.size(), seats.size()):
		var champion = content().champion(StringName(ids[i].strip_edges()))
		if champion == null:
			continue
		var unit := RosterUnit.new(champion, star)
		unit.cell = seats[i]
		game.board.append(unit)
	events().board_changed.emit()


## Puts named champions on the bench, for shots and touch tests that need one.
func _bench(game: Node, ids: PackedStringArray) -> void:
	for i in mini(ids.size(), game.bench.size()):
		var champion = content().champion(StringName(ids[i].strip_edges()))
		if champion != null:
			game.bench[i] = RosterUnit.new(champion, int(arg("stars", "2")))
	events().board_changed.emit()


## Seats named champions in the shop, so a shot can show a card against a known
## fleet rather than whatever the roll happened to offer.
func _stock_shop(game: Node, ids: PackedStringArray) -> void:
	for i in game.shop.size():
		game.shop[i] = &"" if i >= ids.size() else StringName(ids[i].strip_edges())
	events().shop_rolled.emit(game.shop.duplicate())


## Adds the one explanation that is not a bug in the game.
##
## Every hover check here drives the real mouse pointer, because that is what the
## inspector reads. Run the tool while somebody is using the machine and their
## hand wins: the cursor leaves the card, the inspector closes itself exactly as
## designed, and the assertion reports a bug that is not there. A run that ends
## with the pointer somewhere other than where the last hover put it is the one
## case worth calling out, because it is otherwise indistinguishable.
func fail(message: String) -> void:
	if _hover_home.x >= 0.0 and root.get_mouse_position().distance_to(_hover_home) > 2.0:
		super(message
			+ "\n           (the pointer was moved during the run — this "
			+ "tool drives the real cursor, so run it on an idle machine)")
	else:
		super(message)


# --- scripted touch ----------------------------------------------------------

## Viewport coordinates to window coordinates.
##
## Everything here is aimed by measuring a Control, which lives in the viewport's
## space — but `Input.parse_input_event` and `Input.warp_mouse` both speak the
## *window's*, and Godot maps between the two with the content-scale transform.
##
## They are the same numbers only while that transform is identity, which it was
## at every layout this tool had ever run at. A phone held sideways is the first
## that is not: the game is played upright, so a portrait canvas is letterboxed
## into the wider window at 0.46 with a third of the screen as an offset. Aimed
## without this, every tap landed off the left edge and all fifteen checks
## reported the game ignoring the player. The game was fine — a real finger
## arrives in window coordinates already, which is the half a scripted one has
## to do for itself.
func _to_window(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


## One finger down at a point, held for `seconds`, then lifted.
func _touch(at: Vector2, seconds: float = 0.05) -> void:
	_touch_down(at)
	await _frames(maxi(2, roundi(seconds * 60.0)))
	_touch_up(at)
	await _frames(4)


## The two halves separately, for the checks that have to look at the screen
## while the finger is still on it.
func _touch_down(at: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = _to_window(at)
	Input.parse_input_event(down)


func _touch_up(at: Vector2) -> void:
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = _to_window(at)
	Input.parse_input_event(up)


## Moves the pointer, the way a browser does on the way into a tap.
##
## A phone's tap is not only a touch: the browser synthesises the compatibility
## mouse events with it, and the `mousemove` in that set is what makes a control
## report `mouse_entered` and open the inspector. Godot's own
## `emulate_mouse_from_touch` sends the button but not the move, so a scripted
## touch on its own never opens one — and a test of "does the inspector close
## again" that never opened one passes for the wrong reason.
func _hover_at(at: Vector2) -> void:
	# The pointer is actually moved, not merely told about: the inspector closes
	# itself when `get_viewport().get_mouse_position()` leaves its owner, and that
	# reports where the pointer *is*, not what was last parsed. A parsed motion
	# alone opens the inspector and then the next frame closes it again.
	#
	# Which means the tool is sharing one pointer with whoever is sitting at the
	# machine, and loses every argument about where it should be. The warp is
	# checked and repeated rather than assumed, and `fail()` below says so when
	# the thing that moved it was a hand.
	var window_at := _to_window(at)
	for attempt in 5:
		Input.warp_mouse(window_at)
		if root.get_mouse_position().distance_to(at) <= 2.0:
			break
	_hover_home = at

	var motion := InputEventMouseMotion.new()
	motion.position = window_at
	motion.global_position = window_at
	Input.parse_input_event(motion)


## A left click where the pointer already is.
func _click_at(at: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = _to_window(at)
		click.global_position = _to_window(at)
		Input.parse_input_event(click)


func _centre_of(control: Control) -> Vector2:
	return control.global_position + control.size * 0.5


## Replays the sequence that left the shop unresponsive on a phone.
##
## The report was "I could not interact with the store after a round — I think it
## was after I opened the forge guide or looked at an item tooltip". Both of those
## leave state behind that the shop does not know about, so this walks the whole
## path with real touch events and then checks that a tap still buys a pirate.
func _sequence(game: Node, which: String) -> void:
	# Look at a card first, so the hover state the inspector reads is populated.
	await _touch(_centre_of(_scene.shop._cards[0]), 0.05)
	print("  after a plain tap on a card: gold %d" % game.player.gold)

	match which:
		"forge":
			_scene.modals.open_forge_chart()
			await _frames(8)
			# Rest a finger on the chart, the way anyone reading it would.
			await _touch(Vector2(Layout.css_size.x * 0.5, Layout.css_size.y * 0.4), 0.6)
			print("  while the chart is open: tooltip pinned=%s"
				% str(_scene.tooltip.pinned))
			_scene.modals.close()
			await _frames(8)
		"item":
			game.give_item(&"blade", &"salvage")
			await _frames(8)
			var chip: Control = _scene.hold._grid.get_child(0)
			await _touch(_centre_of(chip), 0.6)
			print("  after holding an item: tooltip pinned=%s" % str(_scene.tooltip.pinned))
			_scene.tooltip.hide_now()
			await _frames(4)
		"almanac":
			await _browse_the_almanac()
		"buy":
			await _tap_to_buy(game)
		_:
			fail("unknown sequence '%s'" % which)
			return

	print("  after closing: tooltip pinned=%s visible=%s"
		% [str(_scene.tooltip.pinned), str(_scene.tooltip.visible)])

	# Fund the rest of the run. What is under test here is whether a tap reaches
	# the control, and a player who cannot afford the thing they tapped answers a
	# different question: the opening tap on a card leaves 1 gold, which disables
	# the Roll button, and a disabled button not responding is correct behaviour
	# reported as a lock-up.
	game.player.gold = 50
	events().gold_changed.emit(game.player.gold, 0)
	await _frames(2)

	# Now the thing that was reported broken: buying from the shop. A card that
	# has already been bought is empty and buys nothing, so pick a full one.
	var gold_before: int = game.player.gold
	var bought := -1
	for attempt in 3:
		var target: Control = null
		for c in _scene.shop._cards:
			if c.champion != null:
				target = c
				break
		if target == null:
			fail("the shop is empty; nothing left to tap")
			return
		await _touch(_centre_of(target), 0.05)
		if game.player.gold != gold_before:
			bought = attempt + 1
			break

	# The same question for an ordinary Button, which is most of the HUD.
	var before_roll: int = game.player.gold
	var rolled := -1
	for attempt in 3:
		await _touch(_centre_of(_scene.shop._reroll_button), 0.05)
		if game.player.gold != before_roll:
			rolled = attempt + 1
			break
	if rolled < 0:
		fail("the Roll button never responded")
	elif rolled > 1:
		fail("the Roll button swallowed %d tap(s)" % (rolled - 1))
	else:
		print("  the first tap on Roll worked")

	if bought < 0:
		fail("the shop never responded: three taps after %s bought nothing" % which)
	elif bought > 1:
		fail("the shop swallowed %d tap(s) after %s before responding" % [bought - 1, which])
	else:
		print("  the first tap after %s bought a pirate" % which)


## Taps its way through the almanac and leaves by the scrim.
##
## Everything here is a real touch at a measured coordinate rather than a call
## into the dialog, because what the sequence around it is checking is whether a
## full-screen overlay hands input back cleanly — the failure this project has
## had twice, where a panel left Godot's press/release bookkeeping one event
## behind and the shop looked dead afterwards.
func _browse_the_almanac() -> void:
	var wiki: Node = _scene.wiki
	wiki.open(&"pirates")
	await _frames(8)

	# A finger dragged down the rows themselves, which is the part of the list a
	# phone could not scroll at all: every row is a Button, a Button is STOP, and
	# Godot's own touch scrolling only ever saw the two points of separation
	# between them. Fifty-one pirates, so this list scrolls at every layout.
	var list_scroll: ScrollContainer = wiki._list.get_parent()
	var was_entry: StringName = wiki._entry
	var swipe_row: Control = _first_row(wiki)
	if swipe_row == null:
		fail("the almanac's list has no rows to swipe")
		return
	await _swipe(_centre_of(swipe_row), Vector2(0, -90.0))
	print("  after a swipe down the rows: scroll 0 -> %d, entry=%s"
		% [list_scroll.scroll_vertical, wiki._entry])
	if list_scroll.scroll_vertical <= 0:
		fail("swiping the list of pirates did not scroll it")
	if wiki._entry != was_entry:
		fail("the swipe opened '%s' — a scroll must not press the row it started on"
			% wiki._entry)
	# Everything below taps a measured coordinate, so the list goes back to where
	# those coordinates were measured.
	list_scroll.scroll_vertical = 0
	await _frames(2)

	# The tabs are in SECTIONS order; index 2 is TRAITS.
	await _touch(_centre_of(wiki._tabs.get_child(2)), 0.05)
	if wiki._section != &"traits":
		fail("tapping the TRAITS tab left the almanac on '%s'" % wiki._section)
	print("  after tapping a tab: section=%s" % wiki._section)

	var row: Control = _first_row(wiki)
	if row == null:
		fail("the almanac's list has no rows to tap")
		return
	await _touch(_centre_of(row), 0.05)
	if wiki._entry == &"":
		fail("tapping a list row opened nothing")
	print("  after tapping a row: entry=%s, page is %d characters"
		% [wiki._entry, wiki._page.text.length()])

	# On a narrow screen the list is replaced by the page rather than sitting
	# beside it, and BACK is then the only way out of an entry.
	if not wiki._two_pane():
		if wiki._list_pane.visible:
			fail("drilled into an entry and the list is still showing")
		if not wiki._back.visible:
			fail("drilled into an entry with no BACK button")
		await _touch(_centre_of(wiki._back), 0.05)
		if not wiki._list_pane.visible:
			fail("BACK did not return to the list")
		print("  BACK returned to the list")

	# Out by the scrim, which is the corner of the screen the box never covers.
	await _touch(Vector2(4.0, Layout.css_size.y - 4.0), 0.05)
	if wiki.is_open():
		fail("tapping outside the almanac did not close it")
	else:
		print("  tapping outside closed it")


## The first tappable row of the almanac's list, past any group heading.
func _first_row(wiki: Node) -> Control:
	for child in wiki._list.get_children():
		if child is Button:
			return child
	return null


## Drags a finger across the screen: down, a run of real `InputEventScreenDrag`
## a frame apart, then up.
##
## Spread over frames rather than sent as one big jump, because that is what
## decides whether the gesture is a scroll or a tap — a drag is only a scroll
## once it has travelled far enough, and one enormous relative would say nothing
## about where that line is.
func _swipe(from: Vector2, by: Vector2, steps: int = 6) -> void:
	_touch_down(from)
	await _frames(2)

	var step := by / float(steps)
	var at := from
	for i in steps:
		at += step
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = _to_window(at)
		drag.relative = root.get_final_transform().basis_xform(step)
		Input.parse_input_event(drag)
		await _frames(1)

	_touch_up(at)
	await _frames(4)


## Opens one champion's almanac entry and checks it came up with a figure on it.
##
## The portrait is a node beside the page rather than anything in the page text,
## so `test_wiki.gd` walking every entry and rendering every page says nothing
## about whether it appeared — a champion whose portrait never shows still has a
## complete, correct page.
func _almanac_entry(id: String) -> void:
	var wiki: Node = _scene.wiki
	var section: StringName = &"pirates"
	var champion = content().champion(StringName(id))
	var sea: Variant = content().sea(StringName(id))
	if champion == null and sea == null:
		fail("nothing in the almanac is called '%s'" % id)
		return
	if champion == null:
		section = &"seas"
	elif champion.cost == 0:
		section = &"monsters"

	wiki.open(section)
	await _frames(4)
	wiki._open_entry(section, StringName(id))
	await _frames(6)

	if wiki._entry != StringName(id):
		fail("the almanac opened '%s' rather than '%s'" % [wiki._entry, id])
		return
	# A sea has no figure to draw, so what is asserted there is that the page
	# came up with the sea's own words in it rather than an empty frame — the
	# failure a section added to `SECTIONS` and never given a `page_for` branch
	# produces, which renders as a blank page and throws nothing.
	if section == &"seas":
		var page: String = wiki.page_for(section, StringName(id))
		if not page.contains(sea.display_name):
			fail("the %s page came up without the sea in it" % id)
		elif not page.contains(sea.herald):
			fail("the %s page dropped its herald line" % id)
		else:
			print("  the almanac opened %s, %d characters" % [id, page.length()])
		return

	var portrait: Control = wiki._page_portrait
	if portrait == null:
		fail("the almanac page has no portrait node at all")
		return
	if not portrait.visible:
		fail("%s's entry drew no portrait" % id)
	elif portrait.size.x < 20.0 or portrait.size.y < 20.0:
		fail("%s's portrait collapsed to %s" % [id, portrait.size])
	else:
		print("  %s: %s, portrait %d x %d"
			% [id, champion.art_body, portrait.size.x, portrait.size.y])


## Prints the height of every block of the HUD.
##
## The phone layout is a fight over vertical space and the board loses it by
## default: it is the one panel that takes what is left over. Numbers beat
## squinting at a screenshot when deciding which piece of furniture to cut.
func _measure() -> void:
	var total: float = Layout.css_size.y
	print("  viewport %d x %d (css)" % [Layout.css_size.x, total])
	var blocks := {
		"top bar": _scene.top_bar,
		"board": _scene.board,
		"traits": _scene.traits,
		"cargo hold": _scene.hold,
		"bench": _scene.bench,
		"shop": _scene.shop,
	}
	for name in blocks:
		var control: Control = blocks[name]
		if control == null:
			continue
		print("  %-12s %6.1f  (%4.1f%%)"
			% [name, control.size.y, 100.0 * control.size.y / maxf(total, 1.0)])
	print("  board scale %.3f -> %d x %d hexes drawn"
		% [_scene.board.board_scale,
			roundi(Hex.board_size().x * _scene.board.board_scale),
			roundi(Hex.board_size().y * _scene.board.board_scale)])


## Resizes a running HUD and checks it did the right thing — which is the
## opposite thing on a touchscreen.
##
## A window resize on a desktop crosses a breakpoint and has to rebuild, and that
## is a resize the *running* game must notice rather than one it is launched
## with. A phone being turned is the same event and now has to be **ignored**:
## the game is played upright, so the HUD keeps the size it had and the extra
## width becomes bars. So the assertion inverts rather than being skipped — "it
## did not rebuild" is the pass on touch, and a phone that quietly went back to
## reflowing would otherwise look exactly like a phone that was never tested.
func _rotate(spec: String) -> void:
	var parts := spec.split("x")
	if parts.size() != 2:
		fail("--rotate wants WxH")
		return

	var was_short := Layout.short()
	var was_compact := Layout.compact()
	var was_css := Layout.css_size
	var old_shop: Node = _scene.shop

	root.size = Vector2i(int(parts[0]), int(parts[1]))
	await _frames(12)

	print("  before: compact=%s short=%s css=%.0fx%.0f"
		% [str(was_compact), str(was_short), was_css.x, was_css.y])
	print("  after:  compact=%s short=%s css=%.0fx%.0f"
		% [str(Layout.compact()), str(Layout.short()),
			Layout.css_size.x, Layout.css_size.y])

	if Layout.touch():
		if Layout.css_size != was_css:
			fail("turning the phone changed the layout size from %.0fx%.0f to %.0fx%.0f"
				% [was_css.x, was_css.y, Layout.css_size.x, Layout.css_size.y])
		elif _scene.shop != old_shop:
			fail("turning the phone rebuilt the HUD; it is supposed to do nothing")
		return

	if Layout.short() == was_short and Layout.compact() == was_compact:
		fail("the layout did not change; pick a size on the other side of a breakpoint")
	elif _scene.shop == old_shop:
		fail("the layout changed but the HUD was not rebuilt")


## Rests a finger on something and photographs what opens.
##
## Real `InputEventScreenTouch`, not a synthetic mouse click, because that is the
## distinction the press-and-hold code makes: a mouse held still is a slow click
## and must not open anything.
func _press_and_hold(game: Node, what: String) -> void:
	var target: Control = null
	match what:
		"card":
			target = _scene.shop._cards[0]
		"bench":
			# A slot with nobody in it reports no hover, so there is nothing for
			# the hold to pin and nothing for SELL to sell. Seat a pirate the way
			# "item" hands itself loot, unless --bench already put one there.
			if game.bench[0] == null:
				_bench(game, PackedStringArray([_a_champion(game)]))
				await _frames(4)
			target = _scene.bench._slots[0]
		"item":
			for id in [&"blade", &"plate"]:
				game.give_item(id, &"salvage")
			await _frames(6)
			target = _scene.hold._grid.get_child(0)
		"trait":
			# The trait strip is empty until something is fielded, and the trait
			# inspector is the longest panel in the game now that it lists every
			# pirate carrying the trait — which makes it the one most likely to
			# run off the bottom of a phone.
			# Blackbeard Ashmore rather than any champion: his first badge is
			# Corsair, the widest trait in the game at nine carriers, so the
			# panel under test is the tallest one a player can open.
			if game.board.is_empty():
				_field(game, PackedStringArray(["ashmore"]))
				await _frames(4)
			var rows: Node = _scene.traits._rows
			if rows.get_child_count() == 0:
				fail("nothing was fielded, so no trait badge to hold")
				return
			target = rows.get_child(0)
		"chart":
			_scene.modals.open_forge_chart()
			await _frames(10)
			# The grid is the first child of the dialog's content after the
			# heading and the subtitle; a forged cell is past the header row.
			for node in _scene.modals._content.get_children():
				if node is GridContainer:
					target = node.get_child(node.columns + 2)
					break
		_:
			fail("unknown hold target '%s'" % what)
			return

	var at := target.global_position + target.size * 0.5
	var gold_before: int = game.player.gold

	_touch_down(at)

	# Long enough for Main's timer to elapse, with frames for the hover to land
	# and the inspector to lay itself out.
	await _frames(45)

	_touch_up(at)
	await _frames(6)

	print("  inspector pinned: %s" % str(_scene.tooltip.pinned))
	print("  gold %d -> %d (a hold must not buy)" % [gold_before, game.player.gold])
	if not _scene.tooltip.pinned:
		fail("press and hold did not pin the inspector")
	if game.player.gold != gold_before:
		fail("press and hold bought the card it was meant to describe")

	_check_inspector_fits()

	if what == "bench":
		await _check_sell_button(game)


## A pinned inspector that runs off the screen is one a phone cannot read and
## cannot close — its Close button is past the edge.
##
## Worth its own check because the panel's height is content: the trait
## inspector grew five lines when it started naming every carrier, and the
## longest of those is nine pirates over five costs.
func _check_inspector_fits() -> void:
	var tip: Control = _scene.tooltip
	# An inspector that never opened has a stale size and position, and measuring
	# those reports "it runs off the screen" on top of the real failure, which is
	# that the hold pinned nothing. `fail()` does not abort, so that one has
	# already been recorded by the time we get here.
	if not tip.visible:
		return
	var screen: Vector2 = tip.get_viewport_rect().size
	var rect := Rect2(tip.global_position, tip.size)
	print("  inspector %.0f x %.0f at %.0f, %.0f in %.0f x %.0f"
		% [rect.size.x, rect.size.y, rect.position.x, rect.position.y,
			screen.x, screen.y])
	if rect.position.x < -1.0 or rect.position.y < -1.0:
		fail("the inspector is off the top or left of the screen")
	elif rect.end.x > screen.x + 1.0 or rect.end.y > screen.y + 1.0:
		fail("the inspector runs off the screen by %.0f x %.0f"
			% [maxf(0.0, rect.end.x - screen.x), maxf(0.0, rect.end.y - screen.y)])


## Any champion, for a test that needs a body on the bench and does not care
## whose. The shop has already rolled, so its first card keeps this deterministic
## for a given seed rather than pinning the test to one hand-picked id.
func _a_champion(game: Node) -> String:
	for id in game.shop:
		if id != &"":
			return String(id)
	var all: Array = content().champions()
	return String(all[0].id)


## The SELL button is the only way to sell a pirate without a right mouse button,
## so it is worth proving it sells and not merely that it is drawn.
func _check_sell_button(game: Node) -> void:
	var benched: int = 0
	for u in game.bench:
		if u != null:
			benched += 1
	var gold_before: int = game.player.gold

	_scene.tooltip._sell_button.emit_signal("pressed")
	await _frames(4)

	var left: int = 0
	for u in game.bench:
		if u != null:
			left += 1
	print("  sold from the inspector: bench %d -> %d, gold %d -> %d"
		% [benched, left, gold_before, game.player.gold])
	if left != benched - 1:
		fail("the inspector's SELL button did not sell the pirate")
	if game.player.gold <= gold_before:
		fail("selling from the inspector paid nothing")
	if _scene.tooltip.visible:
		fail("the inspector stayed open after selling the pirate it described")


## Rests the cursor on a pirate mid-fight and checks the inspector keeps up.
##
## The board only reports a hover when the cursor *moves*, so a stat block read by
## holding still — which is how anyone reads one — used to be frozen at whatever
## was true when the cursor arrived. One motion event, then nothing: everything
## after this point has to come from the tooltip re-reading the unit itself.
##
## The damage is applied by hand rather than waited for. What is under test is
## whether a change in the unit reaches the panel, and letting the fight decide
## when someone gets hit makes that a coin toss on the frame count.
func _watch_a_fight(game: Node) -> void:
	game.start_combat_now()
	await _frames(20)

	var sim = game.sim
	if sim == null:
		fail("no fight to watch")
		return

	# Untyped on purpose: naming a class whose script mentions an autoload makes
	# this whole tool fail to compile. See tool_script.gd.
	var unit = null
	for u in sim.units:
		if u.team == 0 and u.alive:
			unit = u
			break
	if unit == null:
		fail("nobody of ours is in the fight — pass --units=")
		return

	var board = _scene.board
	var at: Vector2 = board.global_position + unit.pos * board.board_scale + board.board_offset
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(at)
	motion.global_position = _to_window(at)
	Input.parse_input_event(motion)
	await _frames(4)

	if not _scene.tooltip.visible:
		fail("hovering a pirate mid-fight opened no inspector")
		return
	var before: String = _scene.tooltip._body.text

	# The cursor does not move again from here.
	unit.hp = maxf(1.0, unit.hp - 30.0)
	await _frames(20)
	var after: String = _scene.tooltip._body.text

	print("  health %d, inspector says %s" % [roundi(unit.hp), _line_with(after, "Health")])
	if after == before:
		fail("the inspector froze: it still reads %s" % _line_with(before, "Health"))
	_capture()

	# And it closes itself when the pirate it describes is killed, which on a
	# touchscreen is the only way a pinned one ever finds out.
	unit.alive = false
	await _frames(20)
	print("  after the pirate died: inspector visible=%s" % str(_scene.tooltip.visible))
	if _scene.tooltip.visible:
		fail("the inspector stayed open over a dead pirate")


func _line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line.strip_edges()
	return "(no %s line)" % needle


## Starts a battle and photographs it a couple of seconds in, when the effects
## layer is busy.
func _run_a_fight(game: Node) -> void:
	game.start_combat_now()
	await _frames(int(arg("combat_frames", "150")))
	_capture()


## Sound, asserted by what came out rather than by what is on disk.
##
## `test_audio` can only check the bank: the suite is headless, so `Audio` builds
## no voices there and every cue is a no-op. That leaves the whole feed untested
## — the bus connections, `FxLayer` calling in, the throttle, the voice pool —
## and every one of those fails as silence, which is indistinguishable from a
## quiet moment. So this fights a round with the sound on and asks what played.
func _listen_to_a_fight(game: Node) -> void:
	if game.awaiting_start:
		fail("the run was still holding, so nothing would have fought")
		return

	# Fetched by node path, never named. `Audio` is an autoload, and an autoload
	# named in a `--script` target does not resolve at compile time — it fails the
	# whole tool to compile, and takes the script it was named in down with it.
	var sound := autoload("Audio")
	if sound == null:
		fail("no Audio")
		return

	# Mute is a saved player setting, so it is borrowed and put back rather than
	# left however this tool happened to leave it.
	var was_muted := bool(sound.muted)
	sound.set_muted(false)
	sound.plays = 0
	sound.cues_played.clear()

	if game.board.is_empty():
		_field(game, PackedStringArray(["pip", "grimscale", "ned"]))
		await _frames(2)

	game.start_combat_now()
	await _frames(int(arg("combat_frames", "220")))
	_capture()

	if int(sound.plays) == 0:
		fail("a whole round went by without a single sound")
		sound.set_muted(was_muted)
		return

	# A fight is the half fed by the renderer rather than by the bus, and it is
	# the half that can break without anything else noticing: the UI cues fire
	# from signals that other panels also listen to, where an attack sound has
	# only `FxLayer` behind it.
	var played: Dictionary = sound.cues_played
	var fight := 0
	for cue in played:
		if String(cue).begins_with("shot") or String(cue).begins_with("melee") 				or cue in [&"crit", &"death", &"cast", &"nova"]:
			fight += int(played[cue])
	if fight == 0:
		fail("the round made noise, but none of it came from the fight: %s"
			% str(played.keys()))
		sound.set_muted(was_muted)
		return

	print("  %d sounds, %d of them from the fight: %s"
		% [int(sound.plays), fight, str(played.keys())])

	# And the mute has to actually stop it, which is the one control the player
	# has over any of this.
	sound.set_muted(true)
	var before := int(sound.plays)
	sound.play(&"buy")
	if int(sound.plays) != before:
		fail("muted, and a cue played anyway")
	else:
		print("  muted: silent")
	sound.set_muted(was_muted)


## Buying a pirate with a tap, and the inspector that opened on the way in.
##
## The reported bug: on a phone the card's tooltip stayed up after the purchase,
## until a tap somewhere else. **A finger has no hover** — the emulated cursor
## stops wherever the tap landed, still inside the shop, so the un-hover that
## closes an inspector on a desktop never arrives.
##
## Both halves are asserted, and in this order, because either one alone passes
## for the wrong reason: an inspector that never opened is not a fix, and a tap
## that stopped buying is a worse bug than the one being fixed.
func _tap_to_buy(game: Node) -> void:
	game.player.gold = 50
	events().gold_changed.emit(game.player.gold, 0)
	await _frames(3)

	var before: int = game.player.gold
	var card: Control = _scene.shop._cards[1]
	var at := _centre_of(card)

	_hover_at(at)
	await _frames(3)
	_touch_down(at)
	await _frames(4)
	var opened: bool = _scene.tooltip.visible

	_touch_up(at)
	await _frames(8)

	if not opened:
		fail("the inspector never opened on the way into the tap, so this proves nothing")
		return
	if game.player.gold >= before:
		fail("the tap did not buy anything — gold is still %d" % before)
		return
	print("  tapped a card: gold %d -> %d, inspector opened" % [before, game.player.gold])

	if _scene.tooltip.visible:
		fail("the inspector is still up after buying — stuck until the next tap")
		return
	print("  and closed again when the finger came off")

	# The other half, and the one a purchase cannot fix for itself. Buying empties
	# the slot, so the inspector on a bought card closes because what it was
	# describing is gone — but a tap that buys *nothing* leaves the card exactly
	# where it was, and then only the finger coming off the glass can close it.
	game.player.gold = 0
	events().gold_changed.emit(0, 0)
	await _frames(3)

	var other: Control = _scene.shop._cards[2]
	var elsewhere := _centre_of(other)
	_hover_at(elsewhere)
	await _frames(3)
	_touch_down(elsewhere)
	await _frames(4)
	if not _scene.tooltip.visible:
		fail("the inspector did not open on a card the player cannot afford")
		return
	_touch_up(elsewhere)
	await _frames(8)

	if _scene.tooltip.visible:
		fail("a tap that bought nothing left the inspector up")
		return
	print("  a tap that could not afford anything closed it too")

	# And the desktop half of the same complaint, with no finger involved: the
	# cursor rests on a card and clicks it. Nothing here closes the inspector on
	# its own — the pointer has not moved and the card is still under it — so what
	# has to close it is the card itself being gone, which is the refresh the shop
	# handler is the only one that used to do without.
	game.player.gold = 50
	events().gold_changed.emit(50, 0)
	await _frames(3)

	var third: Control = _scene.shop._cards[3]
	var over := _centre_of(third)
	_hover_at(over)
	await _frames(4)
	if not _scene.tooltip.visible:
		fail("the inspector did not open under the cursor")
		return

	var gold_before: int = game.player.gold
	_click_at(over)
	await _frames(10)

	if game.player.gold >= gold_before:
		fail("the click did not buy anything")
		return
	if _scene.tooltip.visible:
		fail("the inspector stayed up over a card that has been bought — it is describing a slot that is now empty")
	else:
		print("  a mouse click on a card closed it as well")


## Puts the run on its weather round, with a named sea running.
##
## Set here rather than played into, because the weather round is 2-4 and
## reaching it honestly is twenty rounds of a run this tool has no reason to
## play. Announced through the bus exactly as `_begin_planning` would, so the
## HUD finds out the way it does in a real game rather than being poked.
func _set_sea(game: Node, id: StringName) -> void:
	var def: Variant = content().sea(id)
	var effect: Variant = content().sea_effect(id)
	if def == null or effect == null:
		fail("no sea '%s'" % id)
		return

	game.stage = 2
	game.round_number = game.SEA_ROUND
	game.sea_id = id
	game.sea_cells = effect.cells(def, game.rng)
	if not game.sea_active():
		fail("%s did not land on a round that is fought" % id)
		return
	events().round_began.emit(game.stage, game.round_number)
	events().sea_changed.emit(id, 0)


## The weather has to be visible, or it is a dice roll the player never saw.
##
## Both halves have failed silently in this project before, in other panels: a
## board that was never told, and a chip built fresh by a rebuild carrying its
## own defaults. Asserted on the board's own marks rather than on the pixels,
## because a mark drawn in the wrong colour is a look and a mark that is not
## there at all is a bug.
func _check_sea(game: Node) -> void:
	var def: Variant = content().sea(game.sea_id)

	if not _scene.top_bar.sea_shown():
		fail("the round is being fought in %s and the top bar says nothing" % def.id)
	elif not def.marks_cells:
		print("  %s named in the top bar; it marks no water" % def.id)

	if not def.marks_cells:
		return

	var marked: int = _scene.board.sea_cells.size()
	if marked != game.sea_cells.size():
		fail("%s touches %d hexes and the board marked %d"
			% [def.id, game.sea_cells.size(), marked])
		return
	print("  %s named in the top bar, %d hexes marked on the board"
		% [def.id, marked])


## The meter with no fight behind it. It has to say so in words and stay
## dismissable; an empty panel and a live CLOSE are the difference between "no
## data yet" and "the game has stopped responding".
func _check_empty_dps_meter() -> void:
	var meter: Node = null
	for node in _scene.modals._content.get_children():
		if node.has_method("row_count"):
			meter = node
	if meter == null:
		fail("the dialog opened without a meter in it")
		return
	if meter.row_count() != 0:
		fail("the meter invented %d rows with no fight to read" % meter.row_count())
	if not _scene.modals.is_open():
		fail("the meter closed itself instead of reporting an empty fight")

	var closable := false
	for node in _scene.modals._actions.get_children():
		if node is Button:
			closable = true
	if not closable:
		fail("the empty meter has no way out of it")
	else:
		print("  empty meter: 0 rows, dismissable")


## A DPS meter that renders perfectly and reports zero is the failure a
## screenshot cannot see. Both halves are checked: that the fight produced
## numbers, and that the panel actually built a row per combatant to show them
## in — a meter reading the right data into no widgets looks like an empty frame.
func _check_dps_meter(game: Node) -> void:
	var stats: Array = game.battle_stats()
	if stats.is_empty():
		fail("the meter opened with no fight to report")
		return

	var dealt := 0.0
	for row in stats:
		dealt += row["dealt"]
	if dealt <= 0.0:
		fail("a fight ran and the meter reports no damage dealt by anyone")

	# Found by the method it answers to, not by its class. Naming `DpsPanel` here
	# pulls it into this tool's compile graph, where the `GameState` global does
	# not resolve — which failed the class to compile for the whole run and left
	# the dialog genuinely empty. One of the headless traps in CLAUDE.md, arriving
	# through the assertion written to catch an empty meter.
	var meter: Node = null
	for node in _scene.modals._content.get_children():
		if node.has_method("row_count"):
			meter = node
	if meter == null:
		fail("the dialog opened without a meter in it")
		return

	var rows: int = meter.row_count()
	if rows != stats.size():
		fail("the meter shows %d rows for %d combatants" % [rows, stats.size()])

	print("  meter: %d rows, %d damage dealt over %.1fs"
		% [rows, roundi(dealt), game.battle_duration()])

	# Every tab, not just the one that happens to open first. Two of the three are
	# a click away and would otherwise never be rendered by anything.
	for key in [&"dealt", &"taken", &"healed"]:
		var total := 0.0
		for row in stats:
			total += row[key]
		meter.show_tab(key)
		await _frames(2)
		print("  tab %-7s total %d" % [key, roundi(total)])

	var taken := 0.0
	for row in stats:
		taken += row[&"taken"]
	# Damage that was dealt was taken by somebody. A taken tab reading zero after
	# a fight means the counter is not wired, not that nobody got hit.
	if dealt > 0.0 and taken <= 0.0:
		fail("%d damage was dealt and the taken tab reports none of it"
			% roundi(dealt))

	# Left on whichever tab was asked for, so the shot is of that one.
	meter.show_tab(StringName(arg("tab", "dealt")))
	await _frames(2)


## The opening screen: the almanac up, the run holding its clock behind it.
##
## Both halves are asserted because both are invisible in the shot. A briefing
## over a clock that is already counting looks exactly like one over a clock that
## is not, and `HOLD` on the shop's clock is the only thing on screen that says
## which — so if that word is missing, the shot is of a game quietly eating the
## player's first planning phase while they read.
func _briefing(game: Node) -> void:
	await _frames(4)

	if not _scene.wiki.is_open():
		fail("a new run did not open the briefing")
	if not game.awaiting_start:
		fail("the briefing was up but the run's clock was already running")

	var clock: String = _scene.shop._timer_label.text
	if clock != "HOLD":
		fail("the shop clock says '%s' behind the briefing, not HOLD" % clock)
	print("  briefing up, clock says %s" % clock)

	# Photographed here, with the almanac still up: this is the shot. Closing it
	# below is the assertion, and a capture after it is a picture of the ordinary
	# opening board with nothing to show.
	_capture()

	# And it lets go when the almanac does. This is the whole point of the screen.
	_scene.wiki.close()
	await _frames(2)
	if game.awaiting_start:
		fail("closing the briefing left the run holding at the line")
	print("  closing it started the run")


## The almanac opens on the first run and would otherwise be in every shot.
func _close_modals() -> void:
	if _scene == null:
		return
	if _scene.get("modals") != null:
		_scene.modals.close()
	if _scene.get("wiki") != null:
		_scene.wiki.close()


## Fast-forwards the real round loop until the armoury opens itself.
func _play_to_the_armoury(game: Node) -> void:
	game.instant = true
	game.speed = 64
	for i in 3000:
		if game.phase == game.Phase.ARMOURY:
			return
		if game.phase == game.Phase.PLAN:
			game.start_combat_now()
		elif game.phase == game.Phase.OVER:
			break
		await process_frame
	fail("the run never reached an armoury")


func _frames(count: int) -> void:
	for i in count:
		await process_frame     # this script IS the SceneTree; the signal is ours


func _capture() -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(_out)
	if error != OK:
		fail("could not write %s (error %d)" % [_out, error])
	else:
		print("  wrote %s" % ProjectSettings.globalize_path(_out))


## Opens one of the dialogs directly, so a screenshot can prove it renders.
func _open_modal(which: String, game: Node) -> void:
	if _scene == null:
		return
	match which:
		"forge":
			# Hold a few components so the chart has something to mark as makeable.
			for id in [&"blade", &"plate", &"lens"]:
				game.give_item(id, &"salvage")
			_scene.modals.open_forge_chart()
		"armoury":
			# Played to, not injected. Handing the modal a made-up offer is how a
			# screenshot of a working armoury coexisted with an armoury that
			# opened empty in the actual game for a whole stage.
			await _play_to_the_armoury(game)
		"help", "wiki":
			# --wiki= names the section, because the almanac is five different
			# pages in one dialog and a shot of the first one proves the least.
			var section := arg("wiki", "guide")
			_scene.wiki.open(StringName(section), StringName(arg("entry", "")))
		"dps":
			if arg("fight", "yes") == "no":
				# Opened before the first fight of a run. The armoury shipped in
				# exactly this shape once — a dialog with a title, nothing in it,
				# and no way past it — and the run stopped there every time.
				_scene.modals.open_dps()
				await _frames(3)
				_check_empty_dps_meter()
				return

			# Measured off a real fight rather than an injected one. A meter is
			# exactly the kind of panel that photographs beautifully while
			# reporting nothing, so this plays a round and then asserts.
			if game.board.is_empty():
				_field(game, PackedStringArray(["barnaby", "lyra", "coral"]))
			# Regeneration on the front-liner, so the healing tab has real numbers
			# in it. A healer's *ability* needs mana and the opening wave dies in
			# two seconds, so relying on one left that tab a column of zeroes —
			# indistinguishable from the tab being broken.
			for unit in game.board:
				if unit.can_take_item():
					unit.items.append(&"hull_of_the_deep")
					break
			game.start_combat_now()
			await _frames(int(arg("combat_frames", "150")))
			_scene.modals.open_dps()
			await _frames(3)
			await _check_dps_meter(game)
		"fleet":
			# The compact layout's bottom sheet. Nothing on a desktop.
			_scene._toggle_sheet(true)
		_:
			fail("unknown modal '%s'" % which)
