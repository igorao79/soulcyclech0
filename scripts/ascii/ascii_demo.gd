class_name SoulcycleAsciiDemo
extends Node

const CharacterProfile := preload("res://scripts/dialogue/character_profile.gd")
const AsciiWorld := preload("res://scripts/ascii/ascii_world.gd")
const AsciiHud := preload("res://scripts/ascii/ascii_hud.gd")
const AsciiGrassField := preload("res://scripts/ascii/ascii_grass_field.gd")

const CharacterCatalog := preload("res://scripts/dialogue/character_catalog.gd")
const DialogueCatalog := preload("res://scripts/dialogue/dialogue_catalog.gd")
const BELL_WRAITH := preload("res://data/battle/actors/bell_wraith.tres")
const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const BellSynth := preload("res://scripts/audio/bell_synth.gd")
const SCENE_SHADER := preload("res://scripts/ascii/ascii_scene.gdshader")
const FIGURE_SHADER := preload("res://scripts/ascii/ascii_figure_layer.gdshader")
const GLYPH_SHADER := preload("res://scripts/ascii/ascii_glyph.gdshader")
# Зимняя тема собрана генератором tools/compose_winter_theme.py: петля начинается после вступления.
const WINTER_THEME := preload("res://assets/music/snowbound_crossroads.ogg")
const WINTER_LOOP_START := 4 * 3 * 60.0 / 66.0
const FOOTSTEPS := {
	&"snow": [
		preload("res://assets/audio/footsteps/snow_01.wav"),
		preload("res://assets/audio/footsteps/snow_02.wav"),
		preload("res://assets/audio/footsteps/snow_03.wav"),
	],
	&"wood": [
		preload("res://assets/audio/footsteps/wood_01.wav"),
		preload("res://assets/audio/footsteps/wood_02.wav"),
		preload("res://assets/audio/footsteps/wood_03.wav"),
	],
	&"ground": [
		preload("res://assets/audio/footsteps/ground_01.wav"),
		preload("res://assets/audio/footsteps/ground_02.wav"),
		preload("res://assets/audio/footsteps/ground_03.wav"),
	],
}

const BASE_FONT_SIZE := 8
const VIEW_HEIGHT := 7.4
const CAMERA_TILT := deg_to_rad(42.0)
const WALK_SPEED := 2.1
const WALK_ACCEL := 9.0
const WALK_BRAKE := 11.0
const TURN_RATE := 9.0
# Совпадает с GAIT_REACH * FIGURE_SCALE / GAIT_STANCE в шейдере: так ступня не скользит.
const STEP_LENGTH := 0.68
const FOOT_REACH := 0.37
# Шаг звучит чуть раньше касания: у записи удар не в самом начале, плюс задержка звука.
const STEP_LEAD := 0.35
const FOOT_SIDE := 0.09
const LEAN_PER_SPEED := 0.035
const LEAN_PER_ACCEL := 0.012
const LEAN_LIMIT := 0.17
const COAT_TRAIL := 0.14
const COAT_STIFFNESS := 60.0
const COAT_DAMPING := 7.0
const COAT_LIMIT := 0.42
const PHYSICS_STEP := 1.0 / 120.0
const MAX_FRAME_TIME := 0.05
const WADE_SPEED := 0.55
# Доля шага, которую сдвиг вдоль препятствия должен пройти вперёд, иначе это упор.
const SLIDE_MIN_PROGRESS := 0.08
const STEP_BUS := &"AsciiFootsteps"
const STEP_KICK := 4.5
const STEP_KICK_RADIUS := 0.6
const FIGURE_LAYER_CELLS := Vector2i(56, 44)
const INTERACT_RADIUS := 2.6

const FLOWER_SEQUENCE: Array[Dictionary] = [
	{"speaker": &"", "text": "Цветок чёрный, как вода под ним. Он ничем не пахнет — только тихо звенит."},
	{"speaker": &"wraith", "text": "Посмотри вниз. Ты ведь уже стоял здесь. Вас там двое."},
]

signal dialogue_finished

## Раскладка мира и режим главы задаются до добавления в дерево.
var world_layout := &"crossroads"
## В главе герой один (Безымянный), музыку ведёт сама глава, событий перекрёстка нет.
var chapter_mode := false

var world: AsciiWorld
var grass_field := AsciiGrassField.new()
var hud: AsciiHud
var font: SystemFont
var font_size := BASE_FONT_SIZE
var cell := Vector2i(8, 14)
var grid := Vector2i(160, 45)
var cell_world := Vector2(0.08, 0.15)

var scene_viewport: SubViewport
var scene_rect: ColorRect
var glyph_rect: ColorRect
var scene_material: ShaderMaterial
var figure_material: ShaderMaterial
var glyph_material: ShaderMaterial
var ready_to_play := false

var player_position := AsciiWorld.SPAWN
var player_height := 0.3
var player_yaw := 0.0
var target_yaw := 0.0
var player_phase := 0.0
var player_move := 0.0
var player_velocity := Vector2.ZERO
var last_velocity := Vector2.ZERO
var player_lean := Vector2.ZERO
var coat_offset := Vector2.ZERO
var coat_velocity := Vector2.ZERO
var coat_lag := Vector2.ZERO
var character_index := 0
var camera_position := AsciiWorld.SPAWN
var elapsed := 0.0

var ripples: Array[Vector3] = []
var footprints: Array[Vector3] = []
var last_step_sound := -1

var dialogue_lines: Array = []
var dialogue_index := 0
var dialogue_progress := 0.0
var seen_flower := false

var bell_angle := 0.0
var bell_velocity := 0.0
var toll_count := 0
var scramble := 0.0
var resetting := false
var notice_timer := 0.0

var music: AudioStreamPlayer
var bell_player: AudioStreamPlayer
var step_players: Array[AudioStreamPlayer] = []
var step_voice := 0
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.randomize()
	_install_input_actions()
	_configure_window()
	font = FontAtlas.create_font()
	world = AsciiWorld.new(world_layout)
	player_position = world.spawn
	camera_position = world.spawn
	player_height = world.stand_height(world.spawn)
	player_yaw = world.spawn_yaw
	target_yaw = world.spawn_yaw
	_build_audio()
	await _build_screen()
	get_window().size_changed.connect(_fit_grid)
	ready_to_play = true


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	elapsed += delta

	if dialogue_lines.is_empty() and not resetting:
		_handle_movement(delta)
		_handle_interaction()
	else:
		_handle_movement(delta, false)
		_handle_dialogue(delta)

	var in_grass := world.surface_at(player_position) == &"ground"
	grass_field.step(delta, player_position, player_velocity, in_grass)
	_update_timers(delta)
	_update_camera()
	_push_uniforms()
	_update_hud()


# Окно не трогаем: его размер задан проектом (1440×810) и настройками (полный экран).
# Раньше сцена сама растягивала окно на масштаб экрана, и на Retina оно разворачивалось почти на весь экран.
func _configure_window() -> void:
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if not chapter_mode:
		window.title = "Цикл душ — ночь символов"
	font_size = roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())


func _build_screen() -> void:
	cell = FontAtlas.measure_cell(font, font_size)
	var atlas := await FontAtlas.build(self, font, font_size, cell)

	scene_viewport = SubViewport.new()
	scene_viewport.disable_3d = true
	scene_viewport.transparent_bg = true
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(scene_viewport)

	scene_material = ShaderMaterial.new()
	scene_material.shader = SCENE_SHADER
	scene_rect = ColorRect.new()
	scene_rect.material = scene_material
	scene_viewport.add_child(scene_rect)

	var figure_viewport := SubViewport.new()
	figure_viewport.disable_3d = true
	figure_viewport.transparent_bg = true
	figure_viewport.size = FIGURE_LAYER_CELLS
	figure_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(figure_viewport)

	figure_material = ShaderMaterial.new()
	figure_material.shader = FIGURE_SHADER
	figure_material.set_shader_parameter("layer_size", Vector2(FIGURE_LAYER_CELLS))
	var figure_rect := ColorRect.new()
	figure_rect.size = Vector2(FIGURE_LAYER_CELLS)
	figure_rect.material = figure_material
	figure_viewport.add_child(figure_rect)

	var layer := CanvasLayer.new()
	add_child(layer)

	glyph_material = ShaderMaterial.new()
	glyph_material.shader = GLYPH_SHADER
	glyph_material.set_shader_parameter("scene_tex", scene_viewport.get_texture())
	glyph_material.set_shader_parameter("figure_tex", figure_viewport.get_texture())
	glyph_material.set_shader_parameter("atlas_tex", atlas)
	glyph_material.set_shader_parameter("grass_bend", grass_field.texture)
	glyph_material.set_shader_parameter("cam_sin", sin(CAMERA_TILT))
	glyph_material.set_shader_parameter("cell_px", Vector2(cell))
	glyph_rect = ColorRect.new()
	glyph_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph_rect.material = glyph_material
	layer.add_child(glyph_rect)

	hud = AsciiHud.new()
	hud.font = font
	hud.font_size = font_size
	hud.cell = cell
	layer.add_child(hud)

	_push_static_uniforms()
	_fit_grid()


func _fit_grid() -> void:
	var window_size := get_window().size
	# Запас в три ячейки: сетка мира едет под окном.
	grid = Vector2i(ceili(float(window_size.x) / cell.x) + 3, ceili(float(window_size.y) / cell.y) + 3)
	scene_viewport.size = grid
	scene_rect.size = Vector2(grid)
	hud.grid = Vector2i(window_size.x / cell.x, window_size.y / cell.y)
	var world_per_px := VIEW_HEIGHT / float(window_size.y)
	cell_world = Vector2(cell) * world_per_px
	_set_scene_parameter("grid_size", Vector2(grid))
	_set_scene_parameter("cell_world", cell_world)
	glyph_material.set_shader_parameter("screen_px", Vector2(window_size))
	glyph_material.set_shader_parameter("cell_world", cell_world)


func _set_scene_parameter(parameter: StringName, value: Variant) -> void:
	scene_material.set_shader_parameter(parameter, value)
	figure_material.set_shader_parameter(parameter, value)


func _push_static_uniforms() -> void:
	_set_scene_parameter("world_map", world.map_texture)
	_set_scene_parameter("prop_map", world.prop_texture)
	_set_scene_parameter("world_size", AsciiWorld.SIZE)
	_set_scene_parameter("ruins_on", 1.0 if world.layout == &"crossroads" else 0.0)
	_set_scene_parameter("sea_on", 1.0 if world.island else 0.0)
	_set_scene_parameter("cam_sin", sin(CAMERA_TILT))
	_set_scene_parameter("cam_cos", cos(CAMERA_TILT))
	_set_scene_parameter("keeper_pos", _far_or_ground(world.keeper))
	_set_scene_parameter("keeper_yaw", 0.0)
	_set_scene_parameter("bell_pos", _far_or_ground(world.bell))
	var chapel := world.chapel
	_set_scene_parameter("chapel_pos", Vector3(chapel.x, 0.1, chapel.y))
	_set_scene_parameter("flower_pos", _far_or_ground(world.flower))
	_set_scene_parameter("pier_rect", world.pier_rect)
	_set_scene_parameter("pier_top", AsciiWorld.PIER_TOP)

	var lantern_data := PackedVector3Array(world.lanterns)
	while lantern_data.size() < 10:
		lantern_data.append(Vector3(0.0, -1.0, 0.0))
	_set_scene_parameter("lanterns", lantern_data)


func _push_uniforms() -> void:
	# Камера едет по целым пикселям: символы остаются чёткими, а мир не прыгает на ячейку.
	var cell_size := Vector2(cell)
	var window_size := Vector2(get_window().size)
	var camera_px := (Vector2(
		camera_position.x / cell_world.x,
		camera_position.y * sin(CAMERA_TILT) / cell_world.y
	) * cell_size).round()
	var camera_cell := (camera_px / cell_size).floor()
	var half_grid := (Vector2(grid) * 0.5).floor()
	var scroll := camera_px - camera_cell * cell_size + half_grid * cell_size - (window_size * 0.5).round()
	_set_scene_parameter("cam_cell", camera_cell)
	glyph_material.set_shader_parameter("cam_cell", camera_cell)
	glyph_material.set_shader_parameter("scroll_px", scroll)
	glyph_material.set_shader_parameter(
		"figure_origin", (window_size * 0.5 - Vector2(FIGURE_LAYER_CELLS) * cell_size * 0.5).round()
	)
	glyph_material.set_shader_parameter("hero_root_row", floori(((window_size * 0.5).round().y + scroll.y) / cell_size.y))
	_set_scene_parameter("time", elapsed)
	_set_scene_parameter(
		"player_pos", Vector3(player_position.x, player_height, player_position.y)
	)
	_set_scene_parameter("player_yaw", player_yaw)
	_set_scene_parameter("player_phase", player_phase)
	_set_scene_parameter("player_move", player_move)
	_set_scene_parameter("player_lean", player_lean)
	_set_scene_parameter("coat_lag", coat_lag)
	_set_scene_parameter("player_style", character_index)
	_set_scene_parameter("bell_swing", bell_angle)
	_set_scene_parameter("tolls", float(toll_count))
	_set_scene_parameter("wraith_on", 1.0 if seen_flower else 0.0)
	# Эхо держится за спиной игрока и видно только в отражении.
	var wraith_point := player_position + Vector2(1.5, -1.6)
	_set_scene_parameter("wraith_pos", Vector3(wraith_point.x, 0.0, wraith_point.y))

	var ripple_data := PackedVector3Array()
	for ripple in ripples:
		ripple_data.append(Vector3(ripple.x, ripple.y, elapsed - ripple.z))
	while ripple_data.size() < 8:
		ripple_data.append(Vector3(0.0, 0.0, -1.0))
	_set_scene_parameter("ripples", ripple_data)

	var print_data := PackedVector3Array()
	for footprint in footprints:
		print_data.append(Vector3(footprint.x, footprint.y, elapsed - footprint.z))
	while print_data.size() < 32:
		print_data.append(Vector3(0.0, 0.0, -1.0))
	_set_scene_parameter("footprints", print_data)

	glyph_material.set_shader_parameter("time", elapsed)
	glyph_material.set_shader_parameter("scramble", scramble)


func _handle_movement(delta: float, has_control: bool = true) -> void:
	var direction := Vector2.ZERO
	if has_control:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# Рывок кадра не должен проносить героя сквозь препятствие и раскачивать пружины.
	delta = minf(delta, MAX_FRAME_TIME)
	# В воде идти тем тяжелее, чем глубже: у кромки почти как по берегу.
	var depth := 0.0 if world.is_on_pier(player_position) else clampf(
		-world.height_at(player_position) / AsciiWorld.WADE_DEPTH, 0.0, 1.0
	)
	var top_speed := WALK_SPEED * lerpf(1.0, WADE_SPEED, depth)
	var rate := WALK_ACCEL if direction != Vector2.ZERO else WALK_BRAKE
	player_velocity = player_velocity.move_toward(direction * top_speed, rate * delta)
	var before := player_position
	_move_with_collisions(player_velocity * delta)

	var moved := player_position.distance_to(before)
	var moving := moved > 0.0001
	if direction != Vector2.ZERO:
		target_yaw = atan2(direction.x, direction.y)
	player_yaw = lerp_angle(player_yaw, target_yaw, 1.0 - exp(-delta * TURN_RATE))
	player_move = move_toward(player_move, 1.0 if moving else 0.0, delta * 5.0)
	var previous_phase := player_phase
	player_phase += moved * PI / STEP_LENGTH
	player_height = lerpf(player_height, world.stand_height(player_position), minf(delta * 14.0, 1.0))
	_update_body_motion(delta)

	if moving:
		_track_steps(previous_phase)


# Упёршись в камень или ствол, герой обтекает его по касательной, а не залипает.
# Скорость теряет только ту часть, что направлена в препятствие, поэтому скольжение плавное.
func _move_with_collisions(step: Vector2) -> void:
	var length := step.length()
	if length < 0.00001:
		return
	var target := player_position + step
	if world.can_stand(target):
		player_position = target
		return
	# Если герой всё же оказался внутри препятствия, наружу его выпускаем.
	var depth := world.clearance(player_position)
	if depth < 0.0:
		if world.clearance(target) > depth:
			player_position = target
		return

	var slid := world.push_out(target)
	var offset := slid - player_position
	if world.can_stand(slid) and offset.length() <= length * 1.05 + 0.001:
		# Лобовой упор или угол между двумя препятствиями: сдвиг почти не ведёт вперёд,
		# поэтому герой останавливается, а не дёргается от одной стенки к другой.
		if offset.dot(step) > length * length * SLIDE_MIN_PROGRESS:
			player_position = slid
		else:
			player_velocity = Vector2.ZERO
		_cancel_velocity_into(world.clearance_gradient(slid))
		return

	# Запасной путь для острых углов и края мостков: движение по осям раздельно.
	var moved_x := player_position + Vector2(step.x, 0.0)
	if world.can_stand(moved_x):
		player_position = moved_x
	else:
		player_velocity.x = 0.0
	var moved_z := player_position + Vector2(0.0, step.y)
	if world.can_stand(moved_z):
		player_position = moved_z
	else:
		player_velocity.y = 0.0


func _cancel_velocity_into(gradient: Vector2) -> void:
	if gradient.length_squared() < 0.0001:
		return
	var normal := gradient.normalized()
	var into := player_velocity.dot(normal)
	if into < 0.0:
		player_velocity -= normal * into


# Наклон корпуса и отставание пальто: пружина перехлёстывает при остановке и повороте.
# Пружина считается мелкими шагами фиксированной длины: от частоты кадров её поведение не зависит.
func _update_body_motion(delta: float) -> void:
	var acceleration := (player_velocity - last_velocity) / maxf(delta, 0.001)
	last_velocity = player_velocity
	var right := Vector2(cos(player_yaw), -sin(player_yaw))
	var forward := Vector2(sin(player_yaw), cos(player_yaw))

	var push := player_velocity * LEAN_PER_SPEED + acceleration * LEAN_PER_ACCEL
	var lean_target := Vector2(
		clampf(push.dot(right), -LEAN_LIMIT, LEAN_LIMIT),
		clampf(push.dot(forward), -LEAN_LIMIT, LEAN_LIMIT)
	)
	player_lean = player_lean.lerp(lean_target, 1.0 - exp(-delta * 8.0))

	var substeps := maxi(ceili(delta / PHYSICS_STEP), 1)
	var dt := delta / substeps
	for substep in range(substeps):
		var coat_force := (-player_velocity * COAT_TRAIL - coat_offset) * COAT_STIFFNESS
		coat_velocity += (coat_force - coat_velocity * COAT_DAMPING) * dt
		coat_offset += coat_velocity * dt
		# Упёршись в предел, полы не копят скорость наружу, иначе отскок выходит рывком.
		if coat_offset.length() > COAT_LIMIT:
			var outward := coat_offset.normalized()
			coat_offset = outward * COAT_LIMIT
			var radial := coat_velocity.dot(outward)
			if radial > 0.0:
				coat_velocity -= outward * radial
	coat_lag = Vector2(coat_offset.dot(right), coat_offset.dot(forward))


# Шаг звучит и оставляет след в тот момент, когда пятка касается земли.
func _track_steps(previous_phase: float) -> void:
	var strike := floori((player_phase + STEP_LEAD) / PI)
	if strike == floori((previous_phase + STEP_LEAD) / PI):
		return
	var is_left := posmod(strike, 2) == 0
	var right := Vector2(cos(player_yaw), -sin(player_yaw))
	var forward := Vector2(sin(player_yaw), cos(player_yaw))
	var planted := player_position + forward * FOOT_REACH + right * (-FOOT_SIDE if is_left else FOOT_SIDE)
	if world.is_water(planted):
		_add_ripple(planted)
	elif not world.is_on_pier(planted):
		footprints.append(Vector3(planted.x, planted.y, elapsed))
		if footprints.size() > 32:
			footprints.pop_front()
	if world.surface_at(planted) == &"ground":
		grass_field.kick(planted, STEP_KICK, STEP_KICK_RADIUS)
	_play_step(is_left)


func _add_ripple(point: Vector2) -> void:
	ripples.append(Vector3(point.x, point.y, elapsed))
	if ripples.size() > 8:
		ripples.pop_front()


func _handle_interaction() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	var target := _nearest_interactable()
	match target:
		&"keeper":
			_open_catalog_dialogue(&"keeper_first_meeting")
		&"bell":
			_toll_bell()
		&"flower":
			_open_lines(FLOWER_SEQUENCE)
			seen_flower = true
			_add_ripple(world.flower + Vector2(0.0, 2.5))


func _nearest_interactable() -> StringName:
	var candidates := world.interactables()
	var best := &""
	var best_distance := INTERACT_RADIUS
	for id: StringName in candidates:
		var distance := player_position.distance_to(candidates[id])
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


func _open_catalog_dialogue(sequence_id: StringName) -> void:
	var lines: Array[Dictionary] = []
	for line: Dictionary in DialogueCatalog.get_sequence(sequence_id):
		lines.append({"speaker": line["character"], "text": line["text"]})
	_open_lines(lines)


func _open_lines(lines: Array[Dictionary]) -> void:
	dialogue_lines = lines
	dialogue_index = 0
	dialogue_progress = 0.0


func _handle_dialogue(delta: float) -> void:
	if dialogue_lines.is_empty():
		return
	var line_length: int = String(dialogue_lines[dialogue_index]["text"]).length()
	var was_done := dialogue_progress >= line_length
	dialogue_progress = minf(dialogue_progress + delta * 42.0, line_length)
	if not Input.is_action_just_pressed("interact"):
		return
	if not was_done:
		dialogue_progress = line_length
		return
	dialogue_index += 1
	dialogue_progress = 0.0
	if dialogue_index >= dialogue_lines.size():
		dialogue_lines = []
		dialogue_finished.emit()


func _toll_bell() -> void:
	bell_velocity += 1.4 if bell_angle <= 0.0 else -1.4
	bell_player.play()
	toll_count += 1
	_add_ripple(world.pond_center + Vector2(-5.0, -3.0))
	_add_ripple(world.pond_center + Vector2(6.0, 2.0))
	if toll_count >= 3:
		_restart_night()
	else:
		_show_notice("Колокол: %d из 3" % toll_count)


func _restart_night() -> void:
	resetting = true
	_show_notice("Эта ночь начинается сначала")
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(self, "scramble", 1.0, 1.2)
	tween.tween_callback(func() -> void:
		player_position = world.spawn
		camera_position = player_position
		player_height = world.stand_height(player_position)
		footprints.clear()
		ripples.clear()
		toll_count = 0
		seen_flower = false
	)
	tween.tween_property(self, "scramble", 0.0, 1.0)
	tween.tween_callback(func() -> void: resetting = false)


func _show_notice(text: String) -> void:
	hud.notice_text = text
	notice_timer = 2.6


func _update_timers(delta: float) -> void:
	notice_timer = maxf(notice_timer - delta, 0.0)
	# Качание колокола — затухающий маятник.
	bell_velocity += (-bell_angle * 9.0 - bell_velocity * 0.55) * delta
	bell_angle += bell_velocity * delta

	while not ripples.is_empty() and elapsed - ripples[0].z > 6.0:
		ripples.pop_front()
	while not footprints.is_empty() and elapsed - footprints[0].z > 45.0:
		footprints.pop_front()


# Камера жёстко держит героя в центре: плавность даёт разгон и торможение самого героя.
# Камера смотрит туда, где на экране стоят его ступни: на возвышенности (городок выше озера)
# точка у подножия уезжает вниз на высоту × ctg(наклона), поэтому центр сдвигаем на неё же.
func _update_camera() -> void:
	camera_position = player_position - Vector2(0.0, player_height * cos(CAMERA_TILT) / sin(CAMERA_TILT))


func _update_hud() -> void:
	hud.notice_alpha = minf(notice_timer, 1.0)
	hud.tags.clear()

	var target := _nearest_interactable() if dialogue_lines.is_empty() and not resetting else &""
	match target:
		&"keeper":
			hud.tags.append(_make_tag(
				world.keeper, 1.75, "[E] Смотритель", Color(0.94, 0.77, 0.42)
			))
		&"bell":
			hud.tags.append(_make_tag(
				world.bell, 3.0, "[E] ударить в колокол", Color(0.94, 0.77, 0.42)
			))
		&"flower":
			hud.tags.append(_make_tag(
				world.flower, 1.75, "[E] чёрный цветок", Color(0.94, 0.77, 0.42)
			))

	if dialogue_lines.is_empty():
		hud.dialogue_speaker = ""
	else:
		var line: Dictionary = dialogue_lines[dialogue_index]
		_apply_speaker(line["speaker"])
		hud.dialogue_text = line["text"]
		hud.dialogue_visible_chars = int(dialogue_progress)
	hud.queue_redraw()


func _apply_speaker(speaker: StringName) -> void:
	if speaker == &"wraith":
		hud.dialogue_speaker = BELL_WRAITH.display_name
		hud.dialogue_color = BELL_WRAITH.accent_color
		return
	var is_player := speaker == &"" or speaker == &"nameless" or speaker == &"wanderer"
	var profile: CharacterProfile = (
		CharacterCatalog.get_playable_profile(character_index)
		if is_player
		else CharacterCatalog.get_profile(speaker)
	)
	hud.dialogue_speaker = profile.display_name
	hud.dialogue_color = DialogueCatalog.get_theme(profile.dialogue_theme_id).name_color


func _make_tag(point: Vector2, height: float, text: String, color: Color) -> Dictionary:
	var anchor := _world_to_screen(Vector3(point.x, height, point.y))
	var col := floori(anchor.x / cell.x)
	var row := floori(anchor.y / cell.y)
	return {
		"col": col,
		"row": row,
		"shift": anchor - Vector2(col * cell.x, row * cell.y),
		"text": text,
		"color": color,
	}


func _world_to_screen(point: Vector3) -> Vector2:
	var world_per_px := cell_world.x / cell.x
	var rise := point.y * cos(CAMERA_TILT) - (point.z - camera_position.y) * sin(CAMERA_TILT)
	return Vector2(get_window().size) * 0.5 + Vector2(point.x - camera_position.x, -rise) / world_per_px


# Чего нет в этой раскладке, уносится далеко за край мира, а не ставится на землю.
func _far_or_ground(point: Vector2) -> Vector3:
	if point.x < -100.0:
		return Vector3(-1000.0, 0.0, -1000.0)
	return _ground_point(point)


## Реплики, запущенные снаружи (например, главой): как обычный диалог.
func say(lines: Array[Dictionary]) -> void:
	_open_lines(lines)


func _ground_point(point: Vector2) -> Vector3:
	return Vector3(point.x, world.stand_height(point), point.y)


func _build_audio() -> void:
	var looped_theme := WINTER_THEME.duplicate() as AudioStreamOggVorbis
	looped_theme.loop = true
	looped_theme.loop_offset = WINTER_LOOP_START
	music = AudioStreamPlayer.new()
	music.stream = looped_theme
	music.volume_db = -20.0
	music.bus = &"Music"
	add_child(music)
	if not chapter_mode:
		music.play()

	bell_player = AudioStreamPlayer.new()
	bell_player.stream = BellSynth.create()
	bell_player.volume_db = -7.0
	bell_player.bus = &"SFX"
	add_child(bell_player)

	_build_step_bus()
	for voice in range(2):
		var step_player := AudioStreamPlayer.new()
		step_player.bus = STEP_BUS
		add_child(step_player)
		step_players.append(step_player)


# Срез верхов убирает щелчок в начале шага, короткий хвост склеивает шаги между собой.
func _build_step_bus() -> void:
	# Шина живёт дольше сцены: при повторном входе из меню её не создаём заново.
	if AudioServer.get_bus_index(STEP_BUS) >= 0:
		return
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, STEP_BUS)
	# Шаги идут через общую шину звуков, чтобы их громкость задавалась в настройках.
	AudioServer.set_bus_send(bus, &"SFX")
	var low_pass := AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = 3600.0
	AudioServer.add_bus_effect(bus, low_pass)
	var tail := AudioEffectReverb.new()
	tail.room_size = 0.22
	tail.damping = 0.8
	tail.wet = 0.1
	tail.dry = 1.0
	AudioServer.add_bus_effect(bus, tail)


func _play_step(is_left: bool) -> void:
	var surface := world.surface_at(player_position)
	var sounds: Array = FOOTSTEPS[surface]
	var sound_index := random.randi_range(0, sounds.size() - 1)
	if sound_index == last_step_sound:
		sound_index = (sound_index + 1) % sounds.size()
	last_step_sound = sound_index

	var step_player := step_players[step_voice]
	step_voice = (step_voice + 1) % step_players.size()
	step_player.stream = sounds[sound_index]
	# Левая и правая нога звучат чуть по-разному, а первый шаг с места тише остальных.
	step_player.pitch_scale = (0.99 if is_left else 1.005) + random.randf_range(-0.01, 0.01)
	var pace := clampf(player_velocity.length() / WALK_SPEED, 0.0, 1.0)
	step_player.volume_db = lerpf(-15.0, -9.0, pace) + random.randf_range(-1.0, 1.0)
	step_player.play()


func _install_input_actions() -> void:
	_add_key_to_action("move_left", KEY_A)
	_add_key_to_action("move_left", KEY_LEFT)
	_add_key_to_action("move_right", KEY_D)
	_add_key_to_action("move_right", KEY_RIGHT)
	_add_key_to_action("move_up", KEY_W)
	_add_key_to_action("move_up", KEY_UP)
	_add_key_to_action("move_down", KEY_S)
	_add_key_to_action("move_down", KEY_DOWN)
	_add_key_to_action("interact", KEY_E)
	_add_key_to_action("interact", KEY_SPACE)
	_add_key_to_action("interact", KEY_ENTER)


func _add_key_to_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, key_event)
