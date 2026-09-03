# Sound

Every file in this folder is **CC0 1.0 (public domain)** by Kenney
(<https://kenney.nl>), taken from four of his audio packs:

| Pack | Files taken |
|---|---|
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `bong_001`, `confirmation_002`, `confirmation_004`, `error_004`, `error_008`, `glass_005`, `maximize_006`, `open_004`, `pluck_002`, `select_005`, `switch_004`, `tick_002` |
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) | `impactBell_heavy_002`, `impactMetal_heavy_000`, `impactMetal_heavy_001`, `impactMetal_light_001`, `impactMetal_light_002`, `impactPlank_medium_000`, `impactPlank_medium_001`, `impactPlate_heavy_000`, `impactWood_heavy_001` |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | `beltHandle1`, `creak1`, `drawKnife2`, `dropLeather`, `handleCoins`, `knifeSlice`, `knifeSlice2`, `metalLatch` |
| [Casino Audio](https://kenney.nl/assets/casino-audio) | `chips-handle-2` |

CC0 asks for nothing, but credit is polite, so it is here.

## Why these files

The names are kept exactly as Kenney ships them, so any one of them can be
found again in its pack and swapped for a neighbour. Which sound plays when is
**not** decided here — that is `BANK` in `scripts/autoload/audio.gd`, one line
per cue.

The choices were made by what each file is *named*. "Confirmation" and "error"
carry their meaning in the name and can be trusted to mean yes and no; an
impact on metal, wood or leather is a physical noise that means whatever it is
put behind. A melody cannot be read off a filename at all, which is why Kenney's
jingle pack is not used: a jingle picked without hearing it is a coin flip on
whether losing a round sounds triumphant.

Nothing here is a cannon, because a CC0 interface pack does not contain one. The
cannon is `impactMetal_heavy` played at half speed, and the same file at its own
pitch is the anvil behind the forge. Pitch is part of the cue, not part of the
file.
