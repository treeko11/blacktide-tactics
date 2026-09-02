extends "res://tools/tool_script.gd"

## Crops and magnifies a PNG, for looking at the art closely.
##
##     Godot --headless --path . --script res://tools/crop.gd -- \
##         --in=shot.png --out=zoom.png --rect=500,380,620,280 --zoom=3
##
## Nearest-neighbour on purpose: the question this answers is "what did the
## renderer actually put there", and a smoothed magnification answers a different
## one.

func run() -> void:
	var source := arg("in")
	var target := arg("out", "user://zoom.png")
	var image := Image.load_from_file(source)
	if image == null:
		fail("Cannot load %s" % source)
		return

	var parts := arg("rect").split(",")
	var rect := Rect2i(Vector2i.ZERO, image.get_size())
	if parts.size() == 4:
		rect = Rect2i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))

	var out := image.get_region(rect)
	var zoom := int(arg("zoom", "3"))
	out.resize(rect.size.x * zoom, rect.size.y * zoom, Image.INTERPOLATE_NEAREST)
	out.save_png(target)
	print("  wrote %s (%dx%d)" % [target, out.get_width(), out.get_height()])
