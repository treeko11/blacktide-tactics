class_name Hex
extends RefCounted

## Board geometry. Odd-r offset layout, pointy-top hexes.
##
## The board is 7 columns by 8 rows. Rows 0-3 are the enemy half, rows 4-7 are
## the player's. A fight mirrors the opponent's board onto the top half, so both
## sides author their formation in the same coordinate space and only the sim
## knows they were flipped.
##
## Everything here is static and pure: no board state, no nodes. The sim reasons
## in (col, row) and only ever asks this for a pixel position when it has
## something to draw.

const COLS := 7
const ROWS := 8
const PLAYER_ROW_MIN := 4

const HEX_W := 70.0   ## corner-to-corner width of a pointy-top hex
const HEX_H := 80.0   ## point-to-point height
const V_SPACE := 60.0 ## vertical distance between row centres (0.75 * HEX_H)

## Neighbour offsets differ between even and odd rows in an offset layout, which
## is the whole reason cube coordinates exist further down this file.
const NEIGHBOURS_EVEN: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const NEIGHBOURS_ODD: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1),
]


static func board_size() -> Vector2:
	return Vector2(COLS * HEX_W + HEX_W * 0.5, (ROWS - 1) * V_SPACE + HEX_H)


## Pixel centre of a cell, relative to the top-left of the board.
static func to_pixel(cell: Vector2i) -> Vector2:
	var odd := 1 if cell.y % 2 != 0 else 0
	return Vector2(
		cell.x * HEX_W + odd * HEX_W * 0.5 + HEX_W * 0.5,
		cell.y * V_SPACE + HEX_H * 0.5
	)


## Nearest cell to a pixel position, whether or not it is on the board.
static func from_pixel(pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in ROWS:
		for c in COLS:
			var d := pos.distance_squared_to(to_pixel(Vector2i(c, r)))
			if d < best_d:
				best_d = d
				best = Vector2i(c, r)
	return best


static func on_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


static func is_player_half(cell: Vector2i) -> bool:
	return cell.y >= PLAYER_ROW_MIN


## Offset coordinates to cube, so distance is a straight subtraction.
static func to_cube(cell: Vector2i) -> Vector3i:
	@warning_ignore("integer_division")
	var x := cell.x - (cell.y - (cell.y & 1)) / 2
	var z := cell.y
	return Vector3i(x, -x - z, z)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var ca := to_cube(a)
	var cb := to_cube(b)
	return (absi(ca.x - cb.x) + absi(ca.y - cb.y) + absi(ca.z - cb.z)) / 2


static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var table := NEIGHBOURS_ODD if cell.y % 2 != 0 else NEIGHBOURS_EVEN
	for d in table:
		var n := cell + d
		if on_board(n):
			out.append(n)
	return out


## Every cell within `radius` of a cell. Excludes the origin unless asked.
static func in_range(cell: Vector2i, radius: int, include_self: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in ROWS:
		for c in COLS:
			var other := Vector2i(c, r)
			if other == cell and not include_self:
				continue
			if distance(cell, other) <= radius:
				out.append(other)
	return out


## Mirrors a cell onto the opposite half, used to seat the opposing fleet.
static func mirror(cell: Vector2i) -> Vector2i:
	return Vector2i(COLS - 1 - cell.x, ROWS - 1 - cell.y)


## Stable integer key for a cell, for occupancy dictionaries.
static func key(cell: Vector2i) -> int:
	return cell.y * COLS + cell.x


## Seats in the given rows, filled from the middle of each row outward, so a
## small board still meets in the centre rather than hugging one flank. The
## rows are taken in the order given: a fleet fields melee through [4, 5] and
## ranged through [7, 6], which is the player's half read front-to-back.
static func seats(rows: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in rows:
		for col in [3, 2, 4, 1, 5, 0, 6]:
			out.append(Vector2i(col, row))
	return out
