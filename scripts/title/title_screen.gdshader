// Главный экран: иллюстрация с двумя героями, пересобранная из символов атласа.
// Цвет и яркость каждой ячейки берутся из картинки, контуры — знаками по направлению
// края, а снег, мерцание звёзд, дыхание луны и шорох перьев дорисовываются кодом.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Ряды атласа, см. RAMPS в ascii_font_atlas.gd.
const int RAMP_SNOW = 0;
const int RAMP_DENSE = 5;
const int RAMP_EDGE = 9;
const int RAMP_FLAKE = 11;
const vec3 LUMA = vec3(0.3, 0.55, 0.15);

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform sampler2D art_tex : filter_linear, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(960.0, 540.0);
uniform float art_aspect = 1.5;
uniform float time = 0.0;
uniform float intro = 1.0;
uniform float outro = 0.0;
// Прямоугольник под заголовком и меню (в пикселях): там картинка притушена, чтобы текст читался.
uniform vec4 calm_rect = vec4(0.0);
// Заголовок: маска букв шрифтом Soulcycle Thorn, из неё знаки складывают «ЦИКЛ ДУШ».
uniform sampler2D title_mask : filter_linear, repeat_disable;
uniform vec4 title_box = vec4(0.0);
uniform float title_time = 0.0;


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


// Доля ячейки, закрытая буквами заголовка.
float title_cover(vec2 cell) {
	float sum = 0.0;
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 px = (cell + (vec2(float(x), float(y)) + 0.5) / 3.0) * cell_px;
			sum += texture(title_mask, px / screen_px).a;
		}
	}
	return sum / 9.0;
}


// Картинка вписана с обрезкой по краям: заполняет экран целиком.
vec2 art_uv(vec2 px) {
	float height = max(screen_px.x / art_aspect, screen_px.y);
	vec2 size = vec2(height * art_aspect, height);
	// Обрезаем в основном снизу: луна наверху должна остаться целой.
	vec2 overflow = screen_px - size;
	return (px - vec2(overflow.x * 0.5, overflow.y * 0.12)) / size;
}


// Среднее по ячейке: девять проб, иначе мелкие штрихи картинки мерцают при смене размера окна.
vec3 cell_color(vec2 cell) {
	vec3 sum = vec3(0.0);
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 px = (cell + (vec2(float(x), float(y)) + 0.5) / 3.0) * cell_px;
			sum += texture(art_tex, art_uv(px)).rgb;
		}
	}
	return sum / 9.0;
}


// Перья и полы шуршат: нижняя половина кадра чуть колышется, знаки на кромках перебегают.
vec3 rustled_color(vec2 cell) {
	vec2 uv = art_uv((cell + 0.5) * cell_px);
	float sway = smoothstep(0.45, 0.8, uv.y) * 0.0035;
	vec2 shift = vec2(sin(uv.y * 38.0 + time * 1.7) + sin(uv.y * 13.0 - time * 0.9) * 0.6, 0.0) * sway;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 px = (cell + vec2(0.25 + 0.5 * float(i & 1), 0.25 + 0.5 * float(i >> 1))) * cell_px;
		sum += texture(art_tex, art_uv(px) + shift).rgb;
	}
	return sum * 0.25;
}


float luma_at(vec2 cell) {
	return dot(texture(art_tex, art_uv((cell + 0.5) * cell_px)).rgb, LUMA);
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 center = (cell + 0.5) * cell_px;
	vec2 p = (center - screen_px * 0.5) / screen_px.y;
	float grain = hash21(cell);

	vec3 col = mix(cell_color(cell), rustled_color(cell), 0.6);
	float lum = dot(col, LUMA);
	// Иллюстрация ночная и тёмная: в символах её нужно вытянуть, иначе знаки сольются с фоном.
	col = pow(col, vec3(0.72)) * 1.75;
	col = max(mix(vec3(dot(col, LUMA)), col, 1.45), vec3(0.0));
	vec2 uv = art_uv(center);

	// Луна дышит, вокруг неё тлеет ореол.
	float moonish = smoothstep(0.55, 0.8, lum) * (1.0 - smoothstep(0.1, 0.32, uv.y));
	col *= 1.0 + moonish * 0.12 * sin(time * 0.8);

	int ramp = RAMP_DENSE;
	int level = int(clamp(pow(lum * 2.2, 0.8) * 15.0 + (grain - 0.5) * 1.5, 0.0, 15.0));
	float backing = 0.42;
	if (lum < 0.07) {
		// Тёмное небо и тени: редкие знаки, чтобы ночь оставалась ночью.
		ramp = RAMP_SNOW;
		level = int(clamp(lum * 130.0 + (grain - 0.5) * 3.0, 0.0, 9.0));
		backing = 0.3;
	}

	// Контуры фигур: знак по направлению края, светлее самой ячейки.
	float gx = luma_at(cell + vec2(1.0, 0.0)) - luma_at(cell - vec2(1.0, 0.0));
	float gy = (luma_at(cell + vec2(0.0, 1.0)) - luma_at(cell - vec2(0.0, 1.0))) * 1.4;
	if (gx * gx + gy * gy > 0.03 && lum > 0.1) {
		float angle = atan(gy, gx);
		ramp = RAMP_EDGE;
		level = int(floor(fract(angle / PI + 1.0 / 8.0) * 4.0));
		col = col * 1.3 + vec3(0.04, 0.04, 0.06);
	}

	// Звёзды и снежинки картинки подмигивают каждая в своём ритме.
	if (lum > 0.25 && uv.y < 0.5 && luma_at(cell + vec2(1.0, 0.0)) < lum * 0.6 && luma_at(cell - vec2(1.0, 0.0)) < lum * 0.6) {
		col *= 0.75 + 0.45 * sin(time * (1.3 + grain * 3.0) + grain * 40.0);
	}

	// Заголовок из знаков: тело букв — плотные знаки, раскалённые снизу, кромка — знаки
	// по направлению контура. Буквы расшифровываются из шума, строки изредка дёргаются.
	vec2 box_min = title_box.xy - vec2(cell_px.x * 3.0, title_box.w);
	vec2 box_max = title_box.xy + title_box.zw + vec2(cell_px.x * 3.0, cell_px.y);
	bool near_title = title_box.z > 0.0 && all(greaterThan(center, box_min)) && all(lessThan(center, box_max));
	float cover = 0.0;
	bool glowing = false;
	bool ember_cell = false;
	vec3 art_col = col;
	if (near_title) {
		float jolt = hash21(vec2(cell.y, floor(time * 7.0)));
		float shift = jolt > 0.975 ? (hash21(vec2(cell.y, floor(time * 7.0) + 5.0)) > 0.5 ? 2.0 : -2.0) : 0.0;
		vec2 title_cell = cell + vec2(shift, 0.0);
		cover = title_cover(title_cell);
		float rise = clamp((center.y - title_box.y) / max(title_box.w, 1.0), 0.0, 1.0);
		float heat = value_noise(title_cell * vec2(0.22, 0.45) + vec2(0.0, time * 1.6));
		vec3 bone = vec3(0.96, 0.91, 0.83);
		vec3 ember = vec3(1.0, 0.46, 0.22);
		vec3 blood = vec3(0.78, 0.10, 0.16);
		if (cover > 0.5) {
			ramp = RAMP_DENSE;
			level = clamp(12 + int(heat * 4.0), 12, 15);
			col = mix(bone, ember, smoothstep(0.4, 0.95, heat) * (0.3 + 0.7 * rise));
			backing = 0.62;
		} else if (cover > 0.1) {
			float gx_t = title_cover(title_cell + vec2(1.0, 0.0)) - title_cover(title_cell - vec2(1.0, 0.0));
			float gy_t = (title_cover(title_cell + vec2(0.0, 1.0)) - title_cover(title_cell - vec2(0.0, 1.0))) * 1.4;
			ramp = RAMP_EDGE;
			level = int(floor(fract(atan(gy_t, gx_t) / PI + 1.0 / 8.0) * 4.0));
			col = mix(blood, ember, heat) * 1.3;
			backing = 0.18;
		} else if (center.y < title_box.y + title_box.w) {
			// Над буквами поднимаются угли и гаснут по пути.
			vec2 drift = vec2(cell.x + floor(sin(time * 0.8 + cell.y * 0.35) * 1.5), cell.y + floor(time * 9.0));
			vec2 tile = vec2(9.0, 7.0);
			vec2 id = floor(drift / tile);
			vec2 spot = floor(vec2(hash21(id + 3.0), hash21(id + 9.0)) * tile);
			float glow = clamp((center.y - (title_box.y - title_box.w)) / (title_box.w * 1.6), 0.0, 1.0);
			if (mod(drift, tile) == spot && hash21(id + 17.0) > 0.5 && glow > 0.3) {
				ramp = RAMP_FLAKE;
				level = hash21(id + 21.0) > 0.75 ? 5 : 0;
				col = mix(vec3(0.85, 0.22, 0.14), vec3(1.0, 0.76, 0.42), glow) * (0.4 + glow * 0.9);
				glowing = true;
				ember_cell = true;
			}
		}
		glowing = glowing || cover > 0.1;
		float settle = title_time - 0.15 - hash21(cell + 31.0) * 1.4;
		if (cover > 0.1 && settle < 0.0) {
			ramp = RAMP_DENSE;
			level = 4 + int(hash21(cell + floor(time * 20.0)) * 11.0);
			col = blood * (title_time > 0.0 ? 1.1 : 0.0);
			backing = 0.1;
		}
	}

	// Снежинка не выбивает дыру: подложка остаётся цветом картины под ней.
	vec3 under = ember_cell ? art_col : col;
	// Падающий снег поверх картины, но не поверх букв заголовка.
	for (int i = 2; i >= 0 && cover <= 0.1; i--) {
		float layer = float(i);
		vec2 tile = vec2(8.0 + layer * 3.0, 6.0 + layer * 2.0);
		float gust = sin(time * 0.35 + layer) * 3.0;
		vec2 v = cell + vec2(floor(time * (1.2 + layer) + gust), -floor(time * (2.5 + layer * 3.5)));
		vec2 id = floor(v / tile);
		vec2 spot = floor(vec2(hash21(id + layer), hash21(id + layer + 11.0)) * tile);
		if (mod(v, tile) == spot && hash21(id + layer + 23.0) > 0.3) {
			ramp = RAMP_FLAKE;
			level = i == 2 ? 6 : (i == 1 ? 5 : 0);
			col = vec3(0.82, 0.86, 0.96) * mix(0.35, 0.95, layer / 2.0);
			break;
		}
	}

	// Под заголовком и меню картинка уходит в тень.
	vec2 calm_center = calm_rect.xy + calm_rect.zw * 0.5;
	vec2 calm_half = calm_rect.zw * 0.5 + vec2(1.0);
	vec2 into = abs(center - calm_center) / calm_half;
	float calm = (1.0 - smoothstep(0.5, 1.2, length(into))) * step(1.0, calm_rect.z);
	if (!glowing) {
		col *= 1.0 - calm * 0.72;
	}
	under *= 1.0 - calm * (glowing && !ember_cell ? 0.15 : 0.72);

	// Знаки медленно перебирают свои варианты: картинка живёт, не меняя рисунка.
	int variant = int(hash21(cell + floor(time * (0.25 + grain * 0.5) + grain * 9.0)) * 4.0);

	// Появление из шума от центра и уход в шум.
	float r = length(p);
	float reveal = intro * 1.25;
	if (r > reveal) {
		col = vec3(0.0);
		under = col;
		level = 0;
	} else if (r > reveal - 0.07 && intro < 1.0) {
		ramp = RAMP_DENSE;
		level = 4 + int(hash21(cell + floor(time * 20.0)) * 11.0);
		col = vec3(0.55, 0.42, 0.62);
	}
	if (outro > 0.0) {
		float front = outro * 1.4;
		if (r < front - 0.14) {
			col = vec3(0.0);
			under = col;
			level = 0;
		} else if (r < front) {
			ramp = RAMP_DENSE;
			level = 5 + int(hash21(cell + floor(time * 24.0)) * 10.0);
			col = mix(vec3(0.95, 0.28, 0.34), vec3(0.2, 0.04, 0.06), (front - r) / 0.14);
		}
	}

	float vignette = smoothstep(1.1, 0.35, length(p * vec2(0.8, 1.2)));
	col *= mix(0.35, 1.0, vignette);
	under *= mix(0.35, 1.0, vignette);

	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	vec3 bg = under * backing + vec3(0.006, 0.006, 0.014);
	COLOR = vec4(mix(bg, col * 1.15 + vec3(0.01), coverage), 1.0);
}
