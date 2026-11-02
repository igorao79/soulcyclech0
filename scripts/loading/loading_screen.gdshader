// Загрузочный экран целиком из символов того же атласа, что и ASCII-ночь.
// Прогресс загрузки — фаза луны: от новолуния к полной. Вокруг луны вращается колесо душ:
// буквы SOULCYCLE по одной встают на место из шума. Перед луной качается колокол,
// внизу на холме спиной к зрителю стоит Безымянный.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Ряды атласа, см. RAMPS в ascii_font_atlas.gd.
const int RAMP_SNOW = 0;
const int RAMP_DENSE = 5;
const int RAMP_SOLID = 7;
const int RAMP_EDGE = 9;
const int RAMP_FLAKE = 11;
const int RAMP_LETTERS = 15;
const int LETTER_DOT = 7;

const vec2 MOON_CENTER = vec2(0.0, -0.06);
const float MOON_RADIUS = 0.24;
const float RING_DOTS = 0.295;
const float RING_TEXT = 0.355;
const float RING_TICKS = 0.405;
const float RING_SLOTS = 72.0;
const float BELL_DROP = 0.03;
const float FIGURE_HEIGHT = 0.2;

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(960.0, 540.0);
uniform float time = 0.0;
uniform float progress = 0.0;
uniform float ready_glow = 0.0;
uniform float intro = 0.0;
uniform float outro = 0.0;
uniform float bell_angle = 0.0;
uniform float toll = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}


// Координаты центра ячейки: начало в центре экрана, единица — высота экрана, y вниз.
vec2 cell_point(vec2 cell) {
	return ((cell + vec2(0.5)) * cell_px - screen_px * 0.5) / screen_px.y;
}


// Знак по направлению нормали контура: | / - \ (ряд RAMP_EDGE).
int edge_level(vec2 outward) {
	float angle = atan(outward.y, outward.x);
	return int(floor(fract(angle / PI + 1.0 / 8.0) * 4.0));
}


// Буква колеса по номеру места: S O U L C Y C L E, пауза, точка, пауза.
int ring_letter(int slot) {
	int i = slot % 12;
	if (i == 0) {
		return 0;
	} else if (i == 1) {
		return 1;
	} else if (i == 2) {
		return 2;
	} else if (i == 3 || i == 7) {
		return 3;
	} else if (i == 4 || i == 6) {
		return 4;
	} else if (i == 5) {
		return 5;
	} else if (i == 8) {
		return 6;
	} else if (i == 10) {
		return LETTER_DOT;
	}
	return -1;
}


float horizon(float x) {
	return 0.29 + 0.022 * sin(x * 4.0 + 1.0) + 0.011 * sin(x * 11.0 + 0.4) - 0.035 * exp(-x * x * 22.0);
}


// Колокол в своей системе: начало в точке подвеса, y вниз. Повёрнут на угол качания.
bool bell_inside(vec2 p) {
	vec2 pivot = vec2(MOON_CENTER.x, MOON_CENTER.y - MOON_RADIUS - BELL_DROP);
	vec2 q = p - pivot;
	float s = sin(-bell_angle);
	float c = cos(-bell_angle);
	vec2 b = vec2(c * q.x - s * q.y, s * q.x + c * q.y);
	// Ушко над куполом.
	float eye = length(b - vec2(0.0, 0.012));
	if (eye < 0.014 && eye > 0.006) {
		return true;
	}
	if (b.y < 0.02 || b.y > 0.17) {
		// Язык выглядывает из-под юбки.
		return length(b - vec2(sin(bell_angle * 2.0) * 0.014, 0.178)) < 0.012;
	}
	// Профиль колокола: купол, прямая талия, раструб и толстая губа.
	float t = (b.y - 0.02) / 0.15;
	float half_width = 0.045 + 0.02 * t + 0.045 * pow(smoothstep(0.5, 1.0, t), 1.5);
	half_width *= sqrt(clamp(t / 0.14, 0.0, 1.0));
	half_width += smoothstep(0.9, 0.97, t) * 0.012;
	return abs(b.x) < half_width;
}


// Безымянный со спины: высокий ворот, спутанные волосы, полы пальто треплет ветер.
bool figure_inside(vec2 p) {
	vec2 feet = vec2(0.0, horizon(0.0) + 0.004);
	vec2 f = vec2(p.x - feet.x, feet.y - p.y) / FIGURE_HEIGHT;
	if (f.y < -0.02 || f.y > 1.1 || abs(f.x) > 0.6) {
		return false;
	}
	float gust = 0.6 + 0.4 * sin(time * 0.9) * sin(time * 0.37 + 1.0);
	// Ноги в разрезе пальто.
	if (f.y < 0.24 && abs(abs(f.x) - 0.075) < 0.045) {
		return true;
	}
	// Пальто: трапеция от плеч к подолу, подол сносит ветром вправо и он волнуется.
	float low = clamp((0.80 - f.y) / 0.62, 0.0, 1.0);
	float fx = f.x - gust * low * low * 0.16;
	float hem = 0.18 + 0.035 * sin(fx * 28.0 + time * 3.2) * low;
	float half_width = mix(0.175, 0.28, low) + low * low * 0.05 * sin(time * 2.1 + f.y * 9.0);
	if (f.y > hem && f.y < 0.80 && abs(fx) < half_width) {
		return true;
	}
	// Покатые плечи и высокий ворот.
	if (length(vec2(abs(f.x) - 0.12, f.y - 0.76)) < 0.085) {
		return true;
	}
	if (abs(f.x) < 0.06 && f.y > 0.76 && f.y < 0.87) {
		return true;
	}
	// Голова со спутанными прядями.
	vec2 h = f - vec2(0.0, 0.96);
	float angle = atan(h.y, h.x);
	float strands = 0.092 + 0.018 * sin(angle * 7.0 + time * 1.3 + gust) * step(-0.6, sin(angle));
	strands += 0.01 * sin(angle * 13.0 - time * 0.7);
	return length(h * vec2(1.0, 0.92)) < strands;
}


float silhouette(vec2 p, bool bell) {
	bool inside = bell ? bell_inside(p) : figure_inside(p);
	return inside ? 1.0 : 0.0;
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 p = cell_point(cell);
	vec2 cell_size = cell_px / screen_px.y;
	float grain = hash21(cell);

	vec3 col = vec3(0.0);
	int ramp = RAMP_SOLID;
	int level = 0;
	float backing = 0.08;

	vec2 from_moon = p - MOON_CENTER;
	float r = length(from_moon);
	vec2 radial = from_moon / max(r, 0.0001);
	// Толщина одной ячейки вдоль радиуса: кольца выходят ровно в один знак.
	float ring_half = 0.5 * length(radial * cell_size);
	float around = fract(atan(from_moon.x, -from_moon.y) / TAU);
	float ground_y = horizon(p.x);
	bool sky = p.y < ground_y;

	if (!sky) {
		// Снежный склон: у гребня ярче, ниже тонет в темноте.
		float below = p.y - ground_y;
		float moonlit = exp(-below * 9.0);
		ramp = RAMP_SNOW;
		if (below < cell_size.y) {
			level = grain < 0.5 ? 9 : 10;
			moonlit = 1.2;
		} else {
			float drift = value_noise(cell * vec2(0.09, 0.3) + vec2(time * 0.05, 0.0));
			level = int(clamp(moonlit * 9.0 * (0.4 + drift) + (grain - 0.5) * 3.0, 0.0, 12.0));
		}
		col = vec3(0.50, 0.58, 0.78) * (0.25 + moonlit * 0.55 * (0.6 + 0.4 * progress));
		backing = 0.06;
	} else {
		// Небо: редкие звёзды мерцают каждая в своём ритме.
		if (grain > 0.992) {
			float twinkle = 0.5 + 0.5 * sin(time * (1.5 + grain * 30.0) + grain * 90.0);
			ramp = RAMP_FLAKE;
			level = twinkle > 0.8 ? 5 : 0;
			col = vec3(0.70, 0.76, 0.92) * (0.25 + twinkle * 0.5);
		}

		// Ореол луны растёт вместе с фазой.
		float halo = exp(-max(r - MOON_RADIUS, 0.0) * 9.0) * (0.15 + 0.85 * progress);
		if (r > MOON_RADIUS && hash21(cell + floor(time * 1.5) * 0.37) < halo * 0.42) {
			ramp = RAMP_SNOW;
			level = int(clamp(halo * 10.0, 1.0, 6.0));
			col = vec3(0.45, 0.55, 0.82) * (0.3 + halo * 0.6);
		}

		if (r < MOON_RADIUS) {
			vec2 mq = from_moon / MOON_RADIUS;
			float z = sqrt(max(1.0 - dot(mq, mq), 0.0));
			vec3 n = vec3(mq.x, -mq.y, z);
			float phase = PI * (1.0 - progress);
			vec3 light = normalize(vec3(sin(phase), 0.1, cos(phase)));
			float lit = smoothstep(-0.06, 0.22, dot(n, light));
			// Моря и кратеры: тёмные пятна и светлые кольца валов.
			float maria = value_noise(mq * 3.2 + vec2(7.0, 3.0)) * 0.65 + value_noise(mq * 7.5) * 0.35;
			float albedo = 0.68 + 0.32 * smoothstep(0.62, 0.38, maria);
			for (int i = 0; i < 5; i++) {
				vec2 crater = vec2(hash21(vec2(float(i), 3.0)), hash21(vec2(float(i), 7.0))) * 1.3 - vec2(0.65);
				float size = 0.08 + hash21(vec2(float(i), 11.0)) * 0.14;
				float d = length(mq - crater) / size;
				albedo *= d < 1.0 ? 0.78 : (d < 1.25 ? 1.12 : 1.0);
			}
			float earthshine = 0.07 * (1.0 - progress);
			float bright = lit * albedo * (0.55 + 0.45 * z) + earthshine;
			ramp = RAMP_DENSE;
			level = int(clamp(bright * 15.0 + (grain - 0.5) * 1.6, 1.0, 15.0));
			col = mix(vec3(0.16, 0.19, 0.30), vec3(0.93, 0.94, 1.0), clamp(bright, 0.0, 1.0));
			col = mix(col, col * vec3(1.08, 0.92, 0.86), ready_glow * 0.5);
			backing = 0.16;
		}

		// Внутреннее кольцо — бегущий пунктир.
		if (abs(r - RING_DOTS) < ring_half && fract(around * 54.0 - time * 0.25) < 0.34) {
			ramp = RAMP_FLAKE;
			level = 0;
			col = vec3(0.42, 0.50, 0.72) * (0.6 + 0.4 * progress);
		}

		// Внешнее кольцо — штрихи по касательной, разорванные вращающимися просветами.
		if (abs(r - RING_TICKS) < ring_half && fract(around * 36.0 + time * 0.12) < 0.68) {
			ramp = RAMP_EDGE;
			level = edge_level(radial);
			col = mix(vec3(0.30, 0.36, 0.55), vec3(0.95, 0.70, 0.40), ready_glow) * (0.7 + 0.3 * progress);
		}

		// Колесо душ: каждая буква стоит в своём месте, места медленно плывут по кругу.
		if (abs(r - RING_TEXT) < ring_half * 2.0) {
			float spin = time * 0.03;
			float slot = floor(fract(around - spin) * RING_SLOTS);
			float slot_angle = (slot + 0.5) / RING_SLOTS + spin;
			vec2 slot_point = MOON_CENTER + vec2(sin(slot_angle * TAU), -cos(slot_angle * TAU)) * RING_TEXT;
			vec2 slot_cell = floor((slot_point * screen_px.y + screen_px * 0.5) / cell_px);
			int letter = ring_letter(int(slot));
			if (slot_cell == cell && letter >= 0) {
				float settle = (slot + 0.5) / RING_SLOTS;
				if (settle < progress) {
					// Буква только что встала — вспыхивает, потом гаснет до янтаря.
					float fresh = clamp(1.0 - (progress - settle) * 14.0, 0.0, 1.0);
					ramp = RAMP_LETTERS;
					level = letter;
					col = mix(vec3(0.95, 0.72, 0.42), vec3(1.0, 0.36, 0.40), ready_glow * 0.45);
					col = mix(col, vec3(1.0), fresh * 0.8);
				} else {
					// Ещё не собрана: на её месте мечется случайный знак.
					float flicker = hash21(cell + floor(time * 11.0) * vec2(1.7, 3.1));
					ramp = RAMP_DENSE;
					level = 6 + int(flicker * 9.0);
					col = vec3(0.24, 0.30, 0.46);
				}
			}
		}

		// Верёвка от верхнего края к колоколу.
		vec2 pivot = vec2(MOON_CENTER.x, MOON_CENTER.y - MOON_RADIUS - BELL_DROP);
		if (p.y < pivot.y && abs(p.x - pivot.x) < cell_size.x * 0.5) {
			ramp = RAMP_EDGE;
			level = 0;
			col = vec3(0.26, 0.28, 0.36);
		}
	}

	// Колокол и фигура — тёмные силуэты с контуром, на который ложится свет луны.
	bool in_bell = bell_inside(p);
	bool in_figure = !in_bell && figure_inside(p);
	if (in_bell || in_figure) {
		vec2 dx = vec2(cell_size.x, 0.0);
		vec2 dy = vec2(0.0, cell_size.y);
		float left = silhouette(p - dx, in_bell);
		float right = silhouette(p + dx, in_bell);
		float up = silhouette(p - dy, in_bell);
		float down = silhouette(p + dy, in_bell);
		vec2 outward = vec2(left - right, up - down);
		if (dot(outward, outward) > 0.5) {
			// Контур светится со стороны луны: у колокола — по краю диска, у фигуры — сверху.
			vec2 to_light = in_bell ? -radial : normalize(MOON_CENTER - p);
			float rim = clamp(dot(normalize(outward), to_light) * 0.5 + 0.5, 0.0, 1.0);
			ramp = RAMP_EDGE;
			level = edge_level(outward);
			col = mix(vec3(0.16, 0.18, 0.26), vec3(0.78, 0.84, 1.0), rim * (0.4 + 0.6 * progress));
			col += vec3(0.6, 0.12, 0.16) * toll * (in_bell ? 1.0 : 0.0);
		} else {
			ramp = RAMP_SOLID;
			level = grain > 0.86 ? 1 : 0;
			col = vec3(0.05, 0.055, 0.08);
		}
		backing = 0.5;
	}

	// Снег поверх всего: три слоя, ближние хлопья крупнее и быстрее.
	for (int i = 2; i >= 0; i--) {
		float layer = float(i);
		vec2 tile = vec2(7.0 + layer * 3.0, 5.0 + layer * 2.0);
		float gust = sin(time * 0.4 + layer) * 3.0;
		vec2 v = cell + vec2(floor(time * (1.5 + layer) + gust), -floor(time * (3.0 + layer * 4.0)));
		vec2 id = floor(v / tile);
		vec2 spot = floor(vec2(hash21(id + layer), hash21(id + layer + 11.0)) * tile);
		float strength = hash21(id + layer + 23.0);
		if (mod(v, tile) == spot && strength > 0.25) {
			ramp = RAMP_FLAKE;
			level = i == 2 ? 6 : (i == 1 ? 5 : int(strength * 3.99));
			col = vec3(0.80, 0.86, 0.95) * mix(0.3, 0.95, layer / 2.0);
			backing = 0.0;
			break;
		}
	}

	// Удар колокола расходится кольцом от луны.
	if (toll > 0.0) {
		float shock = MOON_RADIUS + (1.0 - toll) * 0.75;
		if (abs(r - shock) < ring_half) {
			ramp = RAMP_EDGE;
			level = edge_level(radial);
			col = vec3(1.0, 0.42, 0.46) * toll;
		}
	}

	// Появление: мир проступает из шума от центра к краям.
	float reveal = intro * 1.3;
	if (r > reveal) {
		col = vec3(0.0);
		level = 0;
	} else if (r > reveal - 0.06 && intro < 1.0) {
		ramp = RAMP_DENSE;
		level = 4 + int(hash21(cell + floor(time * 20.0)) * 11.0);
		col = vec3(0.45, 0.52, 0.75);
	}

	// Уход: волна шума от центра, за ней — чернота.
	if (outro > 0.0) {
		float front = outro * 1.45;
		if (r < front - 0.14) {
			col = vec3(0.0);
			level = 0;
		} else if (r < front) {
			ramp = RAMP_DENSE;
			level = 5 + int(hash21(cell + floor(time * 24.0)) * 10.0);
			col = mix(vec3(0.95, 0.28, 0.34), vec3(0.2, 0.04, 0.06), (front - r) / 0.14);
		}
	}

	// Края кадра тонут в ночи.
	float vignette = smoothstep(1.05, 0.3, length(p * vec2(0.85, 1.35)));
	col *= mix(0.3, 1.0, vignette);

	int variant = int(hash21(cell + vec2(17.0, 5.0)) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	vec3 bg = col * backing + vec3(0.008, 0.010, 0.020);
	COLOR = vec4(mix(bg, col * 1.25 + vec3(0.01, 0.012, 0.02), coverage), 1.0);
}
