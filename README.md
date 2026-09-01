# Blacktide Tactics

**[▶ Play it here](https://treeko11.github.io/blacktide-tactics/)**

A pirate/nautical auto battler in the style of Teamfight Tactics.

## Two builds

The game is being **moved into Godot 4.7**, and both builds currently live in this repository.

| | Browser build | Godot build |
|---|---|---|
| Where | `index.html`, `css/`, `js/` | `project.godot`, `scenes/`, `scripts/`, `data/` |
| Play it | **[the link above](https://treeko11.github.io/blacktide-tactics/)**, or double-click `index.html` | **[/web/](https://treeko11.github.io/blacktide-tactics/web/)**, or double-click `Play.bat` |
| Input | mouse **and touch** | mouse **and touch** |
| Load | instant | ~50 MB WebAssembly download |
| State | complete | full feature parity, plus the first playtest's fixes |

The browser build keeps the top-level link because it loads instantly rather than pulling ~50 MB of
WebAssembly; the Godot build sits a click away at `/web/`. Both are the same game: same 44 pirates,
same 13 traits, same 20 items, same round loop and economy, and both now play on a phone.

**What the Godot build adds**, all from the first playthrough's notes: shop cards call out
duplicates and star-ups, gold and the round clock sit beside the shop instead of across the screen,
every archetype has its own directional attack effect rather than one shared line and ring, items
announce themselves when acquired and explain what they do, a forge chart shows every component
pairing, the AI actually collects and forges items, and tooltips close when you stop hovering them.

**On a phone** it reflows the way the browser build does: below 900 points the side columns collapse
into a trait strip and a cargo strip above the bench, the bench splits into two rows of five, the
shop wraps to three cards a row, and the fleet standings and log move into a sheet behind the FLEET
button. Press and hold anything to inspect it; the inspector for a pirate you own carries a SELL
button, since a phone has no right mouse button. Turning the phone sideways rebuilds the layout.

Development notes for the Godot build are in [CLAUDE.md](CLAUDE.md).

---

## The browser build

Zero dependencies, zero build step — play in the browser at the link above, or clone and
**double-click `index.html`**.

Plays on desktop and on phones. Below 1080px the layout switches to a touch build: the manifest
and cargo hold become compact strips above the bench, the bench splits into two rows of five,
and the fleet standings and log move into a bottom sheet behind the ☰ button.

---

## The game

Eight captains, one shared champion pool, last fleet afloat wins. You buy pirates from a rotating
shop, arrange them on your half of a hex board, and they fight automatically against one other
captain each round. Lose and your **hull** (100 HP) takes damage.

**Round schedule**

| Stage | Rounds |
|---|---|
| 1 | three monster rounds, then the Armoury |
| 2+ | PvP, PvP, monsters, PvP, PvP, Armoury |

Monster rounds drop item components and gold. The Armoury at the end of each stage lets you pick
one finished item out of three.

**Economy** — 5 gold per round, plus interest (1 per 10 banked, capped at 5), plus win/loss streak
bonuses, plus 1 for a win. Refresh the shop for 2, buy 4 XP for 4. Your level is your board capacity
(max 9).

**Upgrading** — three copies of a pirate merge into ★★; three ★★ merge into ★★★. Bench and board
copies both count, and items carry across the merge.

**Items** — drag two components onto the same pirate to forge one of 15 full items. Three items
per pirate. Selling a pirate returns their items to the hold.

## Controls

**Desktop**

| | |
|---|---|
| Drag | move pirates between bench and board, or drop items onto pirates |
| Hover | inspect anything — pirates, traits, items, rival captains |
| Right-click / `E` | sell the pirate under the cursor |
| `D` | refresh the shop |
| `F` | buy 4 XP |
| `Space` | start the battle early |
| `1` `2` `4` | battle speed |

**Touch**

| | |
|---|---|
| Drag | same as desktop — the piece floats above your finger and drops where it floats |
| Press and hold | inspect a pirate, item or shop card; held pirates get a Sell button |
| Tap | buy from the shop, or inspect a trait / rival captain |
| ☰ | fleet standings, battle log and the rules |

## The 13 traits

**Origins** — Corsair (team attack damage + crit), Leviathan (huge health, damage reduction),
Siren (ability power, mana refunds), Ghost Fleet (units rise again after dying),
Tidecaller (team regeneration that overflows into shields), Stormborn (periodic lightning strikes),
Royal Navy (team resistances, damage recovered over time).

**Classes** — Gunner (extra shots every third attack), Swashbuckler (stacking attack speed + dodge),
Bosun (bulk health), Harpooner (armor shred + true damage), Navigator (team mana and regeneration),
Reaver (omnivamp + bonus damage to wounded enemies).

Hover anything — pirates, traits, items, rival captains — for full details.

---

## Code layout

```
index.html            markup shell
css/main.css          all styling
js/util.js            hex math (odd-r offset, pointy-top), RNG, helpers
js/data/traits.js     13 traits; each has an apply(ctx) run at combat start
js/data/items.js      5 components, 15 forged items, recipe table
js/data/champions.js  44 pirates + 7 monsters' worth of stat blocks and abilities
js/combat.js          the simulation: fixed 30Hz timestep, runs headless or rendered
js/ai.js              the seven rival captains
js/game.js            pool, economy, shop, rounds, matchmaking, damage
js/ui.js              rendering, drag & drop, touch gestures, tooltips, modals
js/main.js            phase loop
```

Scripts are plain classic scripts (no ES modules) precisely so `file://` works without a server.

### How combat works

`Sim` runs both teams on one 7×8 hex grid — you occupy rows 4–7, the opponent's board is mirrored
onto rows 0–3. Every tick (1/30s) each unit ticks statuses, then acts: cast if at full mana,
otherwise attack if the target is within range, otherwise BFS one hex closer. Damage is
`amount × 100/(100+resist)`, mana is gained from attacking (10) and from being hit
(1% pre-mitigation + 7% post, capped at 42.5).

The exact same class runs the AI-vs-AI matches with `render: false` and `runToEnd()` — about
3ms per battle, so the other six fights resolve instantly between rounds.

### Responsive behaviour

One breakpoint drives everything: `1080px`, declared in `css/main.css` and mirrored by
`UI.isMobile()`. Crossing it, `UI.syncLayoutMode()` physically moves the trait list and cargo
hold between the desktop side panel and the mobile strip — same elements, same render code, so
there is no second UI to keep in sync. `UI.fitLayout()` then scales the board to whatever space
is left.

Touch input runs through `UI.beginPointer()`: a mouse drags immediately, while a finger waits —
move past 10px and it becomes a drag, hold still for 340ms and it opens the inspector instead.

### Tuning knobs

- `js/combat.js` — `COMBAT_TIME_LIMIT`, `MOVE_TIME`, `BASE_CRIT`, `AS_CAP`
- `js/game.js` — `SHOP_ODDS`, `XP_TABLE`, `PLAN_TIME`, `stageDamage()`, `creepWave()`
- `js/ai.js` — `Bot.targetLevel` and the `inc += Math.max(0, Game.stage - 2)` handicap control
  how hard the rivals push. Raise or lower that line to change difficulty.
- `js/data/champions.js` — star scaling lives in `statsFor()` (health ×1.8, attack damage ×1.55).

Adding a pirate is one object in `CHAMPIONS` (stats + a `cast(sim, self, vals)` function) — the
shop, pool, traits and tooltips all pick it up automatically.
