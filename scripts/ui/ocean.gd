class_name Ocean
extends ColorRect

## The water behind the hex grid.
##
## One full-panel rect with `shaders/ocean.gdshader` on it, drawn *behind* its own
## parent — `show_behind_parent`, because a CanvasItem paints itself before its
## children and BoardView draws the grid in its own `_draw`. Without that flag the
## sea would be over the board rather than under it.
##
## **It must never take a click.** `Control.mouse_filter` defaults to STOP, so a
## rect laid over the whole board panel is, by default, an invisible sheet that
## eats every press meant for the board: no dragging a pirate, no dropping an
## item, no inspecting anything. That is the toast bug in a place with a bigger
## blast radius, and `test_hud.gd` checks for it rather than trusting this
## comment.

const SHADER_PATH := "res://shaders/ocean.gdshader"

## Board units per screen unit for the wave field. Tuned so a crest is roughly a
## third of a hex across at desktop scale — big enough to read as water, small
## enough not to read as a gradient.
const WAVE_DENSITY := 0.009


func _ready() -> void:
	# The one line this class exists to guarantee.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = UITheme.BG

	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		# A missing shader leaves a flat dark panel, which is the old board.
		# Worth surviving: a broken sea should not be a broken game.
		push_warning("Ocean: %s did not load; falling back to flat water" % SHADER_PATH)
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	# A deliberately narrow range. The board has to stay readable through this —
	# the first tuning ran deep-to-shallow across four stops of brightness and
	# the grid disappeared into what looked like upholstery.
	mat.set_shader_parameter("deep_color", Color("05141d"))
	mat.set_shader_parameter("shallow_color", Color("0a2231"))
	mat.set_shader_parameter("foam_color", UITheme.FOAM)
	material = mat

	resized.connect(_fit_field)
	_fit_field()


## The wave field is sized from the panel so the swell keeps its scale when the
## panel does not — a phone turned sideways changes this control's shape
## completely, and waves stretched with it would read as a different sea.
func _fit_field() -> void:
	if material == null:
		return
	(material as ShaderMaterial).set_shader_parameter("field", size * WAVE_DENSITY)
