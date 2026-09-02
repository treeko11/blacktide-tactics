# Blacktide Tactics

**[▶ Play it here](https://treeko11.github.io/blacktide-tactics/web/)**

A pirate/nautical auto battler in the style of Teamfight Tactics. Godot 4.7, GDScript.

Eight captains, one shared champion pool, last fleet afloat wins. You buy pirates from a rotating
shop, arrange them on your half of a hex board, and they fight automatically against one other
captain each round. Lose and your **hull** (100 HP) takes damage.

Plays on desktop and on phones — mouse, touch, and a layout that reflows for both.

---

## The JavaScript build is retired

This game began as a vanilla-JavaScript prototype. `index.html`, `css/` and `js/` are that
prototype, and they are **frozen**: no further features, fixes or balance changes go into them. The
Godot build has been ahead of it since it reached feature parity, and everything below describes the
Godot build.

The old prototype is still served at the [repository root](https://treeko11.github.io/blacktide-tactics/)
and still runs from a double-clicked `index.html`, because it loads instantly where the Godot build
pulls ~50 MB of WebAssembly. Treat it as an archive. Both directories carry a `.gdignore` so the
engine ignores them.

**What the Godot build has that the prototype never will**: art — the board is an animated ocean and
every pirate is a drawn figure that winds up, lunges, recoils and sinks, rather than an emoji in a
circle. Sound on every action. An almanac of every pirate, trait, item and monster wave. A live DPS
meter. Shop cards that call out duplicates and star-ups. A forge chart. Rivals that actually collect
and forge items. And a phone layout that rebuilds itself when you turn the device.

---

## The game

**Round schedule**

| Stage | Rounds |
|---|---|
| 1 | three monster rounds, then the Armoury |
| 2+ | PvP, PvP, monsters, PvP, PvP, Armoury |

Monster rounds drop item components and gold. The Armoury at the end of each stage lets you pick
one finished item out of three.

**Economy** — a wage each round that ramps in (2 from 1-2, 3 at 1-4, 4 at 2-1, 5 from 2-2 on),
plus interest (1 per 10 banked, capped at 5), plus win/loss streak bonuses at 3, 5 and 6 rounds in a
row, plus 1 for beating another captain. Refresh the shop for 2, buy 4 XP for 4. Your level is your
board capacity (max 9).

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
| Drag | the piece floats above your finger and drops where it floats |
| Press and hold | inspect a pirate, item or shop card; held pirates get a Sell button |
| Tap | buy from the shop, or inspect a trait / rival captain |
| FLEET | fleet standings and battle log |
| ALMANAC | every pirate, trait, item and wave, plus how to sail |

## The 13 traits

**Origins** — Corsair (team attack damage + crit), Leviathan (huge health, damage reduction),
Siren (ability power, mana refunds), Ghost Fleet (units rise again after dying),
Tidecaller (team regeneration that overflows into shields), Stormborn (periodic lightning strikes),
Royal Navy (team resistances, damage recovered over time).

**Classes** — Gunner (extra shots every third attack), Swashbuckler (stacking attack speed + dodge),
Bosun (bulk health), Harpooner (armor shred + true damage), Navigator (team mana and regeneration),
Reaver (omnivamp + bonus damage to wounded enemies).

Hover anything — or press and hold it on a phone — for full details.

---

## Code layout

```
project.godot                      autoloads, window, input
scenes/main.tscn                   a bare Control; the HUD is built in code
data/champions/, traits/, items/   authored .tres definitions — balance lives here
audio/                             CC0 sound files + CREDITS.md
scripts/autoload/                  Events, Content, GameState, Audio
scripts/core/                      Hex, Sim, SimUnit, Captain, Bot, RosterUnit, the Defs
scripts/core/abilities/            one file per champion
scripts/core/traits/               one file per trait
scripts/core/items/                one file per item
scripts/ui/                        the HUD: board, ocean, unit art, shop, panels, almanac
scripts/game/main.gd               assembles the HUD and wires it to GameState
tests/                             test_*.gd, discovered automatically
tools/                             the test runner, playthrough, soak, screenshot, balance
web/                               the exported web build
```

Development notes — the architecture rules, the headless traps, and the reason behind
every awkward-looking decision — are in [CLAUDE.md](CLAUDE.md).

### How combat works

`Sim` runs both teams on one 7×8 hex grid — you occupy rows 4–7, the opponent's board is mirrored
onto rows 0–3. Every tick (a fixed 1/30s) each unit ticks statuses, then acts: cast if at full mana,
otherwise attack if the target is within range, otherwise move one hex closer. Damage is
`amount × 100/(100+resist)`, mana is gained from attacking and from being hit.

The same class runs the six rival-vs-rival matches with `render` false, so they cost nothing to
resolve and are silent — no renderer ever sees them.

### Tuning knobs

- `scripts/core/sim.gd` — `COMBAT_TIME_LIMIT`, `MOVE_TIME`, `BASE_CRIT`, `ATTACK_SPEED_CAP`
- `scripts/autoload/game_state.gd` — shop odds, the XP table, planning time, stage damage, waves
- `scripts/core/bot.gd` — the rivals' target level and their per-stage gold handicap
- `data/` — every champion, trait and item stat block

Adding a pirate is a `.tres` in `data/champions/` plus a file in `scripts/core/abilities/`; the
shop, pool, traits, almanac and tooltips all pick it up automatically.
