class_name SoulcycleWinterMap
extends Node2D

const TERRAIN_ATLAS := preload("res://assets/tiles/winter_terrain.png")
const PATH_RIBBON_TEXTURE := preload("res://assets/tiles/path_ribbon.png")
const PINE_TEXTURE := preload("res://assets/props/pine.png")
const PROPS_ATLAS := preload("res://assets/props/winter_props.png")

const TILE_SIZE := 64
const GRID_WIDTH := 30
const GRID_HEIGHT := 20
const WORLD_SIZE := Vector2(GRID_WIDTH * TILE_SIZE, GRID_HEIGHT * TILE_SIZE)

const ATLAS_SNOW_START := 0
const ATLAS_PATH_VERTICAL := 4
const ATLAS_PATH_HORIZONTAL := 5
const ATLAS_RIVER_START := 6
const ATLAS_BRIDGE := 8

const PROP_ROCKS := 0
const PROP_BERRIES := 1
const PROP_FENCE := 2
const PROP_LANTERN := 3
const PROP_STUMP := 4
const PROP_GRAVE := 5
const PROP_WELL := 6
const PROP_SIGN := 7
const PROP_CART := 8
const PROP_FRAME_SIZE := 96

enum Tile {
	FOREST,
	PATH,
	RIVER,
	BRIDGE,
}

var location_id: StringName = &"crossroads"
var tiles: Array[Array] = []


func _ready() -> void:
	_generate_layout()
	_build_tile_layers()
	_build_path_ribbons()
	_build_forest_canopy()
	_build_path_decorations()
	_build_landmark_sets()
	_build_river_details()
	_build_collision_runs()


func get_spawn_position() -> Vector2:
	if location_id == &"northern_grove":
		return _cell_center(Vector2i(15, 17))
	return _cell_center(Vector2i(4, 18))


func get_arrival_position(from_edge: StringName) -> Vector2:
	if from_edge == &"north":
		return _cell_center(Vector2i(15, 3))
	if from_edge == &"south":
		return _cell_center(Vector2i(15, 17))
	return get_spawn_position()


func get_npc_position() -> Vector2:
	return _cell_center(Vector2i(6, 17))


func get_chapel_position() -> Vector2:
	return _cell_center(Vector2i(26, 6))


func get_bell_position() -> Vector2:
	return _cell_center(Vector2i(4, 7))


func get_travel_exit(world_position: Vector2) -> StringName:
	var cell := Vector2i(
		floori(world_position.x / TILE_SIZE),
		floori(world_position.y / TILE_SIZE)
	)
	if location_id == &"crossroads":
		if cell.y <= 1 and cell.x in range(13, 18):
			return &"north"
	elif location_id == &"northern_grove":
		if cell.y >= 18 and cell.x in range(13, 18):
			return &"south"
	return &""


func get_footstep_surface(world_position: Vector2) -> StringName:
	var cell := Vector2i(
		floori(world_position.x / TILE_SIZE),
		floori(world_position.y / TILE_SIZE)
	)
	if (
		cell.x < 0
		or cell.y < 0
		or cell.x >= GRID_WIDTH
		or cell.y >= GRID_HEIGHT
	):
		return &"ground"

	match int(tiles[cell.y][cell.x]):
		Tile.BRIDGE:
			return &"wood"
		Tile.PATH:
			return &"snow"
		_:
			return &"ground"


func _generate_layout() -> void:
	tiles.clear()
	for y in range(GRID_HEIGHT):
		var row: Array[int] = []
		row.resize(GRID_WIDTH)
		row.fill(Tile.FOREST)
		tiles.append(row)

	if location_id == &"northern_grove":
		_generate_northern_grove_layout()
		return

	# Main route: southern entrance -> bridge -> clearing -> northern exit.
	_carve_route([
		Vector2i(4, 19), Vector2i(4, 18), Vector2i(8, 17),
		Vector2i(8, 14), Vector2i(11, 12), Vector2i(14, 10),
		Vector2i(14, 5), Vector2i(15, 1)
	], 1)
	_carve_circle(Vector2i(14, 10), 4)

	# Four distinct branches end in useful dead ends.
	_carve_route([
		Vector2i(12, 10), Vector2i(10, 9), Vector2i(8, 7), Vector2i(4, 7)
	], 1)
	_carve_route([
		Vector2i(13, 7), Vector2i(11, 5), Vector2i(8, 3)
	], 1)
	_carve_route([
		Vector2i(17, 9), Vector2i(20, 8), Vector2i(23, 8), Vector2i(26, 6)
	], 1)
	_carve_route([
		Vector2i(17, 11), Vector2i(20, 12), Vector2i(24, 13)
	], 1)
	_carve_route([
		Vector2i(11, 12), Vector2i(9, 13), Vector2i(6, 13)
	], 1)

	# A frozen river creates a meaningful choke point.
	for x in range(GRID_WIDTH):
		tiles[15][x] = Tile.RIVER
		tiles[16][x] = Tile.RIVER
	for y in range(15, 17):
		for x in range(7, 10):
			tiles[y][x] = Tile.BRIDGE


func _generate_northern_grove_layout() -> void:
	# A winding, more enclosed route with two quiet dead ends.
	_carve_route([
		Vector2i(15, 19), Vector2i(15, 17), Vector2i(12, 15),
		Vector2i(11, 12), Vector2i(14, 9), Vector2i(14, 6),
		Vector2i(18, 4), Vector2i(18, 2)
	], 1)
	_carve_circle(Vector2i(12, 14), 2)
	_carve_circle(Vector2i(14, 9), 3)
	_carve_circle(Vector2i(18, 4), 2)
	_carve_route([
		Vector2i(12, 11), Vector2i(9, 10), Vector2i(7, 8)
	], 1)
	_carve_route([
		Vector2i(16, 9), Vector2i(20, 10), Vector2i(23, 11)
	], 1)
	_carve_route([
		Vector2i(15, 6), Vector2i(12, 4), Vector2i(10, 3)
	], 1)

	# A frozen pond shapes the western dead end without blocking the route.
	for y in range(11, 14):
		for x in range(3, 8):
			if Vector2(x - 5, y - 12).length() <= 2.35:
				tiles[y][x] = Tile.RIVER


func _build_tile_layers() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = TERRAIN_ATLAS
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for atlas_x in range(9):
		atlas.create_tile(Vector2i(atlas_x, 0))
	var source_id := tile_set.add_source(atlas)

	var ground_layer := TileMapLayer.new()
	ground_layer.name = "SnowGround"
	ground_layer.tile_set = tile_set
	ground_layer.z_index = -100
	ground_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ground_layer)

	var terrain_layer := TileMapLayer.new()
	terrain_layer.name = "RoutesAndRiver"
	terrain_layer.tile_set = tile_set
	terrain_layer.z_index = -80
	terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(terrain_layer)

	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var cell := Vector2i(x, y)
			var snow_variant: int = ATLAS_SNOW_START + absi((x * 17 + y * 29) % 4)
			ground_layer.set_cell(cell, source_id, Vector2i(snow_variant, 0))

			match int(tiles[y][x]):
				Tile.PATH:
					pass
				Tile.RIVER:
					var river_variant := ATLAS_RIVER_START + ((x + y) % 2)
					terrain_layer.set_cell(cell, source_id, Vector2i(river_variant, 0))
				Tile.BRIDGE:
					terrain_layer.set_cell(cell, source_id, Vector2i(ATLAS_BRIDGE, 0))


func _build_path_ribbons() -> void:
	if location_id == &"northern_grove":
		_build_northern_grove_path_ribbons()
		return

	var main_route: Array[Vector2i] = [
		Vector2i(4, 19), Vector2i(4, 18), Vector2i(8, 17),
		Vector2i(8, 14), Vector2i(11, 12), Vector2i(14, 10),
		Vector2i(14, 5), Vector2i(15, 1)
	]
	var west_route: Array[Vector2i] = [
		Vector2i(12, 10), Vector2i(10, 9), Vector2i(8, 7), Vector2i(4, 7)
	]
	var north_west_route: Array[Vector2i] = [
		Vector2i(13, 7), Vector2i(11, 5), Vector2i(8, 3)
	]
	var chapel_route: Array[Vector2i] = [
		Vector2i(17, 9), Vector2i(20, 8), Vector2i(23, 8), Vector2i(26, 6)
	]
	var graveyard_route: Array[Vector2i] = [
		Vector2i(17, 11), Vector2i(20, 12), Vector2i(24, 13)
	]
	var camp_route: Array[Vector2i] = [
		Vector2i(11, 12), Vector2i(9, 13), Vector2i(6, 13)
	]

	_add_path_ribbon(main_route, 154.0)
	_add_path_ribbon(west_route, 154.0)
	_add_path_ribbon(north_west_route, 154.0)
	_add_path_ribbon(chapel_route, 154.0)
	_add_path_ribbon(graveyard_route, 154.0)
	_add_path_ribbon(camp_route, 154.0)

	# A broad, visually calm hub instead of a tiled checkerboard.
	_add_path_ribbon(
		[Vector2i(11, 10), Vector2i(14, 10), Vector2i(17, 10)],
		286.0
	)


func _build_northern_grove_path_ribbons() -> void:
	_add_path_ribbon([
		Vector2i(15, 19), Vector2i(15, 17), Vector2i(12, 15),
		Vector2i(11, 12), Vector2i(14, 9), Vector2i(14, 6),
		Vector2i(18, 4), Vector2i(18, 2)
	], 148.0)
	_add_path_ribbon([
		Vector2i(12, 11), Vector2i(9, 10), Vector2i(7, 8)
	], 142.0)
	_add_path_ribbon([
		Vector2i(16, 9), Vector2i(20, 10), Vector2i(23, 11)
	], 142.0)
	_add_path_ribbon([
		Vector2i(15, 6), Vector2i(12, 4), Vector2i(10, 3)
	], 138.0)
	_add_path_ribbon([
		Vector2i(11, 9), Vector2i(14, 9), Vector2i(17, 9)
	], 224.0)


func _add_path_ribbon(cells: Array[Vector2i], width: float) -> void:
	var line := Line2D.new()
	var world_points := PackedVector2Array()
	for cell in cells:
		world_points.append(_cell_center(cell))
	line.points = world_points
	line.width = width
	line.texture = PATH_RIBBON_TEXTURE
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.default_color = Color(0.88, 0.93, 1.0, 0.94)
	line.z_index = -90
	add_child(line)


func _build_forest_canopy() -> void:
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			if int(tiles[y][x]) != Tile.FOREST:
				continue

			var close_to_route := _has_walkable_neighbor(x, y)
			if not close_to_route and (x + y * 3) % 2 != 0:
				continue

			var tree := Sprite2D.new()
			tree.name = "Pine_%d_%d" % [x, y]
			tree.texture = PINE_TEXTURE
			tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tree.position = _cell_center(Vector2i(x, y))
			tree.position.x += float(((x * 13 + y * 7) % 13) - 6)
			tree.position.y += 30 + float((x * 5 + y * 11) % 8)
			tree.offset = Vector2(0, -PINE_TEXTURE.get_height() * 0.5)
			var scale_value := 0.82 + float((x * 19 + y * 23) % 21) / 100.0
			tree.scale = Vector2(-scale_value if (x + y) % 3 == 0 else scale_value, scale_value)
			tree.modulate = Color(
				0.88 + float((x + y) % 3) * 0.035,
				0.91 + float((x * 2 + y) % 2) * 0.035,
				1.0
			)
			tree.z_index = int(tree.position.y)
			add_child(tree)


func _build_path_decorations() -> void:
	if location_id == &"northern_grove":
		_build_northern_grove_path_decorations()
		return

	# Sparse edge vegetation guides the eye without cluttering the path.
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(6, 8)) + Vector2(-24, 27), 0.66)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(11, 5)) + Vector2(26, 27), 0.60)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(20, 8)) + Vector2(-26, 27), 0.64)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(22, 12)) + Vector2(24, 27), 0.62)

	_add_footprint_trail(_cell_center(Vector2i(4, 18)), _cell_center(Vector2i(8, 17)), 9)
	_add_footprint_trail(_cell_center(Vector2i(10, 12)), _cell_center(Vector2i(14, 10)), 8)
	_add_footprint_trail(_cell_center(Vector2i(17, 9)), _cell_center(Vector2i(22, 8)), 10)


func _build_northern_grove_path_decorations() -> void:
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(13, 16)) + Vector2(-22, 27), 0.62)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(10, 11)) + Vector2(24, 27), 0.58)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(20, 9)) + Vector2(-25, 27), 0.62)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(12, 4)) + Vector2(22, 27), 0.56)
	_add_footprint_trail(_cell_center(Vector2i(15, 17)), _cell_center(Vector2i(12, 15)), 8)
	_add_footprint_trail(_cell_center(Vector2i(12, 12)), _cell_center(Vector2i(14, 9)), 7)
	_add_footprint_trail(_cell_center(Vector2i(15, 6)), _cell_center(Vector2i(18, 4)), 7)


func _build_landmark_sets() -> void:
	if location_id == &"northern_grove":
		_build_northern_grove_landmarks()
		return

	# Starting approach and bridge: readable navigation silhouette.
	_add_prop(PROP_SIGN, _cell_center(Vector2i(5, 17)) + Vector2(-18, 28), 0.68)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(7, 17)) + Vector2(-21, 31), 0.72)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(10, 14)) + Vector2(24, 30), 0.68)
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(5, 18)) + Vector2(22, 30), 0.54)

	# Central clearing: keep the middle empty and frame only its perimeter.
	_add_prop(PROP_SIGN, _cell_center(Vector2i(14, 8)) + Vector2(24, 29), 0.68)
	_add_prop(PROP_STUMP, _cell_center(Vector2i(11, 11)) + Vector2(-18, 31), 0.58)
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(17, 11)) + Vector2(20, 31), 0.54)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(16, 8)) + Vector2(22, 31), 0.64)

	# North-west dead end: frozen well, abandoned cart, enclosure.
	_add_prop(PROP_WELL, _cell_center(Vector2i(8, 3)) + Vector2(0, 34), 0.78, Vector2(58, 34))
	_add_prop(PROP_CART, _cell_center(Vector2i(9, 4)) + Vector2(19, 33), 0.66, Vector2(50, 26))
	_add_prop(PROP_FENCE, _cell_center(Vector2i(7, 2)) + Vector2(0, 30), 0.70)
	_add_prop(PROP_FENCE, _cell_center(Vector2i(9, 2)) + Vector2(0, 30), 0.70)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(10, 4)) + Vector2(23, 31), 0.65)

	# Western bell shrine: rocks, berries, and collapsed fence.
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(3, 8)) + Vector2(16, 32), 0.67)
	_add_prop(PROP_BERRIES, _cell_center(Vector2i(5, 6)) + Vector2(22, 28), 0.62)
	_add_prop(PROP_FENCE, _cell_center(Vector2i(4, 6)) + Vector2(0, 31), 0.64, Vector2.ZERO, 0.12)

	# Chapel yard: framed entrance rather than a lone building.
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(24, 7)) + Vector2(-18, 31), 0.70)
	_add_prop(PROP_FENCE, _cell_center(Vector2i(25, 7)) + Vector2(0, 31), 0.72)
	_add_prop(PROP_FENCE, _cell_center(Vector2i(27, 7)) + Vector2(0, 31), 0.72)
	_add_prop(PROP_WELL, _cell_center(Vector2i(24, 6)) + Vector2(-18, 33), 0.60)

	# South-east graveyard dead end.
	for grave_cell in [Vector2i(22, 13), Vector2i(23, 13), Vector2i(24, 13)]:
		_add_prop(PROP_GRAVE, _cell_center(grave_cell) + Vector2(0, 30), 0.58)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(21, 12)) + Vector2(-20, 31), 0.64)
	_add_prop(PROP_FENCE, _cell_center(Vector2i(23, 12)) + Vector2(0, 31), 0.72)

	# Lower-west short dead end: remains of a traveller camp.
	_add_prop(PROP_STUMP, _cell_center(Vector2i(6, 13)) + Vector2(-8, 31), 0.64)
	_add_prop(PROP_CART, _cell_center(Vector2i(7, 13)) + Vector2(22, 33), 0.58)
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(6, 12)) + Vector2(-22, 31), 0.54)


func _build_northern_grove_landmarks() -> void:
	# Southern arrival: a small lit trailhead.
	_add_prop(PROP_SIGN, _cell_center(Vector2i(14, 17)) + Vector2(-22, 28), 0.66)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(16, 17)) + Vector2(22, 31), 0.68)
	_add_prop(PROP_STUMP, _cell_center(Vector2i(12, 15)) + Vector2(-24, 31), 0.56)

	# Western pond: abandoned cart and an old well form a readable destination.
	_add_prop(PROP_WELL, _cell_center(Vector2i(7, 8)) + Vector2(-6, 34), 0.70, Vector2(58, 34))
	_add_prop(PROP_CART, _cell_center(Vector2i(8, 9)) + Vector2(24, 33), 0.58, Vector2(50, 26))
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(9, 10)) + Vector2(-22, 31), 0.62)
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(6, 10)) + Vector2(18, 31), 0.50)

	# Central grove: restrained ring of details keeps the walking space open.
	_add_prop(PROP_STUMP, _cell_center(Vector2i(12, 9)) + Vector2(-20, 31), 0.62)
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(16, 10)) + Vector2(24, 31), 0.52)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(15, 7)) + Vector2(22, 31), 0.62)

	# Eastern dead end: a forgotten grave cluster among the trees.
	for grave_cell in [Vector2i(22, 10), Vector2i(23, 11), Vector2i(22, 12)]:
		_add_prop(PROP_GRAVE, _cell_center(grave_cell) + Vector2(0, 30), 0.56)
	_add_prop(PROP_FENCE, _cell_center(Vector2i(21, 11)) + Vector2(-12, 31), 0.64, Vector2.ZERO, -0.08)

	# Northern approach: colder and more sparse.
	_add_prop(PROP_SIGN, _cell_center(Vector2i(17, 4)) + Vector2(-22, 29), 0.62)
	_add_prop(PROP_ROCKS, _cell_center(Vector2i(10, 3)) + Vector2(18, 31), 0.56)
	_add_prop(PROP_LANTERN, _cell_center(Vector2i(18, 3)) + Vector2(22, 31), 0.60)


func _build_river_details() -> void:
	if location_id == &"northern_grove":
		_build_northern_grove_pond_details()
		return

	for x in [1, 4, 12, 16, 20, 26, 28]:
		var crack := Line2D.new()
		var origin := _cell_center(Vector2i(x, 15))
		crack.points = PackedVector2Array([
			origin + Vector2(-24, -9),
			origin + Vector2(-7, 1),
			origin + Vector2(3, -5),
			origin + Vector2(19, 9)
		])
		crack.width = 2
		crack.default_color = Color(0.48, 0.68, 0.92, 0.65)
		crack.z_index = -68
		add_child(crack)

	for x in [2, 13, 18, 27]:
		_add_prop(PROP_ROCKS, _cell_center(Vector2i(x, 14)) + Vector2(0, 34), 0.42)


func _build_northern_grove_pond_details() -> void:
	for cell in [Vector2i(4, 12), Vector2i(5, 11), Vector2i(6, 12), Vector2i(5, 13)]:
		var crack := Line2D.new()
		var origin := _cell_center(cell)
		crack.points = PackedVector2Array([
			origin + Vector2(-18, -7),
			origin + Vector2(-5, 1),
			origin + Vector2(4, -4),
			origin + Vector2(17, 8)
		])
		crack.width = 2
		crack.default_color = Color(0.48, 0.68, 0.92, 0.62)
		crack.z_index = -68
		add_child(crack)


func _add_prop(
	prop_id: int,
	position: Vector2,
	scale_value: float = 1.0,
	collision_size: Vector2 = Vector2.ZERO,
	rotation_value: float = 0.0
) -> void:
	var anchor := Node2D.new()
	anchor.name = "WinterProp_%d" % prop_id
	anchor.position = position
	anchor.rotation = rotation_value
	anchor.scale = Vector2(scale_value, scale_value)
	anchor.z_index = int(position.y)

	var sprite := Sprite2D.new()
	sprite.texture = _create_prop_texture(prop_id)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0, -PROP_FRAME_SIZE * 0.5)
	anchor.add_child(sprite)

	var resolved_collision: Vector2 = (
		collision_size
		if collision_size != Vector2.ZERO
		else _default_prop_collision(prop_id)
	)
	if resolved_collision != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = resolved_collision
		var collider := CollisionShape2D.new()
		collider.position = Vector2(0, -resolved_collision.y * 0.35)
		collider.shape = shape
		body.add_child(collider)
		anchor.add_child(body)

	if prop_id == PROP_LANTERN:
		_add_warm_light(anchor, Vector2(-12, -54), 0.72)

	add_child(anchor)


func _create_prop_texture(prop_id: int) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = PROPS_ATLAS
	atlas_texture.region = Rect2(
		(prop_id % 3) * PROP_FRAME_SIZE,
		floori(float(prop_id) / 3.0) * PROP_FRAME_SIZE,
		PROP_FRAME_SIZE,
		PROP_FRAME_SIZE
	)
	return atlas_texture


func _default_prop_collision(prop_id: int) -> Vector2:
	match prop_id:
		PROP_ROCKS:
			return Vector2(58, 34)
		PROP_BERRIES:
			return Vector2(44, 28)
		PROP_FENCE:
			return Vector2(82, 18)
		PROP_LANTERN:
			return Vector2(18, 18)
		PROP_STUMP:
			return Vector2(48, 30)
		PROP_GRAVE:
			return Vector2(30, 22)
		PROP_WELL:
			return Vector2(62, 38)
		PROP_SIGN:
			return Vector2(28, 18)
		PROP_CART:
			return Vector2(68, 34)
	return Vector2.ZERO


func _add_warm_light(parent: Node, position: Vector2, energy: float) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.92))
	gradient.set_color(1, Color(1, 1, 1, 0))

	var light_texture := GradientTexture2D.new()
	light_texture.gradient = gradient
	light_texture.width = 128
	light_texture.height = 128
	light_texture.fill = GradientTexture2D.FILL_RADIAL
	light_texture.fill_from = Vector2(0.5, 0.5)
	light_texture.fill_to = Vector2(1.0, 0.5)

	var light := PointLight2D.new()
	light.position = position
	light.texture = light_texture
	light.color = Color("#ffc77a")
	light.energy = energy
	light.texture_scale = 1.15
	parent.add_child(light)


func _add_footprint_trail(from: Vector2, to: Vector2, count: int) -> void:
	var direction := (to - from).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	for footprint_index in range(count):
		var amount := float(footprint_index + 1) / float(count + 1)
		var side := -1.0 if footprint_index % 2 == 0 else 1.0
		var footprint := Polygon2D.new()
		footprint.position = from.lerp(to, amount) + perpendicular * side * 5.0
		footprint.rotation = direction.angle()
		footprint.polygon = PackedVector2Array([
			Vector2(-5, -2), Vector2(2, -3), Vector2(5, 0),
			Vector2(2, 3), Vector2(-5, 2)
		])
		footprint.color = Color(0.26, 0.38, 0.61, 0.30)
		footprint.z_index = -67
		add_child(footprint)


func _has_walkable_neighbor(x: int, y: int) -> bool:
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if _is_walkable(x + offset_x, y + offset_y):
				return true
	return false


func _is_walkable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= GRID_WIDTH or y >= GRID_HEIGHT:
		return false
	return int(tiles[y][x]) in [Tile.PATH, Tile.BRIDGE]


func _carve_route(points: Array[Vector2i], radius: int) -> void:
	for index in range(points.size() - 1):
		var from := points[index]
		var to := points[index + 1]
		var delta := to - from
		var steps: int = maxi(abs(delta.x), abs(delta.y))
		for step in range(steps + 1):
			var amount := float(step) / float(maxi(steps, 1))
			var cell := Vector2i(
				roundi(lerp(float(from.x), float(to.x), amount)),
				roundi(lerp(float(from.y), float(to.y), amount))
			)
			_carve_circle(cell, radius)


func _carve_circle(center: Vector2i, radius: int) -> void:
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			if Vector2(offset_x, offset_y).length() > radius + 0.35:
				continue
			var cell := center + Vector2i(offset_x, offset_y)
			if cell.x <= 0 or cell.y <= 0 or cell.x >= GRID_WIDTH - 1 or cell.y >= GRID_HEIGHT - 1:
				continue
			tiles[cell.y][cell.x] = Tile.PATH


func _build_collision_runs() -> void:
	for y in range(GRID_HEIGHT):
		var run_start := -1
		for x in range(GRID_WIDTH + 1):
			var blocked := false
			if x < GRID_WIDTH:
				blocked = int(tiles[y][x]) in [Tile.FOREST, Tile.RIVER]
			if blocked and run_start == -1:
				run_start = x
			elif not blocked and run_start != -1:
				_add_collision_run(run_start, x, y)
				run_start = -1


func _add_collision_run(from_x: int, to_x: int, y: int) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = Vector2((to_x - from_x) * TILE_SIZE, TILE_SIZE)
	var collider := CollisionShape2D.new()
	collider.position = Vector2(
		(from_x + to_x) * TILE_SIZE * 0.5,
		(y + 0.5) * TILE_SIZE
	)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE_SIZE
