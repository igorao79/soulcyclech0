extends Node

# Библиотека изнутри и видение за столом (глава первая, после городка).
# 1. Вид сбоку (library.gdshader): Безымянный входит с улицы, идёт вдоль полок, снимает
#    светящуюся книгу (E), идёт к столу со свечой и садится (E).
#    Когда он садится, музыка улицы стихает совсем.
# 2. Он начинает читать — кадр сгорает красным шумом от середины, как «Начать путь»
#    на главном экране, бьёт колокол, и нас уносит в видение (vision.gdshader): двойник
#    с чёрным лицом, звёздными глазами и белыми полосами по телу парит в пустой тьме.
#    Слов нет — рядом раскрыта книга «Цикл душ» с названиями томов: вписан пока
#    только первый, «Звездопад». Книгу можно только закрыть. Сохранения делаются
#    сами на чекпоинтах (save_book.gd), а чекпоинтов пока нет.
# Когда книгу закрыли, сцена гаснет и сообщает finished.

signal finished

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const DialogueView := preload("res://scripts/ui/dialogue_view.gd")
const AsciiMenu := preload("res://scripts/ui/ascii_menu.gd")
const LIBRARY_SHADER := preload("res://scripts/chapter/library.gdshader")
const VISION_SHADER := preload("res://scripts/chapter/vision.gdshader")
const VISION_ART := preload("res://assets/chapter/vision.jpg")
# Тема видения собрана генератором tools/compose_vision_theme.py, петля — весь файл.
const VISION_MUSIC := preload("res://assets/music/vision_theme.ogg")
const STEPS: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/wood_01.wav"),
	preload("res://assets/audio/footsteps/wood_02.wav"),
	preload("res://assets/audio/footsteps/wood_03.wav"),
]

const BASE_FONT_SIZE := 8
const VIEW_HEIGHT := 4.4
const CAMERA_Y := 1.55
# Те же числа, что в library.gdshader: края комнаты, книга на полке, стул.
const ROOM := Vector2(-6.9, 8.1)
const CAMERA_LIMIT := Vector2(-3.6, 4.6)
const BOOK_X := -1.32
const SEAT_X := 3.12
const START_X := -6.5
const WALK_SPEED := 1.55
const ACCEL := 6.0
const BRAKE := 8.0
const STEP_LENGTH := 0.68
# Шаг звучит чуть раньше касания: у записи удар не в самом начале, плюс задержка звука.
const STEP_LEAD := 0.35
const REACH := 0.55
const SIT_TIME := 1.3
const OUTRO_TIME := 1.1
const MUSIC_FADE := 2.5
# Оглавление книги: вписан только первый том.
const VOLUMES: Array[String] = ["Том первый. Звездопад", "Том второй. страницы пусты", "Том третий. страницы пусты"]
# Взгляд вправо и чуть на зрителя; за столом — строго на столешницу.
const FACE_RIGHT := PI * 0.5 - 0.4
const FACE_LEFT := -PI * 0.5 + 0.4
const FACE_TABLE := PI * 0.5

const ENTER_LINES: Array[Dictionary] = [
	{"speaker": &"nameless", "text": "Свечи ещё горят. Значит, не опоздал."},
	{"speaker": &"nameless", "text": "…Та книга у фонаря опять светится."},
]
const BOOK_LINES: Array[Dictionary] = [
	{"speaker": &"nameless", "text": "«Цикл душ». Ни автора, ни года."},
]
const READ_LINES: Array[Dictionary] = [
	{"speaker": &"nameless", "text": "Пусто… Нет. Буквы проступают."},
]
const SPEAKERS := {
	&"nameless": ["Безымянный", Color(0.86, 0.89, 0.98)],
}

enum State { ENTER, WALK, TAKING, TO_SEAT, SITTING, READING, TO_VISION, VISION, OUT }

var library_material: ShaderMaterial
var vision_material: ShaderMaterial
var library_rect: ColorRect
var vision_rect: ColorRect
var overlay: Control
var mono: Font
var serif: Font
var step_player: AudioStreamPlayer
var ready_to_play := false

var state := State.ENTER
var state_time := 0.0
var elapsed := 0.0
var x := START_X
var velocity := 0.0
var yaw := FACE_RIGHT
var phase := 0.0
var move := 0.0
var lean := Vector2.ZERO
var coat := 0.0
var chair := 0.0
var holding := false
var taken := false
var book_open := false
var fade := 1.0
var vision_fade := 0.0
var outro := 0.0
## Музыка главы: глава отдаёт её сюда, чтобы она стихла, когда герой сядет за стол.
var music: AudioStreamPlayer
var save_menu: AsciiMenu
var vision_music: AudioStreamPlayer

var lines: Array = []
var line_index := 0
var line_progress := 0.0
var _after_lines := Callable()


func _ready() -> void:
	_ensure_actions()
	mono = FontAtlas.create_font()
	serif = UiStyle.serif(600.0)
	var font_size := roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())
	var cell := FontAtlas.measure_cell(mono, font_size)
	var atlas := await FontAtlas.build(self, mono, font_size, cell)
	_build(atlas, cell)
	ready_to_play = true


func _build(atlas: Texture2D, cell: Vector2i) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	library_material = ShaderMaterial.new()
	library_material.shader = LIBRARY_SHADER
	library_material.set_shader_parameter("atlas_tex", atlas)
	library_material.set_shader_parameter("cell_px", Vector2(cell))
	library_material.set_shader_parameter("view_height", VIEW_HEIGHT)
	# Смотрителя здесь нет: уводим его подальше, чтобы швы ткани считались от героя.
	library_material.set_shader_parameter("keeper_pos", Vector3(9999.0, 0.0, 9999.0))
	library_rect = _full_rect(library_material)
	layer.add_child(library_rect)

	vision_material = ShaderMaterial.new()
	vision_material.shader = VISION_SHADER
	vision_material.set_shader_parameter("atlas_tex", atlas)
	vision_material.set_shader_parameter("cell_px", Vector2(cell))
	vision_material.set_shader_parameter("art_tex", VISION_ART)
	vision_material.set_shader_parameter("art_aspect", float(VISION_ART.get_width()) / VISION_ART.get_height())
	vision_rect = _full_rect(vision_material)
	vision_rect.hide()
	layer.add_child(vision_rect)

	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)

	step_player = AudioStreamPlayer.new()
	# Та же шина, что у шагов снаружи: срез верхов и короткий хвост, если она уже есть.
	step_player.bus = &"AsciiFootsteps" if AudioServer.get_bus_index(&"AsciiFootsteps") >= 0 else &"SFX"
	add_child(step_player)


func _full_rect(material: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	delta = minf(delta, 0.05)
	elapsed += delta
	state_time += delta
	var talking := not lines.is_empty()
	if talking:
		_advance_lines(delta)

	match state:
		State.ENTER:
			fade = clampf(1.0 - state_time / 1.4, 0.0, 1.0)
			_walk(delta, 0.0)
			if state_time > 1.2 and not talking:
				_say(ENTER_LINES, func() -> void: _go(State.WALK))
		State.WALK:
			var axis := 0.0 if talking else Input.get_axis(&"move_left", &"move_right")
			_walk(delta, axis)
			if not talking and Input.is_action_just_pressed(&"interact"):
				_try_interact()
		State.TAKING:
			_walk(delta, 0.0)
			if state_time > 0.35:
				holding = true
				taken = true
				_say(BOOK_LINES, func() -> void: _go(State.WALK))
				state = State.WALK
		State.TO_SEAT:
			# Подходит к стулу сам и разворачивается к столу.
			var gap := SEAT_X - x
			_walk(delta, clampf(gap * 2.5, -1.0, 1.0) * 0.6)
			if absf(gap) < 0.03 and absf(velocity) < 0.05:
				_fade_music()
				_go(State.SITTING)
		State.SITTING:
			_walk(delta, 0.0)
			x = lerpf(x, SEAT_X, minf(delta * 6.0, 1.0))
			yaw = lerp_angle(yaw, FACE_TABLE, minf(delta * 5.0, 1.0))
			var t := clampf(state_time / SIT_TIME, 0.0, 1.0)
			chair = t * t * (3.0 - 2.0 * t)
			if t >= 1.0:
				holding = false
				book_open = true
				_go(State.READING)
		State.READING:
			if state_time > 0.9 and not talking and _after_lines.is_null():
				_say(READ_LINES, _start_reading)
		State.TO_VISION:
			# Кадр сгорает красным от середины, как при «Начать путь», и нас уносит.
			var t := clampf(state_time / OUTRO_TIME, 0.0, 1.0)
			outro = sin(t * PI * 0.5) * t
			if state_time >= OUTRO_TIME + 0.5:
				library_rect.hide()
				vision_rect.show()
				_start_vision_music()
				_go(State.VISION)
		State.VISION:
			_vision()
		State.OUT:
			vision_fade = clampf(state_time / 2.0, 0.0, 1.0)
			if vision_music != null:
				vision_music.volume_db = lerpf(-12.0, -60.0, vision_fade)
			if state_time > 2.2:
				set_process(false)
				finished.emit()
	_push()
	overlay.queue_redraw()


# Под паузой реплики не просвечивают сквозь меню.
func _notification(what: int) -> void:
	if (what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED) and overlay != null:
		overlay.queue_redraw()


func _go(next: State) -> void:
	state = next
	state_time = 0.0


func _start_reading() -> void:
	_go(State.TO_VISION)
	var director := get_node_or_null("/root/SoundDirector")
	if director != null:
		director.toll(-6.0)


# Тема видения входит из тишины, пока загораются глаза.
func _start_vision_music() -> void:
	var looped := VISION_MUSIC.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	vision_music = AudioStreamPlayer.new()
	vision_music.stream = looped
	vision_music.bus = &"Music"
	vision_music.volume_db = -50.0
	add_child(vision_music)
	vision_music.play()
	create_tween().tween_property(vision_music, "volume_db", -12.0, 4.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


# Когда герой садится за стол, музыка улицы уходит совсем: остаются свеча и тишина.
func _fade_music() -> void:
	if music == null:
		return
	var tween := create_tween()
	tween.tween_property(music, "volume_db", -60.0, MUSIC_FADE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(music.stop)


# Видение: сначала из темноты загораются глаза, потом проступает всё остальное,
# камера медленно подходит. Без слов: рядом раскрывается книга — точка сохранения.
func _vision() -> void:
	var t := state_time
	vision_material.set_shader_parameter("eyes", clampf((t - 0.8) / 1.6, 0.0, 1.0))
	vision_material.set_shader_parameter("reveal", clampf((t - 2.4) / 3.0, 0.0, 1.0))
	var push := clampf(t / 30.0, 0.0, 1.0)
	vision_material.set_shader_parameter("zoom", lerpf(1.0, 1.35, push * push * (3.0 - 2.0 * push)))
	if t > 4.6 and save_menu == null:
		_open_save_menu()


# Книга «Цикл душ» раскрыта над тьмой: названия томов и единственный выход — закрыть её.
func _open_save_menu() -> void:
	save_menu = AsciiMenu.new()
	save_menu.heading = "Цикл душ"
	save_menu.heading_size = 30.0
	save_menu.columns = 42
	save_menu.spacing = 2
	# Слева, над пустой тьмой: справа парит двойник.
	save_menu.center = Vector2(0.27, 0.52)
	for index in range(VOLUMES.size()):
		save_menu.add_button(StringName("volume_%d" % index), VOLUMES[index])
	save_menu.add_button(&"close", "закрыть книгу")
	save_menu.activated.connect(_on_save_menu)
	overlay.get_parent().add_child(save_menu)
	save_menu.open()
	save_menu.selected = save_menu.entries.size() - 1


func _on_save_menu(id: StringName) -> void:
	if id != &"close":
		return
	save_menu.hide()
	_go(State.OUT)


func _try_interact() -> void:
	if not taken and absf(x - BOOK_X) < REACH:
		_go(State.TAKING)
		velocity = 0.0
	elif taken and absf(x - SEAT_X) < REACH + 0.25:
		_go(State.TO_SEAT)


func _walk(delta: float, axis: float) -> void:
	var target := axis * WALK_SPEED
	velocity = move_toward(velocity, target, (ACCEL if absf(axis) > 0.01 else BRAKE) * delta)
	var before := x
	x = clampf(x + velocity * delta, ROOM.x, ROOM.y)
	if x == ROOM.x or x == ROOM.y:
		velocity = 0.0
	var moved := absf(x - before)
	if chair < 0.01:
		if axis > 0.01:
			yaw = lerp_angle(yaw, FACE_RIGHT, minf(delta * 9.0, 1.0))
		elif axis < -0.01:
			yaw = lerp_angle(yaw, FACE_LEFT, minf(delta * 9.0, 1.0))
	move = move_toward(move, 1.0 if moved > 0.0005 else 0.0, delta * 5.0)
	var previous := phase
	phase += moved * PI / STEP_LENGTH
	if floori((phase + STEP_LEAD) / PI) != floori((previous + STEP_LEAD) / PI):
		_step()
	# Корпус клонится в шаг, полы отстают.
	lean = lean.lerp(Vector2(0.0, clampf(absf(velocity) * 0.04, 0.0, 0.12)), minf(delta * 8.0, 1.0))
	coat = lerpf(coat, -absf(velocity) * 0.12, minf(delta * 6.0, 1.0))


func _step() -> void:
	step_player.stream = STEPS[randi() % STEPS.size()]
	step_player.pitch_scale = randf_range(0.98, 1.02)
	step_player.volume_db = lerpf(-17.0, -11.0, clampf(absf(velocity) / WALK_SPEED, 0.0, 1.0))
	step_player.play()


func _push() -> void:
	var m := library_material
	var cam_x := clampf(x, CAMERA_LIMIT.x, CAMERA_LIMIT.y)
	m.set_shader_parameter("screen_px", get_viewport().get_visible_rect().size)
	m.set_shader_parameter("time", elapsed)
	m.set_shader_parameter("cam_center", Vector2(cam_x, CAMERA_Y))
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("player_pos", Vector3(x, 0.0, 0.0))
	m.set_shader_parameter("player_yaw", yaw)
	m.set_shader_parameter("player_phase", phase)
	m.set_shader_parameter("player_move", move)
	m.set_shader_parameter("player_lean", lean)
	m.set_shader_parameter("player_sit", 0.0)
	m.set_shader_parameter("player_chair", chair)
	m.set_shader_parameter("player_book", 1.0 if holding else 0.0)
	m.set_shader_parameter("coat_lag", Vector2(0.0, coat))
	m.set_shader_parameter("book_taken", 1.0 if taken else 0.0)
	m.set_shader_parameter("book_open", 1.0 if book_open else 0.0)
	m.set_shader_parameter("outro", outro)
	# Книга тлеет всегда, а когда герой рядом — разгорается.
	var near := 1.0 - smoothstep(0.4, 3.0, absf(x - BOOK_X))
	m.set_shader_parameter("book_glow", 0.35 + 0.65 * near)
	vision_material.set_shader_parameter("screen_px", get_viewport().get_visible_rect().size)
	vision_material.set_shader_parameter("time", elapsed)


func _say(new_lines: Array[Dictionary], after: Callable) -> void:
	lines = new_lines
	line_index = 0
	line_progress = 0.0
	_after_lines = after


func _advance_lines(delta: float) -> void:
	var length := String(lines[line_index]["text"]).length()
	var was_done := line_progress >= length
	line_progress = minf(line_progress + delta * 40.0, length)
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
	if get_tree().paused:
		return
	if not lines.is_empty():
		var line: Dictionary = lines[line_index]
		var speaker: Array = SPEAKERS.get(line["speaker"], SPEAKERS[&"nameless"])
		DialogueView.draw(overlay, mono, serif, speaker[0], speaker[1], line["text"], int(line_progress), elapsed)
	if vision_fade > 0.0:
		overlay.draw_rect(overlay.get_rect(), Color(0.0, 0.0, 0.01, vision_fade))
		if save_menu != null:
			save_menu.modulate.a = 1.0 - vision_fade


func _ensure_actions() -> void:
	var keys := {
		&"move_left": [KEY_A, KEY_LEFT], &"move_right": [KEY_D, KEY_RIGHT],
		&"interact": [KEY_E, KEY_SPACE, KEY_ENTER],
	}
	for action: StringName in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
