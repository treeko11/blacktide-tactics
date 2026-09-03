class_name ArtTable
extends RefCounted

## What every champion looks like: one body, one colour, a couple of accessories.
##
## This is authoring data, not runtime data — it is read by `assign_art.gd`, which
## stamps it into `data/champions/*.tres`, and by `generate_content.gd`, so a
## champion added through the generator arrives with a face rather than as a
## default blue pirate. The game itself never loads this file; it reads the
## `.tres`, which stays the only copy of anything the game asks about.
##
## Kept in one table rather than fifty-one scattered edits because the job it
## actually does is *contrast*: two 4-costs the same shade of teal is a mistake
## you can only see by reading the colours next to each other.
##
## Names nothing outside itself. It is compiled into `--script` targets, where an
## autoload does not exist and naming one fails the whole tool.

const DEFAULT := { "body": &"pirate", "tint": "4d8fb5", "marks": [] }

const ART := {
	# Grouped by the **origin trait each champion actually carries**, not by
	# flavour. The headings used to be written by feel — "the ghost fleet: pale,
	# tattered", "leviathans and whatever else came up from under the hull" — and
	# nothing checked them against `traits` in the `.tres`, so nine champions
	# quietly ended up wearing another faction's silhouette: a Stormborn drawn as
	# a wraith, a Ghost Fleet harpooner drawn as a perfectly solid shark, and two
	# Tidecallers drawn as mermaids with no Siren trait between them.

	# --- Royal Navy: the `officer` body, which is a different outline rather ---
	# --- than a different hat. The bicorn and the shoulder boards come from   ---
	# --- the body now, so neither is listed as a mark.                        ---
	&"vance":     { "body": &"officer", "tint": "d6b84f", "marks": [&"musket", &"plume"] },
	&"corvane":   { "body": &"officer", "tint": "2f5a9e", "marks": [&"musket", &"beard"] },
	&"marlowe":   { "body": &"officer", "tint": "3f5f8f", "marks": [&"musket"] },
	&"voss":      { "body": &"officer", "tint": "5a7a8f", "marks": [&"musket", &"keg"] },
	&"tuck":      { "body": &"officer", "tint": "4f86b8", "marks": [&"spyglass", &"parrot"] },
	&"ned":       { "body": &"officer", "tint": "1f3f66", "marks": [&"anchor", &"beard", &"eyepatch"] },

	# --- Corsairs: the round-shouldered jacket, warm, too many feathers ---
	&"ashmore":   { "body": &"gunner", "tint": "2b2f38", "marks": [&"beard", &"tricorn", &"musket", &"lantern"] },
	&"ravenna":   { "body": &"pirate", "tint": "a03f6a", "marks": [&"tricorn", &"plume", &"dual"] },
	&"isla":      { "body": &"pirate", "tint": "d1443f", "marks": [&"plume", &"dual"] },
	&"rook":      { "body": &"pirate", "tint": "3a4450", "marks": [&"parrot", &"eyepatch"] },
	&"pip":       { "body": &"pirate", "tint": "d69f3f", "marks": [&"parrot", &"plume", &"bandana"] },
	&"barnaby":   { "body": &"pirate", "tint": "b6642f", "marks": [&"keg", &"bandana"] },
	&"finn":      { "body": &"pirate", "tint": "4f8f6a", "marks": [&"harpoon", &"bandana"] },
	&"saltyjo":   { "body": &"gunner", "tint": "c96a3f", "marks": [&"bandana", &"musket"] },
	&"lyra":      { "body": &"gunner", "tint": "c98a3f", "marks": [&"musket", &"plume"] },

	# --- the ghost fleet: pale, tattered, lit from inside. Every one of them ---
	# --- is the `ghost` body, because "Ghost Fleet" that does not look dead   ---
	# --- is a trait the board cannot be read for.                            ---
	&"davy":      { "body": &"ghost",  "tint": "8a6fd6", "marks": [&"crown", &"horns", &"tattered"] },
	&"brine":     { "body": &"ghost",  "tint": "6fd3b8", "marks": [&"tattered"] },
	&"silas":     { "body": &"ghost",  "tint": "8fd6c0", "marks": [&"tattered", &"beard"] },
	&"skarn":     { "body": &"ghost",  "tint": "9eb0c0", "marks": [&"tattered", &"horns"] },
	&"grimscale": { "body": &"ghost",  "tint": "a8d68f", "marks": [&"tattered", &"hook"] },
	&"barnacleking": { "body": &"ghost", "tint": "5fb894", "marks": [&"crown", &"tattered"] },

	# --- sirens: the one family allowed to be pretty. The mermaid silhouette ---
	# --- means the Siren trait and nothing else.                             ---
	&"sirene":    { "body": &"siren",  "tint": "4fd6c9", "marks": [&"crown"] },
	&"nautica":   { "body": &"siren",  "tint": "3f8fd6", "marks": [&"crown"] },
	&"meredine":  { "body": &"siren",  "tint": "4fc9c0", "marks": [&"tide"] },
	&"nerida":    { "body": &"siren",  "tint": "5fd6a8", "marks": [&"tide"] },
	&"coral":     { "body": &"siren",  "tint": "ef7f9d", "marks": [&"tide"] },
	&"morgause":  { "body": &"siren",  "tint": "a06fd6", "marks": [] },
	&"mira":      { "body": &"siren",  "tint": "7fb8f0", "marks": [&"storm"] },

	# --- leviathans: whatever came up from under the hull. The shark is two ---
	# --- of these and nobody else, so a fin on the board means Leviathan.   ---
	&"kraken":    { "body": &"kraken", "tint": "6a3f7a", "marks": [&"horns"] },
	&"maelstrom": { "body": &"serpent", "tint": "4f6fd6", "marks": [&"storm", &"horns"] },
	&"dredge":    { "body": &"shark",  "tint": "4a6a52", "marks": [] },
	&"kelpar":    { "body": &"shark",  "tint": "3f7a5a", "marks": [&"tide"] },

	# --- Stormborn and Tidecaller are callings rather than lineages: no body ---
	# --- of their own, so they are crew wearing the weather. Each is a mark  ---
	# --- `draw_unit` puts over any body at all: `storm` above the head and   ---
	# --- `tide` around the feet, which is what lets Calypso and Thalassa     ---
	# --- wear both. The other five Tidecallers are filed under their own     ---
	# --- lineage above and carry `tide` there.                               ---
	&"kade":      { "body": &"gunner", "tint": "4fa8d6", "marks": [&"storm", &"eyepatch", &"musket"] },
	&"squall":    { "body": &"gunner", "tint": "7fc9f0", "marks": [&"storm", &"spyglass"] },
	&"calypso":   { "body": &"gunner", "tint": "7f6bd6", "marks": [&"crown", &"storm", &"tide"] },
	&"thalassa":  { "body": &"gunner", "tint": "3fb8d6", "marks": [&"storm", &"tide"] },
	&"selka":     { "body": &"pirate", "tint": "4fc0a0", "marks": [&"dual", &"bandana", &"tide"] },

	# --- no origin trait at all: plain crew, and deliberately so. Each of ---
	# --- these used to borrow a silhouette that promised a trait it did    ---
	# --- not have — Hookjaw a Leviathan's fin, Grull and Sable a monster's. ---
	&"bess":      { "body": &"pirate", "tint": "a83f52", "marks": [&"harpoon", &"bandana"] },
	&"hookjaw":   { "body": &"pirate", "tint": "4a7f9e", "marks": [&"harpoon", &"hook", &"bandana"] },
	&"grull":     { "body": &"pirate", "tint": "8a5a3a", "marks": [&"beard", &"bandana"] },
	&"sable":     { "body": &"pirate", "tint": "2f6a8f", "marks": [&"plume", &"dual"] },
	&"kessa":     { "body": &"pirate", "tint": "b02f4a", "marks": [&"dual", &"bandana"] },
	&"doss":      { "body": &"gunner", "tint": "6b5236", "marks": [&"eyepatch", &"tricorn", &"musket"] },
	&"halloway":  { "body": &"gunner", "tint": "3f7f8f", "marks": [&"tricorn", &"musket"] },

	# --- monsters. Drab on purpose: nothing here is in anybody's fleet ---
	&"rat":       { "body": &"brute",  "tint": "7a6a5a", "marks": [] },
	&"crab":      { "body": &"crab",   "tint": "a8552f", "marks": [] },
	&"gull":      { "body": &"bird",   "tint": "b8b0a0", "marks": [] },
	&"serpent":   { "body": &"serpent", "tint": "5f9e4a", "marks": [] },
	&"skiff":     { "body": &"ship",   "tint": "7f8f9e", "marks": [&"tattered"] },
	&"golem":     { "body": &"golem",  "tint": "5c6470", "marks": [] },
	&"elder":     { "body": &"kraken", "tint": "5a4a7a", "marks": [&"crown"] },
}


## What a champion looks like, or the default. A champion missing from the table
## is a plain blue pirate rather than an error, which is the right failure: a new
## pirate is playable the moment its stats exist, and looks unfinished until
## somebody comes back here, which is exactly what it is.
static func lookup(id: StringName) -> Dictionary:
	return ART.get(id, DEFAULT)
