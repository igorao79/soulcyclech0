class_name SoulcycleAsciiWorld
extends RefCounted

const SIZE := Vector2(120.0, 90.0)
const TEXELS_PER_METER := 2
const PROP_CELL := 3.0
const PROP_JITTER := 0.7

const PROP_PINE := 1
const PROP_TREE := 2
const PROP_BUSH := 3
const PROP_LANTERN := 4
const PROP_GRAVE := 5
const PROP_ROCK := 6
const PROP_STUMP := 7
const PROP_BOULDER := 8

const SPAWN := Vector2(60.0, 33.0)
const KEEPER := Vector2(64.5, 30.5)
const BELL := Vector2(55.5, 27.0)
const CHAPEL := Vector2(88.0, 16.0)
const POND_CENTER := Vector2(58.0, 65.0)
const POND_RADII := Vector2(14.0, 9.0)
const ISLET := Vector2(58.0, 66.5)
const FLOWER := Vector2(58.0, 67.2)
const PIER_RECT := Vector4(57.2, 52.5, 58.8, 64.6)
const PIER_TOP := 0.42
const WADE_DEPTH := 0.26
# Смотритель стоит на месте и тоже препятствие: сквозь него не пройти.
const KEEPER_RADIUS := 0.55
const NORMAL_PROBE := 0.04

# Именно Array[Array]: в Array[PackedVector2Array] внутренний литерал при обходе становится пустым,
# и тропы молча исчезают из мира.
const ROUTES: Array[Array] = [
	# От перекрёстка к часовне, к кладбищу и вниз, к чёрной воде.
	[Vector2(60, 31), Vector2(72, 26), Vector2(82, 22), Vector2(88, 20)],
	[Vector2(60, 31), Vector2(48, 28), Vector2(38, 33)],
	[Vector2(60, 31), Vector2(58, 43), Vector2(58, 53)],
]

# Скалы у пруда и по краю ложбины: x, z, радиус. Центр лучше держать рядом с центром клетки сетки.
const BOULDERS: Array[Vector3] = [
	Vector3(46.5, 55.5, 2.0), Vector3(43.5, 58.5, 1.5),
	Vector3(70.5, 58.5, 2.3), Vector3(70.5, 64.5, 1.8), Vector3(70.5, 70.5, 2.1),
	Vector3(43.5, 70.5, 2.3), Vector3(46.5, 73.5, 1.5),
	Vector3(64.5, 52.5, 1.5),
	Vector3(40.5, 49.5, 2.2), Vector3(76.5, 52.5, 2.4), Vector3(79.5, 64.5, 2.0),
	Vector3(37.5, 61.5, 2.0), Vector3(52.5, 79.5, 2.2), Vector3(67.5, 79.5, 1.8),
]
# Руины на северном краю ложбины, тропа проходит в разрыв между башнями.
# Те же числа в ascii_props.gdshaderinc (RUIN_*).
const RUIN_WALLS: Array[Rect2] = [
	Rect2(44.0, 45.45, 10.2, 1.1), Rect2(62.0, 45.45, 10.5, 1.1),
	Rect2(53.4, 45.2, 1.6, 1.6), Rect2(61.2, 45.2, 1.6, 1.6),
]

var texel_size: Vector2i
var heights := PackedFloat32Array()
var prop_grid: Vector2i
var obstacles: Array[Vector3] = []
# Препятствия разложены по клеткам сетки реквизита: проверяются только соседние клетки.
var _obstacle_cells := {}
var lanterns := PackedVector3Array()
var map_texture: ImageTexture
var prop_texture: ImageTexture

var _noise := FastNoiseLite.new()
var _prop_image: Image
var _random := RandomNumberGenerator.new()


func _init() -> void:
	_noise.seed = 79
	_noise.frequency = 0.06
	_random.seed = 4117
	texel_size = Vector2i(SIZE) * TEXELS_PER_METER
	prop_grid = Vector2i(ceili(SIZE.x / PROP_CELL), ceili(SIZE.y / PROP_CELL))
	_build_terrain()
	_build_props()


func height_at(point: Vector2) -> float:
	var fx := clampf(point.x * TEXELS_PER_METER - 0.5, 0.0, texel_size.x - 1.001)
	var fy := clampf(point.y * TEXELS_PER_METER - 0.5, 0.0, texel_size.y - 1.001)
	var x := int(fx)
	var y := int(fy)
	var tx := fx - x
	var ty := fy - y
	var a := heights[y * texel_size.x + x]
	var b := heights[y * texel_size.x + x + 1]
	var c := heights[(y + 1) * texel_size.x + x]
	var d := heights[(y + 1) * texel_size.x + x + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func is_on_pier(point: Vector2) -> bool:
	return (
		point.x >= PIER_RECT.x
		and point.x <= PIER_RECT.z
		and point.y >= PIER_RECT.y
		and point.y <= PIER_RECT.w
	)


func stand_height(point: Vector2) -> float:
	return PIER_TOP if is_on_pier(point) else height_at(point)


func can_stand(point: Vector2) -> bool:
	return clearance(point) >= 0.0


# Поле расстояний до всего, что не пускает героя: меньше нуля — точка занята.
# Глубокая вода входит сюда глубиной, а не расстоянием: для отталкивания хватает знака и уклона.
func clearance(point: Vector2) -> float:
	var best := minf(
		minf(point.x - 2.0, point.y - 2.0),
		minf(SIZE.x - 2.0 - point.x, SIZE.y - 2.0 - point.y)
	)
	if not is_on_pier(point):
		best = minf(best, height_at(point) + WADE_DEPTH)
	var cell := Vector2i(floori(point.x / PROP_CELL), floori(point.y / PROP_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for obstacle: Vector3 in _obstacle_cells.get(cell + Vector2i(dx, dz), []):
				best = minf(best, point.distance_to(Vector2(obstacle.x, obstacle.y)) - obstacle.z)
	best = minf(best, point.distance_to(KEEPER) - KEEPER_RADIUS)
	return minf(best, _structure_distance(point))


# Направление наружу из препятствия: градиент поля расстояний.
func clearance_gradient(point: Vector2) -> Vector2:
	var dx := Vector2(NORMAL_PROBE, 0.0)
	var dz := Vector2(0.0, NORMAL_PROBE)
	return Vector2(
		clearance(point + dx) - clearance(point - dx),
		clearance(point + dz) - clearance(point - dz)
	) / (2.0 * NORMAL_PROBE)


# Выталкивает точку из препятствия на его границу, как шаг Ньютона по полю расстояний.
# Если вытолкнуть не удалось (край мостков, острый угол), возвращает исходную точку.
func push_out(point: Vector2) -> Vector2:
	var result := point
	for attempt in range(4):
		var depth := clearance(result)
		if depth >= 0.0:
			return result
		var gradient := clearance_gradient(result)
		if gradient.length_squared() < 0.0001:
			break
		result += gradient.normalized() * (-depth / maxf(gradient.length(), 0.25) + 0.002)
	return result if can_stand(result) else point


func is_water(point: Vector2) -> bool:
	return not is_on_pier(point) and height_at(point) < 0.0


func surface_at(point: Vector2) -> StringName:
	if is_on_pier(point):
		return &"wood"
	if _garden(point) > 0.5:
		return &"ground"
	return &"snow"


# Часовня, колокольня и стены руин — прямоугольники со знаковым расстоянием.
func _structure_distance(point: Vector2) -> float:
	var best := _box_distance(point - CHAPEL - Vector2(0.0, 0.2), Vector2(1.9, 2.7))
	best = minf(best, _box_distance(point - BELL, Vector2(1.4, 0.8)))
	return minf(best, _ruin_distance(point))


func _ruin_distance(point: Vector2) -> float:
	var best := 1000.0
	for wall in RUIN_WALLS:
		best = minf(best, _box_distance(point - wall.get_center(), wall.size * 0.5))
	return best


func _box_distance(offset: Vector2, half: Vector2) -> float:
	var outside := offset.abs() - half
	return Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length() + minf(maxf(outside.x, outside.y), 0.0)


func _pond_field(point: Vector2) -> float:
	var offset := (point - POND_CENTER) / POND_RADII
	var wobble := _noise.get_noise_2dv(point * 1.4) * 0.22 + _noise.get_noise_2dv(point * 4.5) * 0.09
	return 1.0 - offset.length() + wobble


func _garden(point: Vector2) -> float:
	var distance := point.distance_to(POND_CENTER + Vector2(0.0, -1.0))
	var wobble := _noise.get_noise_2dv(point * 0.7) * 5.0
	return 1.0 - smoothstep(19.0, 25.0, distance + wobble)


func _route_distance(point: Vector2) -> float:
	var best := 1000.0
	for route in ROUTES:
		for index in range(route.size() - 1):
			var nearest := Geometry2D.get_closest_point_to_segment(point, route[index], route[index + 1])
			best = minf(best, point.distance_to(nearest))
	return best


func _clearing_distance(point: Vector2) -> float:
	return minf(
		point.distance_to(Vector2(60.0, 31.0)) - 5.5,
		minf(point.distance_to(Vector2(88.0, 22.0)) - 4.0, point.distance_to(Vector2(38.0, 33.0)) - 5.0)
	)


func _build_terrain() -> void:
	heights.resize(texel_size.x * texel_size.y)
	var image := Image.create_empty(texel_size.x, texel_size.y, false, Image.FORMAT_RGBAH)
	for y in range(texel_size.y):
		for x in range(texel_size.x):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / TEXELS_PER_METER
			var field := _pond_field(point)
			var land := 0.30 + _noise.get_noise_2dv(point) * 0.32
			var height := lerpf(land, -0.72, smoothstep(-0.12, 0.42, field))
			var islet := 1.0 - point.distance_to(ISLET) / 2.7
			if islet > 0.0:
				height = maxf(height, -0.3 + smoothstep(0.0, 0.8, islet) * 0.72)
			var route := _route_distance(point)
			var path_edge := 1.7 + _noise.get_noise_2dv(point * 2.3) * 0.5
			var path := 1.0 - smoothstep(path_edge - 0.3, path_edge + 0.3, route)
			path = maxf(path, 1.0 - smoothstep(-1.0, 0.5, _clearing_distance(point)))
			heights[y * texel_size.x + x] = height
			image.set_pixel(x, y, Color(height, path, _garden(point), 1.0))
	map_texture = ImageTexture.create_from_image(image)


func _build_props() -> void:
	_prop_image = Image.create_empty(prop_grid.x, prop_grid.y, false, Image.FORMAT_RGBA8)
	_prop_image.fill(Color(0, 0, 0, 0.5))

	# Сначала фиксированные ориентиры, затем лес заполняет оставшиеся клетки.
	for lantern_point: Vector2 in [
		Vector2(55.5, 34.5), Vector2(66.0, 26.0), Vector2(76.0, 26.0),
		Vector2(85.0, 24.5), Vector2(46.5, 31.5), Vector2(60.8, 44.0),
		Vector2(55.4, 51.0), Vector2(60.8, 51.0),
	]:
		var placed := _place(PROP_LANTERN, lantern_point, 0.5, 0.28)
		# Источник поднят над головой фонаря: пятно света слабее и не выжигает снег.
		lanterns.append(Vector3(placed.x, 2.7, placed.y))

	# Свет из окон и двери часовни ложится на снег перед ней.
	# Источник вынесен вперёд, иначе камень фасада заливает оранжевым.
	lanterns.append(Vector3(CHAPEL.x, 1.6, CHAPEL.y + 7.5))

	for grave_point: Vector2 in [
		Vector2(35.0, 30.0), Vector2(38.1, 36.3), Vector2(41.4, 30.5), Vector2(32.0, 36.0),
	]:
		_place(PROP_GRAVE, grave_point, 0.5, 0.45)
	_place(PROP_ROCK, Vector2(66.5, 37.0), 0.6, 0.65)
	_place(PROP_STUMP, Vector2(52.2, 36.8), 0.5, 0.4)
	_place(PROP_ROCK, Vector2(79.0, 30.0), 0.2, 0.55)
	# Обломки у подножия руин.
	_place(PROP_ROCK, Vector2(49.5, 47.5), 0.9, 0.65)
	_place(PROP_ROCK, Vector2(43.5, 47.5), 0.5, 0.55)
	_place(PROP_ROCK, Vector2(73.5, 47.5), 0.8, 0.6)

	for boulder in BOULDERS:
		var scale := clampf((boulder.z - 1.1) / 1.7, 0.0, 1.0)
		_place(PROP_BOULDER, Vector2(boulder.x, boulder.y), scale, boulder.z * 0.9)

	for cell_y in range(prop_grid.y):
		for cell_x in range(prop_grid.x):
			var cell := Vector2i(cell_x, cell_y)
			if _prop_image.get_pixelv(cell).r > 0.0:
				continue
			_try_forest(cell)

	prop_texture = ImageTexture.create_from_image(_prop_image)


func _try_forest(cell: Vector2i) -> void:
	var jitter := Vector2(_random.randf_range(-0.5, 0.5), _random.randf_range(-0.5, 0.5))
	var point := (Vector2(cell) + Vector2(0.5, 0.5) + jitter * PROP_JITTER) * PROP_CELL
	var keep_out := minf(_route_distance(point) - 2.5, _clearing_distance(point) - 1.2)
	if keep_out < 0.0 or _pond_field(point) > -0.22:
		return
	if point.distance_to(CHAPEL) < 6.5 or point.distance_to(BELL) < 3.5:
		return
	if _ruin_distance(point) < 2.2:
		return
	for boulder in BOULDERS:
		if point.distance_to(Vector2(boulder.x, boulder.y)) < boulder.z + 1.0:
			return

	var garden := _garden(point)
	var scale := _random.randf()
	if garden > 0.5:
		var roll := _random.randf()
		if roll < 0.28:
			_place(PROP_TREE, point, scale, 0.42)
		elif roll < 0.50:
			_place(PROP_PINE, point, scale * 0.6, 0.45)
		elif roll < 0.74:
			_place(PROP_BUSH, point, scale, 0.65)
	else:
		var density := 0.74 + _noise.get_noise_2dv(point * 0.6) * 0.5
		if keep_out > 7.0:
			density = 1.0
		if _random.randf() < density:
			_place(PROP_PINE, point, scale, 0.45)


func _place(kind: int, point: Vector2, scale: float, collision_radius: float) -> Vector2:
	var cell := Vector2i(floori(point.x / PROP_CELL), floori(point.y / PROP_CELL))
	var offset := (point / PROP_CELL - Vector2(cell) - Vector2(0.5, 0.5)) / PROP_JITTER
	var encoded := (offset + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	_prop_image.set_pixelv(cell, Color(kind / 255.0, encoded.x, encoded.y, scale))
	var center := (Vector2(cell) + Vector2(0.5, 0.5) + (encoded - Vector2(0.5, 0.5)) * PROP_JITTER) * PROP_CELL
	var obstacle := Vector3(center.x, center.y, collision_radius)
	obstacles.append(obstacle)
	if not _obstacle_cells.has(cell):
		_obstacle_cells[cell] = []
	_obstacle_cells[cell].append(obstacle)
	return center
