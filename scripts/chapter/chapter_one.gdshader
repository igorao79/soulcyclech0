// Глава первая: вид сбоку, целиком из символов атласа.
// Ночное небо со звездопадом, открытый океан до горизонта отражает небо, снежный склон
// острова с тропинкой, ели наверху и огонёк дома. Безымянный — та же SDF-фигура, что в ASCII-ночи,
// снятая ортографической камерой сбоку.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://scripts/ascii/ascii_common.gdshaderinc"
#include "res://scripts/ascii/ascii_figures.gdshaderinc"

const int RAMP_EDGE = 9;
const int RAMP_DENSE = 5;
const int RAMP_RIPPLE = 13;
const vec3 LUMA = vec3(0.3, 0.55, 0.15);
const int METEORS = 16;
// Болид идёт медленнее всех: его успевают проводить взглядом.
const float BIG_SPEED = 0.26;

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(1440.0, 810.0);
// Камера: центр кадра в мире и сколько мира помещается по высоте экрана.
uniform vec2 cam_center = vec2(4.0, 2.0);
uniform float view_height = 12.0;
// Сколько звёзд падает: к концу заставки больше; 0 — ни одной. Скорость от неё не зависит.
uniform float meteor_rate = 1.0;
// Большой болид: x — время с начала (меньше нуля — нет), yz — откуда, w — угол.
uniform vec4 big_meteor = vec4(-1.0, 0.0, 0.0, 0.0);
uniform float fade = 0.0;
uniform float home_light = 1.0;


float fbm(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.1 + 3.7) * 0.3 + value_noise(p * 4.3 + 9.1) * 0.1;
}


// Берег: из-под воды слева невысокий откос, дальше вправо ровная снежная тропа.
float ground_height(float x) {
	float bank = 0.9 * smoothstep(-1.5, 4.0, x) - 0.35 + 0.05 * sin(x * 0.9) + 0.025 * sin(x * 2.3 + 1.0);
	// У берега откос круто уходит под воду: левее — открытый океан.
	return bank - 9.0 * (1.0 - smoothstep(-2.4, 0.6, x));
}


vec2 world_of(vec2 screen) {
	vec2 offset = (screen - screen_px * 0.5) / screen_px.y * view_height;
	return cam_center + vec2(offset.x, -offset.y);
}


vec2 screen_of(vec2 world) {
	vec2 offset = (world - cam_center) / view_height * screen_px.y;
	return screen_px * 0.5 + vec2(offset.x, -offset.y);
}


int edge_level(vec2 normal) {
	return int(floor(fract(atan(normal.y, normal.x) / PI + 1.0 / 8.0) * 4.0));
}


// Один метеор: голова, светящийся ореол и тлеющий след, который гаснет с хвоста.
// start, dir — экранные доли (y вниз), age — секунды с появления, speed — долей экрана в секунду.
void meteor_trace(vec2 sp, float cell_h, vec2 start, vec2 dir, float age, float speed, float reach,
		float bright, vec3 tint, float seed, inout vec3 col, inout int ramp, inout int level, inout float best, inout vec3 halo) {
	float travelled = min(age * speed, reach);
	vec2 head = start + dir * travelled;
	vec2 to_p = sp - head;
	float along = -dot(to_p, dir);
	vec2 normal = vec2(-dir.y, dir.x);
	float across = abs(dot(to_p, normal));
	float burnt_out = max(age - reach / speed, 0.0);
	float head_alive = 1.0 - smoothstep(0.0, 0.5, burnt_out);

	// Ореол у головы подсвечивает соседние ячейки, не меняя знака.
	float r = length(to_p * vec2(1.0, 1.3)) / cell_h;
	halo += tint * bright * head_alive * exp(-r * r * 0.35) * 0.35;

	if (across > cell_h * 0.6 || along < -cell_h * 0.7 || along > travelled + cell_h) {
		return;
	}
	// Возраст этой точки следа: сколько прошло с тех пор, как через неё прошла голова.
	float passed = max(along, 0.0) / speed;
	float train = 1.0 - smoothstep(0.0, 1.7, passed - 0.1 + burnt_out * 0.5);
	if (train <= 0.0) {
		return;
	}
	float heat = exp(-passed * 2.4);
	vec3 c = mix(tint * 0.55, vec3(1.0, 0.96, 0.88), heat) * bright * train * 1.5;
	float lum = dot(c, LUMA);
	if (lum <= best) {
		return;
	}
	int new_ramp = RAMP_EDGE;
	int new_level = edge_level(normal);
	if (along < cell_h * 0.7 && head_alive > 0.3) {
		new_ramp = RAMP_FLAKE;
		new_level = 6;
	} else if (passed >= 0.3) {
		// Старый след рассыпается на мерцающие искры.
		float spark = hash21(floor(sp / cell_h) + seed + floor(time * 12.0));
		if (spark < 0.45) {
			return;
		}
		new_ramp = RAMP_FLAKE;
		new_level = spark > 0.85 ? 5 : 0;
	}
	best = lum;
	col = c;
	ramp = new_ramp;
	level = new_level;
}


// Звездопад — поток из одного радианта справа вверху: все звёзды разлетаются из этой точки.
// Тусклые искры, обычные звёзды, яркие с ореолом; болид в конце раскалывается на осколки.
bool meteor_at(vec2 sp, float cell_h, out vec3 col, out int ramp, out int level, out vec3 halo) {
	col = vec3(0.0);
	ramp = RAMP_FLAKE;
	level = 0;
	halo = vec3(0.0);
	float best = 0.0;
	float aspect = screen_px.x / screen_px.y;
	vec2 radiant = vec2(aspect * 0.92, -0.18);
	if (meteor_rate > 0.0) {
		for (int i = 0; i < METEORS; i++) {
			float fi = float(i);
			float period = 4.0 + hash21(vec2(fi, 1.0)) * 7.0;
			float clock = time + hash21(vec2(fi, 2.0)) * period;
			float cycle = floor(clock / period);
			float age = mod(clock, period);
			// Частота звездопада решает, сколько мест загорится в этот раз, а не скорость полёта.
			if (hash21(vec2(fi + 7.0, cycle)) > meteor_rate * 0.45) {
				continue;
			}
			float kind = hash21(vec2(fi, cycle + 3.0));
			// Звёзды плывут медленно: путь — секунда-полторы, потом ещё долго тлеет след.
			float speed = 0.22 + kind * 0.14;
			float reach_of = kind > 0.8 ? 0.42 : (kind > 0.35 ? 0.26 : 0.14);
			float life = reach_of / speed + 1.8;
			if (age > life) {
				continue;
			}
			vec2 start = vec2(hash21(vec2(fi, cycle)) * (aspect + 0.3) - 0.3, 0.02 + hash21(vec2(cycle, fi)) * 0.32);
			vec2 dir = normalize(start - radiant + vec2(0.0, 0.25));
			float bright = kind > 0.8 ? 1.25 : (kind > 0.35 ? 0.75 : 0.4);
			float hue = hash21(vec2(cycle, fi + 9.0));
			vec3 tint = hue > 0.85 ? vec3(0.55, 1.0, 0.75) : (hue > 0.6 ? vec3(1.0, 0.78, 0.45) : vec3(0.60, 0.70, 1.0));
			meteor_trace(sp, cell_h, start, dir, age, speed, reach_of, bright, tint, fi, col, ramp, level, best, halo);
		}
	}
	if (big_meteor.x >= 0.0 && big_meteor.x < 7.0) {
		float age = big_meteor.x;
		vec2 start = big_meteor.yz;
		vec2 dir = vec2(cos(big_meteor.w), sin(big_meteor.w));
		meteor_trace(sp, cell_h, start, dir, age, BIG_SPEED, 0.75, 2.2, vec3(1.0, 0.82, 0.55), 40.0, col, ramp, level, best, halo);
		// В конце пути болид раскалывается: осколки расходятся веером и гаснут.
		float split = age - 0.75 / BIG_SPEED;
		if (split > 0.0) {
			vec2 burst = start + dir * 0.75;
			for (int k = 0; k < 5; k++) {
				float fk = float(k);
				float angle = atan(dir.y, dir.x) + (fk - 2.0) * 0.16;
				vec2 shard_dir = vec2(cos(angle), sin(angle));
				meteor_trace(sp, cell_h, burst, shard_dir, split, 0.12, 0.10 + hash21(vec2(fk, 5.0)) * 0.08,
					1.0, vec3(1.0, 0.62, 0.40), 50.0 + fk, col, ramp, level, best, halo);
			}
		}
	}
	return best > 0.02;
}


// Вспышка болида на мгновение высветляет всё небо.
float sky_flash() {
	if (big_meteor.x < 0.0) {
		return 0.0;
	}
	float burst = big_meteor.x - 0.75 / BIG_SPEED;
	return exp(-burst * burst * 18.0) * 0.55;
}


// Небо, звёзды, звездопад и тучи над горизонтом. sp — экранные доли (y вниз), wp — мир.
// sky — цвет неба под знаком: звезда и метеор рисуются поверх него, а не на чёрном.
void background(vec2 sp, vec2 wp, vec2 star_cell, float cell_h, out vec3 col, out vec3 sky, out int ramp, out int level) {
	float up = clamp(1.0 - sp.y, 0.0, 1.0);
	col = mix(vec3(0.20, 0.17, 0.36), vec3(0.03, 0.045, 0.12), pow(up, 0.7));
	sky = col;
	ramp = RAMP_SNOW;
	level = 0;

	// Млечный Путь — косая полоса тумана и частых звёзд.
	float band = exp(-pow((sp.y - 0.12 - (sp.x - 0.9) * 0.35) * 5.5, 2.0));
	float haze = band * fbm(star_cell * 0.09);
	col += vec3(0.16, 0.14, 0.30) * haze;
	sky = col;
	if (hash21(star_cell + 3.0) < haze * 0.35) {
		level = 1 + int(haze * 4.0);
	}

	float star = hash21(star_cell);
	if (star > 0.988 - band * 0.012) {
		float twinkle = 0.55 + 0.45 * sin(time * (1.0 + star * 4.0) + star * 70.0);
		ramp = RAMP_FLAKE;
		level = star > 0.997 ? 6 : (star > 0.993 ? 5 : 0);
		col = vec3(0.86, 0.90, 1.0) * (0.5 + 0.7 * twinkle);
	}

	vec3 m_col;
	int m_ramp;
	int m_level;
	vec3 halo;
	bool streak = meteor_at(sp, cell_h, m_col, m_ramp, m_level, halo);
	float flash = sky_flash();
	sky += halo + vec3(0.30, 0.26, 0.40) * flash * up;
	col += halo + vec3(0.30, 0.26, 0.40) * flash * up;
	if (streak) {
		col = m_col;
		ramp = m_ramp;
		level = m_level;
	}

	// До горизонта ни земли, ни гор: над водой только фиолетовая полоса света и низкие тучи.
	// Они бесконечно далеко и почти не сдвигаются вместе с камерой.
	float rise = max(wp.y, 0.0);
	float far_x = (wp.x - cam_center.x * 0.92) * 0.3;
	vec3 horizon = vec3(0.13, 0.08, 0.26) * exp(-rise * 1.6);
	sky += horizon;
	col += horizon;
	float cloud = smoothstep(0.44, 0.6, fbm(vec2(far_x - time * 0.008, rise * 1.8))) * smoothstep(1.8, 0.4, rise);
	if (cloud > 0.4) {
		ramp = RAMP_SNOW;
		level = int(clamp(1.0 + fbm(vec2(far_x * 4.0, rise * 7.0)) * 5.0, 1.0, 6.0));
		col = mix(vec3(0.26, 0.22, 0.44), vec3(0.13, 0.12, 0.26), clamp(rise, 0.0, 1.0));
		sky = vec3(0.07, 0.065, 0.15);
	}
	// Морская дымка стелется над самой водой и медленно плывёт.
	float mist = smoothstep(0.5, 0.0, rise) * fbm(vec2(wp.x * 0.35 - time * 0.06, wp.y * 2.0));
	sky += vec3(0.08, 0.08, 0.15) * mist;
	col += vec3(0.08, 0.08, 0.15) * mist;
}


// Ели на плато: ярусы треугольников со снегом на лапах.
float pine_at(vec2 wp, out float snow) {
	snow = 0.0;
	float best = 1.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		float x = 11.5 + fi * 1.55 + hash21(vec2(fi, 4.0)) * 0.9;
		float base = ground_height(x) - 0.2;
		float height = 2.2 + hash21(vec2(fi, 9.0)) * 1.8;
		float half_w = height * 0.32;
		vec2 q = vec2(wp.x - x, wp.y - base);
		if (q.y < 0.0 || q.y > height || abs(q.x) > half_w) {
			continue;
		}
		float h = q.y / height;
		float tier = fract(h * 4.0);
		float width = half_w * (1.0 - h) * (0.55 + 0.45 * (1.0 - tier));
		if (abs(q.x) < width || (abs(q.x) < 0.07 && h < 0.2)) {
			best = 0.0;
			snow = max(snow, tier > 0.82 ? 1.0 : 0.0);
		}
	}
	return best;
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
	// Ниже снега фигуры не видно: в сугробе тонут ступни и полы пальто.
	if (p.y < ground_height(p.x) - 0.04) {
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
	// Свет: звёздное небо сверху-слева, холодный контур со стороны океана, тёплый отблеск снега снизу.
	vec3 sky_dir = normalize(vec3(-0.45, 0.8, 0.4));
	vec3 lighting = vec3(0.58, 0.64, 0.86) * max(dot(n, sky_dir), 0.0);
	lighting += vec3(0.16, 0.18, 0.28) * (0.55 + 0.45 * n.y);
	lighting += vec3(0.62, 0.70, 1.0) * pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.0);
	lighting += vec3(0.20, 0.22, 0.30) * max(-n.y, 0.0);
	col = albedo * lighting * 1.35 + emissive;
	if (ramp == RAMP_FIGURE) {
		figure_glyph(mat, p, cell, dot(lighting, LUMA), col, level);
		// Кромка силуэта светится знаком по направлению контура.
		if (abs(n.z) < 0.35 && mat != MAT_EYE_DARK) {
			ramp = RAMP_EDGE;
			level = edge_level(vec2(n.x, -n.y));
			col = col * 1.3 + vec3(0.42, 0.48, 0.70) * clamp(dot(n, sky_dir) + 0.5, 0.0, 1.0);
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
	vec2 sp = center / screen_px.y;
	float cell_h = cell_px.y / screen_px.y;
	float row_world = view_height * cell_h;
	float grain = hash21(cell);
	// Звёзды привязаны к небу, а не к камере: смещаются чуть-чуть, как бесконечно далёкие.
	// Звёзды бесконечно далеко: закреплены на экране и не прыгают, когда камера едет.
	vec2 star_cell = cell;

	vec3 col = vec3(0.0);
	// Цвет подложки под знаком; по умолчанию совпадает с цветом знака.
	vec3 under = vec3(-1.0);
	int ramp = RAMP_SNOW;
	int level = 0;
	float backing = 0.1;
	float ground = ground_height(wp.x);

	if (wp.y >= ground) {
		if (wp.y < 0.0) {
			// Океан: тёмная вода отражает небо и падающие звёзды, из глубины кадра катятся валы.
			float depth = -wp.y;
			float near = min(depth, 1.0);
			// Перспектива: у горизонта валы тонкие и частые, к низу кадра широкие.
			float far = 1.0 / (depth + 0.35);
			float swell = sin(far * 9.0 + time * 0.75 + value_noise(vec2(wp.x * far * 0.35, far * 0.6)) * 4.0);
			vec2 mirror = vec2(
				wp.x + (sin(wp.y * 9.0 + time * 1.4) * 0.06 + swell * 0.14) * near,
				max(depth + swell * 0.12 * near, 0.0)
			);
			vec2 msp = screen_of(mirror) / screen_px.y;
			vec2 mcell = floor(screen_of(mirror) / cell_px);
			mcell = vec2(cell.x, mcell.y);
			vec3 mirror_sky;
			background(msp, mirror, mcell, cell_h, col, mirror_sky, ramp, level);
			vec3 tint = vec3(0.62, 0.68, 0.86) * (0.72 + 0.28 * swell);
			col *= tint;
			under = mirror_sky * tint;
			backing = 0.62;
			if (ramp == RAMP_SNOW || ramp == RAMP_DENSE || ramp == RAMP_PATH) {
				ramp = RAMP_WATER;
				level = min(level, 6);
			}
			// Гребни вала: рваная строка знаков, на самом верху пена.
			float crest = swell * smoothstep(0.06, 0.5, depth);
			if (mod(cell.y, 2.0) < 1.0 && crest > 0.76 && value_noise(vec2(cell.x * 0.07 + time * 0.15, cell.y * 0.4)) > 0.34) {
				ramp = RAMP_RIPPLE;
				level = crest > 0.95 ? 8 : (hash21(vec2(floor(cell.x / 2.0), cell.y)) < 0.6 ? 5 : 6);
				col = mix(vec3(0.34, 0.40, 0.60), vec3(0.76, 0.82, 0.98), smoothstep(0.85, 1.0, crest));
			}
			// Прибой: пена бьётся о подножие откоса, набегает и откатывается.
			float surge = 0.5 + 0.5 * sin(time * 0.8 + wp.y * 2.0);
			if (wp.y - ground < 0.14 + surge * 0.3 && hash21(vec2(floor(cell.x / 2.0), cell.y) + floor(time * 1.6 + grain)) < 0.7) {
				ramp = RAMP_RIPPLE;
				level = grain < 0.5 ? 8 : 5;
				col = vec3(0.70, 0.76, 0.94) * (0.75 + surge * 0.3);
			}
		} else {
			vec3 sky;
			background(sp, wp, star_cell, cell_h, col, sky, ramp, level);
			// Небо — градиент под знаками, звёзды, метеоры и горы поверх него.
			under = sky;
			backing = 0.6;
			float above = wp.y - ground;
			// Сухие стебли у берега торчат из снега и клонятся по ветру.
			// Редкие кустики: по два-три стебля рядом, разной высоты, верхушки клонит ветер.
			float clump = hash21(vec2(floor(cell.x / 5.0), 91.0));
			float stalk_seed = hash21(vec2(cell.x, 37.0));
			float near_shore = smoothstep(6.0, 2.0, wp.x) * step(0.5, wp.x);
			float stalk_height = (0.08 + stalk_seed * 0.26) * near_shore;
			if (clump > 0.62 && stalk_seed > 0.45 && above < stalk_height) {
				float sway = sin(time * 1.6 + cell.x * 0.7) * 0.5 + 0.5;
				ramp = RAMP_EDGE;
				level = above > stalk_height * 0.55 ? (sway > 0.5 ? 1 : 3) : 0;
				col = vec3(0.50, 0.45, 0.40) * (0.7 + 0.3 * stalk_seed);
			}
			// Позёмка: ветер гонит над склоном редкие снежинки.
			if (above < 1.4 && hash21(vec2(cell.x - floor(time * 7.0 + cell.y * 0.3), cell.y)) > 0.994) {
				ramp = RAMP_FLAKE;
				level = 0;
				col = vec3(0.86, 0.90, 1.0) * (1.0 - above / 1.4);
			}
			float snow = 0.0;
			if (pine_at(wp, snow) < 0.5) {
				ramp = RAMP_DENSE;
				level = int(clamp(3.0 + grain * 4.0, 2.0, 8.0));
				col = vec3(0.07, 0.12, 0.14);
				if (snow > 0.5) {
					ramp = RAMP_PATH;
					level = 8 + int(grain * 4.0);
					col = vec3(0.62, 0.68, 0.86);
				}
				backing = 0.35;
				under = vec3(-1.0);
			}
			// Огонёк дома за ельником: окно и тёплый ореол на снегу.
			vec2 home = vec2(28.5, ground_height(28.5) + 0.55);
			vec2 to_home = (wp - home) * vec2(1.0, 1.3);
			float glow = exp(-dot(to_home, to_home) * 1.4) * home_light;
			if (abs(wp.x - home.x) < 0.9 && wp.y < home.y + 0.55 && wp.y > ground - 0.1) {
				ramp = RAMP_DENSE;
				level = 2;
				col = vec3(0.05, 0.05, 0.08);
				backing = 0.5;
				under = vec3(-1.0);
				if (abs(wp.x - home.x) < 0.18 && abs(wp.y - home.y) < 0.16) {
					ramp = RAMP_GLOW;
					level = 12;
					col = vec3(1.0, 0.70, 0.36) * (0.85 + 0.15 * sin(time * 3.0)) * home_light;
				}
			} else if (glow > 0.08 && level < 4) {
				col += vec3(0.6, 0.38, 0.18) * glow;
			}
		}
	} else {
		// Снежный склон: наст сверху ловит свет, глубже снег уходит в синюю тень.
		float depth = ground - wp.y;
		float slope = ground_height(wp.x + 0.2) - ground_height(wp.x - 0.2);
		float lit = clamp(0.55 + slope * 0.6, 0.2, 1.0);
		ramp = RAMP_SNOW;
		level = int(clamp((0.5 + fbm(wp * vec2(1.6, 3.0)) * 0.6) * 11.0 * exp(-depth * 0.35) * lit, 1.0, 12.0));
		col = vec3(0.62, 0.68, 0.92) * (0.35 + 0.75 * exp(-depth * 0.45)) * lit;
		backing = 0.32;
		bool path = wp.x > 0.6 && wp.x < 34.0;
		if (depth < row_world * 1.1) {
			ramp = RAMP_PATH;
			level = 11 + int(grain * 4.0);
			col = vec3(0.92, 0.95, 1.0) * lit;
			if (path) {
				// Тропинка протоптана в насте: тёмные следы вперемешку со снегом.
				ramp = RAMP_SNOW;
				level = grain > 0.45 ? 6 : 3;
				col = vec3(0.50, 0.50, 0.64) * lit;
			}
		} else if (path && depth < row_world * 2.2 && grain > 0.6) {
			ramp = RAMP_SNOW;
			level = 4;
			col = vec3(0.46, 0.48, 0.64) * lit;
		}
		if (wp.y < 0.0 && depth < row_world * 1.2) {
			// Кромка у воды — светлая полоса наледи.
			ramp = RAMP_RIPPLE;
			level = 5;
			col = vec3(0.55, 0.62, 0.80);
		}
	}

	vec3 f_col;
	int f_ramp;
	int f_level;
	if (figure_at(wp, cell, f_col, f_ramp, f_level)) {
		col = f_col;
		ramp = f_ramp;
		level = f_level;
		backing = f_ramp == RAMP_FIGURE ? 0.72 : 0.3;
		under = vec3(-1.0);
	}

	float vignette = smoothstep(1.15, 0.35, length((center / screen_px - 0.5) * vec2(1.5, 1.2)));
	col *= mix(0.45, 1.0, vignette) * (1.0 - fade);

	int variant = int(hash21(cell + vec2(17.0, 5.0)) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	vec3 base = under.x < 0.0 ? col : under * mix(0.45, 1.0, vignette) * (1.0 - fade);
	vec3 bg = base * backing + vec3(0.006, 0.007, 0.016) * (1.0 - fade);
	COLOR = vec4(mix(bg, col * 1.2, coverage), 1.0);
}
