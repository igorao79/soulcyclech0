class_name SoulcycleUiStyle
extends RefCounted

# Общие числа интерфейса: логическая высота, под которую вёрстаются меню, и шрифт заголовка.

const LOGICAL_HEIGHT := 540.0
const SERIF_FONT := preload("res://assets/fonts/CormorantGaramond.ttf")
# Высота прописной в долях кегля: нужна, чтобы буквы разных шрифтов выходили одной высоты.
const SERIF_CAP := 0.625


## Cormorant Garamond нужной жирности: шрифт переменный, ось wght от 300 до 700.
static func serif(weight: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = SERIF_FONT
	font.variation_opentype = {"wght": weight}
	return font
