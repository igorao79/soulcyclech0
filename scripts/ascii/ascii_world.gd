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
const PROP_HOUSE := 9
# Домик городка: те же числа в ascii_props.gdshaderinc (HOUSE_HALF).
const HOUSE_HALF := Vector2(2.1, 1.5)

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
# Полуширина героя по полам пальто: препятствие держит его на этом расстоянии от своей кромки.
const HERO_RADIUS := 0.3
const KEEPER_RADIUS := 0.31 + HERO_RADIUS
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

# Раскладка мира: перекрёсток ASCII-ночи или тропа на острове из первой главы.
var layout := &"crossroads"
var spawn := SPAWN
var keeper := KEEPER
var bell := BELL
var chapel := CHAPEL
var pond_center := POND_CENTER
var pond_radii := POND_RADII
var islet := ISLET
var flower := FLOWER
var pier_rect := PIER_RECT
var routes: Array[Array] = ROUTES
var boulders: Array[Vector3] = BOULDERS
var ruin_walls: Array[Rect2] = RUIN_WALLS
# Поляны без леса: x, z, радиус.
var clearings: Array[Vector3] = [Vector3(60.0, 31.0, 5.5), Vector3(88.0, 22.0, 4.0), Vector3(38.0, 33.0, 5.0)]
var lantern_points: Array[Vector2] = [
	Vector2(55.5, 34.5), Vector2(66.0, 26.0), Vector2(76.0, 26.0),
	Vector2(85.0, 24.5), Vector2(46.5, 31.5), Vector2(60.8, 44.0),
	Vector2(55.4, 51.0), Vector2(60.8, 51.0),
]
var graves: Array[Vector2] = [Vector2(35.0, 30.0), Vector2(38.1, 36.3), Vector2(41.4, 30.5), Vector2(32.0, 36.0)]
# Камни и пни: x, z, размер.
var rocks: Array[Vector3] = [
	Vector3(66.5, 37.0, 0.6), Vector3(79.0, 30.0, 0.2),
	Vector3(49.5, 47.5, 0.9), Vector3(43.5, 47.5, 0.5), Vector3(73.5, 47.5, 0.8),
]
var stumps: Array[Vector3] = [Vector3(52.2, 36.8, 0.5)]
# Каменные домики: x, z, вариант (0..1: ширина, труба, горит ли свет).
var house_points: Array[Vector3] = []
# Городок: центр и радиус, внутри не растёт лес и выровнена земля.
var town := Vector3(-1000.0, -1000.0, 0.0)
var garden_on := true
# Насколько земля поднимается от воды: у тропы к дому это заметный склон.
var shore_rise := 0.0
# Вода не внутри эллипса pond_*, а снаружи: эллипс — остров, вокруг океан.
var island := false
# Весь мир — живая трава, деревья внутри стен редкие, ходить можно только в этом прямоугольнике.
var yard := Rect2()
# Направление взгляда героя при появлении.
var spawn_yaw := 0.0

var texel_size: Vector2i
var heights := PackedFloat32Array()
var prop_grid: Vector2i
var obstacles: Array[Vector3] = []
# Препятствия разложены по клеткам сетки реквизита, которые они накрывают.
var _obstacle_cells := {}
var lanterns := PackedVector3Array()
# Поставленные домики: x, z, полуширина по x (с учётом варианта).
var houses: Array[Vector3] = []
var map_texture: ImageTexture
var prop_texture: ImageTexture

var _noise := FastNoiseLite.new()
var _prop_image: Image
var _random := RandomNumberGenerator.new()


func _init(world_layout: StringName = &"crossroads") -> void:
	layout = world_layout
	if layout == &"island_trail":
		_use_island_trail()
	elif layout == &"temple_yard":
		_use_temple_yard()
	_noise.seed = 79
	_noise.frequency = 0.06
	_random.seed = 4117
	texel_size = Vector2i(SIZE) * TEXELS_PER_METER
	prop_grid = Vector2i(ceili(SIZE.x / PROP_CELL), ceili(SIZE.y / PROP_CELL))
	_build_terrain()
	_build_props()


# Тропа на острове: вокруг открытый океан, от берега снежный склон, тропа через ельник
# в городок с каменными домиками. Улица идёт на север, в её конце библиотека.
func _use_island_trail() -> void:
	var nowhere := Vector2(-1000.0, -1000.0)
	spawn = Vector2(49.0, 45.0)
	spawn_yaw = deg_to_rad(-140.0)
	keeper = nowhere
	bell = nowhere
	flower = nowhere
	islet = nowhere
	pier_rect = Vector4(-10.0, -10.0, -9.0, -9.0)
	# Библиотека — каменное здание с башней в конце улицы, дверью к югу.
	chapel = Vector2(88.0, 9.5)
	island = true
	pond_center = Vector2(74.0, 28.0)
	pond_radii = Vector2(44.0, 26.0)
	routes = [[
		Vector2(49, 45), Vector2(53, 40), Vector2(59, 37), Vector2(64, 33), Vector2(70, 31),
		Vector2(77, 30.5), Vector2(83, 30), Vector2(88, 27.5), Vector2(88, 20), Vector2(88, 14),
	]]
	boulders = [Vector3(43.5, 49.5, 1.6), Vector3(55.5, 49.5, 1.4), Vector3(61.5, 43.5, 1.8)]
	ruin_walls = []
	clearings = [Vector3(49.0, 45.0, 3.5), Vector3(88.0, 14.5, 3.0)]
	town = Vector3(88.0, 20.0, 15.0)
	house_points = [
		Vector3(83.3, 26.0, 0.62), Vector3(92.7, 26.0, 0.83), Vector3(83.3, 19.0, 0.21),
		Vector3(92.7, 19.0, 0.38), Vector3(77.6, 22.5, 0.47), Vector3(98.4, 22.5, 0.95),
	]
	lantern_points = [Vector2(86.0, 29.6), Vector2(90.0, 22.6), Vector2(86.0, 15.4)]
	graves = []
	rocks = [Vector3(66.0, 35.5, 0.5), Vector3(73.0, 31.0, 0.4), Vector3(52.0, 47.0, 0.3)]
	stumps = [Vector3(56.5, 41.5, 0.5)]
	garden_on = false
	shore_rise = 0.8


# Внутренний двор храма летом: на севере главное здание, вдоль боков красные постройки,
# по середине тропа к воротам на юге. Воды нет, вместо Смотрителя — идущий впереди воин.
func _use_temple_yard() -> void:
	var nowhere := Vector2(-1000.0, -1000.0)
	yard = Rect2(47.0, 31.0, 26.0, 45.0)
	spawn = Vector2(60.0, 33.0)
	spawn_yaw = 0.0
	keeper = Vector2(60.0, 36.0)
	bell = nowhere
	flower = nowhere
	islet = nowhere
	pier_rect = Vector4(-10.0, -10.0, -9.0, -9.0)
	chapel = Vector2(60.0, 26.0)
	pond_center = nowhere
	pond_radii = Vector2(1.0, 1.0)
	routes = [[Vector2(60, 30), Vector2(60, 76)]]
	boulders = []
	ruin_walls = []
	clearings = [Vector3(60.0, 33.0, 3.0)]
	house_points = []
	for z in range(36, 78, 7):
		house_points.append(Vector3(44.0, float(z), 0.0))
		house_points.append(Vector3(76.0, float(z), 0.0))
	lantern_points = [Vector2(57.0, 40.0), Vector2(63.0, 40.0), Vector2(57.0, 56.0), Vector2(63.0, 56.0)]
	graves = []
	rocks = [Vector3(52.0, 46.0, 0.5), Vector3(68.0, 62.0, 0.6)]
	stumps = []
	garden_on = true
	shore_rise = 0.0


## Места, с которыми можно говорить или действовать: в главе их нет.
func interactables() -> Dictionary:
	if layout != &"crossroads":
		return {}
	return {&"keeper": keeper, &"bell": bell, &"flower": flower}


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
		point.x >= pier_rect.x
		and point.x <= pier_rect.z
		and point.y >= pier_rect.y
		and point.y <= pier_rect.w
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
	if yard.has_area():
		best = minf(best, minf(
			minf(point.x - yard.position.x, point.y - yard.position.y),
			minf(yard.end.x - point.x, yard.end.y - point.y)
		))
	if not is_on_pier(point):
		best = minf(best, height_at(point) + WADE_DEPTH)
	var cell := Vector2i(floori(point.x / PROP_CELL), floori(point.y / PROP_CELL))
	for obstacle: Vector3 in _obstacle_cells.get(cell, []):
		best = minf(best, point.distance_to(Vector2(obstacle.x, obstacle.y)) - obstacle.z)
	best = minf(best, point.distance_to(keeper) - KEEPER_RADIUS)
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


# Часовня, колокольня, домики и стены руин — прямоугольники со знаковым расстоянием.
func _structure_distance(point: Vector2) -> float:
	var best := _box_distance(point - chapel - Vector2(0.0, 0.2), Vector2(1.9, 2.7))
	best = minf(best, _box_distance(point - bell, Vector2(1.4, 0.8)))
	for house in houses:
		var offset := point - Vector2(house.x, house.y)
		if absf(offset.x) < 6.0 and absf(offset.y) < 5.0:
			best = minf(best, _box_distance(offset, Vector2(house.z, HOUSE_HALF.y)) - HERO_RADIUS)
	return minf(best, _ruin_distance(point))


func _ruin_distance(point: Vector2) -> float:
	var best := 1000.0
	for wall in ruin_walls:
		best = minf(best, _box_distance(point - wall.get_center(), wall.size * 0.5))
	return best


func _box_distance(offset: Vector2, half: Vector2) -> float:
	var outside := offset.abs() - half
	return Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length() + minf(maxf(outside.x, outside.y), 0.0)


func _pond_field(point: Vector2) -> float:
	var offset := (point - pond_center) / pond_radii
	var wobble := _noise.get_noise_2dv(point * 1.4) * 0.22 + _noise.get_noise_2dv(point * 4.5) * 0.09
	return (offset.length() - 1.0 if island else 1.0 - offset.length()) + wobble


func _garden(point: Vector2) -> float:
	if not garden_on:
		return 0.0
	if yard.has_area():
		return 1.0
	var distance := point.distance_to(pond_center + Vector2(0.0, -1.0))
	var wobble := _noise.get_noise_2dv(point * 0.7) * 5.0
	return 1.0 - smoothstep(19.0, 25.0, distance + wobble)


func _route_distance(point: Vector2) -> float:
	var best := 1000.0
	for route in routes:
		for index in range(route.size() - 1):
			var nearest := Geometry2D.get_closest_point_to_segment(point, route[index], route[index + 1])
			best = minf(best, point.distance_to(nearest))
	return best


func _clearing_distance(point: Vector2) -> float:
	var best := 1000.0
	for clearing in clearings:
		best = minf(best, point.distance_to(Vector2(clearing.x, clearing.y)) - clearing.z)
	return best


func _build_terrain() -> void:
	heights.resize(texel_size.x * texel_size.y)
	var image := Image.create_empty(texel_size.x, texel_size.y, false, Image.FORMAT_RGBAH)
	for y in range(texel_size.y):
		for x in range(texel_size.x):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / TEXELS_PER_METER
			var field := _pond_field(point)
			var land := 0.30 + _noise.get_noise_2dv(point) * 0.32 + clampf(-field, 0.0, 2.5) * shore_rise
			var height := lerpf(land, -0.72, smoothstep(-0.12, 0.42, field))
			# Городок стоит на ровной площадке: склон под ним выглажен.
			var in_town := 1.0 - smoothstep(town.z * 0.75, town.z, point.distance_to(Vector2(town.x, town.y)))
			if in_town > 0.0:
				height = lerpf(height, _town_level(), in_town)
			var islet_rise := 1.0 - point.distance_to(islet) / 2.7
			if islet_rise > 0.0:
				height = maxf(height, -0.3 + smoothstep(0.0, 0.8, islet_rise) * 0.72)
			var route := _route_distance(point)
			var path_edge := 1.7 + _noise.get_noise_2dv(point * 2.3) * 0.5
			var path := 1.0 - smoothstep(path_edge - 0.3, path_edge + 0.3, route)
			path = maxf(path, 1.0 - smoothstep(-1.0, 0.5, _clearing_distance(point)))
			heights[y * texel_size.x + x] = height
			image.set_pixel(x, y, Color(height, path, _garden(point), 1.0))
	map_texture = ImageTexture.create_from_image(image)


# Высота площадки городка: склон в его центре без мелкого шума.
func _town_level() -> float:
	var field := _pond_field(Vector2(town.x, town.y))
	return 0.30 + clampf(-field, 0.0, 2.5) * shore_rise


func _build_props() -> void:
	_prop_image = Image.create_empty(prop_grid.x, prop_grid.y, false, Image.FORMAT_RGBA8)
	_prop_image.fill(Color(0, 0, 0, 0.5))

	# Сначала фиксированные ориентиры, затем лес заполняет оставшиеся клетки.
	for lantern_point in lantern_points:
		var placed := _place(PROP_LANTERN, lantern_point, 0.5)
		# Источник поднят над головой фонаря: пятно света слабее и не выжигает снег.
		lanterns.append(Vector3(placed.x, 2.7, placed.y))

	# Свет из окон и двери часовни ложится на снег перед ней.
	# Источник вынесен вперёд, иначе камень фасада заливает оранжевым.
	lanterns.append(Vector3(chapel.x, 1.6, chapel.y + 7.5))

	for house_point in house_points:
		var center := _place(PROP_HOUSE, Vector2(house_point.x, house_point.y), house_point.z)
		var width := lerpf(0.86, 1.12, fposmod(house_point.z * 7.3, 1.0))
		houses.append(Vector3(center.x, center.y, HOUSE_HALF.x * width))
		# Свет из окон ложится на снег перед домом, если в доме не спят.
		if fposmod(house_point.z * 13.7, 1.0) > 0.3:
			lanterns.append(Vector3(center.x - HOUSE_HALF.x * width * 0.18, 1.4, center.y + HOUSE_HALF.y + 2.0))

	for grave_point in graves:
		_place(PROP_GRAVE, grave_point, 0.5)
	for rock in rocks:
		_place(PROP_ROCK, Vector2(rock.x, rock.y), rock.z)
	for stump in stumps:
		_place(PROP_STUMP, Vector2(stump.x, stump.y), stump.z)

	for boulder in boulders:
		var scale := clampf((boulder.z - 1.1) / 1.7, 0.0, 1.0)
		_place(PROP_BOULDER, Vector2(boulder.x, boulder.y), scale)

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
	if point.distance_to(chapel) < 6.5 or point.distance_to(bell) < 3.5:
		return
	# В городке леса нет, только редкие молодые ели во дворах; к стенам деревья не жмутся.
	if not houses.is_empty() and _near_house(point) < 2.4:
		return
	if point.distance_to(Vector2(town.x, town.y)) < town.z - 1.0:
		if _random.randf() < 0.14 and _near_house(point) > 3.4:
			_place(PROP_PINE, point, _random.randf() * 0.4)
		return
	if _ruin_distance(point) < 2.2:
		return
	for boulder in boulders:
		if point.distance_to(Vector2(boulder.x, boulder.y)) < boulder.z + 1.0:
			return

	var garden := _garden(point)
	var scale := _random.randf()
	if yard.has_point(point):
		# Внутри стен ухоженный сад: редкие деревья и кусты, тропа открыта.
		if keep_out < 2.0:
			return
		var pick := _random.randf()
		if pick < 0.07:
			_place(PROP_TREE, point, scale)
		elif pick < 0.14:
			_place(PROP_BUSH, point, scale)
	elif garden > 0.5:
		var roll := _random.randf()
		if roll < 0.28:
			_place(PROP_TREE, point, scale)
		elif roll < 0.50:
			_place(PROP_PINE, point, scale * 0.6)
		elif roll < 0.74:
			_place(PROP_BUSH, point, scale)
	else:
		var density := 0.74 + _noise.get_noise_2dv(point * 0.6) * 0.5
		if keep_out > 7.0:
			density = 1.0
		if _random.randf() < density:
			_place(PROP_PINE, point, scale)


func _near_house(point: Vector2) -> float:
	var best := 1000.0
	for house in houses:
		best = minf(best, _box_distance(point - Vector2(house.x, house.y), Vector2(house.z, HOUSE_HALF.y)))
	return minf(best, _route_distance(point) - 1.2)


func _place(kind: int, point: Vector2, scale: float) -> Vector2:
	var collision_radius := _collision_radius(kind, scale)
	var cell := Vector2i(floori(point.x / PROP_CELL), floori(point.y / PROP_CELL))
	var offset := (point / PROP_CELL - Vector2(cell) - Vector2(0.5, 0.5)) / PROP_JITTER
	var encoded := (offset + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	_prop_image.set_pixelv(cell, Color(kind / 255.0, encoded.x, encoded.y, scale))
	var center := (Vector2(cell) + Vector2(0.5, 0.5) + (encoded - Vector2(0.5, 0.5)) * PROP_JITTER) * PROP_CELL
	var obstacle := Vector3(center.x, center.y, collision_radius)
	obstacles.append(obstacle)
	# Препятствие записано во все клетки, которые накрывает: проверка смотрит только свою клетку.
	var low := Vector2i(((center - Vector2.ONE * collision_radius) / PROP_CELL).floor())
	var high := Vector2i(((center + Vector2.ONE * collision_radius) / PROP_CELL).floor())
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var key := Vector2i(x, z)
			if not _obstacle_cells.has(key):
				_obstacle_cells[key] = []
			_obstacle_cells[key].append(obstacle)
	return center


# Радиус столкновения повторяет размеры из sd_props в ascii_props.gdshaderinc
# и добавляет полуширину героя: так фигура не заходит в предмет, а встаёт вплотную.
func _collision_radius(kind: int, scale: float) -> float:
	match kind:
		PROP_BOULDER:
			# Валун шире всего на высоте пояса, неровности выпирают ещё на ~0.2.
			return 1.1 + scale * 1.7 + 0.15 + HERO_RADIUS
		PROP_ROCK:
			return 0.5 + scale * 0.4 + 0.1 + HERO_RADIUS
		PROP_BUSH:
			# Куст мягкий: полы пальто чуть заходят в листву.
			return 0.72 + scale * 0.3 + HERO_RADIUS * 0.5
		PROP_PINE:
			# Нижний ярус хвои висит на высоте груди.
			return (1.0 + scale * 0.45) * 0.55 + HERO_RADIUS
		PROP_TREE:
			return 0.13 + HERO_RADIUS
		PROP_LANTERN:
			return 0.05 + HERO_RADIUS
		PROP_GRAVE:
			return 0.42 + HERO_RADIUS * 0.6
		PROP_STUMP:
			return 0.32 + HERO_RADIUS
		PROP_HOUSE:
			# Дом не пускает героя своей коробкой в _structure_distance.
			return 0.0
	return HERO_RADIUS
