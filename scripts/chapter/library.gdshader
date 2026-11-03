// Библиотека изнутри: вид сбоку, целиком из символов атласа.
// Каменная стена, высокие стеллажи с книгами, арочное окно со снегопадом и луной,
// подвесной фонарь, стол со свечой и стул. Безымянный — та же SDF-фигура, что снаружи,
// снятая ортографической камерой сбоку. Пол — доски, по ним ложится лунная полоса.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://scripts/ascii/ascii_common.gdshaderinc"
#include "res://scripts/ascii/ascii_figures.gdshaderinc"

const int RAMP_EDGE = 9;
const int RAMP_DENSE = 5;
const vec3 LUMA = vec3(0.3, 0.55, 0.15);

// Комната: стены по краям, потолок, полки (x0, x1), окно, стол, стул, свеча, фонарь.
const float ROOM_LEFT = -7.6;
const float ROOM_RIGHT = 8.6;
const float CEILING = 3.4;
const float SHELF_TOP = 2.75;
const float SHELF_ROW = 0.42;
const vec4 SHELVES[3] = vec4[3](vec4(-5.7, -3.0, 0.0, 0.0), vec4(-2.6, 0.2, 0.0, 0.0), vec4(5.9, 8.2, 0.0, 0.0));
const vec2 WINDOW_X = vec2(0.85, 2.25);
const vec2 WINDOW_Y = vec2(0.95, 2.75);
const vec2 TABLE_X = vec2(3.55, 5.35);
const float TABLE_TOP = 0.76;
const vec2 CHAIR_X = vec2(2.92, 3.38);
const float CHAIR_SEAT = 0.46;
const vec2 CANDLE = vec2(5.0, 0.76);
const vec2 LAMP = vec2(-1.2, 2.55);
const vec2 DOOR_X = vec2(-7.25, -6.25);
// Книга, которую нужно взять: светится на полке, пока её не сняли.
const vec2 BOOK = vec2(-1.32, 1.47);

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(1440.0, 810.0);
uniform vec2 cam_center = vec2(0.0, 1.6);
uniform float view_height = 4.4;
uniform float fade = 0.0;
uniform float book_taken = 0.0;
uniform float book_open = 0.0;
// Насколько светится книга на полке: тлеет, когда герой рядом.
uniform float book_glow = 0.0;
// Уход в видение, как «Начать путь» на главном экране: от середины расходится
// красный шум, за ним остаётся темнота. 0 — нет, 1 — кадр погас.
uniform float outro = 0.0;


float fbm(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.1 + 3.7) * 0.3 + value_noise(p * 4.3 + 9.1) * 0.1;
}


vec2 world_of(vec2 screen) {
	vec2 offset = (screen - screen_px * 0.5) / screen_px.y * view_height;
	return cam_center + vec2(offset.x, -offset.y);
}


int edge_level(vec2 normal) {
	return int(floor(fract(atan(normal.y, normal.x) / PI + 1.0 / 8.0) * 4.0));
}


float flicker() {
	return 0.88 + 0.08 * sin(time * 9.0) * sin(time * 4.3 + 1.0) + 0.04 * sin(time * 23.0);
}


// Тёплый свет свечи и фонаря, холодный — из окна. Возвращает цвет освещения точки стены.
vec3 room_light(vec2 wp) {
	vec2 to_candle = (wp - (CANDLE + vec2(0.0, 0.3))) * vec2(1.0, 1.15);
	vec2 to_lamp = (wp - LAMP) * vec2(1.0, 1.2);
	vec3 c = vec3(0.10, 0.10, 0.16);
	c += vec3(1.0, 0.62, 0.30) * exp(-dot(to_candle, to_candle) * 0.55) * 1.25 * flicker();
	c += vec3(0.95, 0.60, 0.32) * exp(-dot(to_lamp, to_lamp) * 0.42) * 0.85;
	// Лунный столб из окна, наклонённый вправо-вниз.
	float beam_x = wp.x - (wp.y - WINDOW_Y.x) * -0.55;
	float beam = smoothstep(WINDOW_X.x - 0.1, WINDOW_X.x + 0.25, beam_x) * smoothstep(WINDOW_X.y + 0.1, WINDOW_X.y - 0.25, beam_x);
	beam *= smoothstep(WINDOW_Y.y, WINDOW_Y.x, wp.y) * step(-0.6, wp.y);
	c += vec3(0.42, 0.50, 0.78) * beam * 0.55;
	return c;
}


bool in_window(vec2 wp) {
	if (wp.x < WINDOW_X.x || wp.x > WINDOW_X.y || wp.y < WINDOW_Y.x) {
		return false;
	}
	float half_w = (WINDOW_X.y - WINDOW_X.x) * 0.5;
	vec2 c = vec2((WINDOW_X.x + WINDOW_X.y) * 0.5, WINDOW_Y.y - half_w);
	return wp.y < c.y || length(wp - c) < half_w;
}


// Книга на полке: номер ячейки ряда → толщина, высота, цвет, наклон.
void book_slot(float x, float row, out float id, out float rel, out float width) {
	// Книги разной толщины: идём по ряду отрезками, ширина каждого — от хэша.
	float unit = 0.055;
	float k = floor(x / unit);
	id = k + row * 131.0;
	width = unit;
	rel = fract(x / unit);
}


// Стеллаж: рамы, полки, корешки. Возвращает true, если точка внутри стеллажа.
bool shelf_at(vec2 wp, vec2 cell, float grain, inout vec3 col, inout int ramp, inout int level, inout float backing) {
	for (int i = 0; i < 3; i++) {
		vec4 s = SHELVES[i];
		if (wp.x < s.x || wp.x > s.y || wp.y < 0.0 || wp.y > SHELF_TOP + 0.12) {
			continue;
		}
		vec3 light = room_light(wp);
		vec3 wood = vec3(0.36, 0.22, 0.13);
		backing = 0.4;
		// Карниз сверху и боковины.
		if (wp.y > SHELF_TOP || wp.x < s.x + 0.07 || wp.x > s.y - 0.07) {
			ramp = RAMP_DENSE;
			level = 9 + int(grain * 4.0);
			col = wood * light * 1.6;
			if (wp.y > SHELF_TOP) {
				ramp = RAMP_PLANK;
				level = 12;
			}
			return true;
		}
		float row_f = wp.y / SHELF_ROW;
		float row = floor(row_f);
		float in_row = fract(row_f) * SHELF_ROW;
		// Полка — доска толщиной в строку.
		if (in_row < 0.045) {
			ramp = RAMP_PLANK;
			level = 13;
			col = wood * light * 1.8;
			return true;
		}
		float id;
		float rel;
		float width;
		book_slot(wp.x, row, id, rel, width);
		float h = hash21(vec2(id, 7.0));
		float book_h = SHELF_ROW * (0.62 + 0.3 * h);
		bool gap = hash21(vec2(id, 3.0)) > 0.9;
		bool leaning = hash21(vec2(id, 5.0)) > 0.93;
		// Снятая книга оставляет пустое место.
		bool is_target = abs(wp.x - BOOK.x) < 0.035 && row == floor(BOOK.y / SHELF_ROW);
		if (is_target && book_taken > 0.5) {
			gap = true;
		}
		float top = 0.045 + book_h;
		if (gap || in_row > top) {
			// Глубина полки — тёмная задняя стенка.
			ramp = RAMP_SNOW;
			level = int(grain * 3.0);
			col = vec3(0.10, 0.07, 0.06) * light;
			backing = 0.6;
			return true;
		}
		vec3 tint = mix(vec3(0.42, 0.14, 0.12), vec3(0.16, 0.22, 0.40), hash21(vec2(id, 1.0)));
		tint = mix(tint, vec3(0.42, 0.36, 0.22), step(0.7, hash21(vec2(id, 2.0))));
		tint = mix(tint, vec3(0.20, 0.30, 0.22), step(0.85, hash21(vec2(id, 9.0))));
		ramp = RAMP_EDGE;
		level = leaning ? 1 : 0;
		col = tint * light * 2.2;
		// Тиснение на корешке — поперечная полоска.
		if (abs(in_row - top * 0.62) < 0.02 || abs(in_row - top * 0.3) < 0.02) {
			ramp = RAMP_PLANK;
			level = 10;
			col = vec3(0.80, 0.68, 0.40) * light * 1.2;
		}
		// Корешки разделены тёмным швом.
		if (rel < 0.18) {
			ramp = RAMP_SNOW;
			level = 1;
			col *= 0.4;
		}
		if (is_target) {
			// Нужная книга: тёмно-синий переплёт тлеет звёздным светом.
			float pulse = 0.55 + 0.45 * sin(time * 2.2);
			col = mix(vec3(0.20, 0.24, 0.55), vec3(0.62, 0.70, 1.0), pulse * book_glow) * 1.3;
			ramp = book_glow > 0.4 ? RAMP_GLOW : RAMP_EDGE;
			level = book_glow > 0.4 ? 10 + int(pulse * 4.0) : 0;
		}
		backing = 0.35;
		return true;
	}
	return false;
}


// Мебель: стол, стул, свеча, открытая книга. true — точка занята мебелью.
bool furniture_at(vec2 wp, float grain, inout vec3 col, inout int ramp, inout int level, inout float backing) {
	vec3 light = room_light(wp);
	vec3 wood = vec3(0.40, 0.25, 0.15);
	// Свеча: огарок в подсвечнике и пламя.
	vec2 c = wp - CANDLE;
	if (abs(c.x) < 0.07 && c.y > 0.0 && c.y < 0.035) {
		ramp = RAMP_PLANK;
		level = 14;
		col = vec3(0.60, 0.50, 0.34) * light;
		return true;
	}
	if (abs(c.x) < 0.028 && c.y > 0.0 && c.y < 0.2) {
		ramp = RAMP_EDGE;
		level = 0;
		col = vec3(0.95, 0.88, 0.74) * (0.8 + 0.2 * flicker());
		return true;
	}
	float sway = sin(time * 3.7) * 0.012 + sin(time * 7.9) * 0.006;
	vec2 f = (c - vec2(sway, 0.255)) * vec2(1.0, 0.55);
	if (length(f) < 0.03 * flicker() + 0.008) {
		ramp = RAMP_GLOW;
		level = 13 + int(grain * 2.0);
		col = vec3(1.0, 0.78, 0.40) * 1.3;
		return true;
	}
	// Открытая книга на столе: страницы светлые, переплёт тёмный.
	if (book_open > 0.5 && wp.x > TABLE_X.x + 0.25 && wp.x < TABLE_X.x + 0.78 && wp.y > TABLE_TOP && wp.y < TABLE_TOP + 0.05) {
		bool cover = wp.y < TABLE_TOP + 0.015;
		ramp = cover ? RAMP_PLANK : RAMP_PLANK;
		level = cover ? 12 : 9;
		col = cover ? vec3(0.20, 0.24, 0.50) * light * 1.8 : vec3(0.92, 0.86, 0.72) * light * 1.4;
		return true;
	}
	// Столешница и ножки.
	if (wp.x > TABLE_X.x && wp.x < TABLE_X.y) {
		if (wp.y > TABLE_TOP - 0.06 && wp.y < TABLE_TOP) {
			ramp = RAMP_PLANK;
			level = wp.y > TABLE_TOP - 0.02 ? 14 : 12;
			col = wood * light * 1.9;
			backing = 0.45;
			return true;
		}
		bool leg = (wp.x < TABLE_X.x + 0.08 || wp.x > TABLE_X.y - 0.08) && wp.y > 0.0 && wp.y < TABLE_TOP;
		bool rail = wp.y > TABLE_TOP - 0.16 && wp.y < TABLE_TOP - 0.06 && wp.x > TABLE_X.x + 0.08 && wp.x < TABLE_X.y - 0.08;
		if (leg || rail) {
			ramp = RAMP_EDGE;
			level = leg ? 0 : 2;
			col = wood * light * 1.5;
			backing = 0.4;
			return true;
		}
	}
	// Стул: сиденье, спинка слева, ножки.
	if (wp.x > CHAIR_X.x - 0.04 && wp.x < CHAIR_X.y) {
		if (wp.y > CHAIR_SEAT - 0.04 && wp.y < CHAIR_SEAT) {
			ramp = RAMP_PLANK;
			level = 13;
			col = wood * light * 1.7;
			return true;
		}
		bool back = wp.x < CHAIR_X.x + 0.04 && wp.y > 0.0 && wp.y < 1.08;
		bool leg = wp.x > CHAIR_X.y - 0.05 && wp.y > 0.0 && wp.y < CHAIR_SEAT;
		bool slat = wp.x < CHAIR_X.x + 0.04 && (abs(wp.y - 0.95) < 0.03 || abs(wp.y - 0.75) < 0.025);
		if (back || leg || slat) {
			ramp = RAMP_EDGE;
			level = slat ? 2 : 0;
			col = wood * light * 1.5;
			return true;
		}
	}
	// Подвесной фонарь: цепь и стеклянный короб с огнём.
	vec2 l = wp - LAMP;
	if (abs(l.x) < 0.012 && l.y > 0.18 && wp.y < CEILING) {
		ramp = RAMP_EDGE;
		level = 0;
		col = vec3(0.30, 0.28, 0.26) * light;
		return true;
	}
	if (abs(l.x) < 0.11 && abs(l.y) < 0.17) {
		bool frame = abs(l.x) > 0.085 || abs(l.y) > 0.14;
		ramp = frame ? RAMP_EDGE : RAMP_DENSE;
		level = frame ? (abs(l.x) > 0.085 ? 0 : 2) : 12 + int(grain * 4.0);
		col = frame ? vec3(0.22, 0.20, 0.18) : vec3(1.0, 0.72, 0.38) * flicker() * 1.1;
		return true;
	}
	return false;
}


// Фигура: луч идёт сбоку, вдоль -z. Возвращает true и цвет со знаком, если попали.
bool figure_at(vec2 wp, vec2 cell, out vec3 col, out int ramp, out int level) {
	col = vec3(0.0);
	ramp = RAMP_FIGURE;
	level = 0;
	vec2 rel = wp - player_pos.xy;
	if (abs(rel.x) > 1.1 || rel.y < -0.4 || rel.y > 1.7) {
		return false;
	}
	vec3 ro = vec3(wp.x, wp.y, 3.0);
	vec3 rd = vec3(0.0, 0.0, -1.0);
	float t = 1.8;
	int mat = MAT_TERRAIN;
	bool hit = false;
	for (int i = 0; i < 48; i++) {
		vec3 p = ro + rd * t;
		float d = 1000.0;
		int m = MAT_TERRAIN;
		sd_nameless(to_local(p, player_pos, player_yaw) / FIGURE_SCALE, player_phase, player_move, d, m);
		d *= FIGURE_SCALE;
		if (d < 0.006) {
			hit = true;
			mat = m;
			break;
		}
		t += d * 0.9;
		if (t > 4.2) {
			break;
		}
	}
	if (!hit) {
		return false;
	}
	vec3 p = ro + rd * t;
	if (p.y < -0.02) {
		return false;
	}
	vec3 n = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec3 e = 0.5773 * (2.0 * vec3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.0);
		float d = 1000.0;
		int m = MAT_TERRAIN;
		sd_nameless(to_local(p + 0.012 * e, player_pos, player_yaw) / FIGURE_SCALE, player_phase, player_move, d, m);
		n += e * d;
	}
	n = normalize(n);
	vec3 albedo = vec3(0.45);
	vec3 emissive = vec3(0.0);
	figure_surface(mat, p, n, albedo, emissive, ramp);
	// Свет: свеча и фонарь тёплые, сбоку от окна холодная луна.
	vec3 to_candle = normalize(vec3(CANDLE + vec2(0.0, 0.3), 0.4) - p);
	vec3 to_lamp = normalize(vec3(LAMP, 0.6) - p);
	float candle_near = exp(-pow(length(p.xy - CANDLE - vec2(0.0, 0.3)), 2.0) * 0.35);
	float lamp_near = exp(-pow(length(p.xy - LAMP), 2.0) * 0.3);
	vec3 lighting = vec3(1.0, 0.64, 0.32) * max(dot(n, to_candle), 0.0) * (0.25 + 1.4 * candle_near) * flicker();
	lighting += vec3(0.95, 0.62, 0.34) * max(dot(n, to_lamp), 0.0) * (0.15 + 1.1 * lamp_near);
	lighting += vec3(0.16, 0.17, 0.26) * (0.55 + 0.45 * n.y);
	lighting += vec3(0.50, 0.58, 0.90) * pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.0) * 0.7;
	col = albedo * lighting * 1.35 + emissive;
	if (ramp == RAMP_FIGURE) {
		figure_glyph(mat, p, cell, dot(lighting, LUMA), col, level);
		if (abs(n.z) < 0.35 && mat != MAT_EYE_DARK) {
			ramp = RAMP_EDGE;
			level = edge_level(vec2(n.x, -n.y));
			col = col * 1.3 + vec3(0.55, 0.40, 0.26) * clamp(dot(n, to_candle) + 0.5, 0.0, 1.0) * (0.3 + candle_near);
		}
	} else {
		level = int(clamp(dot(col, LUMA) * 15.0, 1.0, 15.0));
	}
	return true;
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 center = (cell + 0.5) * cell_px;
	vec2 wp = world_of(center);
	float grain = hash21(cell);

	vec3 col = vec3(0.0);
	vec3 under = vec3(-1.0);
	int ramp = RAMP_SNOW;
	int level = 0;
	float backing = 0.25;
	vec3 light = room_light(wp);

	if (wp.x < ROOM_LEFT || wp.x > ROOM_RIGHT || wp.y > CEILING + 0.5) {
		col = vec3(0.0);
	} else if (wp.y < 0.0) {
		// Пол: доски, к зрителю темнее; лунная полоса и отсвет свечи.
		float depth = -wp.y;
		float plank = floor(wp.x / 0.6 + floor(depth / 0.12) * 0.37);
		ramp = RAMP_PLANK;
		level = mod(depth, 0.12) < 0.04 ? 8 : 11 + int(hash21(vec2(plank, floor(depth / 0.12))) * 4.0);
		col = vec3(0.42, 0.27, 0.17) * room_light(vec2(wp.x, 0.05)) * 1.7 * exp(-depth * 1.6);
		backing = 0.3;
	} else if (wp.y > CEILING) {
		// Потолочные балки.
		ramp = RAMP_PLANK;
		level = mod(wp.x, 1.6) < 0.25 ? 14 : 10;
		col = vec3(0.24, 0.15, 0.09) * light * 1.4;
	} else {
		// Стена: кладка из крупного камня, у пола — тёмная деревянная панель.
		float row = floor(wp.y / 0.26);
		float bx = wp.x / 0.52 + mod(row, 2.0) * 0.5;
		bool seam = fract(wp.y / 0.26) < 0.16 || fract(bx) < 0.06;
		float stone = 0.6 + 0.5 * hash21(vec2(floor(bx), row)) + fbm(wp * 3.0) * 0.3;
		ramp = RAMP_DENSE;
		level = seam ? 1 : int(clamp(stone * 4.0 + grain * 2.0, 2.0, 8.0));
		col = vec3(0.34, 0.33, 0.38) * stone * light * 1.4;
		backing = 0.3;
		if (wp.y < 0.55) {
			ramp = RAMP_EDGE;
			level = mod(cell.x, 9.0) < 1.0 ? 0 : (wp.y > 0.5 ? 2 : 0);
			col = vec3(0.30, 0.19, 0.11) * light * (mod(cell.x, 9.0) < 1.0 ? 1.4 : 0.8);
			if (mod(cell.x, 9.0) >= 1.0 && wp.y <= 0.5) {
				ramp = RAMP_SNOW;
				level = 1 + int(grain * 2.0);
			}
		}
		// Дверь слева: доски под аркой, кованые петли.
		if (wp.x > DOOR_X.x && wp.x < DOOR_X.y && wp.y < 2.25) {
			float dc = (DOOR_X.x + DOOR_X.y) * 0.5;
			bool arch = wp.y < 1.75 || length(vec2((wp.x - dc) * 1.0, wp.y - 1.75)) < 0.5;
			if (arch) {
				ramp = RAMP_EDGE;
				level = 0;
				col = vec3(0.34, 0.21, 0.12) * light * 1.5;
				if (fract((wp.x - DOOR_X.x) / 0.2) < 0.15) {
					col *= 0.35;
				}
				if (abs(wp.y - 0.5) < 0.03 || abs(wp.y - 1.5) < 0.03) {
					ramp = RAMP_PLANK;
					level = 14;
					col = vec3(0.22, 0.22, 0.24) * light * 1.6;
				}
			}
		}
		// Окно: ночь, снег и луна за переплётом.
		if (in_window(wp)) {
			float mid = (WINDOW_X.x + WINDOW_X.y) * 0.5;
			bool mullion = abs(wp.x - mid) < 0.025 || abs(wp.y - 1.75) < 0.025 || abs(wp.y - 2.3) < 0.02;
			bool frame = !in_window(wp + vec2(0.05, 0.0)) || !in_window(wp - vec2(0.05, 0.0)) || wp.y < WINDOW_Y.x + 0.05
				|| !in_window(wp + vec2(0.0, 0.06));
			if (frame || mullion) {
				ramp = RAMP_EDGE;
				level = mullion && abs(wp.x - mid) >= 0.025 ? 2 : 0;
				col = vec3(0.20, 0.14, 0.10) * light * 1.6;
			} else {
				vec3 sky = mix(vec3(0.05, 0.07, 0.16), vec3(0.16, 0.20, 0.38), smoothstep(WINDOW_Y.y, WINDOW_Y.x, wp.y));
				ramp = RAMP_SNOW;
				level = int(grain * 2.0);
				col = sky;
				under = sky;
				backing = 0.7;
				// Серп луны в верхнем углу окна: светлый диск, от которого откусана тень.
				vec2 moon = wp - vec2(mid + 0.36, 2.36);
				float moon_r = 0.11;
				bool lit_moon = length(moon) < moon_r && length(moon - vec2(-0.05, 0.03)) > moon_r * 0.86;
				if (lit_moon) {
					ramp = RAMP_EDGE;
					level = edge_level(vec2(moon.y, -moon.x));
					col = vec3(0.95, 0.96, 1.0) * 1.2;
					under = vec3(0.30, 0.33, 0.50);
					backing = 0.5;
				} else if (length(moon) < 0.32) {
					col += vec3(0.22, 0.25, 0.42) * (1.0 - length(moon) / 0.32);
					under = col;
				}
				// Снег за стеклом: крупные хлопья ближе, мелкие дальше.
				for (int layer = 0; layer < 2; layer++) {
					float fl = float(layer);
					vec2 v = cell + vec2(floor(sin(time * 0.6 + cell.y * 0.05 + fl) * 2.0), -floor(time * (4.0 + fl * 4.0)));
					vec2 tile = vec2(7.0 - fl, 6.0 - fl);
					vec2 id = floor(v / tile);
					if (mod(v, tile) == floor(vec2(hash21(id + fl), hash21(id + 3.0 + fl)) * tile) && hash21(id + 7.0 + fl) > 0.45) {
						ramp = RAMP_FLAKE;
						level = layer == 1 ? 5 : 0;
						col = vec3(0.86, 0.90, 1.0) * (0.6 + 0.4 * fl);
					}
				}
				// Соседние дома за окном: двускатные крыши под снегом, трубы, тёплые окна.
				float span = 0.62;
				float house = floor((wp.x - WINDOW_X.x + 0.17) / span);
				float hx = fract((wp.x - WINDOW_X.x + 0.17) / span) - 0.5;
				float eave = WINDOW_Y.x + 0.16 + 0.05 * hash21(vec2(house, 4.0));
				float ridge = eave + 0.24 - abs(hx) * span * 0.75;
				float chimney_x = 0.22 * (hash21(vec2(house, 8.0)) - 0.5);
				bool chimney = abs(hx - chimney_x) < 0.05 && wp.y < ridge + 0.1 && wp.y > ridge - 0.1;
				if (wp.y < ridge || chimney) {
					under = vec3(0.03, 0.035, 0.07);
					backing = 0.8;
					if (chimney) {
						ramp = RAMP_EDGE;
						level = 0;
						col = vec3(0.20, 0.22, 0.32);
					} else if (wp.y > ridge - 0.035 || (wp.y > eave && wp.y > ridge - 0.07 + hash21(cell) * 0.02)) {
						// Снег лежит на скатах светлой кромкой.
						ramp = RAMP_PATH;
						level = 10 + int(grain * 4.0);
						col = vec3(0.78, 0.84, 1.0) * 0.85;
					} else if (wp.y < eave && abs(hx) < 0.3 && abs(hx - 0.12) < 0.05 && wp.y > WINDOW_Y.x + 0.06 && hash21(vec2(house, 2.0)) > 0.35) {
						// Окно соседа светится.
						ramp = RAMP_DENSE;
						level = 12;
						col = vec3(1.0, 0.70, 0.36) * 0.9;
					} else {
						ramp = wp.y < eave ? RAMP_SNOW : RAMP_PLANK;
						level = wp.y < eave ? 1 + int(grain * 2.0) : 9;
						col = wp.y < eave ? vec3(0.16, 0.17, 0.26) : vec3(0.24, 0.26, 0.40);
					}
				}
			}
		}
		shelf_at(wp, cell, grain, col, ramp, level, backing);
		furniture_at(wp, grain, col, ramp, level, backing);
		// Пылинки в тёплом свете медленно плывут вверх.
		vec2 dv = cell + vec2(floor(sin(time * 0.3 + cell.y * 0.1) * 3.0), floor(time * 1.3));
		vec2 dt = vec2(23.0, 17.0);
		vec2 did = floor(dv / dt);
		float warm = dot(light, LUMA);
		if (warm > 0.35 && mod(dv, dt) == floor(vec2(hash21(did + 1.0), hash21(did + 2.0)) * dt) && hash21(did + 5.0) > 0.5) {
			ramp = RAMP_FLAKE;
			level = 0;
			col = vec3(1.0, 0.82, 0.55) * warm;
		}
	}

	vec3 f_col;
	int f_ramp;
	int f_level;
	if (figure_at(wp, cell, f_col, f_ramp, f_level)) {
		// Ножки стола и край столешницы стоят перед сидящим: стол ближе к зрителю.
		bool table_front = wp.x > TABLE_X.x && wp.x < TABLE_X.y && wp.y > TABLE_TOP - 0.06 && wp.y < TABLE_TOP;
		if (!table_front) {
			col = f_col;
			ramp = f_ramp;
			level = f_level;
			backing = f_ramp == RAMP_FIGURE ? 0.72 : 0.3;
			under = vec3(-1.0);
		}
	}

	float vignette = smoothstep(1.2, 0.35, length((center / screen_px - 0.5) * vec2(1.4, 1.25)));
	col *= mix(0.4, 1.0, vignette) * (1.0 - fade);

	if (outro > 0.0) {
		float r = length((center - screen_px * 0.5) / screen_px.y);
		float front = outro * 1.4;
		if (r < front - 0.14) {
			col = vec3(0.0);
			under = vec3(0.0);
			level = 0;
		} else if (r < front) {
			ramp = RAMP_DENSE;
			level = 5 + int(hash21(cell + floor(time * 24.0)) * 10.0);
			col = mix(vec3(0.95, 0.28, 0.34), vec3(0.2, 0.04, 0.06), (front - r) / 0.14);
			under = col * 0.3;
		}
	}

	int variant = int(hash21(cell + vec2(17.0, 5.0)) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	vec3 base = under.x < 0.0 ? col : under * mix(0.4, 1.0, vignette) * (1.0 - fade);
	vec3 bg = base * backing + vec3(0.008, 0.006, 0.008) * (1.0 - fade);
	COLOR = vec4(mix(bg, col * 1.2, coverage), 1.0);
}
