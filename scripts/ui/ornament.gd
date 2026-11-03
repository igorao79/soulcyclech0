extends RefCounted

# Разделитель из знаков вместо тонкой черты с ромбом: от середины к краям знаки редеют
# (« .:-~=≡ ◆ ≡=~-:. »), середина тлеет углём, по линии изредка пробегает искра.
# Рисуется моноширинным шрифтом мира прямо на canvas.

const EMBER := Color(1.0, 0.72, 0.42)
const RULE := Color(0.62, 0.66, 0.82)
# Знаки от середины к краю.
const STEPS := "=~-:.·"


## center — середина, reach — полуширина в пикселях, size — кегль знаков, alpha — прозрачность.
static func draw(canvas: CanvasItem, font: Font, center: Vector2, reach: float, size: int, alpha: float, time: float) -> void:
	if alpha <= 0.0 or reach <= 0.0:
		return
	var advance := font.get_char_size("M".unicode_at(0), size).x
	var count := maxi(int(reach / advance), 1)
	var baseline := center.y + size * 0.32
	# Искра бежит от середины к краям и обратно.
	var spark := fmod(time * 0.35, 1.0)
	for i in range(1, count + 1):
		var share := float(i) / count
		var index := mini(int(share * STEPS.length()), STEPS.length() - 1)
		var letter := STEPS[index]
		var a := alpha * (1.0 - share * 0.75)
		var color := Color(RULE, a)
		if absf(share - spark) < 0.5 / count:
			color = Color(EMBER, alpha)
		for side in [-1.0, 1.0]:
			var x: float = center.x + side * (i + 0.6) * advance - advance * 0.5
			font.draw_string(canvas.get_canvas_item(), Vector2(x, baseline).floor(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	# Середина: угловые скобки и тлеющий ромб.
	var glow := 0.8 + 0.2 * sin(time * 3.0)
	var ember := Color(EMBER.r * glow, EMBER.g * glow, EMBER.b * glow, alpha)
	var mid_w := font.get_string_size("◆", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	font.draw_string(canvas.get_canvas_item(), Vector2(center.x - mid_w * 0.5, baseline).floor(), "◆", HORIZONTAL_ALIGNMENT_LEFT, -1, size, ember)
	font.draw_string(canvas.get_canvas_item(), Vector2(center.x - mid_w * 0.5 - advance * 0.9, baseline).floor(), "<",
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(EMBER, alpha * 0.7))
	font.draw_string(canvas.get_canvas_item(), Vector2(center.x + mid_w * 0.5 + advance * 0.0, baseline).floor(), ">",
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(EMBER, alpha * 0.7))
