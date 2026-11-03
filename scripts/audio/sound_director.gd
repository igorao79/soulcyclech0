extends Node

# Автозагрузка SoundDirector: звуки, которые должны пережить смену сцены.
# Удар колокола на старте игры звучит, пока главный экран растворяется и открывается глава:
# если бы его играл сам главный экран, звук оборвался бы вместе со сценой.

const BellSynth := preload("res://scripts/audio/bell_synth.gd")
# Большой колокол ниже обычного: удар глубокий, гул долгий.
const GREAT_BELL_PITCH := 0.72

var _great_bell: AudioStreamWAV
var _bell_task := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Колокол синтезируется в фоне при запуске игры: к нажатию «Начать путь» он уже готов.
	_bell_task = WorkerThreadPool.add_task(func() -> void: _great_bell = BellSynth.create(GREAT_BELL_PITCH))


## Удар большого колокола. Звук живёт здесь, а не в сцене, и доигрывает до конца.
func toll(volume_db: float = -3.0) -> void:
	if _bell_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bell_task)
		_bell_task = -1
	if _great_bell == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = _great_bell
	player.bus = &"SFX"
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
