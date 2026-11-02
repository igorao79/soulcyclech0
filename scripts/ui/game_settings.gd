extends Node

# Автозагрузка GameSettings: настройки игры, их сохранение и применение.
# Громкость разведена по шинам: музыка — Music, шаги, колокол и прочие звуки — SFX.

signal changed

const PATH := "user://settings.cfg"
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const PAUSE_ACTION := &"pause_menu"

var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.9
var fullscreen := false
var vsync := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	_install_pause_action()
	load_settings()
	apply()


func set_option(option: StringName, value: Variant) -> void:
	set(option, value)
	apply()
	save_settings()


func apply() -> void:
	_set_volume(BUS_MASTER, master_volume)
	_set_volume(BUS_MUSIC, music_volume)
	_set_volume(BUS_SFX, sfx_volume)
	var window := get_window()
	var is_fullscreen := window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	elif not fullscreen and is_fullscreen:
		window.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	changed.emit()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	master_volume = clampf(float(config.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
	vsync = bool(config.get_value("video", "vsync", vsync))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	config.save(PATH)


func _set_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(index, value <= 0.001)


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, BUS_MASTER)


func _install_pause_action() -> void:
	if InputMap.has_action(PAUSE_ACTION):
		return
	InputMap.add_action(PAUSE_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event(PAUSE_ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_START
	InputMap.action_add_event(PAUSE_ACTION, pad)
