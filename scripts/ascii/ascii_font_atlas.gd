class_name SoulcycleAsciiFontAtlas
extends RefCounted

const LEVELS := 16
const VARIANTS := 4
const COLUMNS := LEVELS * VARIANTS

# Порядок рядов совпадает с константами RAMP_* в ascii_common.gdshaderinc.
# Ряд — 16 знаков от тёмного к яркому или 64 знака: по 4 варианта на каждую яркость.
const RAMPS: Array[String] = [
	"       . .  .  ,. ,'.,'`,'`:.;:'-  ~-_ ~~-_-=~-~;:!i*+:;*x+%x*%+",
	"       . .  . . .  ,. ,'.,` ,.:':., :;,.;:.,=-:;-=~:~=-;=~+-~=+*",
	".,'\"|/\\!li()`;:^",
	" .,'`:-~_=+*^;o\"",
	"    .  ..,.':.:':;':|:!;|!][c|(]cao|aocsabdodbapdbqaQ0d8Q08b08Q8",
	"     .  .`',':;.|:!'][|()(/\\oc{}dbqp0QOdQ8@08&Q%@%#8#@$&@#%MM@#W",
	"     .  .,'`;:,'|:;!(]/[cvoeaoqddbqp0QOd8Q0&&%8Q%#@8@#$%M@#%@MNW",
	"     .  .,'`:;,-~!|:/\\()rcvxzsuadbpq0OQd$%&S#Q$8&%@B#$@NM#QWM@N#",
	"               . . '.',.:;.'|!i:=+-~s%cz&S%s!:|':!;|!:';8%&0@#&8",
	"|/-\\            ",
	"     .  .,'`:;:.~:*+*+^~+=*ooxeOO0oQQ0%&&$%88$&##$&@@#$&#@%$@#$&",
	".,`'·+**· o°····",
	"      .  ._.._.__.-___-__-_---_--=-_=-=_==-_=-=======~===+====+=",
	" ()/\\~-_=.'|,`{}",
	" .:'-~=|+*os%#@8",
	# Ряд 15 — буквы колеса на загрузочном экране, не рампа яркости.
	"SOULCYE.:+*o#@%&",
]


static func create_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Menlo", "Monaco", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New",
	])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font


# Шаг ячейки выбирается под моноширинный шрифт, чтобы символы стояли вплотную.
static func measure_cell(font: Font, font_size: int) -> Vector2i:
	var advance := font.get_char_size("M".unicode_at(0), font_size).x
	return Vector2i(ceili(advance), roundi(font_size * 1.02))


# Рисует все рампы в отдельный SubViewport и забирает результат готовой текстурой.
static func build(host: Node, font: Font, font_size: int, cell: Vector2i) -> ImageTexture:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(COLUMNS * cell.x, RAMPS.size() * cell.y)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var canvas := Control.new()
	canvas.size = Vector2(viewport.size)
	canvas.draw.connect(func() -> void:
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color.BLACK)
		var ascent := font.get_ascent(font_size)
		var descent := font.get_descent(font_size)
		var baseline := (cell.y + ascent - descent) * 0.5
		for row in range(RAMPS.size()):
			var ramp: String = RAMPS[row]
			var per_level := ramp.length() / LEVELS
			for column in range(COLUMNS):
				var code := ramp.unicode_at(column / VARIANTS * per_level + column % per_level)
				var advance := font.get_char_size(code, font_size).x
				var origin := Vector2(column * cell.x + (cell.x - advance) * 0.5, row * cell.y + baseline)
				font.draw_char(canvas.get_canvas_item(), origin.floor(), code, font_size, Color.WHITE)
	)
	viewport.add_child(canvas)
	host.add_child(viewport)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return ImageTexture.create_from_image(image)
