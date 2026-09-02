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
	# --- the Royal Navy and the ships of the line: blue and gold, braid on ---
	&"vance":     { "body": &"gunner", "tint": "d6b84f", "marks": [&"bicorn", &"epaulette", &"musket"] },
	&"corvane":   { "body": &"gunner", "tint": "2f5a9e", "marks": [&"bicorn", &"epaulette", &"musket"] },
	&"marlowe":   { "body": &"gunner", "tint": "3f5f8f", "marks": [&"bicorn", &"musket"] },
	&"voss":      { "body": &"gunner", "tint": "5a7a8f", "marks": [&"tricorn", &"musket"] },
	&"tuck":      { "body": &"gunner", "tint": "6a8f4a", "marks": [&"spyglass", &"tricorn"] },
	&"ned":       { "body": &"pirate", "tint": "7a6a4a", "marks": [&"anchor", &"beard", &"tricorn"] },
	&"sable":     { "body": &"ship",   "tint": "2f6a8f", "marks": [] },

	# --- corsairs and swashbucklers: red, gold, too many feathers ---
	&"ashmore":   { "body": &"gunner", "tint": "2b2f38", "marks": [&"beard", &"tricorn", &"musket", &"lantern"] },
	&"ravenna":   { "body": &"pirate", "tint": "a03f6a", "marks": [&"tricorn", &"plume", &"dual"] },
	&"isla":      { "body": &"pirate", "tint": "d1443f", "marks": [&"plume", &"dual"] },
	&"kessa":     { "body": &"pirate", "tint": "b02f4a", "marks": [&"dual", &"bandana"] },
	&"rook":      { "body": &"pirate", "tint": "3a4450", "marks": [&"parrot", &"eyepatch"] },
	&"pip":       { "body": &"pirate", "tint": "d69f3f", "marks": [&"parrot", &"plume", &"bandana"] },
	&"barnaby":   { "body": &"pirate", "tint": "b6642f", "marks": [&"keg", &"bandana"] },
	&"saltyjo":   { "body": &"gunner", "tint": "c96a3f", "marks": [&"bandana", &"musket"] },
	&"lyra":      { "body": &"gunner", "tint": "c98a3f", "marks": [&"musket", &"plume"] },
	&"doss":      { "body": &"gunner", "tint": "6b5236", "marks": [&"eyepatch", &"tricorn", &"musket"] },
	&"halloway":  { "body": &"gunner", "tint": "3f7f8f", "marks": [&"tricorn", &"musket"] },
	&"kade":      { "body": &"gunner", "tint": "4fa8d6", "marks": [&"storm", &"eyepatch", &"musket"] },

	# --- harpooners and the rest of the crew that fights up close ---
	&"bess":      { "body": &"pirate", "tint": "a83f52", "marks": [&"harpoon", &"bandana"] },
	&"finn":      { "body": &"pirate", "tint": "4f8f6a", "marks": [&"harpoon", &"bandana"] },
	&"grull":     { "body": &"golem",  "tint": "8a5a3a", "marks": [&"horns"] },

	# --- sirens: the one family allowed to be pretty ---
	&"sirene":    { "body": &"siren",  "tint": "4fd6c9", "marks": [&"crown"] },
	&"nautica":   { "body": &"siren",  "tint": "3f8fd6", "marks": [&"crown"] },
	&"calypso":   { "body": &"siren",  "tint": "7f6bd6", "marks": [&"crown", &"storm"] },
	&"meredine":  { "body": &"siren",  "tint": "4fc9c0", "marks": [] },
	&"nerida":    { "body": &"siren",  "tint": "5fd6a8", "marks": [] },
	&"coral":     { "body": &"siren",  "tint": "ef7f9d", "marks": [] },
	&"morgause":  { "body": &"siren",  "tint": "a06fd6", "marks": [] },
	&"mira":      { "body": &"siren",  "tint": "7fb8f0", "marks": [&"storm"] },
	&"thalassa":  { "body": &"siren",  "tint": "3fb8d6", "marks": [&"storm"] },
	&"selka":     { "body": &"siren",  "tint": "6fa8c9", "marks": [] },

	# --- the ghost fleet: pale, tattered, lit from inside ---
	&"davy":      { "body": &"ghost",  "tint": "8a6fd6", "marks": [&"crown", &"horns", &"tattered"] },
	&"brine":     { "body": &"ghost",  "tint": "6fd3b8", "marks": [&"tattered"] },
	&"silas":     { "body": &"ghost",  "tint": "8fd6c0", "marks": [&"tattered", &"beard"] },
	&"skarn":     { "body": &"ghost",  "tint": "9eb0c0", "marks": [&"tattered", &"horns"] },
	&"squall":    { "body": &"ghost",  "tint": "7fc9f0", "marks": [&"storm"] },
	&"barnacleking": { "body": &"golem", "tint": "4e7a5e", "marks": [&"crown", &"horns"] },

	# --- leviathans and whatever else came up from under the hull ---
	&"kraken":    { "body": &"kraken", "tint": "6a3f7a", "marks": [&"horns"] },
	&"maelstrom": { "body": &"serpent", "tint": "4f6fd6", "marks": [&"storm", &"horns"] },
	&"hookjaw":   { "body": &"shark",  "tint": "4a7f9e", "marks": [&"hook"] },
	&"dredge":    { "body": &"shark",  "tint": "4a6a52", "marks": [] },
	&"grimscale": { "body": &"shark",  "tint": "6f8f4a", "marks": [&"hook"] },
	&"kelpar":    { "body": &"shark",  "tint": "3f7a5a", "marks": [] },

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
