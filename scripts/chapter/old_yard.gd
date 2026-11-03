extends Node

# Выход из храма — на миг не та игра. Молодой Дэйл и воин оказываются во внутреннем дворе
# храма в графике старой игры: летний день, вид сверху, карта из тайлов и расставленных
# объектов, ходить можно самому. Воин ведёт по тропе и говорит в старом окошке диалога.
# Потом картинка спотыкается, бог роняет «Упс, это не то», и двор от центра сгорает в знаки —
# но криво, в нечитаемую кашу. Бог вздыхает во второй раз, и каша сразу прогорает от центра:
# под ней уже идёт тот же двор в настоящем ASCII-движке. Сцена сообщает finished.
# Ассеты сгенерированы в Runware (GPT Image 2): в листах персонажей кадры 96×96,
# ряды — к нам, от нас, влево, вправо.

## Бог заговорил во второй раз: пора готовить настоящий двор под кашей.
signal second_try
signal finished

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const DialogueView := preload("res://scripts/ui/dialogue_view.gd")
const SCREEN_SHADER := preload("res://scripts/chapter/old_yard.gdshader")
const TERRAIN := preload("res://assets/yard/temple_terrain.png")
const PROPS := preload("res://assets/yard/temple_props.png")
const TREE := preload("res://assets/yard/tree.png")
const GATE := preload("res://assets/yard/gate.png")
const PILLAR := preload("res://assets/yard/pillar.png")
const DALE_SHEET := preload("res://assets/yard/dale_sheet.png")
const WARRIOR_SHEET := preload("res://assets/yard/warrior_sheet.png")
const STONE_STEPS: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/ground_01.wav"),
	preload("res://assets/audio/footsteps/ground_02.wav"),
	preload("res://assets/audio/footsteps/ground_03.wav"),
]
const WOOD_STEPS: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/wood_01.wav"),
	preload("res://assets/audio/footsteps/wood_02.wav"),
	preload("res://assets/audio/footsteps/wood_03.wav"),
]

const BASE_FONT_SIZE := 8
const TILE := 64
const GRID := Vector2i(24, 20)
# Текстуры в атласе: каждая занимает 4×4 тайла, карта берёт их по координате и не повторяется в пределах блока.
const GRASS := 0
const STONE := 1
const WOOD := 2
const WALL := 3
const ROOF := 4
const PATCH := 4
# Объекты в листе 3×3 по 120.
const PROP_FRAME := 120
const PROP_LANTERN := 0
const PROP_FLOWERS := 1
const PROP_BUSH := 2
const PROP_ROCKS := 3
const PROP_BASIN := 4
const PROP_BENCH := 5
const PROP_WELL := 6
const PROP_POT := 7
const PROP_BANNER := 8
# Радиус столкновения объекта и его тени по типу листа.
const PROP_RADIUS: Array[float] = [22.0, 44.0, 26.0, 34.0, 30.0, 34.0, 34.0, 18.0, 12.0]

const FRAME := 96
const ROW_TOWARD := 0
const ROW_AWAY := 1
const ROW_LEFT := 2
const ROW_RIGHT := 3
const WALK_SPEED := 150.0
const STEP_DISTANCE := 54.0
const HERO_RADIUS := 18.0
const WARRIOR_SPEED := 118.0
# Воин не даёт себя потерять и не даёт пройти сквозь себя.
const WARRIOR_WAIT := 260.0
const WARRIOR_GAP := 40.0
const TALK_REACH := 190.0
# Масштаб камеры при высоте окна 810.
const ZOOM := 1.35
const LOGICAL_HEIGHT := 810.0
const FADE_IN := 1.0
const FREEZE_TIME := 0.8
const SWITCH_TIME := 1.8
const ASCII_TIME := 3.5
const OUT_TIME := 1.9
# Реплика бога, допечатавшись, не ждёт нажатия: анимация начинается сама.
const GOD_HOLD := 1.1
# Если игрок ничего не нажмёт, реплика всё равно закроется.
const LINE_TIMEOUT := 7.0
const MOTES := 70

const WARRIOR_LINE := "Двор пуст. Иди по тропе, к воротам."
const GOD_LINE := "Упс, это не то."
const GOD_SECOND_LINE := "…И это не то. Сейчас, сейчас. Вот так."

enum Beat { WALK, WARRIOR_TALK, FREEZE, GOD, SWITCH, ASCII, GOD_AGAIN, OUT }

var beat := Beat.WALK
var beat_time := 0.0
var elapsed := 0.0
var ready_to_play := false
var mono: Font
var serif: Font
var viewport: SubViewport
var camera: Camera2D
var actors: Node2D
var hero: Sprite2D
var warrior: Sprite2D
var motes_view: Control
var overlay: Control
var material: ShaderMaterial
var step_player: AudioStreamPlayer
# Куда нельзя: прямоугольники стен и круги объектов (x, y, радиус).
var walls: Array[Rect2] = []
var blockers: Array[Vector3] = []
var hero_row := ROW_TOWARD
var hero_clock := 0.0
var hero_moving := false
var step_left := STEP_DISTANCE
var warrior_row := ROW_TOWARD
var warrior_clock := 0.0
var warrior_target := Vector2.ZERO
var line_shown := 0.0
var hold := 0.0
## Что должно быть готово, прежде чем каша начнёт прогорать.
var waiting_for: Node
var motes := PackedVector3Array()


func _ready() -> void:
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
		for key in [KEY_E, KEY_SPACE, KEY_ENTER]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(&"interact", event)
	mono = FontAtlas.create_font()
	serif = UiStyle.serif(600.0)
	var font_size := roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())
	var cell := FontAtlas.measure_cell(mono, font_size)
	var atlas := await FontAtlas.build(self, mono, font_size, cell)
	_build_screen(atlas, cell)
	_build_world()
	get_window().size_changed.connect(_fit)
	_fit()
	ready_to_play = true


func _build_screen(atlas: Texture2D, cell: Vector2i) -> void:
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	material = ShaderMaterial.new()
	material.shader = SCREEN_SHADER
	material.set_shader_parameter("scene_tex", viewport.get_texture())
	material.set_shader_parameter("atlas_tex", atlas)
	material.set_shader_parameter("cell_px", Vector2(cell))
	material.set_shader_parameter("fade", 1.0)
	var screen := ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.material = material
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)

	step_player = AudioStreamPlayer.new()
	step_player.bus = &"AsciiFootsteps" if AudioServer.get_bus_index(&"AsciiFootsteps") >= 0 else &"SFX"
	add_child(step_player)


func _build_world() -> void:
	var sun := CanvasModulate.new()
	sun.color = Color(1.0, 0.97, 0.9)
	viewport.add_child(sun)
	_build_tiles()
	actors = Node2D.new()
	actors.y_sort_enabled = true
	viewport.add_child(actors)
	_build_temple()
	_build_garden()

	var door_x := GRID.x * TILE * 0.5
	hero = _add_character(DALE_SHEET, Vector2(door_x, 3.5 * TILE))
	warrior = _add_character(WARRIOR_SHEET, Vector2(door_x, 5.0 * TILE))
	warrior_target = Vector2(door_x, 10.5 * TILE)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = GRID.x * TILE
	camera.limit_bottom = GRID.y * TILE
	camera.position = hero.position
	viewport.add_child(camera)
	camera.make_current()

	# Тёплая пыльца плывёт в солнечном воздухе поверх всего.
	var air := CanvasLayer.new()
	viewport.add_child(air)
	motes_view = Control.new()
	motes_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motes_view.draw.connect(_draw_motes)
	air.add_child(motes_view)
	for index in range(MOTES):
		motes.append(Vector3(randf(), randf(), randf_range(0.4, 1.0)))


func _build_tiles() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = TERRAIN
	source.texture_region_size = Vector2i(TILE, TILE)
	for y in range(PATCH):
		for x in range(PATCH * 5):
			source.create_tile(Vector2i(x, y))
	tile_set.add_source(source, 0)
	var ground := TileMapLayer.new()
	ground.tile_set = tile_set
	viewport.add_child(ground)
	for y in range(GRID.y):
		for x in range(GRID.x):
			var kind := _terrain_at(x, y)
			ground.set_cell(Vector2i(x, y), 0, Vector2i(kind * PATCH + x % PATCH, y % PATCH))


# План двора: крыши и стены замыкают его со всех сторон, посередине мощёная тропа с перекрёстком.
func _terrain_at(x: int, y: int) -> int:
	if y < 2 or y >= GRID.y - 2 or x < 2 or x >= GRID.x - 2:
		return ROOF
	if y == 2 or y == GRID.y - 3 or x == 2 or x == GRID.x - 3:
		return WALL
	if y <= 4 and x >= 8 and x < GRID.x - 8:
		return WOOD
	if x >= 10 and x < GRID.x - 10:
		return STONE
	if (y == 10 or y == 11) and x >= 3 and x < GRID.x - 3:
		return STONE
	return GRASS


# Постройка по кругу непроходима; ворота вписаны в стену, между ними и столбами ритм колонн.
func _build_temple() -> void:
	var width := GRID.x * TILE
	var height := GRID.y * TILE
	walls = [
		Rect2(0, 0, width, 3 * TILE),
		Rect2(0, height - 3 * TILE, width, 3 * TILE),
		Rect2(0, 0, 3 * TILE, height),
		Rect2(width - 3 * TILE, 0, 3 * TILE, height),
	]
	_add_sprite(GATE, Vector2(width * 0.5, 3.05 * TILE))
	_add_sprite(GATE, Vector2(width * 0.5, height - 2.95 * TILE))
	for x in [4, 7, GRID.x - 7, GRID.x - 4]:
		_add_pillar(Vector2((x + 0.5) * TILE, 3.05 * TILE))
		_add_pillar(Vector2((x + 0.5) * TILE, height - 2.95 * TILE))
	for y in range(5, GRID.y - 3, 4):
		_add_pillar(Vector2(3.2 * TILE, y * TILE))
		_add_pillar(Vector2((GRID.x - 3.2) * TILE, y * TILE))


func _add_pillar(at: Vector2) -> void:
	_add_sprite(PILLAR, at)
	blockers.append(Vector3(at.x, at.y, 16.0))


# Сад симметричен тропе: деревья, клумбы и фонари слева и справа, у стен мелочи.
func _build_garden() -> void:
	for side in [-1.0, 1.0]:
		var mirror := func(x: float) -> float: return GRID.x * 0.5 + side * x
		_add_tree(Vector2(mirror.call(7.5), 7.2))
		_add_tree(Vector2(mirror.call(5.2), 9.0))
		_add_tree(Vector2(mirror.call(7.2), 15.0))
		_add_tree(Vector2(mirror.call(4.2), 15.8))
		_add_prop(PROP_LANTERN, Vector2(mirror.call(2.6), 6.2))
		_add_prop(PROP_LANTERN, Vector2(mirror.call(2.6), 13.2))
		_add_prop(PROP_FLOWERS, Vector2(mirror.call(4.2), 6.6))
		_add_prop(PROP_FLOWERS, Vector2(mirror.call(4.4), 13.4))
		_add_prop(PROP_BANNER, Vector2(mirror.call(4.4), 4.4))
		_add_prop(PROP_POT, Vector2(mirror.call(3.0), 4.9))
		_add_prop(PROP_BUSH, Vector2(mirror.call(8.4), 5.0))
		_add_prop(PROP_BUSH, Vector2(mirror.call(8.2), 12.6))
		_add_prop(PROP_ROCKS, Vector2(mirror.call(6.0), 13.2))
	_add_prop(PROP_WELL, Vector2(4.8, 12.8))
	_add_prop(PROP_BASIN, Vector2(GRID.x - 6.2, 8.6))
	_add_prop(PROP_BENCH, Vector2(GRID.x - 4.9, 12.7))
	_add_prop(PROP_BENCH, Vector2(8.2, 9.2))


func _add_tree(cell: Vector2) -> void:
	var at := cell * TILE
	_add_sprite(TREE, at)
	_add_shadow(at, 58.0, 18.0)
	blockers.append(Vector3(at.x, at.y, 22.0))


func _add_prop(id: int, cell: Vector2) -> void:
	var at := cell * TILE
	var texture := AtlasTexture.new()
	texture.atlas = PROPS
	texture.region = Rect2(id % 3 * PROP_FRAME, id / 3 * PROP_FRAME, PROP_FRAME, PROP_FRAME)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	# В кадре объект стоит на нижней кромке с отступом 2.
	sprite.offset = Vector2(0.0, -PROP_FRAME * 0.5 + 2.0)
	sprite.position = at
	actors.add_child(sprite)
	var radius: float = PROP_RADIUS[id]
	_add_shadow(at, radius + 6.0, (radius + 6.0) * 0.32)
	blockers.append(Vector3(at.x, at.y - radius * 0.2, radius))


func _add_sprite(texture: Texture2D, feet: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.offset = Vector2(0.0, -texture.get_height() * 0.5)
	sprite.position = feet
	actors.add_child(sprite)
	return sprite


func _add_character(sheet: Texture2D, feet: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = sheet
	sprite.hframes = 4
	sprite.vframes = 4
	sprite.offset = Vector2(0.0, -FRAME * 0.5 + 2.0)
	sprite.position = feet
	actors.add_child(sprite)
	var shadow := _ellipse(20.0, 7.0)
	shadow.show_behind_parent = true
	sprite.add_child(shadow)
	return sprite


# Мягкая тень лежит прямо на земле, под всеми объектами.
func _add_shadow(at: Vector2, rx: float, ry: float) -> void:
	var shadow := _ellipse(rx, ry)
	shadow.position = at
	shadow.z_index = -1
	actors.add_child(shadow)


func _ellipse(rx: float, ry: float) -> Polygon2D:
	var points := PackedVector2Array()
	for index in range(18):
		var angle := TAU * index / 18.0
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	var shape := Polygon2D.new()
	shape.polygon = points
	shape.color = Color(0.1, 0.13, 0.05, 0.34)
	return shape


func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	viewport.size = Vector2i(size)
	motes_view.size = size
	material.set_shader_parameter("screen_px", size)
	var zoom := size.y / LOGICAL_HEIGHT * ZOOM
	camera.zoom = Vector2(zoom, zoom)


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	delta = minf(delta, 0.05)
	elapsed += delta
	beat_time += delta
	match beat:
		Beat.WALK:
			material.set_shader_parameter("fade", 1.0 - clampf(beat_time / FADE_IN, 0.0, 1.0))
			_walk_hero(delta)
			_lead(delta)
			if warrior.position == warrior_target and hero.position.distance_to(warrior.position) < TALK_REACH:
				_stop_hero()
				warrior_row = ROW_AWAY
				_go(Beat.WARRIOR_TALK)
		Beat.WARRIOR_TALK:
			if _line_finished(WARRIOR_LINE, delta):
				_go(Beat.FREEZE)
		Beat.FREEZE:
			material.set_shader_parameter("glitch", clampf(beat_time / FREEZE_TIME, 0.0, 1.0))
			if beat_time >= FREEZE_TIME:
				material.set_shader_parameter("glitch", 0.25)
				_go(Beat.GOD)
		Beat.GOD:
			if _god_finished(GOD_LINE, delta):
				material.set_shader_parameter("glitch", 0.0)
				var director := get_node_or_null("/root/SoundDirector")
				if director != null:
					director.toll(-6.0)
				_go(Beat.SWITCH)
		Beat.SWITCH:
			var t := clampf(beat_time / SWITCH_TIME, 0.0, 1.0)
			material.set_shader_parameter("amount", t)
			if t >= 1.0:
				# Как ни в чём не бывало: воин идёт дальше к воротам, уже символами.
				warrior_target = Vector2(warrior.position.x, (GRID.y - 3.6) * TILE)
				_go(Beat.ASCII)
		Beat.ASCII:
			_walk_hero(delta)
			_lead(delta)
			if beat_time >= ASCII_TIME:
				_stop_hero()
				second_try.emit()
				_go(Beat.GOD_AGAIN)
		Beat.GOD_AGAIN:
			var ready_below: bool = waiting_for == null or waiting_for.ready_to_play
			if _god_finished(GOD_SECOND_LINE, delta) and ready_below:
				var director := get_node_or_null("/root/SoundDirector")
				if director != null:
					director.toll(-6.0)
				_go(Beat.OUT)
		Beat.OUT:
			material.set_shader_parameter("reveal", clampf(beat_time / OUT_TIME, 0.0, 1.0))
			if beat_time >= OUT_TIME:
				set_process(false)
				finished.emit()
				return
	_animate(delta)
	material.set_shader_parameter("time", elapsed)
	camera.position = hero.position
	motes_view.queue_redraw()
	overlay.queue_redraw()


func _go(next: Beat) -> void:
	beat = next
	beat_time = 0.0
	line_shown = 0.0
	hold = 0.0


# Бог не ждёт игрока: допечатал, чуть подержал реплику — и дальше. Нажатие только ускоряет.
func _god_finished(text: String, delta: float) -> bool:
	line_shown = minf(line_shown + delta * 30.0, text.length())
	var pressed := Input.is_action_just_pressed(&"interact")
	if line_shown >= text.length():
		hold += delta
		return pressed or hold >= GOD_HOLD
	if pressed:
		line_shown = text.length()
	return false


func _walk_hero(delta: float) -> void:
	var move := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	hero_moving = move != Vector2.ZERO
	if not hero_moving:
		return
	if absf(move.x) > absf(move.y):
		hero_row = ROW_RIGHT if move.x > 0.0 else ROW_LEFT
	else:
		hero_row = ROW_TOWARD if move.y > 0.0 else ROW_AWAY
	var before := hero.position
	var step := move.normalized() * WALK_SPEED * delta
	# Скольжение вдоль препятствий: каждая ось проверяется отдельно.
	if _free_at(hero.position + Vector2(step.x, 0.0)):
		hero.position.x += step.x
	if _free_at(hero.position + Vector2(0.0, step.y)):
		hero.position.y += step.y
	step_left -= hero.position.distance_to(before)
	if step_left <= 0.0:
		step_left = STEP_DISTANCE
		var porch := hero.position.y < 5.0 * TILE
		var steps := WOOD_STEPS if porch else STONE_STEPS
		step_player.stream = steps[randi() % steps.size()]
		step_player.pitch_scale = randf_range(0.97, 1.03)
		step_player.volume_db = -15.0
		step_player.play()


func _free_at(point: Vector2) -> bool:
	for wall in walls:
		if wall.grow(-HERO_RADIUS * 0.2).has_point(point):
			return false
	for blocker in blockers:
		if point.distance_to(Vector2(blocker.x, blocker.y)) < blocker.z + HERO_RADIUS:
			return false
	return point.distance_to(warrior.position) >= WARRIOR_GAP


func _stop_hero() -> void:
	hero_moving = false
	hero_clock = 0.0


# Воин идёт к своей точке и ждёт, если Дэйл отстал: тогда оборачивается.
func _lead(delta: float) -> void:
	var lagging := hero.position.distance_to(warrior.position) > WARRIOR_WAIT
	if warrior.position == warrior_target or lagging:
		warrior_clock = 0.0
		warrior_row = ROW_AWAY
		return
	warrior_row = ROW_TOWARD
	warrior.position = warrior.position.move_toward(warrior_target, WARRIOR_SPEED * delta)
	warrior_clock += delta


func _animate(delta: float) -> void:
	for index in range(motes.size()):
		var mote := motes[index]
		mote.x = fposmod(mote.x + delta * 0.012 * mote.z, 1.0)
		mote.y = fposmod(mote.y + delta * 0.006 * sin(elapsed * 0.6 + float(index)), 1.0)
		motes[index] = mote
	if hero_moving:
		hero_clock += delta
	else:
		hero_clock = 0.0
	hero.frame = hero_row * 4 + (int(hero_clock * 7.0) % 4)
	warrior.frame = warrior_row * 4 + (int(warrior_clock * 6.0) % 4)


# Печатает реплику; нажатие дописывает её, следующее — закрывает.
func _line_finished(text: String, delta: float) -> bool:
	var done := line_shown >= text.length()
	line_shown = minf(line_shown + delta * 30.0, text.length())
	if beat_time > LINE_TIMEOUT:
		return true
	if not Input.is_action_just_pressed(&"interact"):
		return false
	if not done:
		line_shown = text.length()
		return false
	return true


func _draw_motes() -> void:
	var pixel := maxf(motes_view.size.y / 300.0, 2.0)
	for mote in motes:
		var glow := 0.45 + 0.35 * sin(elapsed * 1.2 + mote.x * 40.0)
		motes_view.draw_rect(Rect2(Vector2(mote.x, mote.y) * motes_view.size, Vector2(pixel, pixel)), Color(1.0, 0.95, 0.68, glow * mote.z))


func _draw_overlay() -> void:
	if get_tree().paused:
		return
	if beat == Beat.WARRIOR_TALK:
		_draw_old_window("Воин", WARRIOR_LINE)
	elif beat == Beat.GOD:
		# Бог говорит уже языком настоящей игры.
		DialogueView.draw(overlay, mono, serif, "Бог", Color(1.0, 0.9, 0.66), GOD_LINE, int(line_shown), elapsed)
	elif beat == Beat.GOD_AGAIN:
		DialogueView.draw(overlay, mono, serif, "Бог", Color(1.0, 0.9, 0.66), GOD_SECOND_LINE, int(line_shown), elapsed)


# Окошко диалога как в старых RPG: синяя плашка с белой рамкой и ровный шрифт.
func _draw_old_window(speaker: String, text: String) -> void:
	var size := overlay.get_rect().size
	var unit := size.y / UiStyle.LOGICAL_HEIGHT
	var box := Rect2(size.x * 0.12, size.y * 0.72, size.x * 0.76, size.y * 0.22)
	overlay.draw_rect(box, Color(0.05, 0.08, 0.3, 0.92))
	overlay.draw_rect(box, Color(0.92, 0.94, 1.0), false, maxf(3.0 * unit, 2.0))
	var name_size := roundi(20.0 * unit)
	var text_size := roundi(24.0 * unit)
	var left := box.position.x + 26.0 * unit
	overlay.draw_string(mono, Vector2(left, box.position.y + 38.0 * unit), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(1.0, 0.85, 0.45))
	overlay.draw_string(mono, Vector2(left, box.position.y + 82.0 * unit), text.left(int(line_shown)), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52.0 * unit, text_size, Color.WHITE)
