# Blacktide Tactics

A pirate-themed auto battler. Godot 4.7.2 stable, GDScript.

Eight captains, one shared champion pool. Buy pirates, position them on a hex
board, and the fight resolves itself. Ported from a vanilla-JavaScript build that
is now **retired** — see **The retired JavaScript build** below.

## Environment

The Godot binary is **not on PATH**. On Sam's machine it is at:

```
F:\Users\Sam\Downloads\Godot_v4.7.2-stable_win64.exe
```

`Test.bat`, `Play.bat` and `Edit.bat` in the project root find it, or read a
`GODOT_BIN` environment variable. A session running anywhere else — a container,
a remote agent, CI — **has no engine and can verify nothing**. There, prefer work
that needs no engine, and say plainly in the commit message that code is
**unverified**. Never describe untested code as working.

| Tool | What it is for |
|---|---|
| `run_tests.gd` | The suite. `Test.bat`, or `--script res://tools/run_tests.gd` |
| `playthrough.gd` | Plays a whole run through the real round loop; fails on a stall |
| `screenshot.gd` | Renders a PNG. Must run **without** `--headless`. Also the only check of the phone layout, of touch, and of sound: `--size=`, `--measure`, `--rotate=`, `--hold=card\|bench\|item\|chart`, `--sequence=buy\|forge\|item\|almanac`, `--live`, `--modal=dps`, `--briefing`, `--sfx`, all of which assert |
| `soak.gd` | Plays 40+ rounds with the **real HUD** up, reporting objects, nodes, memory and the worst frame of every round. Runs either way; `--headless` is faster and still builds the whole HUD. The only thing watching for a frame that never ends |
| `creep_balance.gd` | Win rate against every monster wave, per stage and round |
| `art_sheet.gd` | Draws **every champion**, or every body in every animation state (`--poses`). Must run **without** `--headless`. The only check that a polygon still triangulates |
| `assign_art.gd` | Stamps `ArtTable` into `data/champions/*.tres`. Idempotent, and preserves balance where `generate_content.gd` would not |
| `crop.gd` | Magnifies a region of a PNG, nearest-neighbour, for looking at the art |
| `generate_content.gd` | One-time bootstrap that writes `data/*.tres`. See below |

All extend `tools/tool_script.gd`. **Write new tools by extending it** — it
carries the two headless traps below so no tool has to rediscover them.

**Run `screenshot.gd`'s assertions at every layout, not just one.** The three
that matter are `--size=390x844` (phone upright), `--size=844x390` (sideways) and
`--size=1600x900` (desktop); they build genuinely different HUDs. The toast
blocking input on the cargo hold was live in all three, and passed unnoticed
because `--hold=item` had only ever been run upright, where the toast happens to
cover nothing.

### Headless gotchas, each learned the hard way

- A `--script` target must `extends SceneTree`. `await process_frame` waits a
  frame — `root.process_frame` does not exist, `root` is a Window.
- **Autoload `_ready()` has not run during `_initialize()`.** It is deferred to
  the first frame, so a tool doing its work there sees empty singletons.
- **Autoload globals do not resolve at compile time in a `--script` target.**
  Naming `Content` or `GameState` in a tool, or in anything a tool depends on,
  fails the whole script to compile. `tool_script.gd` and `tests/test_case.gd`
  fetch them by node path at runtime and **must never name one directly**; test
  *files* are loaded later and can name them normally.
  **"Anything it depends on" includes a UI class named for a type check.** Every
  panel in `scripts/ui/` names an autoload, which is fine because they load at
  runtime with the scene — but `var x: DpsPanel` or `node is DpsPanel` in a tool
  drags that file into the tool's compile graph and fails it there, which then
  fails *the class itself* for the whole run. `screenshot.gd` finds the meter by
  `has_method("row_count")` for exactly this reason. The symptom is a dialog that
  opens genuinely empty, so an assertion written to catch an empty panel is what
  catches it.
- **GDScript lambdas capture by value.** Assigning to a captured local from
  inside a handler silently does nothing. Use `TestCase.probe()` for signals, and
  `unit.scratch` (a Dictionary, a reference) for anything an item or trait hook
  needs to remember between calls. Every stacking effect in the game works that
  way for this reason.
- **`content()` and `state()` return `Node`, so anything they return is a
  Variant.** `var x := content().forge(a, b)` will not compile: type it
  explicitly, `var x: StringName = ...`.
- **Keep the Godot editor closed** while files are edited externally, or expect
  stale caches.

## Working agreements

- **Claude writes the code; explain it as you go, not afterwards.** Sam is an
  escalated support SME in a PHP/Laravel/SQL stack with a basic grasp of code —
  he follows intent and output from context but is not a fluent reader.
- **Ask before building, not after.** A fork that changes what gets built and is
  not settled by these docs is a question, not a default reported later.
- **Run routine commands freely** — reads, tests, builds, commits, pushes.
- **Refactor freely.** Sam would rather existing code be reshaped than worked
  around.
- **Sam does not touch git or GitHub at all.** Branches, PRs and cleanup are
  Claude's job start to finish. On his machine, commit and push straight to
  `main` as work lands.
- **Keep commit messages short** — subject, then a few lines of what and why.

## Architecture rules (non-negotiable — each is a rewrite if broken)

1. **The sim is a fixed tick.** `Sim.step()` advances exactly 1/30s and nothing
   else moves the clock. Frame rate and the speed multiplier decide *how many*
   steps happen, never how big one is, so a fight at 4x resolves identically to
   the same fight at 1x, and a headless fight resolves identically to a watched
   one.
2. **Rendering is downstream of simulation, always.** The sim never touches the
   scene tree; it pushes dictionaries onto `fx_queue` and the renderer drains
   them. Seven fights resolve every round and six are never seen — those cost
   nothing because `Sim.render` is false and `fx()` returns immediately.
3. **Content is Resources.** `ChampionDef`, `TraitDef`, `ItemDef` as `.tres`.
   Balance is a file edit, not a code change.
4. **Three things are added by adding a file**: a champion ability, a trait
   effect, an item effect. `Content` scans the folder through `ScriptDir` and
   keys each by the `id()` it reports. Nothing enumerates them, because a
   hand-maintained register of 44 abilities is what goes stale first.
5. **Cross-system communication goes through the `Events` bus.** The shop does
   not know the HUD exists.
6. **Main is the only place that mutates GameState.** Panels report what the
   player did; Main turns that into a call. One path from a click to a change.

**A unit in a fight is a RefCounted, not a Node** — deliberately unlike
Incrementile's "never Nodes" rule, which exists for factory-scale entity counts.
Eighteen units per fight is not that, and readable code wins.

## Layout

```
data/champions/, traits/, items/   authored .tres definitions
audio/                             CC0 sound files + CREDITS.md
scripts/autoload/                  Events, Content, GameState, Audio
scripts/core/                      Hex, Sim, SimUnit, Captain, Bot, RosterUnit,
                                   the three *Def resources, ScriptDir, and the
                                   three extension-point base classes
scripts/core/abilities/            one file per champion (44)
scripts/core/traits/               one file per trait (13)
scripts/core/items/                one file per item (20)
scripts/ui/                        UITheme, Layout, BoardView, UnitView,
                                   UnitArt, UnitPortrait, Ocean, FxLayer,
                                   ShopBar, BenchBar, SidePanels, TopBar,
                                   Tooltip, ToastLayer, Modals, Wiki, DpsPanel
shaders/                           ocean.gdshader
scripts/game/main.gd               assembles the HUD and wires it to GameState
scripts/dev/                       DEV BUILD ONLY - the log and the dev menu
scenes/main.tscn                   a bare Control; the HUD is built in code
tests/                             test_*.gd, discovered automatically
tools/                             entry points, all extending tool_script.gd
js/, css/, index.html              the original JavaScript build (see below)
```

**There are two HUDs.** `Layout` picks one from the window width in CSS pixels:
the wide one with a column either side of the board, and a compact one for a
phone. They are different arrangements of the same panels, not one arrangement
at two sizes, so crossing a breakpoint **rebuilds** the HUD rather than resizing
it — safe because every piece of state lives in GameState. Each panel reads
`Layout.compact()` and `Layout.short()` when it builds itself.

The HUD is **built in code, not in a .tscn**. The layout is almost entirely
containers and generated rows; a scene file full of nodes nobody positions by
hand is harder to review and change than the code that would have built it.

## Rules

Each of these cost a debugging session or settles a design argument.

### The simulation

- **A unit's cell is committed the moment a move starts**, not when the slide
  finishes. Leaving `cell` on the origin meant a unit was registered in the
  occupancy map at its destination while still reporting the cell it came from —
  and `kill()` erases occupancy by `cell`, so a unit that died mid-step freed
  whichever cell it had left (evicting whoever moved in) and left its own
  destination blocked by a corpse for the rest of the fight. Ported straight from
  the JavaScript, found by `test_two_units_never_share_a_cell`.
- **`add_buff` does not clamp.** The attack-speed cap is applied where attack
  speed is *used*, so removing a buff restores the original value exactly.
  Clamping on the way in loses the difference and leaves the unit permanently
  slower than it started.
- **The six unwatched fights are stepped alongside the one that is watched, not
  resolved in a burst.** `run_to_end()` on all of them at the end of a round is up
  to 7,600 ticks in a single frame: by stage 5 that measured a third of a second
  of a still window on the desktop, and several times that in a browser, on the
  frame the player is waiting for their own result. `_open_bot_fights` builds them
  when the player's fight starts, `_step_bot_fights` gives each
  `UNWATCHED_STEPS_PER_FRAME` ticks a frame while the player watches theirs, and
  `_close_bot_fights` reads the results, finishing anything a short fight left
  half-run. Nothing about the outcomes changes — the same pairings, the same seeds
  drawn in the same order — only when the work happens. `soak.gd` reports the
  worst frame of every round, which is how that is kept honest.
- **`Sim.dispose()` must be called on a finished fight.** A battle builds
  reference cycles — `target` points at another unit, every hook is a lambda that
  captured its unit, every pending delayed call captured the caster — and
  RefCounted has no cycle collector. Seven fights a round is a real leak.
  `TestCase.battle()` disposes automatically.
- **`enemies_near` is relative to the caster; `enemies_near_cell` takes a team.**
  An ability splashing around its *target* wants the caster's enemies, and the
  target's enemies are your own fleet. Getting this backwards turns a nuke into
  friendly fire and the tests will not catch it — the board still changes.
- **Traits count distinct champions, not bodies.** Three copies of one pirate is
  a star-up, never a trait. This is the rule the whole comp-building game rests
  on.
- **Opponent boards are mirrored** onto the top half. A test fixture that seats
  both sides at row 6 puts them six hexes apart, and every proximity ability then
  legitimately finds nothing.

### Presentation

- **Every attack style is a different shape, and all of them are directional.**
  In the JavaScript build every ranged attack was one thin line and every melee
  attack one expanding ring; a fight was unreadable. `Sim.ATTACK_STYLES` names a
  style per archetype and `FxLayer` draws it. None of it touches a number.
- **Projectiles are slower than realistic (700 px/s) and follow their target.**
  At a realistic speed a shot crossed two hexes in five frames and only the
  impact registered, which defeats the point. Damage lands when the shot is
  fired, so the projectile is catch-up — one that arrives where the target used
  to be standing reads as a miss that somehow still hurt.
- **`FxLayer` is one node that draws every effect.** A node per hit meant
  hundreds of allocations a second at 4x for things living a fifth of a second.
- **A phase is announced after the state it needs exists.** `_open_armoury`
  emitted `phase_changed` and *then* filled `armoury_offer`, so Main opened the
  armoury on the array the previous stage's pickup had cleared: a modal with a
  title, no items, and no way to dismiss it. The run stopped there every time.
  `_start_combat` had it right — build the sim, announce COMBAT last.
- **A run holds at the line until the player says go.** The opening planning
  phase used to start its 32-second clock behind the almanac Main opens over it,
  so a new player's first round was spent reading the rules while the shop closed
  on them. `GameState.awaiting_start` freezes `_tick_planning` until the almanac
  is closed (`Main._on_wiki_visibility`) or SET SAIL is pressed — `start_combat_now`
  releases it too, or the button would zero a clock that is not running. Only the
  *first* planning phase waits: the almanac opened mid-round is a reference, not a
  timeout. `instant` runs are never held, which is the whole reason `playthrough.gd`
  and `creep_balance.gd` do not stall on 1-1, and the shop clock reads `HOLD`
  rather than a frozen `32`, which reads as broken.
- **The phone layout is measured in CSS pixels, and the wide one is not.** The
  project ships a 1600x900 design stretched with `canvas_items` + `expand`. On a
  375-point phone that resolves to a 0.23x scale and a 1600x3466 viewport: a
  microscopic HUD in a column of dead space. No uniform scale fixes it — 12px at
  0.23x is three pixels. So `Layout` sets `content_scale_size` to the window *in
  CSS pixels* when compact, which makes one game unit one CSS pixel and the
  breakpoints readable against `css/main.css`. Godot's window size on the web is
  in **device** pixels, so the ratio comes from `window.devicePixelRatio` through
  `JavaScriptBridge`; without it a phone looks like a 1125-pixel tablet.
- **On a phone the board has to win the space fight, and it loses by default.**
  It is the one panel that takes what is left over, and the first compact layout
  left it 24% of the screen at a scale of 0.30 — a 21-point hex, which is not a
  target a thumb can hit. The cause was the shop taking 39%: five cards wrapped
  to two rows, and each card put the name between the icon and the price, so
  "Old Anchor Ned" wrapped into four stacked fragments and made the card 150
  points tall. One row of five, with the name on its own line under the icon,
  took the shop to 24% and the board to 46% at a 43-point hex. `screenshot.gd
  --measure` prints the height of every block; **decide this with numbers**, not
  by squinting at a screenshot.
- **Sideways is a different shape, not a tighter one.** Stacking the portrait
  arrangement on a 390-point-tall landscape phone left the board 94 points —
  less than the board is tall, so it was drawn at the scale floor and *clipped*,
  with the back rows unreachable. A landscape phone is a wide short screen,
  which is what the desktop layout is for, so it gets two columns: board on the
  left, everything else in a narrow column on the right. That column is narrow,
  so the shop and bench inside it use the *portrait* arrangement — the screen
  being wide says nothing about the column.
- **The window size is polled, not watched.** `Window.size_changed` does not fire
  when a browser canvas resizes, so a phone turned sideways kept its portrait
  layout stretched across a landscape window. A Vector2i compare once a frame is
  cheaper than being wrong on the platform the layout exists for. And **both**
  breakpoints trigger the rebuild: portrait and short-landscape are both
  "compact", and watching only WIDE/COMPACT missed the rotation entirely.
- **A rebuild re-wires the panels, never the bus.** Freeing a node disconnects
  its signals for you, which is what makes throwing the HUD away safe — but Main
  itself is *not* freed, and neither is the `Events` autoload, so anything
  connecting the two survives. Re-running that wiring stacked a second copy on
  every rotation: Godot refused the method connections with an error, and
  silently accepted the lambdas, which then ran once per rotation the player had
  ever made. `Main._connect_panels` runs per build; `Main._connect_bus` runs once.
  `screenshot.gd --rotate=` catches it, because the errors print.
- **Anything the HUD shows but GameState owns has to be read back on a rebuild.**
  The new panel starts at its own defaults, and those are a lie the moment the
  run is not in its opening state: the speed buttons came back claiming 1× while
  the fight ran at 4×, the shop lock came back open while the shop was locked,
  and the round clock came back foam with six seconds left. State that is only
  ever pushed by a signal is the trap — the signal already fired, at a panel that
  no longer exists.
- **`queue_free()` does not remove the node, and a loop that waits for it never
  ends.** A queued child is still a child for the rest of the frame: still
  counted by `get_child_count()`, still holding its index, still drawn. The fleet
  panel trimmed its log with `while get_child_count() > 40: get_child(...).queue_free()`,
  and on the forty-first line — a few rounds into every run, on every device —
  the game locked solid at 100% of a core, pushing the same node onto the delete
  queue millions of times a second until memory ran out. No error, no crash, just
  a window that stopped. **Use `UITheme.clear_children` and
  `UITheme.trim_children`**: both detach before freeing, and `trim_children`
  counts the surplus *once* so the loop bound can never depend on the thing being
  deferred. The same "counting the corpses" trap is why `DpsPanel._clear_rows`
  detaches, and why a panel that clears and refills in one call must too.
- **`mouse_filter` is per node, so an overlay is only as transparent as its
  children.** `Container` defaults to STOP where `Label` defaults to IGNORE, so
  setting IGNORE on a toast's panel left the two boxes inside it hit-testable:
  every toast became an invisible five-second blocker over whatever it covered.
  On a sideways phone that was the cargo hold, and press-and-hold stopped opening
  the inspector; on a desktop it was the right of the board, and a pirate could
  not be dropped there for five seconds after any pickup. Both read as the game
  ignoring you — the thing the toast exists to prevent. `test_hud.gd` walks the
  layer and fails anything not IGNORE.
- **Never change a Control's `mouse_filter` while a press is live.** A pinned
  inspector has to swallow taps on its own body, but press-and-hold opens it with
  the finger still down. Setting `mouse_filter` to STOP there left Godot's GUI
  press/release bookkeeping unbalanced: the release went elsewhere, and from then
  on every tap arrived one event behind — a press with no release, then a release
  with no press. Buying happens on release, so **the shop looked completely
  dead** after inspecting anything. `Tooltip.arm_input()` waits a frame first,
  because `_input` still runs *before* the viewport hands the emulated mouse
  release to the GUI. And `hide_now()` resets **both** filters: leaving the inner
  column on PASS meant the next hover put an invisible-looking but very
  hit-testable panel over the shop, and the card underneath never saw the tap.
  `screenshot.gd --sequence=forge` and `--sequence=item` replay both.
- **The web export cannot draw `●`, `★`, `→` or a non-breaking hyphen.** There are no
  system fonts in a WASM sandbox, Godot's bundled fallback covers little beyond
  Latin-1, and the only font this project ships is Noto Color Emoji — which has
  neither, because neither is an emoji. Every price and star rating rendered as a
  tofu box in the browser. `UITheme.COIN` and `UITheme.STAR` are now the emoji
  that mean the same thing, `»` replaced the arrow in the forge lists, and
  `game_theme()` puts the emoji font behind the text font so they resolve in
  ordinary labels and in BBCode. `test_glyphs.gd` now asks the two fonts about
  every character in the scripts and the .tres, so a symbol Windows would have
  hidden fails the suite instead of the export. Confirmed to render: Latin-1,
  `× · • ° « »`, en and em dashes, and anything Noto Color Emoji covers —
  including the Dingbats that are emoji, such as `✔`. Confirmed missing:
  Geometric Shapes, and the arrows and dashes outside Latin-1.
- **The almanac is the reference, and it is not the tooltip.** `Wiki` answers
  "what exists and what would it do" — all three stars of a pirate at once, every
  breakpoint of a trait, every wave of the run — where the floating inspector
  answers "what is this thing in front of me, right now". They are different
  pages, so `Wiki` builds its own rather than borrowing `Tooltip`'s; what they
  share is the Defs, which stay the only copy of the numbers. **How to Sail
  lives in it**, as seven topic pages rather than one dialog: a rules screen
  that only ever opened at the start of a run was a rules screen nobody could
  get back to, so the almanac is one button and `Modals` no longer has a help
  dialog at all.
- **The almanac picks its shape from the width, not from `Layout.compact()`.**
  Given room the list sits beside the page; a portrait phone has none, so it
  drills down and BACK is the way out of an entry. A landscape phone is 844
  points wide and gets two panes — "compact" says the HUD reflowed, it does not
  say the screen is narrow, and that is the one place in this project where the
  two come apart. `screenshot.gd --sequence=almanac` taps a tab, a row, BACK and
  the scrim at every layout, and then falls through the shared tail that checks
  the shop still buys on the *first* tap afterwards.
- **`[table]` is not the way to line up a stat block.** Godot sizes each BBCode
  column to its own widest cell, so the star headings sat off the numbers they
  labelled, and four columns inside the 330 points a portrait phone gives the
  page is not a table at all. A row of numbers separated by `»` carries the
  same meaning at any width, and is already the game's mark for "becomes".
- **GDScript's `\U` escape takes six hex digits, not eight.** `"\U0001f30a"`
  compiles happily and yields `ǳ` followed by a literal `0a` — a wave emoji
  that reads as "dz0a" on screen, and one `test_glyphs` passes because U+01F3
  *is* drawable. Write the emoji itself, the way every `.tres` icon does.

- **Press-and-hold is the touch inspector, and it lives in Main.** A finger has
  no hover. Main watches real `InputEventScreenTouch` — never the emulated mouse,
  which cannot be told from a real one, and a mouse held still for a third of a
  second is a slow click. A hold re-shows the tooltip from the text the hover
  handler recorded rather than pinning whatever is on screen, because the tooltip
  watches the cursor and has usually closed itself by then. A shop card is the
  only thing a bare tap acts on, so it buys on *release* and skips the release
  that a hold consumed (`ShopBar.swallow_click`).
- **A finger has no hover, so a tap must close the inspector itself.** The
  emulated cursor stops wherever the tap landed — still inside the panel that
  opened the inspector — so the un-hover that closes one on a desktop never
  arrives, and buying a pirate on a phone left its card's tooltip up until the
  player tapped somewhere else. `Main._input` dismisses an un-pinned inspector on
  every touch release; a pinned one is exempt, because that was opened
  deliberately by a hold and has its own way out. The other half of the same
  complaint is that **the shop card was the one hover handler that passed no
  `refresh`**, so it could not tell that the card it described had been bought —
  `_shop_card_text` returns `""` for an empty slot, which is what closes it. Both
  halves are replayed by `screenshot.gd --sequence=buy`, and each has an act that
  fails without it.
- **The tooltip closes itself.** A tooltip opened by a hover and closed only by
  the matching un-hover stays up forever when the panel underneath rebuilds —
  which the shop does on every purchase. It watches its owner every frame.
- **The tooltip re-reads its subject; it does not remember it.** Text built once
  by the handler that opened the inspector is a photograph, and the board only
  reports a hover when the cursor *moves* — so a mid-fight stat block, read the
  way anyone reads one, by holding still, was frozen at whatever was true when
  the cursor arrived, and a pinned one on a phone never changed at all. Callers
  hand `show_text` and `pin` a `refresh` Callable instead, built by the
  `_*_text` functions in Main, and the tooltip calls it ten times a second,
  assigning the label only when the string differs. A refresh returning `""`
  means the subject is gone — sold, merged into a star-up, killed, the fight
  over — and closes the inspector, which is the only way a *pinned* one on a
  touchscreen ever finds out. The refresh is dropped on close, because one for a
  fight is a lambda holding a SimUnit and that is exactly what `Sim.dispose()`
  exists to break. `screenshot.gd --live` hovers a pirate mid-fight, changes its
  health without touching the mouse again, and fails if the panel does not
  follow.

### The art

There is no image asset in this project and there is not going to be one. Every
pirate is a few dozen polygons in `UnitArt`, and the sea is a fragment shader.

- **A champion's appearance is data, like its stats.** `art_body`, `art_tint` and
  `art_marks` on `ChampionDef`: one of twelve bodies, one colour, and up to three
  accessories. Fifty-one bespoke silhouettes would be detail nobody can resolve —
  a board hex is 43 points on a phone — and adding a pirate would stop being a
  `.tres` edit. Authored in `tools/art_table.gd` and stamped in by
  `assign_art.gd`, which loads each resource and sets three fields; **do not use
  `generate_content.gd` for this**, because it overwrites a champion whole and
  throws away every number tuned since the port.
- **`draw_set_transform` replaces a CanvasItem's draw transform; it does not
  compose with it.** So a figure cannot be positioned by whatever is drawing it —
  only by moving the node it is drawn into. That is why the board gives every
  unit its own `UnitView`, why `UnitPortrait` is a Control wrapping a Node2D, and
  why `art_sheet.gd` builds one node per figure instead of drawing a grid of them
  into one Control. Written the obvious way, every figure on a page stacks up at
  the origin.
- **A polygon that folds over itself draws nothing and prints once a frame.**
  Godot answers a self-intersecting polygon with "triangulation failed" rather
  than with a wrong shape, so the symptom is a missing limb and a log nobody is
  reading. Three rules came out of it, each having cost a body: a band is walked
  *up one edge and back down the other* so the two can never cross; anything that
  could fold is a **triangle**, not a quad; and `_curl` clamps its own bend and
  width against its length, because the numbers that break it arrive from a sine
  and a siren's tail is fine at rest and folds the moment she swims.
- **A test cannot check that any of this draws.** Godot refuses a draw call made
  outside a real `_draw()`, so a headless test that makes them anyway collects
  errors and still reports green — the loop counting them finishes either way.
  `tools/art_sheet.gd` is the renderer check: it runs windowed, draws every
  champion and every animation state over fourteen frames at a moving clock, and
  surfaces Godot's own complaint. It caught two folded polygons on its first run.
  Same split as the sound — `test_audio` can check the bank, only
  `screenshot.gd --sfx` can check the noise.
- **The animation is derived from the sim, never delivered by it.** An attack is
  an attack timer that jumped back up; a wound is health that went down; a death
  is `alive` going false. `UnitView` reads those every frame and decays a pose.
  Nothing was added to `Sim` and nothing needed to be: `fx_queue` carries
  positions rather than uids and cannot say *which unit* swung, and building a
  channel that could would have put a cost on the six fights a round that are
  never watched. Decay runs in **battle** time, so a swing at 4x still finishes
  before the unit that threw it dies.
- **The board is played up the screen, so a figure faces the viewer and leans.**
  A body turned to face its target spends the fight in profile facing away from
  you. Only the two shapes read from above — a serpent, a gull — actually rotate
  (`TURNS_TO_AIM`), and the two drawn from the side flip (`MIRRORS_TO_AIM`). The
  shark was drawn from above first, to match the board; a shark from above is a
  spindle with two fins, which at forty pixels is a leaf.
- **`Ocean` is a full-panel Control over the board, and `Control` defaults
  `mouse_filter` to STOP.** Left alone that is an invisible sheet that eats every
  press meant for the board — no dragging a pirate, no dropping an item, nothing
  on screen to say why. It is the toast bug with the blast radius of the board,
  and `test_hud.gd` walks a real BoardView rather than trusting the comment. It
  also sets `show_behind_parent`, because a CanvasItem paints itself before its
  children and the grid is drawn in BoardView's own `_draw`.
- **The sea is a shader because water has to move when nothing else is.** A fight
  at 4x, a planning phase where the player is reading, an idle window — animating
  it from GDScript would mean repainting the whole board panel sixty times a
  second forever. Only the foam on the hex rims is drawn, at 15fps, because that
  has to be in board space. Tuned **down** twice: the first pass ran deep to
  shallow across four stops of brightness and the grid vanished into what looked
  like upholstery, and three straight sine trains sum into a diagonal weave that
  reads as quilting until the sample point is warped.
- **`Pose.detail` comes from the board scale, and trims what a small figure
  pays.** A phone draws a unit into a 21-point hex, where a belt buckle and a row
  of teeth are draw calls producing one indistinct pixel each, eighteen times
  over, on the device least able to afford it. Silhouette is never gated; below
  0.45 even the outlines stop.
- **Emoji are not gone, they moved.** They were the whole roster and are now the
  trait and item icons, the coin and the star — text, where a font glyph is the
  right answer and `test_glyphs.gd` still guards them. A champion's emoji is
  still on its `ChampionDef` and still used in the almanac and the tooltip
  headings.
- **Measure the drawing with `soak.gd` run *windowed*.** Headless soak builds the
  whole HUD and never calls `_draw`, so it says nothing at all about the art. The
  figures cost nothing in steady state — both builds sit on the same vsync floor
  — and 8-18ms extra on the frame a fight starts, which is a frame that already
  hitched.

### Sound

- **Sound has two feeds, and the split is the same one rendering uses.** Anything
  the run *announces* comes off the `Events` bus, so no panel calls `Audio`;
  anything a *fight* does comes through `FxLayer.add_effect`, the one node that
  draws every effect. That second one is not a shortcut, it is the point: seven
  fights resolve every round and six never reach a renderer, so they are silent
  for free. Fed from `Sim` instead, every round would play six invisible battles
  over the top of the one being watched.
- **Cues are data.** `Audio.BANK` is one line per cue — files, volume, the pitch
  range, and the shortest gap between two plays. The gap is not a nicety: at 4x,
  eighteen pirates attack faster than a sound finishes, and without it a fight is
  mush. Pitch is part of the cue too, and does real work — there is no cannon in
  a CC0 interface pack, so the cannon is a heavy metal impact at half speed, and
  the same file at its own pitch is the forge's anvil.
- **The sounds were picked by name, not by ear.** They are CC0 from Kenney (see
  `audio/CREDITS.md`), chosen so that "confirmation" and "error" carry their own
  meaning and an impact on wood or leather is a physical noise that means
  whatever it is put behind. Kenney's jingle pack is deliberately unused: a
  melody picked without hearing it is a coin flip on whether losing a round
  sounds triumphant. If one of them sounds wrong, it is a filename in `BANK`.
- **`Audio` stands down headless but still wires itself up.** Playback needs a
  listener and the test suite is not one, so no voices are built there — but
  `_connect_bus()` runs anyway, because a signal named wrongly is a cue that
  never plays and `connect()` is the only thing that ever says so.
- **A sound system is the DPS meter problem again**: it looks perfect while
  producing nothing, and silence is also what most of a game sounds like.
  `test_audio` can only check the bank headless — every cue's file loads, every
  shipped file is used, every attack style in `Sim.ATTACK_STYLES` has its own cue
  rather than falling back — so **`screenshot.gd --sfx` is the one that fights a
  round with the sound on and asserts what actually came out**, including that
  mute stops it.

### What the first playtest asked for

Sam's notes after his first game, and where each landed. Do not quietly undo
these; they are the reason several things are where they are.

| Note | Where |
|---|---|
| Highlight duplicates in the shop | `ShopBar.ShopCard`. Read wrongly first time as "two copies are in the shop"; the ask was **"I already own one of these"**. Ownership is a green frame, a three-pip row and `IN FLEET n/3`; a star-up is a gold frame and `★★ BUY THIS` (or `★★ BUY BOTH` when one is owned and two are on the counter); a pair in the shop you own none of is grey text and no frame |
| Gold visible near the shop | `ShopBar` right column — a large gold panel beside the cards, not only in the top bar |
| Attacks need variation and direction | `Sim.ATTACK_STYLES` + `FxLayer` |
| Feedback when an item is acquired | `ToastLayer`, plus a pulsing highlight on the new item in the hold |
| Item effects need to be visible | Full item text in the champion tooltip; hovering a unit **mid-fight** shows live stats |
| Item combinations need explaining | Forge chart modal, forge preview on the drag, and every pairing listed in a component's tooltip. Every square of the chart opens the full item inspector — it used to carry Godot's own one-line `tooltip_text`, which a phone never sees at all |
| The AI never seemed to use items | Bots now draw the same loot on the same rounds and forge it by the same rules. They previously got one random finished item per stage and never combined anything |
| Round timer near the shop, warn before it ends | `ShopBar` clock, and `Events.plan_time_warning` turns it orange with 8s left |
| Tooltips felt sticky | `Tooltip` watches its own owner — see above |

### Balance

- **Bots are paid a handicap** (`+max(0, stage - 2)` gold a round) because they
  cannot read a shop or plan ahead. **Worth re-measuring now that they also use
  items** — that was added after the handicap was tuned, and nothing has
  confirmed it is still the right number.
- **Monster rounds are a floor, not a wall.** A player who fields anything at
  all should win them; only an empty board should lose. Round 1-1 is the one
  that has to be checked by hand — level 1 seats **one** pirate, so the opening
  wave has to be beatable by a single 1-cost or it is a scripted loss on the
  first round of the game. It was three Deck Rats, and it was. Run
  `creep_balance.gd` after touching a wave or a monster's stats; the naive
  player it drives should win every wave, and the only fleets losing should be
  bots with almost nothing on the board.
- **Losing pays the same streak bonus as winning.** A captain being beaten every
  round has to be able to fund the rebuild that gets them back in.

## The dev build

**All of this comes out before release.** It is playtest scaffolding, not part of
the game.

| Piece | What it is |
|---|---|
| `scripts/dev/dev.gd` | The `Dev` autoload. Writes a playtest log |
| `scripts/dev/dev_menu.gd` | The cheat panel, opened by the DEV chip |
| `tests/test_dev.gd` | The invariants below |

**Removing it is three deletions and nothing else**: `scripts/dev/`,
`tests/test_dev.gd`, and the `Dev=` line under `[autoload]` in `project.godot`.

That is the whole design constraint. **No game code references any of it** — the
menu adds itself to the scene tree *root* rather than being built by `Main`, and
the log listens on the `Events` bus rather than being called from anywhere. So
the deletion cannot break a compile and cannot leave half a hook behind, which is
what happens to a dev menu wired into `main.gd`, and is why those ship by
accident. Do not "tidy" it by giving `Main` a reference to it.

Being a root sibling has a second payoff: a phone rotation rebuilds all of
`Main`'s children and never touches this, so the menu survives a rotation free.

### The log

Every signal on the `Events` bus, one line each, plus the fleet and the active
traits at the moment each fight starts — the decision the player actually made,
which is what the result afterwards is a consequence of. `Events.plan_timer` is
the one signal skipped; it fires thirty times a second and says nothing.

On the desktop it is written to `user://playtests/playtest_<stamp>.log`, flushed
every line, because the part of a playtest log worth having is the last few lines
before whatever went wrong. On the **web there is no reachable filesystem**, so it
is kept in memory and leaves through the menu's COPY LOG and DOWNLOAD LOG
buttons. MARK drops a divider in it, for pointing at a moment.

It stands down in two situations, both deliberate. Headless is the test suite and
the balance tools, and none of those is a playtest. And the **menu** hides under
any `--script` target, because every tool in `tools/` is one and `screenshot.gd`
asserts against panel heights and taps at measured coordinates. Pass
`-- --dev-ui` to opt back in, which is how the menu gets rendered at the three
layouts.

### Rules the menu already broke once each

- **It is the one place allowed to mutate `GameState` outside `Main`.** A cheat
  panel is by definition a second path from a click to a change. Routing it
  through `Main` would spread code that has to be deleted across a file that
  stays.
- **Spawning takes the real cost out of the shared pool** — three copies for a
  two-star, nine for a three-star, exactly as merging bought copies would.
  Anything looser silently drains a champion out of every captain's shop for the
  rest of the run: the failure `test_economy` guards the shop against, arriving
  through a door it does not watch.
- **The overlay is full-screen, so every node in it must be IGNORE** except the
  chip and the open panel. This is the toast bug with a bigger blast radius — a
  full-rect Control left on STOP looks exactly like the game having frozen.
- **A long `Label` sets the panel's width.** A `Label` reports its unwrapped line
  as its minimum width and the panel sizes to its contents, so one unwrapped
  sentence dragged the menu out to 772 points on a 390-point phone, off both
  edges. Explanatory lines go through `_note_line`, which wraps.
- **Everything is positioned from `Layout.css_size`, so a rotation has to re-fit
  it.** A chip in the bottom-right of a landscape phone sits at x=800, which is
  off the right edge of the portrait one — the dev menu unreachable on the only
  device it exists for, and only after a rotation.

**Jump to stage is a scenario jump, not a simulation.** It pays the income and
gives the bots the shopping turns for every round it passes, so the opponents are
not still fielding a stage-1 board, but nobody fights. Good for looking at a late
board and its economy, no use for judging a matchup.

## The retired JavaScript build

`js/`, `css/` and `index.html` are the original prototype. They are **frozen**:
no feature, no fix and no balance change goes into them ever again. Do not read
them for a spec either — where the two builds disagree, the Godot build is right,
because everything since parity has landed only here. Both directories carry a
`.gdignore` so the engine leaves them alone, and they stay in the tree only
because the repository root still serves the prototype to anyone who wants a
build that loads instantly rather than pulling ~50 MB of WebAssembly. The play
link in the README points at `/web/`.

`tools/generate_content.gd` holds the champion, trait and item tables originally
ported from `js/data/*.js`, and **overwrites every .tres it produces**. It is a
one-time bootstrap, not something to re-run after balancing — a number tuned in
the inspector is lost. Balance in the `.tres` from here on; come back to the
generator only to add something new. It is now the last thing in the project that
refers to the JavaScript at all, and only in a comment.

## Testing policy

- The suite must be green before a commit.
- **A test that asserts nothing did not pass.** The runner fails any test that
  made no assertions, because a GDScript runtime error abandons a method and
  returns to the runner as if it had finished.
- `test_abilities.gd` casts all 44 abilities in isolation — allies are copies of
  the caster so no trait activates, everyone is stunned so nobody attacks — and
  fails any that changes nothing. That is the net under the riskiest thousand
  lines of the port.
- `test_hud.gd` holds the invariants whose breakage looks like the game ignoring
  the player rather than like a bug: that nothing in the toast layer can take a
  click, that `queue_free()` leaves the child in place (the fact the freeze rested
  on), that the container helpers take effect immediately, and that the log panel
  survives passing its limit. **A hang in that last one is the freeze returning**,
  not a slow test.
- `test_art.gd` checks that every champion has a body the renderer knows, that
  every mark is one it draws, that no two champions sharing a body share a
  colour, and that the `.tres` still agree with `ArtTable` — editing the table
  without re-running `assign_art.gd` changes nothing and looks like it worked.
  It **cannot check that anything draws**; see the art rules below.
- `test_glyphs.gd` fails any character the web export could not draw. The rule it
  replaces was "check it in the browser", which means exporting, and which is why
  the game shipped twice with tofu where its prices were.
- `test_wiki.gd` walks every section of the almanac, renders every page, and
  follows every cross-link in every one of them. Both ways a reference rots are
  silent: a champion added to `data/` and never listed, and a link to an id that
  was renamed. Neither throws and neither shows up in a screenshot.
- `test_dps.gd` checks that the meter's counters are actually fed. A DPS meter
  is the panel that renders perfectly while reporting nothing, and neither the
  suite nor a screenshot can tell that from an honest zero — so the assertions
  are on the numbers: that one side's *dealt* equals the other's *taken*, that a
  shield absorbing a hit still counts as taking it, and that the snapshot the
  meter reads survives `Sim.dispose()`.
- `test_audio.gd` walks the cue bank: every cue names a file that loads, every
  file in `audio/` is played by something, and every attack style has a cue of
  its own. It cannot test playback — headless has no voices — which is what
  `screenshot.gd --sfx` is for.
- `test_round_start.gd` holds the opening gate: a new run does not run its clock,
  closing the briefing or pressing SET SAIL starts it, and an `instant` run is
  never held, which is what keeps `playthrough.gd` from stalling on 1-1.
- `test_economy.gd` checks that **no champion copies are lost** over forty rounds
  of bot shopping. A card rolled and neither bought nor returned drains the
  shared pool silently, and the shop slowly stops offering that champion to
  anyone.
