extends "res://tools/tool_script.gd"

## Writes the champion, trait and item .tres files from the tables below.
##
##   godot --headless --path . --script res://tools/generate_content.gd
##
## A one-time bootstrap, not something to re-run after balancing — it overwrites
## every file it produces, so a number tuned in the inspector is lost. Balance in
## the .tres from here on; come back to this file only to add a *new* champion,
## trait or item, and then delete its entry from the table once it has been
## generated if you would rather not risk the overwrite.
##
## These tables are the port of the old JavaScript build's js/data/*.js. They are
## kept in one place, in the order the game presents them, so a whole tier can be
## read at a glance.

const CHAMPION_DIR := "res://data/champions"
const TRAIT_DIR := "res://data/traits"
const ITEM_DIR := "res://data/items"


func run() -> void:
	rule("Traits")
	for entry in TRAITS:
		_write_trait(entry)
	rule("Items")
	for entry in ITEMS:
		_write_item(entry)
	rule("Champions")
	for entry in CHAMPIONS:
		_write_champion(entry)
	for entry in CREEPS:
		_write_champion(entry)
	rule("Done")
	print("  %d traits, %d items, %d champions (%d monsters)"
		% [TRAITS.size(), ITEMS.size(), CHAMPIONS.size() + CREEPS.size(), CREEPS.size()])


func _save(res: Resource, dir: String, id: StringName) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s.tres" % [dir, id]
	var err := ResourceSaver.save(res, path)
	if err != OK:
		fail("could not write %s (error %d)" % [path, err])
	else:
		print("  %s" % path)


func _write_trait(entry: Dictionary) -> void:
	var def := TraitDef.new()
	def.id = entry["id"]
	def.display_name = entry["name"]
	def.icon = entry["icon"]
	def.kind = entry["kind"]
	def.description = entry["desc"]
	def.breakpoints.assign(entry["breaks"])
	def.values = entry["values"]
	_save(def, TRAIT_DIR, def.id)


func _write_item(entry: Dictionary) -> void:
	var def := ItemDef.new()
	def.id = entry["id"]
	def.display_name = entry["name"]
	def.icon = entry["icon"]
	def.description = entry["desc"]
	def.is_component = entry.get("component", false)
	def.recipe.assign(entry.get("recipe", []))
	_save(def, ITEM_DIR, def.id)


func _write_champion(entry: Dictionary) -> void:
	var def := ChampionDef.new()
	def.id = entry["id"]
	def.display_name = entry["name"]
	def.icon = entry["icon"]
	def.cost = entry["cost"]
	def.traits.assign(entry.get("traits", []))
	def.hp = entry["hp"]
	def.ad = entry["ad"]
	def.attack_speed = entry["as"]
	def.armor = entry["armor"]
	def.magic_resist = entry["mr"]
	def.attack_range = entry["range"]
	def.mana_start = entry["mana"][0]
	def.mana_max = entry["mana"][1]
	def.ability_name = entry.get("ability", "")
	def.ability_desc = entry.get("desc", "")
	def.ability_values = entry.get("values", {})

	# Appearance comes from the same table `assign_art.gd` stamps in, so a
	# champion added here arrives with a face rather than as a default blue
	# pirate that nobody notices until it is on the board.
	var art := ArtTable.lookup(def.id)
	def.art_body = art["body"]
	def.art_tint = Color(art["tint"])
	def.art_marks.assign(art["marks"])

	_save(def, CHAMPION_DIR, def.id)


# =============================================================================
#  TRAITS — Origins are where they hail from, Classes are what they do.
# =============================================================================

const TRAITS := [
	{
		"id": &"corsair", "name": "Corsair", "icon": "🏴", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 4, 6],
		"desc": "Plunder fuels the crew. Your team gains {teamAd}% Attack Damage. Corsairs gain double, plus {crit}% Critical Strike Chance.",
		"values": { &"teamAd": [10, 22, 40], &"crit": [15, 25, 40] },
	},
	{
		"id": &"leviathan", "name": "Leviathan", "icon": "🐙", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 3, 4],
		"desc": "Things older than ships. Leviathans gain {hp} Health and take {dr}% reduced damage.",
		"values": { &"hp": [500, 1000, 1900], &"dr": [8, 14, 24] },
	},
	{
		"id": &"siren", "name": "Siren", "icon": "🧜", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 4, 6],
		"desc": "Songs that drown men. Your team gains {teamAp} Ability Power. Sirens gain {ap} instead and refund {mana} Mana after casting.",
		"values": { &"teamAp": [10, 20, 35], &"ap": [30, 60, 110], &"mana": [10, 20, 30] },
	},
	{
		"id": &"ghost", "name": "Ghost Fleet", "icon": "💀", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 4, 6],
		"desc": "The drowned do not stay down. The first time a Ghost Fleet unit would die it returns after 1.5s with {hp}% Health. At 6, every ally rises once at 30%.",
		"values": { &"hp": [35, 55, 80] },
	},
	{
		"id": &"tidecaller", "name": "Tidecaller", "icon": "🌊", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 3, 4],
		"desc": "The tide mends what steel breaks. Your team heals {hps}% max Health per second. Overhealing becomes a shield, up to {cap}% max Health.",
		"values": { &"hps": [1.2, 2.2, 4], &"cap": [10, 15, 25] },
	},
	{
		"id": &"stormborn", "name": "Stormborn", "icon": "⚡", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 4, 6],
		"desc": "Every 3 seconds, lightning strikes the {n} highest-Health enemies for {dmg} magic damage.",
		"values": { &"n": [1, 2, 4], &"dmg": [180, 380, 850] },
	},
	{
		"id": &"navy", "name": "Royal Navy", "icon": "⚓", "kind": TraitDef.Kind.ORIGIN,
		"breaks": [2, 3, 4, 5],
		"desc": "Discipline holds the line. Your team gains {res} Armor and Magic Resist. Royal Navy units gain double, and recover {heal}% of damage taken over 3s.",
		"values": { &"res": [15, 30, 55, 95], &"heal": [15, 22, 32, 50] },
	},

	{
		"id": &"gunner", "name": "Gunner", "icon": "🔫", "kind": TraitDef.Kind.CLASS,
		"breaks": [2, 4, 6],
		"desc": "Every third attack, Gunners unload {n} extra shots at nearby enemies for {dmg}.",
		"values": { &"n": [2, 3, 5], &"dmg": [45, 60, 80] },
	},
	{
		"id": &"swash", "name": "Swashbuckler", "icon": "🗡", "kind": TraitDef.Kind.CLASS,
		"breaks": [2, 4, 6],
		"desc": "Swashbucklers gain {as}% Attack Speed per attack, stacking 8 times, and have {dodge}% chance to dodge attacks.",
		"values": { &"as": [5, 9, 15], &"dodge": [10, 18, 30] },
	},
	{
		"id": &"bosun", "name": "Bosun", "icon": "💪", "kind": TraitDef.Kind.CLASS,
		"breaks": [2, 4, 6],
		"desc": "Bosuns gain {hp} Health. Your other units gain {team} Health.",
		"values": { &"hp": [350, 750, 1400], &"team": [0, 150, 350] },
	},
	{
		"id": &"harpooner", "name": "Harpooner", "icon": "🪝", "kind": TraitDef.Kind.CLASS,
		"breaks": [2, 4, 6],
		"desc": "Harpooner attacks Rend for 6s, reducing Armor by {shred}%. They deal {bonus}% bonus true damage to Rent enemies.",
		"values": { &"shred": [20, 30, 45], &"bonus": [8, 15, 28] },
	},
	{
		"id": &"navigator", "name": "Navigator", "icon": "🧭", "kind": TraitDef.Kind.CLASS,
		"breaks": [2, 3, 4],
		"desc": "Your team starts with {start} Mana and gains {reg} Mana per second. Navigators also gain {as}% Attack Speed.",
		"values": { &"start": [15, 30, 50], &"reg": [3, 6, 10], &"as": [15, 25, 45] },
	},
	{
		"id": &"reaver", "name": "Reaver", "icon": "🩸", "kind": TraitDef.Kind.CLASS,
		"breaks": [2, 4, 6],
		"desc": "Reavers gain {ov}% Omnivamp and deal {bonus}% bonus damage to enemies below half Health.",
		"values": { &"ov": [12, 22, 40], &"bonus": [15, 28, 50] },
	},
]


# =============================================================================
#  ITEMS — five components, and every one of the fifteen pairs they forge.
# =============================================================================

const ITEMS := [
	{ "id": &"blade", "name": "Corsair's Blade", "icon": "🗡", "component": true,
		"desc": "+10 Attack Damage" },
	{ "id": &"lens", "name": "Sea-Glass Lens", "icon": "🔮", "component": true,
		"desc": "+10 Ability Power" },
	{ "id": &"plate", "name": "Barnacle Plate", "icon": "🛡", "component": true,
		"desc": "+20 Armor, +20 Magic Resist" },
	{ "id": &"keg", "name": "Powder Keg", "icon": "🛢", "component": true,
		"desc": "+12% Attack Speed" },
	{ "id": &"sextant", "name": "Brass Sextant", "icon": "📐", "component": true,
		"desc": "+15 starting Mana" },

	{ "id": &"bloodletter", "name": "The Bloodletter", "icon": "⚔️", "recipe": [&"blade", &"blade"],
		"desc": "+45 Attack Damage. Gain 10 Attack Damage whenever this unit lands a killing blow." },
	{ "id": &"reckoning", "name": "Corsair's Reckoning", "icon": "🗝", "recipe": [&"blade", &"lens"],
		"desc": "+20 Attack Damage, +20 Ability Power, +25% Omnivamp." },
	{ "id": &"ironclad", "name": "Ironclad Cutlass", "icon": "🔨", "recipe": [&"blade", &"plate"],
		"desc": "+15 Attack Damage, +200 Health. At 50% Health, gain a shield equal to 30% max Health and 25% Attack Damage." },
	{ "id": &"rapier", "name": "Rapier of the Reef", "icon": "🏹", "recipe": [&"blade", &"keg"],
		"desc": "+18 Attack Damage. Attacks grant 6% Attack Speed, stacking without limit." },
	{ "id": &"buccaneers_edge", "name": "Buccaneer's Edge", "icon": "🎯", "recipe": [&"blade", &"sextant"],
		"desc": "+15 Attack Damage, +15 Mana. Attacks restore 6 bonus Mana." },
	{ "id": &"abyssal_prism", "name": "Abyssal Prism", "icon": "💎", "recipe": [&"lens", &"lens"],
		"desc": "+80 Ability Power." },
	{ "id": &"coral_aegis", "name": "Coral Aegis", "icon": "🧿", "recipe": [&"lens", &"plate"],
		"desc": "+30 Ability Power, +25 Armor and Magic Resist. Gain a 350 Health shield for the first 10 seconds." },
	{ "id": &"stormglass", "name": "Stormglass", "icon": "🌀", "recipe": [&"lens", &"keg"],
		"desc": "+30 Ability Power, +15% Attack Speed. After casting, gain 40% Attack Speed for 5 seconds." },
	{ "id": &"sirens_locket", "name": "Siren's Locket", "icon": "📿", "recipe": [&"lens", &"sextant"],
		"desc": "+25 Ability Power, +20 Mana. After casting, restore 20 Mana and gain 10 permanent Ability Power." },
	{ "id": &"hull_of_the_deep", "name": "Hull of the Deep", "icon": "🚢", "recipe": [&"plate", &"plate"],
		"desc": "+800 Health. Regenerate 3% max Health per second." },
	{ "id": &"boarding_hooks", "name": "Boarding Hooks", "icon": "⛓️", "recipe": [&"plate", &"keg"],
		"desc": "+250 Health, +12% Attack Speed. Each attack made or taken grants 3 Armor and Magic Resist (max 25 stacks)." },
	{ "id": &"drowned_anchor", "name": "Drowned Anchor", "icon": "⚓", "recipe": [&"plate", &"sextant"],
		"desc": "+300 Health, +20 Mana. After casting, shield this unit and the 2 lowest-Health allies for 300 for 6 seconds." },
	{ "id": &"grapeshot", "name": "Grapeshot Bandolier", "icon": "💥", "recipe": [&"keg", &"keg"],
		"desc": "+45% Attack Speed. Attacks burn the target for 1.5% max Health per second and reduce its healing by 33% for 5s." },
	{ "id": &"windrunner", "name": "Windrunner's Chart", "icon": "🗺", "recipe": [&"keg", &"sextant"],
		"desc": "+15% Attack Speed, +15 Mana. Every third attack chains lightning to 3 enemies for 90 magic damage and shreds 30% Magic Resist for 5s." },
	{ "id": &"krakens_compass", "name": "Kraken's Compass", "icon": "🧭", "recipe": [&"sextant", &"sextant"],
		"desc": "+15 Ability Power, +30 Mana. After casting, restore 30 Mana." },
]


# =============================================================================
#  CHAMPIONS
# =============================================================================

const CHAMPIONS := [
	# --- Tier 1 ---
	{ "id": &"barnaby", "name": "Barnaby Kegg", "icon": "🍺", "cost": 1,
		"traits": [&"bosun", &"corsair"],
		"hp": 700, "ad": 50, "as": 0.6, "armor": 45, "mr": 45, "range": 1, "mana": [30, 70],
		"ability": "Keg Slam",
		"desc": "Slam a powder keg into the deck, dealing {dmg} magic damage to nearby enemies and gaining a {shield} shield.",
		"values": { &"dmg": [160, 240, 400], &"shield": [180, 300, 550] } },
	{ "id": &"pip", "name": "Pip Sparrow", "icon": "🐦", "cost": 1,
		"traits": [&"swash", &"corsair"],
		"hp": 550, "ad": 55, "as": 0.75, "armor": 25, "mr": 25, "range": 1, "mana": [20, 50],
		"ability": "Featherstep",
		"desc": "Skip to the lowest-Health enemy and strike for {dmg}, then gain {as}% Attack Speed for 5 seconds.",
		"values": { &"dmg": [190, 240, 330], &"as": [40, 55, 90] } },
	{ "id": &"saltyjo", "name": "Salty Jo", "icon": "🔫", "cost": 1,
		"traits": [&"gunner", &"corsair"],
		"hp": 500, "ad": 48, "as": 0.7, "armor": 20, "mr": 20, "range": 4, "mana": [20, 55],
		"ability": "Three Barrels",
		"desc": "Fire three shots at the current target for {dmg} each.",
		"values": { &"dmg": [85, 105, 145] } },
	{ "id": &"nerida", "name": "Nerida", "icon": "🧜", "cost": 1,
		"traits": [&"siren", &"tidecaller"],
		"hp": 520, "ad": 38, "as": 0.65, "armor": 20, "mr": 25, "range": 3, "mana": [30, 65],
		"ability": "Salt Balm",
		"desc": "Heal the lowest-Health ally for {heal} and shield them for {shield} for 6 seconds.",
		"values": { &"heal": [220, 340, 600], &"shield": [120, 190, 340] } },
	{ "id": &"grimscale", "name": "Grimscale", "icon": "🐟", "cost": 1,
		"traits": [&"harpooner", &"ghost"],
		"hp": 620, "ad": 52, "as": 0.65, "armor": 35, "mr": 30, "range": 1, "mana": [40, 80],
		"ability": "Gaff Hook",
		"desc": "Drag the farthest enemy to your side, dealing {dmg} magic damage and stunning them for {stun}s.",
		"values": { &"dmg": [140, 210, 340], &"stun": [1, 1.25, 2] } },
	{ "id": &"tuck", "name": "Cap'n Tuck", "icon": "🧭", "cost": 1,
		"traits": [&"navigator", &"navy"],
		"hp": 560, "ad": 42, "as": 0.7, "armor": 30, "mr": 30, "range": 3, "mana": [25, 60],
		"ability": "Chart the Course",
		"desc": "Grant all allies {mana} Mana and {as}% Attack Speed for 6 seconds.",
		"values": { &"mana": [12, 18, 30], &"as": [22, 32, 55] } },
	{ "id": &"brine", "name": "Brine Wraith", "icon": "👻", "cost": 1,
		"traits": [&"ghost", &"reaver"],
		"hp": 600, "ad": 54, "as": 0.65, "armor": 30, "mr": 30, "range": 1, "mana": [30, 60],
		"ability": "Drown the Living",
		"desc": "Deal {dmg} magic damage to the target and heal for {heal}% of the damage dealt.",
		"values": { &"dmg": [200, 300, 520], &"heal": [60, 70, 90] } },
	{ "id": &"marlowe", "name": "Marlowe", "icon": "⚓", "cost": 1,
		"traits": [&"gunner", &"navy"],
		"hp": 540, "ad": 50, "as": 0.65, "armor": 30, "mr": 30, "range": 4, "mana": [30, 60],
		"ability": "Hull-Piercer",
		"desc": "Fire a shot for {dmg} that ignores {pen}% of the target Armor.",
		"values": { &"dmg": [180, 230, 320], &"pen": [50, 60, 85] } },
	{ "id": &"squall", "name": "Squall", "icon": "⚡", "cost": 1,
		"traits": [&"stormborn", &"navigator"],
		"hp": 520, "ad": 40, "as": 0.7, "armor": 20, "mr": 25, "range": 3, "mana": [25, 60],
		"ability": "Forked Sky",
		"desc": "Lightning arcs to {n} enemies, dealing {dmg} magic damage to each.",
		"values": { &"dmg": [140, 210, 380], &"n": [3, 3, 4] } },
	{ "id": &"ned", "name": "Old Anchor Ned", "icon": "🦾", "cost": 1,
		"traits": [&"bosun", &"navy"],
		"hp": 750, "ad": 45, "as": 0.55, "armor": 55, "mr": 55, "range": 1, "mana": [40, 80],
		"ability": "Anchor Down",
		"desc": "Gain a {shield} shield and {res} Armor and Magic Resist for 8 seconds.",
		"values": { &"shield": [250, 400, 750], &"res": [30, 45, 80] } },
	{ "id": &"coral", "name": "Coral", "icon": "🐚", "cost": 1,
		"traits": [&"tidecaller", &"siren"],
		"hp": 540, "ad": 40, "as": 0.65, "armor": 25, "mr": 25, "range": 3, "mana": [40, 80],
		"ability": "Reef Bloom",
		"desc": "Burst coral at the target for {dmg} magic damage to it and adjacent enemies, healing nearby allies for {heal}.",
		"values": { &"dmg": [150, 225, 380], &"heal": [130, 200, 350] } },
	{ "id": &"finn", "name": "Fishgut Finn", "icon": "🪝", "cost": 1,
		"traits": [&"harpooner", &"corsair"],
		"hp": 600, "ad": 55, "as": 0.7, "armor": 30, "mr": 25, "range": 1, "mana": [20, 50],
		"ability": "Gut Hook",
		"desc": "Rip the target for {dmg} as physical damage plus {tr} true damage.",
		"values": { &"dmg": [160, 200, 280], &"tr": [60, 95, 170] } },

	# --- Tier 2 ---
	{ "id": &"isla", "name": "Isla Redmane", "icon": "🗡", "cost": 2,
		"traits": [&"swash", &"corsair"],
		"hp": 620, "ad": 58, "as": 0.8, "armor": 30, "mr": 30, "range": 1, "mana": [10, 40],
		"ability": "Crimson Flurry",
		"desc": "Strike four times for {dmg} each. These strikes can critically strike.",
		"values": { &"dmg": [60, 75, 115] } },
	{ "id": &"doss", "name": "Deadeye Darcy", "icon": "🎯", "cost": 2,
		"traits": [&"gunner", &"reaver"],
		"hp": 560, "ad": 62, "as": 0.65, "armor": 25, "mr": 25, "range": 4, "mana": [40, 80],
		"ability": "Widow's Round",
		"desc": "Fire a slug at the lowest-Health enemy for {dmg}, increased by up to {amp}% based on how wounded they are.",
		"values": { &"dmg": [230, 290, 420], &"amp": [80, 100, 160] } },
	{ "id": &"morgause", "name": "Morgause", "icon": "🎶", "cost": 2,
		"traits": [&"siren", &"stormborn"],
		"hp": 580, "ad": 40, "as": 0.6, "armor": 25, "mr": 30, "range": 3, "mana": [40, 90],
		"ability": "Dirge of the Drowned",
		"desc": "Sing at the densest cluster of enemies, dealing {dmg} magic damage in a wide area.",
		"values": { &"dmg": [280, 420, 780] } },
	{ "id": &"kelpar", "name": "Kelpar", "icon": "🐋", "cost": 2,
		"traits": [&"leviathan", &"tidecaller"],
		"hp": 800, "ad": 50, "as": 0.55, "armor": 45, "mr": 45, "range": 1, "mana": [50, 100],
		"ability": "Whalesong",
		"desc": "Heal all allies for {heal} and deal {dmg} magic damage to adjacent enemies.",
		"values": { &"heal": [180, 270, 480], &"dmg": [140, 210, 380] } },
	{ "id": &"bess", "name": "Bilgewater Bess", "icon": "💪", "cost": 2,
		"traits": [&"bosun", &"harpooner"],
		"hp": 820, "ad": 55, "as": 0.6, "armor": 45, "mr": 40, "range": 1, "mana": [40, 90],
		"ability": "Hook and Slam",
		"desc": "Yank the two nearest enemies in, dealing {dmg} magic damage and stunning them for {stun}s.",
		"values": { &"dmg": [200, 300, 540], &"stun": [1.25, 1.5, 2.5] } },
	{ "id": &"voss", "name": "Quartermaster Voss", "icon": "📦", "cost": 2,
		"traits": [&"navigator", &"navy"],
		"hp": 700, "ad": 45, "as": 0.6, "armor": 40, "mr": 40, "range": 3, "mana": [30, 70],
		"ability": "Resupply",
		"desc": "Shield the three lowest-Health allies for {shield} for 8 seconds and grant them {mana} Mana.",
		"values": { &"shield": [260, 390, 700], &"mana": [15, 22, 40] } },
	{ "id": &"silas", "name": "Drowned Silas", "icon": "💀", "cost": 2,
		"traits": [&"ghost", &"bosun"],
		"hp": 850, "ad": 52, "as": 0.6, "armor": 50, "mr": 45, "range": 1, "mana": [40, 80],
		"ability": "Barnacle Skin",
		"desc": "Gain a {shield} shield, then deal {dmg} magic damage to nearby enemies each second for 3 seconds.",
		"values": { &"shield": [300, 450, 820], &"dmg": [70, 105, 190] } },
	{ "id": &"mira", "name": "Tempest Mira", "icon": "🌩", "cost": 2,
		"traits": [&"stormborn", &"siren"],
		"hp": 570, "ad": 42, "as": 0.65, "armor": 25, "mr": 30, "range": 4, "mana": [30, 70],
		"ability": "Thunderhead",
		"desc": "Call down a bolt for {dmg} magic damage to the target and half that to enemies beside it, shredding {shred}% Magic Resist for 6s.",
		"values": { &"dmg": [260, 390, 700], &"shred": [25, 30, 45] } },
	{ "id": &"hookjaw", "name": "Hookjaw", "icon": "🦈", "cost": 2,
		"traits": [&"harpooner", &"reaver"],
		"hp": 700, "ad": 60, "as": 0.7, "armor": 35, "mr": 30, "range": 1, "mana": [20, 60],
		"ability": "Feeding Frenzy",
		"desc": "Leap at the lowest-Health enemy and bite for {dmg}, healing for {heal}.",
		"values": { &"dmg": [200, 250, 360], &"heal": [180, 270, 480] } },
	{ "id": &"halloway", "name": "Gunny Halloway", "icon": "💣", "cost": 2,
		"traits": [&"gunner", &"navigator"],
		"hp": 580, "ad": 55, "as": 0.75, "armor": 25, "mr": 25, "range": 4, "mana": [20, 55],
		"ability": "Grapeshot",
		"desc": "Spray the three nearest enemies with pellets, hitting each for {dmg} twice.",
		"values": { &"dmg": [70, 90, 130] } },
	{ "id": &"selka", "name": "Selka", "icon": "🐬", "cost": 2,
		"traits": [&"tidecaller", &"swash"],
		"hp": 640, "ad": 54, "as": 0.8, "armor": 30, "mr": 35, "range": 1, "mana": [15, 45],
		"ability": "Dance of Tides",
		"desc": "Strike three times for {dmg}, healing the lowest-Health ally for {heal} with each strike.",
		"values": { &"dmg": [70, 88, 125], &"heal": [80, 120, 210] } },

	# --- Tier 3 ---
	{ "id": &"ravenna", "name": "Captain Ravenna", "icon": "🌹", "cost": 3,
		"traits": [&"corsair", &"swash"],
		"hp": 750, "ad": 70, "as": 0.8, "armor": 35, "mr": 35, "range": 1, "mana": [20, 60],
		"ability": "Blackrose Flourish",
		"desc": "Unleash five cuts for {dmg} each, gaining {crit}% Critical Strike Chance for the rest of combat.",
		"values": { &"dmg": [65, 80, 125], &"crit": [10, 15, 30] } },
	{ "id": &"dredge", "name": "Dredge", "icon": "🦀", "cost": 3,
		"traits": [&"leviathan", &"bosun"],
		"hp": 950, "ad": 65, "as": 0.55, "armor": 55, "mr": 50, "range": 1, "mana": [50, 110],
		"ability": "Crushing Claw",
		"desc": "Crush all enemies within two hexes for {dmg} magic damage, stunning them for {stun}s.",
		"values": { &"dmg": [260, 390, 720], &"stun": [1.25, 1.5, 3] } },
	{ "id": &"corvane", "name": "Admiral Corvane", "icon": "🎖", "cost": 3,
		"traits": [&"navy", &"gunner"],
		"hp": 720, "ad": 68, "as": 0.7, "armor": 35, "mr": 35, "range": 4, "mana": [40, 90],
		"ability": "Broadside",
		"desc": "Fire a full broadside at the four nearest enemies for {dmg} plus {bonus} magic damage.",
		"values": { &"dmg": [120, 150, 210], &"bonus": [80, 120, 220] } },
	{ "id": &"meredine", "name": "Meredine", "icon": "🎼", "cost": 3,
		"traits": [&"siren", &"tidecaller"],
		"hp": 700, "ad": 45, "as": 0.6, "armor": 30, "mr": 40, "range": 3, "mana": [40, 100],
		"ability": "Hymn of the Deep",
		"desc": "Heal all allies for {heal} and grant them {ap} Ability Power for the rest of combat.",
		"values": { &"heal": [300, 450, 850], &"ap": [15, 22, 45] } },
	{ "id": &"skarn", "name": "Skarn the Hollow", "icon": "👁", "cost": 3,
		"traits": [&"ghost", &"harpooner"],
		"hp": 820, "ad": 66, "as": 0.65, "armor": 45, "mr": 40, "range": 1, "mana": [40, 85],
		"ability": "Soul Drag",
		"desc": "Haul the two farthest enemies to you, dealing {dmg} true damage and reducing their Armor by {shred}% for 8s.",
		"values": { &"dmg": [160, 240, 440], &"shred": [30, 40, 60] } },
	{ "id": &"kade", "name": "Bolt-Eye Kade", "icon": "🔭", "cost": 3,
		"traits": [&"stormborn", &"gunner"],
		"hp": 680, "ad": 62, "as": 0.75, "armor": 30, "mr": 30, "range": 4, "mana": [30, 70],
		"ability": "Storm Rounds",
		"desc": "Fire three charged rounds that each deal {dmg} magic damage and arc to a second enemy for half.",
		"values": { &"dmg": [180, 270, 500] } },
	{ "id": &"grull", "name": "Ironbelly Grull", "icon": "🐗", "cost": 3,
		"traits": [&"bosun", &"reaver"],
		"hp": 980, "ad": 68, "as": 0.6, "armor": 50, "mr": 45, "range": 1, "mana": [40, 85],
		"ability": "Gorge",
		"desc": "Heal {heal}% of missing Health and smash nearby enemies for {dmg}.",
		"values": { &"heal": [30, 38, 60], &"dmg": [150, 190, 280] } },
	{ "id": &"sable", "name": "Wavecutter Sable", "icon": "🌊", "cost": 3,
		"traits": [&"navigator", &"swash"],
		"hp": 760, "ad": 66, "as": 0.85, "armor": 35, "mr": 35, "range": 1, "mana": [15, 50],
		"ability": "Wake Cutter",
		"desc": "Cut through the three nearest enemies, dealing {dmg} to each and gaining {as}% Attack Speed for 4s.",
		"values": { &"dmg": [130, 165, 240], &"as": [30, 40, 70] } },
	{ "id": &"thalassa", "name": "Thalassa", "icon": "🌀", "cost": 3,
		"traits": [&"tidecaller", &"stormborn"],
		"hp": 700, "ad": 48, "as": 0.6, "armor": 30, "mr": 40, "range": 4, "mana": [40, 95],
		"ability": "Tidal Surge",
		"desc": "Send a wave through the enemy line, dealing {dmg} magic damage to the target and everything behind it, and healing allies for {heal}.",
		"values": { &"dmg": [270, 400, 760], &"heal": [140, 210, 380] } },

	# --- Tier 4 ---
	{ "id": &"rook", "name": "Blackwater Rook", "icon": "🗡", "cost": 4,
		"traits": [&"corsair", &"reaver"],
		"hp": 850, "ad": 85, "as": 0.85, "armor": 40, "mr": 40, "range": 1, "mana": [20, 55],
		"ability": "Cutthroat",
		"desc": "Vanish and reappear beside the lowest-Health enemy, dealing {dmg}. If this kills them, immediately do it again.",
		"values": { &"dmg": [280, 340, 600] } },
	{ "id": &"sirene", "name": "Queen Sirene", "icon": "👑", "cost": 4,
		"traits": [&"siren", &"navy"],
		"hp": 800, "ad": 50, "as": 0.6, "armor": 40, "mr": 50, "range": 3, "mana": [40, 100],
		"ability": "Sovereign's Song",
		"desc": "Enthrall the three nearest enemies, stunning them for {stun}s and dealing {dmg} magic damage over the duration.",
		"values": { &"stun": [1.5, 1.75, 4], &"dmg": [350, 520, 1100] } },
	{ "id": &"maelstrom", "name": "Maelstrom", "icon": "🌪", "cost": 4,
		"traits": [&"leviathan", &"stormborn"],
		"hp": 1100, "ad": 70, "as": 0.6, "armor": 55, "mr": 55, "range": 2, "mana": [60, 130],
		"ability": "Whirlpool",
		"desc": "Open a vortex that drags all enemies within three hexes inward and deals {dmg} magic damage over 3 seconds.",
		"values": { &"dmg": [450, 675, 1500] } },
	{ "id": &"vance", "name": "Grand Admiral Vance", "icon": "🎖", "cost": 4,
		"traits": [&"navy", &"navigator"],
		"hp": 900, "ad": 70, "as": 0.7, "armor": 50, "mr": 50, "range": 3, "mana": [40, 90],
		"ability": "All Hands",
		"desc": "Shield every ally for {shield} and grant them {as}% Attack Speed for 6s, then bombard the densest cluster for {dmg} magic damage.",
		"values": { &"shield": [250, 375, 700], &"as": [25, 35, 65], &"dmg": [300, 450, 900] } },
	{ "id": &"barnacleking", "name": "The Barnacle King", "icon": "🐚", "cost": 4,
		"traits": [&"ghost", &"bosun"],
		"hp": 1200, "ad": 65, "as": 0.55, "armor": 65, "mr": 60, "range": 1, "mana": [70, 140],
		"ability": "Rise, Drowned Ones",
		"desc": "Raise your most valuable fallen ally at {rev}% Health, heal yourself for {heal}, and crush nearby enemies for {dmg} magic damage.",
		"values": { &"rev": [40, 55, 100], &"heal": [350, 525, 1000], &"dmg": [200, 300, 600] } },
	{ "id": &"lyra", "name": "Longshot Lyra", "icon": "🏹", "cost": 4,
		"traits": [&"gunner", &"corsair"],
		"hp": 750, "ad": 80, "as": 0.75, "armor": 30, "mr": 30, "range": 5, "mana": [30, 75],
		"ability": "Piercing Shot",
		"desc": "Fire a shot that pierces the whole enemy line for {dmg}, ignoring {pen}% Armor.",
		"values": { &"dmg": [230, 285, 460], &"pen": [40, 50, 80] } },
	{ "id": &"kessa", "name": "Bloodtide Kessa", "icon": "🩸", "cost": 4,
		"traits": [&"reaver", &"swash"],
		"hp": 900, "ad": 88, "as": 0.9, "armor": 40, "mr": 40, "range": 1, "mana": [10, 40],
		"ability": "Bloodtide",
		"desc": "Enter a frenzy: strike six times for {dmg}, healing for {ov}% of all damage dealt.",
		"values": { &"dmg": [55, 68, 110], &"ov": [35, 45, 80] } },

	# --- Tier 5 ---
	{ "id": &"kraken", "name": "The Kraken", "icon": "🐙", "cost": 5,
		"traits": [&"leviathan", &"harpooner"],
		"hp": 1400, "ad": 95, "as": 0.6, "armor": 70, "mr": 70, "range": 2, "mana": [50, 120],
		"ability": "Fleetbreaker",
		"desc": "Eight tentacles erupt. Drag every enemy within four hexes inward, dealing {dmg} magic damage and stunning them for {stun}s. Enemies below {ex}% Health are devoured outright.",
		"values": { &"dmg": [500, 750, 4000], &"stun": [1.5, 2, 5], &"ex": [12, 15, 40] } },
	{ "id": &"davy", "name": "Davy Grim", "icon": "💀", "cost": 5,
		"traits": [&"ghost", &"siren"],
		"hp": 1200, "ad": 75, "as": 0.65, "armor": 55, "mr": 60, "range": 3, "mana": [40, 100],
		"ability": "The Locker Opens",
		"desc": "Deal {dmg} magic damage to all enemies. Every ally that dies in the next {dur}s returns at {rev}% Health.",
		"values": { &"dmg": [350, 525, 2000], &"dur": [6, 8, 30], &"rev": [40, 50, 100] } },
	{ "id": &"calypso", "name": "Calypso", "icon": "⛈️", "cost": 5,
		"traits": [&"stormborn", &"tidecaller"],
		"hp": 1150, "ad": 70, "as": 0.65, "armor": 50, "mr": 60, "range": 4, "mana": [40, 110],
		"ability": "Sovereign Storm",
		"desc": "Summon a hurricane for 4 seconds: strike a random enemy for {dmg} magic damage every 0.4s while healing all allies for {heal} per second.",
		"values": { &"dmg": [130, 195, 700], &"heal": [120, 180, 700] } },
	{ "id": &"ashmore", "name": "Blackbeard Ashmore", "icon": "🏴", "cost": 5,
		"traits": [&"corsair", &"gunner", &"reaver"],
		"hp": 1100, "ad": 100, "as": 0.8, "armor": 45, "mr": 45, "range": 3, "mana": [30, 70],
		"ability": "Six Pistols",
		"desc": "Draw six pistols and fire at the lowest-Health enemies for {dmg} each. Kills grant {ad} permanent Attack Damage.",
		"values": { &"dmg": [110, 135, 400], &"ad": [10, 15, 60] } },
	{ "id": &"nautica", "name": "Empress Nautica", "icon": "👑", "cost": 5,
		"traits": [&"navy", &"siren", &"navigator"],
		"hp": 1150, "ad": 70, "as": 0.7, "armor": 60, "mr": 60, "range": 3, "mana": [40, 100],
		"ability": "Flagship Broadside",
		"desc": "The flagship fires: {dmg} magic damage to all enemies in a huge area. Allies gain {res} Armor and Magic Resist and {ap} Ability Power permanently.",
		"values": { &"dmg": [400, 600, 2400], &"res": [25, 35, 120], &"ap": [20, 30, 120] } },
]


# =============================================================================
#  MONSTERS — cost 0, so they never enter the shop or the shared pool.
# =============================================================================

const CREEPS := [
	{ "id": &"rat", "name": "Deck Rat", "icon": "🐀", "cost": 0, "traits": [],
		"hp": 420, "ad": 32, "as": 0.6, "armor": 15, "mr": 15, "range": 1, "mana": [0, 0] },
	{ "id": &"crab", "name": "Hull Crab", "icon": "🦀", "cost": 0, "traits": [],
		"hp": 900, "ad": 45, "as": 0.5, "armor": 40, "mr": 25, "range": 1, "mana": [0, 0] },
	{ "id": &"gull", "name": "Rot Gull", "icon": "🦅", "cost": 0, "traits": [],
		"hp": 550, "ad": 42, "as": 0.7, "armor": 15, "mr": 15, "range": 3, "mana": [0, 0] },
	{ "id": &"serpent", "name": "Reef Serpent", "icon": "🐍", "cost": 0, "traits": [],
		"hp": 1300, "ad": 70, "as": 0.65, "armor": 45, "mr": 45, "range": 2, "mana": [0, 0] },
	{ "id": &"skiff", "name": "Ghost Skiff", "icon": "🛶", "cost": 0, "traits": [],
		"hp": 1100, "ad": 65, "as": 0.7, "armor": 35, "mr": 55, "range": 4, "mana": [0, 0] },
	{ "id": &"golem", "name": "Wreck Golem", "icon": "🗿", "cost": 0, "traits": [],
		"hp": 3200, "ad": 110, "as": 0.55, "armor": 70, "mr": 70, "range": 1, "mana": [0, 0] },
	{ "id": &"elder", "name": "Elder Kraken", "icon": "🐙", "cost": 0, "traits": [],
		"hp": 6000, "ad": 160, "as": 0.7, "armor": 90, "mr": 90, "range": 2, "mana": [0, 0] },
]
