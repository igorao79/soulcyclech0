class_name SoulcycleBattleSystem
extends CanvasLayer

## «Колесо души».
## Каждое действие поворачивает колесо на фазу вперёд. Воспоминание, применённое
## в своей фазе, резонирует: сильнее эффект и +1 искра. Искры тратятся на
## поворот колеса без траты хода. Воспоминание можно отпустить навсегда ради
## мощного всплеска. Смерть не конец: душа один раз перерождается, но забывает
## одно из воспоминаний. Враг заранее показывает намерение, а его колокол
## копит звон до полночного набата.

signal battle_started
signal battle_ended(victory: bool)

enum BattleState {
	INACTIVE,
	PLAYER_TURN,
	RESOLVING,
	FINISHED,
}

const BattleCatalog := preload("res://scripts/battle/battle_catalog.gd")
const BattleSilhouette := preload("res://scripts/battle/battle_silhouette.gd")
const SoulWheel := preload("res://scripts/battle/battle_soul_wheel.gd")
const BattlePips := preload("res://scripts/battle/battle_pips.gd")
const BATTLE_FONT := preload("res://assets/fonts/CormorantGaramond.ttf")

const MAX_EMBERS := 3
const KNELL_TOLLS := 3
const SEAL_TURNS := 2
const MIDNIGHT_AMPLIFY := 1.5
const LOG_LINES := 3
const CONTROLS_HINT := "1–4 воспоминания · 5 затаиться · Q/E повернуть колесо (искра) · R отпустить · Esc отступить"
const WAIT_DESCRIPTION := "Затаиться: пропустить удар сердца и собрать искру. Эхо не сможет повторить тишину."
const RELEASE_DESCRIPTION := "Отпустить воспоминание: навсегда потерять его в этом бою ради мощного всплеска."

const INTENT_WEIGHTS := {
	&"strike": 35,
	&"toll": 30,
	&"oblivion": 15,
	&"mirror": 20,
}

var overlay: Control
var stage: Control
var player_sprite: TextureRect
var player_aura: TextureRect
var enemy_silhouette: SoulcycleBattleSilhouette
var wheel: SoulcycleSoulWheel
var phase_caption: Label
var enemy_name_label: Label
var enemy_level_label: Label
var enemy_hp_bar: ProgressBar
var enemy_hp_label: Label
var toll_pips: SoulcycleBattlePips
var intent_title: Label
var intent_label: Label
var player_name_label: Label
var player_level_label: Label
var player_hp_label: Label
var player_hp_bar: ProgressBar
var ember_pips: SoulcycleBattlePips
var rebirth_pips: SoulcycleBattlePips
var message_label: RichTextLabel
var info_label: Label
var memory_buttons: Dictionary = {}
var wait_button: Button
var release_button: Button
var shift_back_button: Button
var shift_forward_button: Button

var state := BattleState.INACTIVE
var player_actor: SoulcycleBattleActor
var enemy_actor: SoulcycleBattleActor
var player_hp := 0
var enemy_hp := 0
var embers := 0
var rebirths_total := 0
var rebirths_left := 0
var tolls := 0
var memory_ids: Array[StringName] = []
var lost_memories: Dictionary = {}
var seals: Dictionary = {}
var player_guard_factor := 1.0
var player_parry := false
var invulnerable_hits := 0
var enemy_guarded := false
var intent: Dictionary = {}
var last_intent_id := &""
var last_action: Dictionary = {}
var release_mode := false
var turn_number := 0
var log_lines: Array[String] = []
var player_base_position := Vector2.ZERO
var enemy_base_position := Vector2.ZERO


func _ready() -> void:
	layer = 70
	_build_interface()
	overlay.visible = false


func is_active() -> bool:
	return state != BattleState.INACTIVE


func start_battle(encounter_id: StringName = &"first_wraith") -> void:
	if is_active():
		return

	var encounter := BattleCatalog.get_encounter(encounter_id)
	player_actor = BattleCatalog.get_actor(StringName(encounter.get("player", &"nameless")))
	enemy_actor = BattleCatalog.get_actor(StringName(encounter.get("enemy", &"bell_wraith")))
	memory_ids.clear()
	for memory_id in encounter.get("memories", []):
		memory_ids.append(StringName(memory_id))
	rebirths_total = int(encounter.get("rebirths", 1))
	rebirths_left = rebirths_total

	player_hp = player_actor.max_hp
	enemy_hp = enemy_actor.max_hp
	embers = 0
	tolls = 0
	lost_memories.clear()
	seals.clear()
	player_guard_factor = 1.0
	player_parry = false
	invulnerable_hits = 0
	enemy_guarded = false
	last_intent_id = &""
	last_action = {}
	release_mode = false
	turn_number = 0
	log_lines.clear()
	wheel.reset(BattleCatalog.Phase.DAWN)
	overlay.visible = true

	_apply_actor_visuals()
	_log("[color=#9fb4c8]%s преграждает путь. Колесо души начинает вращаться.[/color]" % enemy_actor.display_name)
	_begin_player_turn()
	battle_started.emit()
	_animate_battle_in()


func end_battle(victory: bool) -> void:
	if not is_active():
		return
	state = BattleState.INACTIVE
	overlay.visible = false
	battle_ended.emit(victory)


func _unhandled_input(event: InputEvent) -> void:
	if state != BattleState.PLAYER_TURN or not overlay.visible:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	match key_event.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			var index := key_event.physical_keycode - KEY_1
			if index < memory_ids.size():
				_on_memory_pressed(memory_ids[index])
		KEY_5:
			_on_wait_pressed()
		KEY_Q:
			_shift_wheel(-1)
		KEY_E:
			_shift_wheel(1)
		KEY_R:
			_toggle_release_mode()
		KEY_ESCAPE:
			if release_mode:
				_toggle_release_mode()
			else:
				_attempt_escape()
		_:
			return
	get_viewport().set_input_as_handled()


# --- Ход игрока -----------------------------------------------------------

func _begin_player_turn() -> void:
	turn_number += 1
	player_guard_factor = 1.0
	player_parry = false
	_choose_intent()
	state = BattleState.PLAYER_TURN
	_refresh_all()
	_focus_first_available()


func _on_memory_pressed(memory_id: StringName) -> void:
	if state != BattleState.PLAYER_TURN or not _is_memory_usable(memory_id):
		return
	if release_mode:
		_run_turn(memory_id, true)
	else:
		_run_turn(memory_id, false)


func _on_wait_pressed() -> void:
	if state != BattleState.PLAYER_TURN:
		return
	_run_turn(&"wait", false)


func _toggle_release_mode() -> void:
	if state != BattleState.PLAYER_TURN:
		return
	release_mode = not release_mode
	info_label.text = RELEASE_DESCRIPTION if release_mode else CONTROLS_HINT
	_refresh_actions()


func _shift_wheel(steps: int) -> void:
	if state != BattleState.PLAYER_TURN or embers <= 0:
		return
	embers -= 1
	wheel.rotate_by(steps)
	var phase_name: String = BattleCatalog.get_phase(wheel.phase)["name"]
	_log("Искра сгорает — колесо поворачивается к фазе «%s»." % phase_name)
	_refresh_all()


func _run_turn(action_id: StringName, releasing: bool) -> void:
	state = BattleState.RESOLVING
	release_mode = false
	_refresh_actions()

	var phase := wheel.phase
	last_action = {"id": action_id, "kind": &"none", "amount": 0, "released": releasing}

	if action_id == &"wait":
		embers = mini(MAX_EMBERS, embers + 1)
		_log("%s затаивается и собирает искру." % player_actor.display_name)
		_spawn_float("+искра", _wheel_point(), Color("#f1d27b"), 22)
	elif releasing:
		await _release_memory(action_id)
	else:
		var memory := BattleCatalog.get_memory(action_id)
		var resonant := int(memory["phase"]) == phase
		if resonant:
			embers = mini(MAX_EMBERS, embers + 1)
			wheel.flash()
			_spawn_float("РЕЗОНАНС", _wheel_point() + Vector2(0, -60), BattleCatalog.get_phase(phase)["color"], 28)
		await _use_memory(action_id, resonant)

	for sealed_id in seals.keys():
		seals[sealed_id] = int(seals[sealed_id]) - 1
		if int(seals[sealed_id]) <= 0:
			seals.erase(sealed_id)

	_refresh_all()
	if enemy_hp <= 0:
		await _finish_victory()
		return

	await get_tree().create_timer(0.35).timeout
	wheel.rotate_by(1)
	if wheel.phase == BattleCatalog.Phase.DAWN:
		var restored := _heal_player(4)
		_log("[color=#e9a58c]Круг замкнулся: рассвет возвращает %d HP.[/color]" % restored)
	_refresh_all()

	await get_tree().create_timer(0.5).timeout
	await _take_enemy_turn()


func _use_memory(memory_id: StringName, resonant: bool) -> void:
	var memory := BattleCatalog.get_memory(memory_id)
	var memory_name: String = memory["name"]
	var tag := " [color=#f1d27b](резонанс)[/color]" if resonant else ""
	match memory_id:
		&"thrust":
			await _lunge_player()
			var damage := _calculate_damage(player_actor.attack, enemy_actor.defense, 1.25)
			if resonant:
				damage *= 2
			damage = _deal_to_enemy(damage)
			last_action["kind"] = &"damage"
			last_action["amount"] = damage
			_log("%s%s — %d урона." % [memory_name, tag, damage])
		&"vow":
			if resonant:
				player_parry = true
				_log("%s%s: следующий удар будет парирован." % [memory_name, tag])
			else:
				player_guard_factor = 0.4
				_log("%s: %s закрывается клинком." % [memory_name, player_actor.display_name])
			last_action["kind"] = &"guard"
		&"lullaby":
			var amount := 16 if resonant else 10
			var restored := _heal_player(amount)
			if resonant and not seals.is_empty():
				seals.clear()
				_log("%s%s: +%d HP, печати забвения спадают." % [memory_name, tag, restored])
			else:
				_log("%s%s: +%d HP." % [memory_name, tag, restored])
			last_action["kind"] = &"heal"
			last_action["amount"] = amount
		&"harvest":
			await _lunge_player()
			var multiplier := 0.9
			if resonant:
				var missing := 1.0 - float(player_hp) / float(player_actor.max_hp)
				multiplier *= 1.0 + missing * 1.6
			var damage := _deal_to_enemy(_calculate_damage(player_actor.attack, enemy_actor.defense, multiplier))
			var restored := _heal_player(ceili(damage * 0.5))
			last_action["kind"] = &"drain"
			last_action["amount"] = damage
			_log("%s%s — %d урона, +%d HP." % [memory_name, tag, damage, restored])


func _release_memory(memory_id: StringName) -> void:
	var memory := BattleCatalog.get_memory(memory_id)
	lost_memories[memory_id] = true
	seals.erase(memory_id)
	wheel.flash()
	_flash_screen(Color(1.0, 0.95, 0.85, 0.55))
	var header := "[color=#e7a0ae]Ты отпускаешь «%s».[/color] " % memory["name"]
	match memory_id:
		&"thrust":
			await _lunge_player()
			var damage := enemy_actor.attack + player_actor.attack * 3
			damage = _deal_to_enemy(damage, true)
			_log(header + "%s: %d урона." % [memory["release_name"], damage])
		&"vow":
			invulnerable_hits = 2
			_log(header + "%s: два удара пройдут сквозь тебя." % memory["release_name"])
		&"lullaby":
			var restored := _heal_player(player_actor.max_hp)
			tolls = 0
			seals.clear()
			_log(header + "%s: +%d HP, колокол затихает." % [memory["release_name"], restored])
		&"harvest":
			await _lunge_player()
			var damage := _deal_to_enemy(ceili(enemy_hp / 3.0) + player_actor.attack, true)
			var restored := _heal_player(damage)
			_log(header + "%s: %d урона, +%d HP." % [memory["release_name"], damage, restored])


func _attempt_escape() -> void:
	state = BattleState.RESOLVING
	_refresh_actions()
	if randf() <= 0.6:
		_log("Ты разрываешь дистанцию и уходишь в метель.")
		state = BattleState.FINISHED
		await get_tree().create_timer(0.8).timeout
		end_battle(false)
		return
	_log("Путь назад исчезает среди снега.")
	last_action = {"id": &"escape", "kind": &"none", "amount": 0, "released": false}
	await get_tree().create_timer(0.5).timeout
	wheel.rotate_by(1)
	_refresh_all()
	await _take_enemy_turn()


# --- Ход врага ------------------------------------------------------------

func _choose_intent() -> void:
	if tolls >= KNELL_TOLLS:
		intent = {"id": &"knell"}
		last_intent_id = &"knell"
		return

	var options := INTENT_WEIGHTS.duplicate()
	if turn_number <= 1:
		options.erase(&"mirror")
		options.erase(&"oblivion")
	if last_intent_id == &"mirror":
		options.erase(&"mirror")
	var seal_targets := _available_memories().filter(func(id: StringName) -> bool: return not seals.has(id))
	if last_intent_id == &"oblivion" or seal_targets.is_empty():
		options.erase(&"oblivion")

	var total := 0
	for weight in options.values():
		total += int(weight)
	var roll := randi_range(1, total)
	var chosen := &"strike"
	for option_id in options.keys():
		roll -= int(options[option_id])
		if roll <= 0:
			chosen = option_id
			break

	intent = {"id": chosen}
	if chosen == &"oblivion":
		intent["target"] = seal_targets.pick_random()
	last_intent_id = chosen


func _take_enemy_turn() -> void:
	if state != BattleState.RESOLVING:
		return
	var amplify := MIDNIGHT_AMPLIFY if wheel.phase == BattleCatalog.Phase.MIDNIGHT else 1.0
	var enemy_name := enemy_actor.display_name

	match StringName(intent.get("id", &"strike")):
		&"strike":
			await _lunge_enemy()
			var damage := _calculate_damage(enemy_actor.attack, player_actor.defense, 1.15 * amplify)
			_log("%s: холодное эхо — %s." % [enemy_name, _hit_player(damage)])
		&"toll":
			tolls = mini(KNELL_TOLLS, tolls + 1)
			var damage := _calculate_damage(enemy_actor.attack, player_actor.defense, 0.5 * amplify)
			_shake(4.0)
			_log("Колокол звонит (%d/%d) — %s." % [tolls, KNELL_TOLLS, _hit_player(damage)])
		&"oblivion":
			var target := StringName(intent.get("target", &""))
			var damage := _calculate_damage(enemy_actor.attack, player_actor.defense, 0.4 * amplify)
			var result := _hit_player(damage)
			if target != &"" and _is_memory_available(target):
				seals[target] = SEAL_TURNS
				_log("Забвение: «%s» запечатано на %d хода — %s." % [BattleCatalog.get_memory(target)["name"], SEAL_TURNS, result])
			else:
				_log("Забвение скользит мимо — %s." % result)
		&"mirror":
			await _resolve_mirror()
		&"knell":
			await _lunge_enemy()
			tolls = 0
			_flash_screen(Color(0.85, 0.2, 0.3, 0.45))
			var damage := _calculate_damage(enemy_actor.attack, player_actor.defense, 3.0 * amplify)
			_log("[color=#ff8f9c]ПОЛНОЧНЫЙ НАБАТ[/color] — %s." % _hit_player(damage, 12.0))

	_refresh_all()
	if enemy_hp <= 0:
		await _finish_victory()
		return
	if player_hp <= 0:
		await _handle_player_fall()
		if state == BattleState.FINISHED:
			return

	await get_tree().create_timer(0.45).timeout
	_begin_player_turn()


func _resolve_mirror() -> void:
	var enemy_name := enemy_actor.display_name
	var amount := int(last_action.get("amount", 0))
	if bool(last_action.get("released", false)):
		_log("%s пытается повторить отпущенное — но от него не осталось эха." % enemy_name)
		return
	match StringName(last_action.get("kind", &"none")):
		&"damage":
			await _lunge_enemy()
			_log("Отзвук повторяет твой удар — %s." % _hit_player(amount))
		&"drain":
			await _lunge_enemy()
			var result := _hit_player(amount)
			var restored := mini(enemy_actor.max_hp - enemy_hp, amount)
			enemy_hp += restored
			_log("Отзвук повторяет жатву — %s, эхо крепнет на %d." % [result, restored])
		&"heal":
			var restored := mini(enemy_actor.max_hp - enemy_hp, amount)
			enemy_hp += restored
			_spawn_float("+%d" % restored, _enemy_point(), Color("#8fe0a0"), 26)
			_log("Отзвук поёт твою колыбельную: эхо восстанавливает %d HP." % restored)
		&"guard":
			enemy_guarded = true
			enemy_silhouette.guarded = true
			_log("Отзвук повторяет клятву: эхо закрывается от следующего удара.")
		_:
			_log("Отзвук тонет в тишине — повторять нечего.")


# --- Урон, лечение, смерть -----------------------------------------------

func _calculate_damage(attacker_attack: int, defender_defense: int, multiplier: float) -> int:
	var base := float(attacker_attack) * multiplier - float(defender_defense) * 0.55
	return maxi(1, roundi(base + randf_range(-1.5, 2.0)))


func _estimate_enemy_damage(multiplier: float) -> int:
	return maxi(1, roundi(float(enemy_actor.attack) * multiplier - float(player_actor.defense) * 0.55))


func _deal_to_enemy(damage: int, pierce: bool = false) -> int:
	if enemy_guarded and not pierce:
		damage = maxi(1, roundi(damage * 0.4))
		enemy_guarded = false
		enemy_silhouette.guarded = false
	elif pierce:
		enemy_guarded = false
		enemy_silhouette.guarded = false
	damage = mini(damage, enemy_hp)
	enemy_hp -= damage
	enemy_silhouette.hit_flash = 1.0
	_spawn_float("-%d" % damage, _enemy_point(), Color("#fff2e0"), 30)
	_shake_node(enemy_silhouette, enemy_base_position, 8.0)
	return damage


func _hit_player(damage: int, shake_strength: float = 5.0) -> String:
	if invulnerable_hits > 0:
		invulnerable_hits -= 1
		_spawn_float("клятва", _player_point(), Color("#aa8ddc"), 24)
		return "удар проходит сквозь нерушимую клятву"
	if player_parry:
		player_parry = false
		var counter := _deal_to_enemy(_calculate_damage(player_actor.attack, enemy_actor.defense, 0.8) + roundi(damage * 0.5))
		_spawn_float("парирование", _player_point(), Color("#aa8ddc"), 24)
		return "парирование! контрудар на %d" % counter

	damage = maxi(1, roundi(damage * player_guard_factor))
	var blocked := player_guard_factor < 1.0
	player_guard_factor = 1.0
	player_hp = maxi(0, player_hp - damage)
	_spawn_float("-%d" % damage, _player_point(), Color("#ff8f9c"), 30)
	_shake(shake_strength)
	player_sprite.modulate = Color(1.6, 0.7, 0.75)
	create_tween().tween_property(player_sprite, "modulate", Color.WHITE, 0.35)
	return ("%d урона (заблокировано)" if blocked else "%d урона") % damage


func _heal_player(amount: int) -> int:
	var restored := mini(amount, player_actor.max_hp - player_hp)
	player_hp += restored
	if restored > 0:
		_spawn_float("+%d" % restored, _player_point(), Color("#8fe0a0"), 26)
	return restored


func _handle_player_fall() -> void:
	if rebirths_left <= 0:
		state = BattleState.FINISHED
		_log("[color=#ff8f9c]Снег укрывает твоё имя. Цикл начинается снова.[/color]")
		_refresh_actions()
		await get_tree().create_timer(1.6).timeout
		end_battle(false)
		return

	rebirths_left -= 1
	await get_tree().create_timer(0.5).timeout
	_flash_screen(Color(1, 1, 1, 0.8))
	player_hp = ceili(player_actor.max_hp * 0.6)
	var burned := &""
	var candidates := _available_memories()
	if candidates.size() > 1:
		burned = candidates.pick_random()
		lost_memories[burned] = true
		seals.erase(burned)
	var steps_to_dawn := wrapi(-wheel.phase, 0, BattleCatalog.PHASES.size())
	if steps_to_dawn > 0:
		wheel.rotate_by(steps_to_dawn)
	wheel.flash()
	if burned != &"":
		_log("[color=#f6efe3]Душа возвращается на круг[/color] — но «%s» остаётся в прошлой жизни." % BattleCatalog.get_memory(burned)["name"])
	else:
		_log("[color=#f6efe3]Душа возвращается на круг.[/color]")
	_refresh_all()


func _finish_victory() -> void:
	state = BattleState.FINISHED
	_refresh_actions()
	var fade := create_tween()
	fade.tween_property(enemy_silhouette, "modulate:a", 0.0, 1.0)
	_log("[color=#f1d27b]%s растворяется в колокольном звоне. Круг разомкнут.[/color]" % enemy_actor.display_name)
	await get_tree().create_timer(1.6).timeout
	end_battle(true)


# --- Состояние воспоминаний ----------------------------------------------

func _is_memory_available(memory_id: StringName) -> bool:
	return memory_ids.has(memory_id) and not lost_memories.has(memory_id)


func _is_memory_usable(memory_id: StringName) -> bool:
	return _is_memory_available(memory_id) and not seals.has(memory_id)


func _available_memories() -> Array[StringName]:
	var result: Array[StringName] = []
	for memory_id in memory_ids:
		if _is_memory_available(memory_id):
			result.append(memory_id)
	return result


# --- Интерфейс: обновление -----------------------------------------------

func _refresh_all() -> void:
	_update_status()
	_update_intent()
	_update_phase_caption()
	_refresh_actions()


func _update_status() -> void:
	enemy_hp_bar.max_value = enemy_actor.max_hp
	enemy_hp_bar.value = enemy_hp
	enemy_hp_label.text = "%d / %d" % [enemy_hp, enemy_actor.max_hp]
	player_hp_bar.max_value = player_actor.max_hp
	player_hp_bar.value = player_hp
	player_hp_label.text = "%d / %d" % [player_hp, player_actor.max_hp]
	toll_pips.set_filled(tolls)
	ember_pips.set_filled(embers)
	rebirth_pips.set_filled(rebirths_left)
	enemy_silhouette.tolls = tolls


func _update_intent() -> void:
	if intent.is_empty() or state == BattleState.FINISHED:
		intent_label.text = ""
		return
	# Враг ходит после поворота колеса, поэтому считаем по следующей фазе.
	var enemy_phase := wheel.phase if state == BattleState.RESOLVING else wrapi(wheel.phase + 1, 0, 4)
	var amplify := MIDNIGHT_AMPLIFY if enemy_phase == BattleCatalog.Phase.MIDNIGHT else 1.0
	var midnight_note := "  (Полночь ×1.5)" if amplify > 1.0 else ""
	var text := ""
	var color := Color("#d9e4f0")
	match StringName(intent.get("id", &"")):
		&"strike":
			text = "Холодное эхо — удар ~%d%s" % [_estimate_enemy_damage(1.15 * amplify), midnight_note]
		&"toll":
			text = "Похоронный звон — ~%d урона, колокол +1%s" % [_estimate_enemy_damage(0.5 * amplify), midnight_note]
		&"oblivion":
			var target := StringName(intent.get("target", &""))
			text = "Забвение — запечатает «%s»" % BattleCatalog.get_memory(target).get("name", "?")
			color = Color("#c6b3ec")
		&"mirror":
			text = "Отзвук — повторит твоё действие"
			color = Color("#9fd6e6")
		&"knell":
			text = "ПОЛНОЧНЫЙ НАБАТ — ~%d урона!%s" % [_estimate_enemy_damage(3.0 * amplify), midnight_note]
			color = Color("#ff8f9c")
	intent_label.text = text
	intent_label.add_theme_color_override("font_color", color)


func _update_phase_caption() -> void:
	var phase_data := BattleCatalog.get_phase(wheel.phase)
	phase_caption.text = phase_data["hint"]
	phase_caption.add_theme_color_override("font_color", phase_data["color"])
	var tint: Color = phase_data["color"]
	tint.a = 0.55
	create_tween().tween_property(player_aura, "modulate", tint, 0.4)
	shift_back_button.disabled = state != BattleState.PLAYER_TURN or embers <= 0
	shift_forward_button.disabled = shift_back_button.disabled


func _refresh_actions() -> void:
	var interactive := state == BattleState.PLAYER_TURN
	for index in range(memory_ids.size()):
		var memory_id := memory_ids[index]
		var button := memory_buttons[memory_id] as Button
		var memory := BattleCatalog.get_memory(memory_id)
		var phase_data := BattleCatalog.get_phase(int(memory["phase"]))
		var phase_color: Color = phase_data["color"]
		var resonant := int(memory["phase"]) == wheel.phase
		var subtitle: String = phase_data["name"]
		var bg := Color("#1c2638")
		var border := phase_color.darkened(0.45)
		var border_width := 2

		if lost_memories.has(memory_id):
			subtitle = "утрачено"
			bg = Color("#101218")
			border = Color("#2b2f38")
		elif seals.has(memory_id):
			subtitle = "печать · %d" % int(seals[memory_id])
			bg = Color("#1a1626")
			border = Color("#6e5a93")
		elif release_mode:
			subtitle = "отпустить навсегда"
			bg = Color("#3a1622")
			border = Color("#e7a0ae")
		elif resonant:
			subtitle = "%s · резонанс" % phase_data["name"]
			bg = phase_color.darkened(0.72)
			border = phase_color
			border_width = 3

		var title: String = memory["release_name"] if release_mode and _is_memory_usable(memory_id) else memory["name"]
		button.text = "%d  %s\n%s" % [index + 1, title.to_upper(), subtitle]
		button.disabled = not interactive or not _is_memory_usable(memory_id)
		_style_button(button, bg, border, border_width)

	wait_button.disabled = not interactive or release_mode
	release_button.disabled = not interactive or _available_memories().is_empty()
	release_button.text = "R  ОТМЕНА\nвернуться" if release_mode else "R  ОТПУСТИТЬ\nпожертвовать"
	_style_button(release_button, Color("#3a1622") if release_mode else Color("#241822"), Color("#b5606f"), 2)
	shift_back_button.disabled = not interactive or embers <= 0
	shift_forward_button.disabled = shift_back_button.disabled

	if interactive:
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or (focused is Button and (focused as Button).disabled):
			_focus_first_available()


func _focus_first_available() -> void:
	if state != BattleState.PLAYER_TURN:
		return
	for memory_id in memory_ids:
		if _is_memory_usable(memory_id):
			(memory_buttons[memory_id] as Button).grab_focus()
			return
	wait_button.grab_focus()


func _log(line: String) -> void:
	log_lines.append(line)
	while log_lines.size() > LOG_LINES:
		log_lines.pop_front()
	var rendered := PackedStringArray()
	for index in range(log_lines.size()):
		if index < log_lines.size() - 1:
			rendered.append("[color=#7d8798]%s[/color]" % log_lines[index])
		else:
			rendered.append(log_lines[index])
	message_label.text = "\n".join(rendered)


func _show_description(action_id: StringName) -> void:
	if action_id == &"wait":
		info_label.text = WAIT_DESCRIPTION
	elif action_id == &"release":
		info_label.text = RELEASE_DESCRIPTION
	else:
		var memory := BattleCatalog.get_memory(action_id)
		info_label.text = memory["release_description"] if release_mode else memory["description"]


# --- Эффекты --------------------------------------------------------------

func _wheel_point() -> Vector2:
	return wheel.position + wheel.size * 0.5


func _enemy_point() -> Vector2:
	return enemy_base_position + enemy_silhouette.size * Vector2(0.5, 0.3)


func _player_point() -> Vector2:
	return player_base_position + player_sprite.size * Vector2(0.45, 0.25)


func _spawn_float(text: String, at: Vector2, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BATTLE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(label)
	label.position = at + Vector2(randf_range(-18, 18), 0) - label.get_minimum_size() * 0.5
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 56.0, 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)


func _shake(strength: float) -> void:
	var tween := create_tween()
	for step in range(5):
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(stage, "position", offset, 0.035)
		strength *= 0.7
	tween.tween_property(stage, "position", Vector2.ZERO, 0.04)


func _shake_node(node: Control, base: Vector2, strength: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position", base + Vector2(strength, 0), 0.04)
	tween.tween_property(node, "position", base + Vector2(-strength * 0.6, 0), 0.05)
	tween.tween_property(node, "position", base, 0.06)


func _flash_screen(color: Color) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.6)
	tween.tween_callback(flash.queue_free)


func _lunge_player() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(player_sprite, "position", player_base_position + Vector2(46, -6), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(player_sprite, "position", player_base_position, 0.22).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.12).timeout


func _lunge_enemy() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(enemy_silhouette, "position", enemy_base_position + Vector2(-40, 8), 0.14).set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy_silhouette, "position", enemy_base_position, 0.24).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.14).timeout


func _apply_actor_visuals() -> void:
	player_sprite.texture = player_actor.battle_sprite
	player_sprite.flip_h = player_actor.sprite_flip_h
	player_sprite.modulate = Color.WHITE
	enemy_silhouette.accent_color = enemy_actor.accent_color
	enemy_silhouette.modulate = Color.WHITE
	enemy_silhouette.guarded = false
	enemy_silhouette.tolls = 0

	enemy_name_label.text = enemy_actor.display_name
	enemy_level_label.text = "УР. %d" % enemy_actor.level
	player_name_label.text = player_actor.display_name
	player_level_label.text = "УР. %d" % player_actor.level
	for memory_id in memory_buttons.keys():
		(memory_buttons[memory_id] as Button).visible = memory_ids.has(memory_id)
	rebirth_pips.total = rebirths_total
	rebirth_pips.custom_minimum_size.x = maxf(18.0, rebirths_total * 18.0)
	info_label.text = CONTROLS_HINT


func _animate_battle_in() -> void:
	player_base_position = player_sprite.position
	enemy_base_position = enemy_silhouette.position
	stage.modulate.a = 0.0
	player_sprite.position.x -= 34.0
	enemy_silhouette.position.x += 34.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(stage, "modulate:a", 1.0, 0.25)
	tween.tween_property(player_sprite, "position", player_base_position, 0.36)
	tween.tween_property(enemy_silhouette, "position", enemy_base_position, 0.36)


# --- Интерфейс: построение ------------------------------------------------

func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "BattleOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(stage)

	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = _create_battle_background()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	stage.add_child(_create_battle_snow())

	_add_platform(Vector2(760, 330), Vector2(150, 34), Color(0.36, 0.52, 0.62, 0.30))
	_add_platform(Vector2(185, 372), Vector2(175, 38), Color(0.24, 0.34, 0.45, 0.42))

	player_aura = TextureRect.new()
	player_aura.texture = _create_radial_texture()
	player_aura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_aura.stretch_mode = TextureRect.STRETCH_SCALE
	player_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_aura.position = Vector2(20, 60)
	player_aura.size = Vector2(330, 330)
	stage.add_child(player_aura)

	player_sprite = TextureRect.new()
	player_sprite.position = Vector2(40, 98)
	player_sprite.size = Vector2(290, 290)
	player_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	player_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(player_sprite)

	enemy_silhouette = BattleSilhouette.new()
	enemy_silhouette.position = Vector2(650, 150)
	enemy_silhouette.size = Vector2(220, 200)
	stage.add_child(enemy_silhouette)

	wheel = SoulWheel.new()
	wheel.position = Vector2(370, 92)
	wheel.size = Vector2(220, 220)
	stage.add_child(wheel)

	phase_caption = _create_label(17, Color.WHITE)
	phase_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_caption.position = Vector2(330, 316)
	phase_caption.size = Vector2(300, 26)
	stage.add_child(phase_caption)

	shift_back_button = _create_small_button("Q ◂")
	shift_back_button.position = Vector2(356, 272)
	shift_back_button.pressed.connect(_shift_wheel.bind(-1))
	shift_back_button.tooltip_text = "Потратить искру: повернуть колесо назад"
	stage.add_child(shift_back_button)
	shift_forward_button = _create_small_button("▸ E")
	shift_forward_button.position = Vector2(554, 272)
	shift_forward_button.pressed.connect(_shift_wheel.bind(1))
	shift_forward_button.tooltip_text = "Потратить искру: повернуть колесо вперёд"
	stage.add_child(shift_forward_button)

	_build_player_card()
	_build_enemy_card()
	_build_bottom_panels()


func _build_player_card() -> void:
	var card := _create_status_card()
	card.position = Vector2(18, 14)
	card.size = Vector2(330, 0)
	stage.add_child(card)
	var column := _create_card_column(card)

	var header := HBoxContainer.new()
	column.add_child(header)
	player_name_label = _create_label(23, Color("#f3eee5"))
	player_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(player_name_label)
	player_level_label = _create_label(17, Color("#9fb0c4"))
	header.add_child(player_level_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	column.add_child(hp_row)
	hp_row.add_child(_create_label(15, Color("#e7a0ae"), "HP"))
	player_hp_bar = _create_hp_bar(Color("#69b879"))
	hp_row.add_child(player_hp_bar)
	player_hp_label = _create_label(15, Color("#d7dde6"))
	player_hp_label.custom_minimum_size.x = 58
	player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(player_hp_label)

	var resource_row := HBoxContainer.new()
	resource_row.add_theme_constant_override("separation", 8)
	column.add_child(resource_row)
	resource_row.add_child(_create_label(15, Color("#f1d27b"), "Искры"))
	ember_pips = BattlePips.new(MAX_EMBERS, Color("#f1d27b"))
	resource_row.add_child(ember_pips)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_row.add_child(spacer)
	resource_row.add_child(_create_label(15, Color("#f6efe3"), "Перерождения"))
	rebirth_pips = BattlePips.new(1, Color("#f6efe3"), true)
	resource_row.add_child(rebirth_pips)


func _build_enemy_card() -> void:
	var card := _create_status_card()
	card.position = Vector2(592, 14)
	card.size = Vector2(350, 0)
	stage.add_child(card)
	var column := _create_card_column(card)

	var header := HBoxContainer.new()
	column.add_child(header)
	enemy_name_label = _create_label(23, Color("#f3eee5"))
	enemy_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(enemy_name_label)
	enemy_level_label = _create_label(17, Color("#9fb0c4"))
	header.add_child(enemy_level_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	column.add_child(hp_row)
	hp_row.add_child(_create_label(15, Color("#e7a0ae"), "HP"))
	enemy_hp_bar = _create_hp_bar(Color("#c95a6a"))
	hp_row.add_child(enemy_hp_bar)
	enemy_hp_label = _create_label(15, Color("#d7dde6"))
	enemy_hp_label.custom_minimum_size.x = 58
	enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(enemy_hp_label)

	var toll_row := HBoxContainer.new()
	toll_row.add_theme_constant_override("separation", 8)
	column.add_child(toll_row)
	toll_row.add_child(_create_label(15, Color("#ff8f9c"), "Звон до набата"))
	toll_pips = BattlePips.new(KNELL_TOLLS, Color("#ff8f9c"))
	toll_row.add_child(toll_pips)

	var divider := ColorRect.new()
	divider.color = Color(0.82, 0.77, 0.7, 0.25)
	divider.custom_minimum_size.y = 1
	column.add_child(divider)

	intent_title = _create_label(13, Color("#8b95a7"), "НАМЕРЕНИЕ")
	column.add_child(intent_title)
	intent_label = _create_label(17, Color("#d9e4f0"))
	intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intent_label)


func _build_bottom_panels() -> void:
	var message_panel := _create_bottom_panel()
	message_panel.position = Vector2(14, 360)
	message_panel.size = Vector2(400, 168)
	stage.add_child(message_panel)
	var message_margin := _create_margin(18, 12, 16, 10)
	message_panel.add_child(message_margin)
	var message_column := VBoxContainer.new()
	message_column.add_theme_constant_override("separation", 4)
	message_margin.add_child(message_column)

	message_label = RichTextLabel.new()
	message_label.bbcode_enabled = true
	message_label.scroll_active = false
	message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_label.add_theme_font_override("normal_font", BATTLE_FONT)
	message_label.add_theme_font_size_override("normal_font_size", 18)
	message_label.add_theme_color_override("default_color", Color("#f3eee5"))
	message_label.add_theme_constant_override("line_separation", 2)
	message_column.add_child(message_label)

	info_label = _create_label(14, Color("#a7b1c2"))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.y = 38
	message_column.add_child(info_label)

	var actions_panel := _create_bottom_panel()
	actions_panel.position = Vector2(426, 360)
	actions_panel.size = Vector2(520, 168)
	stage.add_child(actions_panel)
	var actions_margin := _create_margin(10, 10, 10, 10)
	actions_panel.add_child(actions_margin)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	actions_margin.add_child(grid)

	for memory_id in BattleCatalog.MEMORIES.keys():
		var button := _create_action_button()
		button.pressed.connect(_on_memory_pressed.bind(memory_id))
		button.mouse_entered.connect(_show_description.bind(memory_id))
		button.focus_entered.connect(_show_description.bind(memory_id))
		grid.add_child(button)
		memory_buttons[memory_id] = button

	wait_button = _create_action_button()
	wait_button.text = "5  ЗАТАИТЬСЯ\n+1 искра"
	_style_button(wait_button, Color("#1c2638"), Color("#8396a8"), 2)
	wait_button.pressed.connect(_on_wait_pressed)
	wait_button.mouse_entered.connect(_show_description.bind(&"wait"))
	wait_button.focus_entered.connect(_show_description.bind(&"wait"))
	grid.add_child(wait_button)

	release_button = _create_action_button()
	release_button.pressed.connect(_toggle_release_mode)
	release_button.mouse_entered.connect(_show_description.bind(&"release"))
	release_button.focus_entered.connect(_show_description.bind(&"release"))
	grid.add_child(release_button)


func _create_battle_background() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color("#0b1120"),
		Color("#1b2b42"),
		Color("#4c6a7f"),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 960
	texture.height = 540
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture


func _create_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.7))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _create_battle_snow() -> CPUParticles2D:
	var snow := CPUParticles2D.new()
	snow.position = Vector2(480, -20)
	snow.amount = 70
	snow.lifetime = 8.0
	snow.preprocess = 8.0
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(520, 10)
	snow.direction = Vector2(0.15, 1.0)
	snow.spread = 16.0
	snow.gravity = Vector2(6, 16)
	snow.initial_velocity_min = 12.0
	snow.initial_velocity_max = 26.0
	snow.scale_amount_min = 1.0
	snow.scale_amount_max = 2.4
	snow.color = Color(0.88, 0.93, 1.0, 0.4)
	return snow


func _add_platform(center: Vector2, radii: Vector2, color: Color) -> void:
	var platform := Polygon2D.new()
	var points := PackedVector2Array()
	for point_index in range(40):
		var angle := TAU * float(point_index) / 40.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	platform.position = center
	platform.polygon = points
	platform.color = color
	stage.add_child(platform)


func _create_label(font_size: int, color: Color, text: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BATTLE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _create_status_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.08, 0.9)
	style.border_color = Color("#d0c5b5")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 7
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _create_card_column(card: PanelContainer) -> VBoxContainer:
	var margin := _create_margin(14, 7, 14, 8)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	return column


func _create_hp_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.custom_minimum_size.y = 11
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color("#263548")
	background_style.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", background_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar


func _create_bottom_panel() -> PanelContainer:
	var panel_container := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.075, 0.95)
	style.border_color = Color("#d0c5b5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.52)
	style.shadow_size = 9
	panel_container.add_theme_stylebox_override("panel", style)
	return panel_container


func _create_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _create_action_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(160, 70)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", BATTLE_FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("#f4eee5"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#5d6573"))
	return button


func _create_small_button(title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.size = Vector2(52, 30)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", BATTLE_FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#f1d27b"))
	button.add_theme_color_override("font_disabled_color", Color("#4f5664"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.9)
	style.border_color = Color("#8a7a4c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = Color("#f1d27b")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled := style.duplicate() as StyleBoxFlat
	disabled.border_color = Color("#2b2f38")
	button.add_theme_stylebox_override("disabled", disabled)
	return button


func _style_button(button: Button, bg: Color, border: Color, border_width: int) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = bg
	normal_style.border_color = border
	normal_style.set_border_width_all(border_width)
	normal_style.set_corner_radius_all(6)
	normal_style.content_margin_left = 12
	normal_style.content_margin_right = 8
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("disabled", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = bg.lightened(0.12)
	hover_style.border_color = border.lightened(0.35)
	hover_style.set_border_width_all(border_width + 1)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("focus", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)
