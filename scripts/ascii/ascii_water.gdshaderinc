// Вода: почти чёрная гладь, редкие группы штрихов, круги по касательной и рваное отражение.
// Весь рисунок живёт только на чётных строках, нечётные пусты: так между штрихами остаётся ночь.
const int RAMP_RIPPLE = 13;

// Знаки ряда воды: столбец равен номеру знака.
const int W_DOT = 1;
const int W_COMMA = 2;
const int W_TICK = 3;
const int W_COLON = 5;
const int W_DASH = 6;
const int W_TILDE = 7;
const int W_LOW = 8;
const int W_EQUAL = 9;
const int W_PLUS = 10;
const int W_STAR = 11;
const int W_SEMI = 13;

// Знаки ряда ряби.
const int R_OPEN = 1;
const int R_CLOSE = 2;
const int R_SLASH = 3;
const int R_BACK = 4;
const int R_TILDE = 5;
const int R_DASH = 6;
const int R_LOW = 7;
const int R_EQUAL = 8;

// Второй проход кладёт подложку 5% от цвета: этот цвет даёт ровно #06080f.
const vec3 WATER_VOID = vec3(0.24, 0.34, 0.70);
const float RIPPLE_SPEED = 0.8;
const float RIPPLE_LIFE = 3.5;


// Знак кольца выбирается по наклону касательной к эллипсу на экране.
void ring_mark(vec2 to_p, float dist, float radius, float amp, vec2 wc, float salt, inout float best, inout int glyph) {
	if (amp <= best) {
		return;
	}
	vec2 dir = to_p / max(dist, 0.001);
	float band = abs(dist - radius) / length(dir * vec2(cell_world.x, cell_world.y / cam_sin));
	if (band > 1.0) {
		return;
	}
	// Старое кольцо рвётся на дуги.
	if (value_noise(wc * vec2(0.17, 0.33) + vec2(salt * 7.0, salt * 3.0)) < (1.0 - amp) * 0.5) {
		return;
	}
	vec2 g = vec2(dir.x, dir.y / cam_sin);
	float slope = abs(g.y) / max(abs(g.x), 0.001);
	int picked;
	if (slope < 0.6) {
		picked = g.x < 0.0 ? R_OPEN : R_CLOSE;
	} else if (slope < 1.9) {
		if (band > 0.72) {
			return;
		}
		picked = g.x * g.y > 0.0 ? R_SLASH : R_BACK;
	} else {
		float pick = hash21(wc + vec2(2.0, salt));
		if (g.y < 0.0) {
			picked = pick < 0.75 ? R_TILDE : R_DASH;
		} else {
			picked = pick < 0.45 ? R_TILDE : (pick < 0.8 ? R_DASH : R_LOW);
		}
	}
	best = amp;
	glyph = picked;
}


// Основной рисунок: короткие группы на регулярном шаге, между пятнами только точки или пустота.
void water_marks(vec2 wc, float row, out int mark, out float glow) {
	mark = 0;
	glow = 0.0;
	float field = value_noise(vec2(wc.x * 0.042 + time * 0.008, wc.y * 0.085 - time * 0.006));
	if (field > 0.53) {
		float seed = hash21(vec2(row, 7.0));
		float drift = floor(time * (0.05 + seed * 0.1)) * (seed > 0.5 ? 1.0 : -1.0);
		float x = wc.x + drift + floor(seed * 40.0);
		float band = floor(row / 3.0);
		float tile = 5.0 + floor(hash21(vec2(band, 3.0)) * 4.0);
		float id = floor(x / tile);
		float luck = hash21(vec2(id, row));
		if (luck > 0.22 + smoothstep(0.53, 0.75, field) * 0.68) {
			return;
		}
		float length_cells = 2.0 + floor(hash21(vec2(id, row + 5.0)) * 3.0);
		if (x - id * tile >= length_cells) {
			return;
		}
		float kind = hash21(vec2(band, row * 0.37 + id * 0.11));
		mark = kind < 0.6 ? W_TILDE : (kind < 0.88 ? W_DASH : (kind < 0.97 ? W_LOW : W_EQUAL));
		glow = 0.55 + luck * 0.55;
	} else if (field > 0.27) {
		if (mod(wc.x, 3.0) > 0.5) {
			return;
		}
		float id = floor(wc.x / 3.0);
		float phase = hash21(vec2(id, row + 2.0));
		float luck = hash21(vec2(id + floor(time * 0.22 + phase * 5.0), row));
		if (luck > 0.34 + (field - 0.27) * 1.3) {
			return;
		}
		mark = phase < 0.5 ? W_COMMA : (phase < 0.8 ? W_TICK : W_DOT);
		glow = 0.3 + phase * 0.22;
	}
}


// Глаза эха считаются прямо по ровному лучу: тонкая прорезь не проваливается между строками и не расходится.
float wraith_eyes(vec3 p, vec3 rd, float sway) {
	float t = (wraith_pos.z + 0.24 * FIGURE_SCALE - p.z) / rd.z;
	vec3 q = p + vec3(-rd.x + sway, -rd.y, rd.z) * t - wraith_pos;
	q /= FIGURE_SCALE;
	q.y -= 1.92 + sin(time * 1.1) * 0.05;
	return t > 0.0 && abs(abs(q.x) - 0.16) < 0.085 && abs(q.y) < 0.08 ? 1.0 : 0.0;
}


void shade_water(vec3 p, vec3 rd, vec2 wc, out vec3 col, out int ramp, out int level) {
	col = WATER_VOID;
	ramp = RAMP_WATER;
	level = 0;

	vec4 here = world_at(p.xz);
	float depth = -here.r;
	float garden = here.b;
	float cell_hash = hash21(wc);
	bool row_on = mod(wc.y, 2.0) < 0.5;
	float row = floor(wc.y * 0.5);

	float gx = sin(p.x * 1.7 + time * 0.9) * 0.012 + sin(p.z * 4.3 - time * 1.4 + p.x) * 0.012;
	float gz = sin(p.z * 2.3 + time * 0.8) * 0.018 + sin(p.x * 3.7 + time * 1.2) * 0.010;
	// Каждая строка символов дрожит по-своему: отражение рвётся на полосы.
	gx += sin(wc.y * 1.3 + time * 1.7 + sin(wc.x * 0.04)) * 0.03;

	float ring_amp = 0.0;
	int ring_glyph = 0;
	for (int i = 0; i < 8; i++) {
		if (ripples[i].z < 0.0) {
			continue;
		}
		vec2 to_p = p.xz - ripples[i].xy;
		float dist = length(to_p);
		float front = 0.2 + ripples[i].z * RIPPLE_SPEED;
		float fade = exp(-ripples[i].z * 0.55) * (1.0 - smoothstep(RIPPLE_LIFE - 1.5, RIPPLE_LIFE, ripples[i].z));
		float envelope = exp(-abs(dist - front) * 3.0) * fade;
		vec2 grad = to_p / max(dist, 0.001) * sin((dist - front) * 11.0) * envelope;
		gx += grad.x * 0.16;
		gz += grad.y * 0.16;
		if (row_on && front > 0.45) {
			ring_mark(to_p, dist, front, fade, wc, float(i) + 1.0, ring_amp, ring_glyph);
		}
	}

	vec3 rd2 = reflect(rd, normalize(vec3(gx, 1.0, gz)));

	if (wraith_on > 0.5 && wraith_eyes(p, rd, gx * 0.5) > 0.5) {
		col = mix(vec3(0.72, 0.92, 1.0), vec3(1.0, 0.3, 0.38), clamp(tolls / 3.0, 0.0, 1.0));
		ramp = RAMP_RIPPLE;
		level = hash21(wc + vec2(4.0, 8.0)) < 0.6 ? R_EQUAL : R_DASH;
		return;
	}
	// Мелководье светлеет плавно, шум в глубине не даёт кромке сложиться в лесенку.
	float jittered = depth + (cell_hash - 0.5) * 0.05;
	float shallow = 1.0 - smoothstep(0.03, 0.34, jittered);
	vec3 bottom = garden > 0.5 ? vec3(0.42, 0.72, 0.52) : vec3(0.62, 0.72, 0.92);
	col = mix(WATER_VOID, bottom * 1.9, shallow * 0.9);
	if (!row_on) {
		return;
	}

	if (ring_amp > 0.0) {
		ramp = RAMP_RIPPLE;
		level = ring_glyph;
		col = vec3(0.60, 0.68, 0.80) * (0.5 + ring_amp * 0.7);
		return;
	}

	int mark = 0;
	float glow = 0.0;
	if (shallow > 0.08) {
		float wash = hash21(vec2(floor(wc.x / 3.0), row) + floor(time * 0.35 + cell_hash * 0.4));
		if (shallow > 0.82 && wash < 0.42) {
			mark = wash < 0.2 ? W_TILDE : W_DASH;
			glow = 0.9;
		} else if (value_noise(wc * vec2(0.13, 0.27)) > 0.4 && hash21(wc + vec2(11.0, 2.0)) < shallow * 0.62) {
			float grain = hash21(wc + vec2(6.0, 3.0));
			mark = grain < 0.4 ? W_DOT : (grain < 0.7 ? W_COMMA : (grain < 0.9 ? W_COLON : W_SEMI));
			glow = 0.55;
		}
	} else {
		water_marks(wc, row, mark, glow);
	}

	float group_id = floor(wc.x / 3.0);
	float tear = value_noise(vec2(wc.x * 0.018 + time * 0.05, row * 0.85 + time * 0.3));
	bool mirror_on = tear > 0.3 && hash21(vec2(group_id, row + 9.0)) < 0.72 && hash21(wc + vec2(1.0, 13.0)) < 0.85;

	// Редкий лунный блик мерцает на чёрной воде.
	float glint = step(0.9975, hash21(wc + vec2(3.0, 9.0))) * (0.5 + 0.5 * sin(time * 2.3 + cell_hash * 30.0));
	// Вокруг фигур и их отражений трассируем всегда: силуэт должен быть сплошным.
	vec2 from_hero = p.xz - player_pos.xz;
	vec2 from_echo = p.xz - wraith_pos.xz;
	bool near_hero = abs(from_hero.x) < 0.55 && from_hero.y > -0.3 && from_hero.y < 2.0;
	bool near_echo = wraith_on > 0.5 && abs(from_echo.x) < 0.7 && from_echo.y > -0.6 && from_echo.y < 2.2;
	if (mark == 0 && !mirror_on && !near_hero && !near_echo) {
		if (glint > 0.55) {
			col = vec3(0.72, 0.80, 1.0) * glint;
			level = cell_hash < 0.5 ? W_PLUS : W_STAR;
		}
		return;
	}

	int m = MAT_TERRAIN;
	float t = trace(p + rd2 * 0.03, rd2, 20.0, 34, true, m);
	if (t < 0.0) {
		if (mark != 0) {
			level = mark;
			col = (shallow > 0.08 ? bottom : vec3(0.46, 0.54, 0.68)) * glow;
		} else if (glint > 0.55) {
			col = vec3(0.72, 0.80, 1.0) * glint;
			level = cell_hash < 0.5 ? W_PLUS : W_STAR;
		}
		return;
	}

	vec3 hit = p + rd2 * (t + 0.03);
	float spark = hash21(wc + vec2(31.0, 7.0));
	bool figure = m >= MAT_COAT && m <= MAT_EYE_DARK && m != MAT_FLOWER && m != MAT_STEM;

	if (m == MAT_WRAITH || m == MAT_WRAITH_EYE) {
		// Эхо: тёмная пустая масса, знаки только по боковой кромке, вода сквозь него не видна.
		vec3 n = normal_at(hit, true);
		float rim = pow(clamp(1.0 + dot(n, rd2), 0.0, 1.0), 1.3) * step(wraith_pos.y + 0.22, hit.y);
		col = WATER_VOID;
		if (rim > 0.35 && spark < 0.8) {
			ramp = RAMP_MIRROR;
			col = vec3(0.24, 0.34, 0.45);
			level = 13 + int(spark * 3.0);
		} else if (spark < 0.14) {
			ramp = RAMP_MIRROR;
			col = vec3(0.13, 0.17, 0.24);
			level = 2 + int(spark * 20.0);
		}
	} else if (figure) {
		// Отражение героя почти силуэт: чёрная дыра в ряби с редкими светлыми точками.
		bool pale = m == MAT_SHIRT || m == MAT_SKIN || m == MAT_BLADE || m == MAT_HAIR_BLOND || m == MAT_TUNIC;
		col = WATER_VOID;
		if (m == MAT_EYE) {
			ramp = RAMP_MIRROR;
			col = vec3(0.62, 0.08, 0.12);
			level = 13;
		} else if (spark < (pale ? 0.55 : 0.22) && tear > 0.25) {
			ramp = RAMP_MIRROR;
			col = pale ? vec3(0.52, 0.54, 0.58) : vec3(0.30, 0.33, 0.41);
			level = pale ? 3 + int(spark * 9.0) : 2 + int(spark * 12.0);
		}
	} else if (m == MAT_TERRAIN) {
		// Берег в воде едва угадывается.
		if (mirror_on && spark < 0.32) {
			ramp = RAMP_MIRROR;
			col = (garden > 0.5 ? vec3(0.08, 0.27, 0.16) : vec3(0.26, 0.31, 0.42)) * (0.7 + spark);
			level = 1 + int(spark * 11.0);
		}
	} else if (mirror_on) {
		vec3 n = normal_at(hit, true);
		vec3 albedo;
		vec3 emissive;
		int unused_ramp;
		float hit_garden = world_at(hit.xz).b;
		surface_of(m, hit, n, hit_garden, albedo, emissive, unused_ramp);
		vec3 lit = albedo * light_at(hit, n, rd2, 1.0) + emissive;
		float lum = dot(lit, vec3(0.3, 0.55, 0.15));
		ramp = RAMP_MIRROR;
		col = lit / (1.0 + lum * 0.8) * 0.72;
		// Зелень в лунном свете синеет, в отражении ей возвращается свой цвет.
		if (hit_garden > 0.5 && m != MAT_LAMP) {
			col = mix(col, vec3(0.30, 0.68, 0.46) * (0.45 + sqrt(lum) * 0.75), 0.8);
		}
		level = int(clamp(5.0 + sqrt(lum) * 9.0 + (spark - 0.5) * 8.0, 2.0, 15.0));
	}
}
