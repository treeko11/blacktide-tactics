# Blacktide Tactics

A pirate-themed auto battler. Godot 4.7.2 stable, GDScript.

Eight captains, one shared champion pool. Buy pirates, position them on a hex
board, and the fight resolves itself. Ported from a vanilla-JavaScript build that
still lives in `js/` and `index.html` — see **The port** below.

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
| `screenshot.gd` | Renders a PNG. Must run **without** `--headless`. Also the only check of the phone layout and of touch: `--size=`, `--measure`, `--rotate=`, `--hold=card\|bench\|item\|chart`, `--sequence=forge\|item`, all of which assert |
| `creep_balance.gd` | Win rate against every monster wave, per stage and round |
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
scripts/autoload/                  Events, Content, GameState
scripts/core/                      Hex, Sim, SimUnit, Captain, Bot, RosterUnit,
                                   the three *Def resources, ScriptDir, and the
                                   three extension-point base classes
scripts/core/abilities/            one file per champion (44)
scripts/core/traits/               one file per trait (13)
scripts/core/items/                one file per item (20)
scripts/ui/                        UITheme, Layout, BoardView, UnitView,
                                   FxLayer, ShopBar, BenchBar, SidePanels,
                                   TopBar, Tooltip, ToastLayer, Modals
scripts/game/main.gd               assembles the HUD and wires it to GameState
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
- **Press-and-hold is the touch inspector, and it lives in Main.** A finger has
  no hover. Main watches real `InputEventScreenTouch` — never the emulated mouse,
  which cannot be told from a real one, and a mouse held still for a third of a
  second is a slow click. A hold re-shows the tooltip from the text the hover
  handler recorded rather than pinning whatever is on screen, because the tooltip
  watches the cursor and has usually closed itself by then. A shop card is the
  only thing a bare tap acts on, so it buys on *release* and skips the release
  that a hold consumed (`ShopBar.swallow_click`).
- **The tooltip closes itself.** A tooltip opened by a hover and closed only by
  the matching un-hover stays up forever when the panel underneath rebuilds —
  which the shop does on every purchase. It watches its owner every frame.

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

## The port

`js/`, `css/` and `index.html` are the original build, kept working and still
playable while the Godot version reaches parity. Both directories carry a
`.gdignore` so the engine leaves them alone. **Retire them once the Godot build
is ahead**, and update the play link in the README when that happens.

`tools/generate_content.gd` holds the champion, trait and item tables ported from
`js/data/*.js`, and **overwrites every .tres it produces**. It is a one-time
bootstrap, not something to re-run after balancing — a number tuned in the
inspector is lost. Balance in the `.tres` from here on; come back to the
generator only to add something new.

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
  the player rather than like a bug — currently that nothing in the toast layer
  can take a click.
- `test_glyphs.gd` fails any character the web export could not draw. The rule it
  replaces was "check it in the browser", which means exporting, and which is why
  the game shipped twice with tofu where its prices were.
- `test_economy.gd` checks that **no champion copies are lost** over forty rounds
  of bot shopping. A card rolled and neither bought nor returned drains the
  shared pool silently, and the shop slowly stops offering that champion to
  anyone.
