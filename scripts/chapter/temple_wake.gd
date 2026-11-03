extends Node

# Пробуждение в храме — начало второй главы, от первого лица.
# Герой лежит в кровати и смотрит в потолок: веки тяжело открываются, раз-другой смыкаются,
# взгляд не сразу фокусируется на световом проёме. Он садится, оборачивается к тумбочке
# с вазой и цветком, встаёт. Дальше — свободно по комнате:
# W/S — вперёд-назад, A/D — вбок, мышь или стрелки — поворот головы, E — действие.
# У цветка — короткая мысль, у дверей E — двери разъезжаются, за ними ждёт воин. Он говорит
# и ведёт по коридору, поджидая, если отстать. У дальних дверей сцена гаснет и сообщает finished.

signal finished

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const DialogueView := preload("res://scripts/ui/dialogue_view.gd")
const ROOM_SHADER := preload("res://scripts/chapter/temple_room.gdshader")
const GLYPH_SHADER := preload("res://scripts/chapter/temple_glyph.gdshader")
const STEPS: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/wood_01.wav"),
	preload("res://assets/audio/footsteps/wood_02.wav"),
	preload("res://assets/audio/footsteps/wood_03.wav"),
]

const BASE_FONT_SIZE := 8
# Те же числа, что в temple_room.gdshader: комната, кровать, тумбочка, коридор.
const ROOM_HALF := 2.6
const ROOM_Z := Vector2(-1.5, 5.0)
const BODY := 0.3
const BED_RECT := Rect2(-2.6, 1.4 - BODY, 1.85 + BODY, 2.5 + BODY * 2.0)
const STAND_RECT := Rect2(-0.66 - BODY, 2.59 - BODY, 0.62 + BODY * 2.0, 0.62 + BODY * 2.0)
const FLOWER := Vector3(-0.35, 1.3, 2.9)
const CORRIDOR_HALF := 1.2
const CORRIDOR_END := 22.0
const DOOR_Z := 4.4
const DOOR_TIME := 1.5
# Где лежит, где сидит и куда встаёт.
const LIE_AT := Vector2(-1.575, 3.2)
const SIT_AT := Vector2(-1.575, 3.1)
const STAND_AT := Vector2(-0.35, 2.1)
const LIE_EYE := 0.62
const SIT_EYE := 1.12
# Воин: откуда ведёт, где останавливается, как далеко даёт отстать.
const WARRIOR_START := 6.4
const WARRIOR_END := 20.0
const WARRIOR_WALK := 1.25
const WARRIOR_WAIT := 3.5
const WARRIOR_STEP := 0.72
# Остановиться перед ним, а не пройти насквозь.
const WARRIOR_GAP := 0.9
const ARRIVE_GAP := 2.8
const EYE := 1.6
const WALK := 1.6
const TURN := 1.8
const MOUSE_TURN := 0.0035
const STEP_LENGTH := 0.72

const WAKE_LINES: Array[Dictionary] = [
	{"speaker": &"self", "text": "…Опять этот свет."},
	{"speaker": &"self", "text": "Сколько я спал? И откуда здесь этот цветок…"},
]
const FLOWER_LINES: Array[Dictionary] = [
	{"speaker": &"self", "text": "Он смотрит. С какой стороны ни подойди."},
]
const WARRIOR_LINES: Array[Dictionary] = [
	{"speaker": &"warrior", "text": "Очнулся. Тебя ждут."},
	{"speaker": &"self", "text": "Кто?"},
	{"speaker": &"warrior", "text": "Иди за мной. И не отставай."},
]
const SPEAKERS := {
	&"self": ["???", Color(0.95, 0.72, 0.62)],
	&"warrior": ["Воин", Color(0.78, 0.82, 0.92)],
}

enum State { DARK, WAKING, SITTING_UP, TALK, STANDING, FREE, OPENING, GREETING, FOLLOWING, LEAVING }

var room_material: ShaderMaterial
var glyph_material: ShaderMaterial
var room_viewport: SubViewport
var room_rect: ColorRect
var overlay: Control
var mono: Font
var serif: Font
var step_player: AudioStreamPlayer
var cell := Vector2i(5, 8)
var ready_to_play := false

var state := State.DARK
var state_time := 0.0
var elapsed := 0.0
var pos := LIE_AT
var height := LIE_EYE
var yaw := 0.0
var pitch := 0.6
var roll := 0.0
var lids := 0.0
var blur := 1.0
var fade := 0.0
var walk_phase := 0.0
var door_open := 0.0
var warrior_z := WARRIOR_START
var warrior_yaw := 0.0
var warrior_phase := 0.0
var warrior_walk := 0.0
var warrior_step_player: AudioStreamPlayer
var _talked_this_frame := false

var lines: Array = []
var line_index := 0
var line_progress := 0.0
var _after_lines := Callable()


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
	cell = FontAtlas.measure_cell(mono, font_size)
	var atlas := await FontAtlas.build(self, mono, font_size, cell)
	_build(atlas)
	get_window().size_changed.connect(_fit)
	_fit()
	ready_to_play = true


func _build(atlas: Texture2D) -> void:
	room_viewport = SubViewport.new()
	room_viewport.disable_3d = true
	# Альфа несёт код знака: без прозрачного фона она стала бы 1 и коды бы потерялись.
	room_viewport.transparent_bg = true
	room_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(room_viewport)
	room_material = ShaderMaterial.new()
	room_material.shader = ROOM_SHADER
	room_material.set_shader_parameter("cell_px", Vector2(cell))
	room_rect = ColorRect.new()
	room_rect.material = room_material
	room_viewport.add_child(room_rect)

	# Поверх кадра берега главы, но под её карточками и шторкой.
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	glyph_material = ShaderMaterial.new()
	glyph_material.shader = GLYPH_SHADER
	glyph_material.set_shader_parameter("scene_tex", room_viewport.get_texture())
	glyph_material.set_shader_parameter("atlas_tex", atlas)
	glyph_material.set_shader_parameter("cell_px", Vector2(cell))
	var screen := ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.material = glyph_material
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
	warrior_step_player = AudioStreamPlayer.new()
	warrior_step_player.bus = step_player.bus
	add_child(warrior_step_player)


func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	var grid := Vector2i(ceili(size.x / cell.x), ceili(size.y / cell.y))
	room_viewport.size = grid
	room_rect.size = Vector2(grid)
	room_material.set_shader_parameter("grid_size", Vector2(grid))
	glyph_material.set_shader_parameter("screen_px", size)


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	delta = minf(delta, 0.05)
	elapsed += delta
	state_time += delta
	# Нажатие, которым закрыли реплику, не должно тут же открыть новую.
	var was_talking := not lines.is_empty()
	if was_talking:
		_advance_lines(delta)
	_talked_this_frame = was_talking
	match state:
		State.DARK:
			if state_time > 1.6:
				_go(State.WAKING)
		State.WAKING:
			_waking()
		State.SITTING_UP:
			_sitting_up()
		State.TALK:
			pass
		State.STANDING:
			_standing()
		State.FREE:
			_free(delta)
		State.OPENING:
			_opening(delta)
		State.GREETING:
			_look_at_warrior(delta)
		State.FOLLOWING:
			_free(delta)
			_lead(delta)
		State.LEAVING:
			fade = clampf(state_time / 1.6, 0.0, 1.0)
			if state_time > 1.9:
				set_process(false)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				finished.emit()
	_push()
	overlay.queue_redraw()


func _go(next: State) -> void:
	state = next
	state_time = 0.0


# Веки поднимаются тяжело: приоткрылись — сомкнулись — открылись шире — моргнул — открыл.
func _waking() -> void:
	var t := state_time
	var keys := [[0.0, 0.0], [0.9, 0.28], [1.5, 0.08], [2.4, 0.55], [2.9, 0.3], [3.3, 0.34], [4.2, 0.85], [4.45, 0.05], [4.8, 1.0]]
	lids = _track(keys, t)
	blur = clampf(1.0 - (t - 1.0) / 4.2, 0.0, 1.0)
	# Взгляд блуждает по потолку, задерживается на проёме.
	yaw = 0.55 + 0.25 * sin(t * 0.35) * (1.0 - smoothstep(3.0, 5.0, t))
	pitch = 0.6 - 0.05 * smoothstep(2.0, 5.0, t)
	if t > 5.6:
		_go(State.SITTING_UP)


# Садится: корпус поднимается, голова поворачивается к цветку на тумбочке, мир чуть кренится.
func _sitting_up() -> void:
	var t := clampf(state_time / 2.4, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	height = lerpf(LIE_EYE, SIT_EYE, e)
	pos = LIE_AT.lerp(SIT_AT, e)
	yaw = lerpf(0.55, 1.41, e)
	pitch = lerpf(0.55, 0.12, e)
	roll = sin(t * PI) * 0.12
	blur = 0.0
	if t >= 1.0 and lines.is_empty():
		_say(WAKE_LINES, func() -> void: _go(State.STANDING))
		_go(State.TALK)


# Встаёт с кровати и остаётся лицом к цветку; за ним, дальше, двери.
func _standing() -> void:
	var t := clampf(state_time / 2.0, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	height = lerpf(SIT_EYE, EYE, e)
	pos = SIT_AT.lerp(STAND_AT, e)
	yaw = lerp_angle(1.41, PI, e)
	roll = -sin(t * PI) * 0.05
	pitch = lerpf(0.12, atan2(FLOWER.y - EYE, FLOWER.z - STAND_AT.y), e)
	if t >= 1.0:
		roll = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_go(State.FREE)


func _free(delta: float) -> void:
	var talking := not lines.is_empty()
	var move := Vector2.ZERO
	if not talking:
		if Input.is_physical_key_pressed(KEY_W):
			move.y += 1.0
		if Input.is_physical_key_pressed(KEY_S):
			move.y -= 1.0
		if Input.is_physical_key_pressed(KEY_A):
			move.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			move.x += 1.0
		yaw += (float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))) * TURN * delta
		pitch += (float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))) * TURN * 0.6 * delta
		pitch = clampf(pitch, -0.9, 0.9)
	var forward := Vector2(sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), sin(yaw))
	var step := (forward * move.y + right * move.x).limit_length(1.0) * WALK * delta
	var before := pos
	pos = _collide(pos + step)
	var moved := pos.distance_to(before)
	var previous := walk_phase
	walk_phase += moved * PI / STEP_LENGTH
	if floori(walk_phase / PI) != floori(previous / PI):
		_step()
	# Голова чуть покачивается в такт шагу.
	height = EYE + 0.025 * sin(walk_phase * 2.0) * minf(moved / maxf(WALK * delta, 0.0001), 1.0)
	roll = lerpf(roll, 0.01 * sin(walk_phase), 0.2)
	if not talking and not _talked_this_frame and Input.is_action_just_pressed(&"interact"):
		if state != State.FREE:
			return
		# Дверь раньше цветка: от двери до тумбочки всего шаг.
		if pos.y > DOOR_Z - 0.6 and absf(pos.x) < CORRIDOR_HALF:
			_go(State.OPENING)
		elif pos.distance_to(Vector2(FLOWER.x, FLOWER.z)) < 1.4:
			_say(FLOWER_LINES, Callable())


# Створки разъезжаются, взгляд сам находит того, кто стоит за ними.
func _opening(delta: float) -> void:
	var t := clampf(state_time / DOOR_TIME, 0.0, 1.0)
	door_open = t * t * (3.0 - 2.0 * t)
	_look_at_warrior(delta)
	if t >= 1.0:
		_say(WARRIOR_LINES, func() -> void: _go(State.FOLLOWING))
		_go(State.GREETING)


func _look_at_warrior(delta: float) -> void:
	var to_face := Vector3(0.0, 1.78, warrior_z) - Vector3(pos.x, EYE, pos.y)
	var k := minf(delta * 3.0, 1.0)
	yaw = lerp_angle(yaw, atan2(to_face.x, -to_face.z), k)
	pitch = lerpf(pitch, atan2(to_face.y, Vector2(to_face.x, to_face.z).length()), k)


# Воин разворачивается и идёт впереди; отстанешь — ждёт. У дальних дверей путь кончается.
func _lead(delta: float) -> void:
	warrior_yaw = lerp_angle(warrior_yaw, PI, minf(delta * 3.0, 1.0))
	var turned := state_time > 0.9
	var wants_to_walk := turned and warrior_z < WARRIOR_END and pos.y > warrior_z - WARRIOR_WAIT
	warrior_walk = move_toward(warrior_walk, 1.0 if wants_to_walk else 0.0, delta * 3.0)
	var travel := WARRIOR_WALK * warrior_walk * delta
	warrior_z = minf(warrior_z + travel, WARRIOR_END)
	var previous := warrior_phase
	warrior_phase += travel * PI / WARRIOR_STEP
	if floori(warrior_phase / PI) != floori(previous / PI):
		warrior_step_player.stream = STEPS[randi() % STEPS.size()]
		warrior_step_player.pitch_scale = randf_range(0.8, 0.86)
		warrior_step_player.volume_db = -13.0
		warrior_step_player.play()
	if warrior_z >= WARRIOR_END and warrior_walk < 0.05 and pos.y > WARRIOR_END - ARRIVE_GAP:
		_go(State.LEAVING)


# Стены и мебель не пускают; скольжение вдоль них — по осям. Открытые двери ведут в коридор,
# а воина насквозь не пройти.
func _collide(target: Vector2) -> Vector2:
	var door_edge := ROOM_Z.y - BODY
	var hall := CORRIDOR_HALF - BODY
	var through := door_open >= 1.0 and (pos.y > door_edge or absf(target.x) < hall)
	var far := minf(CORRIDOR_END - BODY, warrior_z - WARRIOR_GAP) if through else door_edge
	var p := Vector2(target.x, clampf(target.y, ROOM_Z.x + BODY, far))
	var half := hall if p.y > door_edge else ROOM_HALF - BODY
	p.x = clampf(p.x, -half, half)
	for rect: Rect2 in [BED_RECT, STAND_RECT]:
		if rect.has_point(p):
			if not rect.has_point(Vector2(p.x, pos.y)):
				p = Vector2(p.x, pos.y)
			elif not rect.has_point(Vector2(pos.x, p.y)):
				p = Vector2(pos.x, p.y)
			else:
				p = pos
	return p


func _step() -> void:
	step_player.stream = STEPS[randi() % STEPS.size()]
	step_player.pitch_scale = randf_range(0.97, 1.02)
	step_player.volume_db = -15.0 + randf_range(-0.8, 0.8)
	step_player.play()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	var looking := state == State.FREE or state == State.FOLLOWING
	if motion != null and looking and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and lines.is_empty():
		yaw += motion.relative.x * MOUSE_TURN
		pitch = clampf(pitch - motion.relative.y * MOUSE_TURN, -0.9, 0.9)


# Пауза отпускает мышь, после паузы ловим её снова.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if overlay != null:
			overlay.queue_redraw()
	elif what == NOTIFICATION_UNPAUSED and (state == State.FREE or state == State.FOLLOWING):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _track(keys: Array, t: float) -> float:
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var k := clampf((t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
			return lerpf(a[1], b[1], k * k * (3.0 - 2.0 * k))
	return keys[-1][1]


func _push() -> void:
	room_material.set_shader_parameter("cam_pos", Vector3(pos.x, height, pos.y))
	room_material.set_shader_parameter("cam_yaw", yaw)
	room_material.set_shader_parameter("cam_pitch", pitch)
	room_material.set_shader_parameter("cam_roll", roll)
	room_material.set_shader_parameter("time", elapsed)
	room_material.set_shader_parameter("door_open", door_open)
	room_material.set_shader_parameter("warrior_pos", Vector3(0.0, 0.0, warrior_z))
	room_material.set_shader_parameter("warrior_yaw", warrior_yaw)
	room_material.set_shader_parameter("warrior_phase", warrior_phase)
	room_material.set_shader_parameter("warrior_walk", warrior_walk)
	glyph_material.set_shader_parameter("time", elapsed)
	glyph_material.set_shader_parameter("lids", lids)
	glyph_material.set_shader_parameter("blur", blur)
	glyph_material.set_shader_parameter("fade", fade)


func _say(new_lines: Array[Dictionary], after: Callable) -> void:
	lines = new_lines
	line_index = 0
	line_progress = 0.0
	_after_lines = after


func _advance_lines(delta: float) -> void:
	var length := String(lines[line_index]["text"]).length()
	var was_done := line_progress >= length
	line_progress = minf(line_progress + delta * 36.0, length)
	if not Input.is_action_just_pressed(&"interact"):
		return
	if not was_done:
		line_progress = length
		return
	line_index += 1
	line_progress = 0.0
	if line_index >= lines.size():
		lines = []
		var after := _after_lines
		_after_lines = Callable()
		if after.is_valid():
			after.call()


func _draw_overlay() -> void:
	if get_tree().paused or lines.is_empty():
		return
	var line: Dictionary = lines[line_index]
	var speaker: Array = SPEAKERS[line["speaker"]]
	DialogueView.draw(overlay, mono, serif, speaker[0], speaker[1], line["text"], int(line_progress), elapsed)
