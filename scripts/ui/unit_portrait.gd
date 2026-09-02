class_name UnitPortrait
extends Control

## A champion's figure at a fixed size, for everywhere that is not the board.
##
## The shop is where a pirate is actually chosen, and it was the last place still
## identifying one by an emoji — which is what the whole roster used to be, and
## the reason nobody could tell a siren from a sea serpent before buying it. This
## puts the same figure the board draws onto the card.
##
## **It is a Control wrapping a Node2D, and that is not incidental.** `UnitArt`
## positions everything with `draw_set_transform`, which *replaces* a CanvasItem's
## draw transform rather than composing with it — so a figure cannot be moved or
## scaled by the thing drawing it, only by the node it is drawn into. The board
## gives each unit its own Node2D for exactly this reason; so does this.
##
## Sizing is by `custom_minimum_size`, so it drops into a container where a Label
## used to be without changing the shape of anything around it.

## The space a figure occupies at scale 1: hat to ground plate, arms out.
const ART_BOX := Vector2(52.0, 66.0)

var champion: ChampionDef = null:
	set(value):
		champion = value
		if _figure != null:
			_figure.champion = value
			_figure.queue_redraw()

## Team colour for the ground plate. The shop shows pirates nobody owns yet, so
## it uses the cost colour for both and the plate reads as the tier.
var team_color: Color = UITheme.MUTED:
	set(value):
		team_color = value
		if _figure != null:
			_figure.team_color = value

var rim_color: Color = UITheme.MUTED:
	set(value):
		rim_color = value
		if _figure != null:
			_figure.rim_color = value

## Breathes if true. Cheap — one node redrawn 24 times a second — but pointless
## on a page that is not being looked at, like a printed almanac entry.
var animate: bool = true

var _figure: Figure = null
var _accum: float = 0.0


func _init(box: Vector2 = Vector2(30.0, 34.0)) -> void:
	custom_minimum_size = box
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_figure = Figure.new()
	add_child(_figure)
	resized.connect(_fit)


func _ready() -> void:
	_figure.champion = champion
	_figure.team_color = team_color
	_figure.rim_color = rim_color
	set_process(animate)
	_fit()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < UnitView.IDLE_FRAME:
		return
	_figure.pose.clock += _accum
	_accum = 0.0
	_figure.queue_redraw()


## Fits the figure into whatever box the container settled on, and stands it on
## the bottom of that box rather than centring it — a figure hovering in the
## middle of a card reads as floating.
func _fit() -> void:
	if _figure == null:
		return
	var box: Vector2 = size if size.x > 1.0 else custom_minimum_size
	var factor: float = minf(box.x / ART_BOX.x, box.y / ART_BOX.y)
	_figure.scale = Vector2(factor, factor)
	_figure.position = Vector2(box.x * 0.5, box.y - UnitArt.GROUND * factor * 1.15)
	# Small enough that trim is a smudge; the figure keeps its silhouette.
	_figure.pose.detail = clampf(factor * 1.2, 0.0, 1.0)
	_figure.queue_redraw()


# =============================================================================

## The figure itself. Its own node, because that is the only thing that can move
## a drawing `UnitArt` has positioned.
class Figure extends Node2D:

	var champion: ChampionDef = null
	var pose := UnitArt.Pose.new()
	var team_color: Color = UITheme.MUTED
	var rim_color: Color = UITheme.MUTED

	func _draw() -> void:
		if champion == null:
			return
		UnitArt.draw_unit(self, champion.art_body, champion.art_tint,
			champion.art_marks, pose, team_color, rim_color)
