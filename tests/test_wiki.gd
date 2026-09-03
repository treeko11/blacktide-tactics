extends TestCase

## The almanac has to stay complete, and its cross-links have to keep landing.
##
## Both are failures that look like nothing. A champion added to `data/` and
## never listed is a champion the reference silently does not know about; a link
## to an id that was renamed is a tap that does nothing at all. Neither throws,
## neither shows up in a screenshot, and both are exactly the rot a wiki
## accumulates.
##
## So this walks every section, renders every page, and follows every `[url]` in
## every one of them. It works on a bare `Wiki.new()` rather than on one in the
## HUD: `entries` and `page_for` are public for this, and nothing they do needs a
## scene tree, which keeps the check away from anything to do with layout.

const LINK := "\\[url=([a-z]+)/([a-z_]*)\\]"

var _wiki: Wiki = null


func before_each() -> void:
	_wiki = Wiki.new()


func after_each() -> void:
	# Never entered the tree, so nothing frees it for us.
	_wiki.free()
	_wiki = null


func test_every_champion_trait_and_item_is_listed() -> void:
	var listed: Dictionary = {}
	for section in Wiki.SECTIONS:
		for row in _wiki.entries(section["id"]):
			listed["%s/%s" % [section["id"], row["id"]]] = true

	for champion in content().champions():
		var section := "monsters" if champion.cost == 0 else "pirates"
		assert_true(listed.has("%s/%s" % [section, champion.id]),
			"the almanac does not list %s" % champion.id)

	for trait_def in content().traits():
		assert_true(listed.has("traits/%s" % trait_def.id),
			"the almanac does not list the %s trait" % trait_def.id)

	for item in content().components() + content().forged_items():
		assert_true(listed.has("items/%s" % item.id),
			"the almanac does not list the item %s" % item.id)


func test_every_entry_has_a_page() -> void:
	for section in Wiki.SECTIONS:
		var rows: Array = _wiki.entries(section["id"])
		assert_gt(rows.size(), 0, "section '%s' is empty" % section["id"])
		for row in rows:
			var page: String = _wiki.page_for(section["id"], row["id"])
			# 80 characters, not "not empty": a page that lost its body to a
			# renamed id still has a title, and a title is not a page.
			assert_gt(page.length(), 80,
				"%s/%s renders %d characters" % [section["id"], row["id"], page.length()])
			assert_true(page.contains(row["title"]),
				"%s/%s does not name itself" % [section["id"], row["id"]])


## Every cross-link in every page points at a section that exists and, unless it
## opens a whole section, at an entry that is in it.
func test_every_link_lands_somewhere() -> void:
	var expression := RegEx.new()
	assert_eq(expression.compile(LINK), OK, "the link pattern does not compile")

	var followed := 0
	for section in Wiki.SECTIONS:
		for row in _wiki.entries(section["id"]):
			var page: String = _wiki.page_for(section["id"], row["id"])
			for found in expression.search_all(page):
				followed += 1
				var target := StringName(found.get_string(1))
				var entry := StringName(found.get_string(2))
				var where := "%s/%s links to %s/%s" % [
					section["id"], row["id"], target, entry]
				var targets: Array = _wiki.entries(target)
				assert_gt(targets.size(), 0, "%s, which is not a section" % where)
				if entry == &"":
					continue
				var hit := false
				for candidate in targets:
					if candidate["id"] == entry:
						hit = true
						break
				assert_true(hit, "%s, which is not in it" % where)

	assert_gt(followed, 40, "found only %d links — is the almanac still linked up?"
		% followed)


## A pirate's page is the one place all three stars are shown at once, which is
## the reason it exists rather than reusing the tooltip's.
func test_a_pirate_page_shows_every_star() -> void:
	var champion: ChampionDef = content().champions_of_cost(1)[0]
	var page: String = _wiki.page_for(&"pirates", champion.id)
	for star in [1, 2, 3]:
		var health := int(champion.stats_at(star)["max_hp"])
		assert_true(page.contains(str(health)),
			"%s's page does not show its %d-star health of %d"
				% [champion.id, star, health])
	assert_true(page.contains(str(content().pool_size(champion.cost))),
		"%s's page does not say how many are in the pool" % champion.id)


## Every wave in the game, not only the one being played. The page reads them
## through GameState, which had to be taught to answer for a stage other than
## the current one.
func test_the_wave_table_covers_the_whole_run() -> void:
	var page: String = _wiki.page_for(&"monsters", &"waves")
	for stage in range(1, Wiki.WAVE_STAGES + 1):
		assert_true(page.contains(state().creep_wave_name(stage)),
			"the wave table omits stage %d" % stage)
	# The opening round is the one that has to be beatable by a single pirate,
	# so it is listed separately from the rest of stage 1.
	assert_true(page.contains("1-1"), "the wave table does not break out round 1-1")
	assert_eq(state().stage, 1, "reading the wave table moved the run")


## Asking for something that is not there is a blank page, never a crash.
func test_an_unknown_page_is_empty() -> void:
	assert_eq(_wiki.page_for(&"pirates", &"nobody"), "")
	assert_eq(_wiki.page_for(&"nowhere", &"nothing"), "")
	assert_eq(_wiki.entries(&"nowhere").size(), 0)


## A champion's entry is headed by its figure; a trait's and an item's are not.
##
## The only test here that needs the almanac actually built, because the portrait
## is a node beside the page rather than anything in the page text — every other
## check in this file reads `page_for`, and a champion whose figure never appears
## still returns a complete, correct page from it.
func test_a_champion_entry_is_headed_by_its_figure() -> void:
	var wiki := Wiki.new()
	Engine.get_main_loop().root.add_child(wiki)

	wiki.open(&"pirates")
	wiki._open_entry(&"pirates", &"sirene")
	assert_true(wiki._page_portrait.visible, "a pirate's entry drew no figure")
	assert_eq(wiki._page_portrait.champion.id, &"sirene",
		"the entry is headed by the wrong pirate")

	wiki._open_entry(&"traits", &"siren")
	assert_false(wiki._page_portrait.visible, "a trait's entry drew a pirate")

	wiki._open_entry(&"monsters", &"waves")
	assert_false(wiki._page_portrait.visible,
		"the wave list drew a pirate — there is no one champion it is about")

	wiki._open_entry(&"monsters", &"kraken")
	assert_true(wiki._page_portrait.visible, "a monster's entry drew no figure")

	wiki.free()
## Scrolling the list does not open whatever the thumb was resting on.
##
## Every row is a Button acting on release, and a finger that has just dragged
## the list is still on the row it started from — so before this, scrolling a
## phone's list of fifty-one pirates opened an entry every time. The rows and the
## page's cross-links both come through `_open_entry`, which is where the gesture
## is asked about.
func test_scrolling_the_list_does_not_open_an_entry() -> void:
	var wiki := Wiki.new()
	Engine.get_main_loop().root.add_child(wiki)
	wiki.open(&"pirates")
	wiki._open_entry(&"pirates", &"sirene")

	var scroll: ScrollContainer = wiki._list.get_parent()
	var driver: TouchScroll = scroll.get_node("TouchScroll")
	assert_not_null(driver, "the almanac's list cannot be dragged at all")

	# The sort that sizes the scrollbar is deferred and the runner has no frame
	# to give it; a fifty-one row list would have said this much.
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(200, 300)
	var bar := scroll.get_v_scroll_bar()
	bar.visible = true
	bar.max_value = 1400.0
	bar.page = 300.0

	var at := Vector2(120, 200)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = at
	driver._input(down)

	var swipe := InputEventScreenDrag.new()
	swipe.index = 0
	swipe.position = at + Vector2(0, -60)
	swipe.relative = Vector2(0, -60)
	driver._input(swipe)
	assert_gt(scroll.scroll_vertical, 0, "the swipe did not scroll the list")

	# What a row's press does when the finger comes off.
	wiki._open_entry(&"pirates", &"barnaby")
	assert_eq(wiki._entry, &"sirene", "the scroll opened the row it started on")

	# The verdict on a gesture is one flag for the whole game, so the finger is
	# put down again to clear it rather than left standing for the next test.
	driver._input(down)
	assert_false(TouchScroll.dragged(), "the gesture outlived the test")

	wiki.free()


## The almanac has to fit inside the screen it is opened on.
##
## It sized its box at 88% of `Layout.css_size`, which is the window in CSS
## pixels and not the space the dialog is laid out in: the wide layout keeps the
## 1600x900 design and stretches it, so that space is 900 units tall on every
## monitor. A 1920x1040 window therefore asked for 915 units of it and a
## 2560x1400 one for 1232 — and a `CenterContainer` given a child taller than
## itself pins it to the top, so the whole overflow hung off the bottom of the
## screen. The almanac is the first thing a new run opens, so on a large monitor
## that was the first thing the game ever showed.
##
## The lie told here is the same one a big monitor tells: `css_size` reports a
## screen half again larger than the space the dialog actually has.
func test_the_box_fits_the_screen_it_is_opened_on() -> void:
	var was := Layout.css_size
	var room: Vector2 = Engine.get_main_loop().root.get_visible_rect().size
	Layout.css_size = room * 1.6

	var wiki := Wiki.new()
	Engine.get_main_loop().root.add_child(wiki)
	wiki.open(&"guide", &"loop")

	var box: Vector2 = wiki._box.custom_minimum_size
	assert_lt(box.y, wiki.size.y, "the almanac is taller than the screen (%s in %s)"
		% [str(box), str(wiki.size)])
	assert_lt(box.x, wiki.size.x, "the almanac is wider than the screen (%s in %s)"
		% [str(box), str(wiki.size)])
	# Not just "it fits": a box that shrank to nothing would also fit.
	assert_gt(box.y, wiki.size.y * 0.5, "the almanac gave up most of the screen")

	wiki.free()
	Layout.css_size = was


## A window resized without crossing a layout breakpoint still resizes the box.
##
## Main rebuilds the HUD when the layout mode changes and not otherwise, so a
## desktop window dragged from 1280x720 to full screen never rebuilds anything —
## and a box sized once, when it was built, keeps the size the small window gave
## it. It is the full rect, so the resize notification is the signal.
func test_a_resize_refits_the_box() -> void:
	var wiki := Wiki.new()
	Engine.get_main_loop().root.add_child(wiki)
	wiki.open(&"guide", &"loop")

	var before: float = wiki._box.custom_minimum_size.y
	# Off the anchors for the duration: the runner has one window and the rest of
	# the suite is using it, and what is being checked is that the box follows the
	# rect it is centred in rather than a number taken once at build time.
	wiki.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	wiki.size = Vector2(700, 400)
	assert_lt(wiki._box.custom_minimum_size.y, before,
		"the box kept the height a bigger window gave it")
	assert_lt(wiki._box.custom_minimum_size.y, 400.0,
		"the box is taller than the room it was resized into")

	wiki.free()
