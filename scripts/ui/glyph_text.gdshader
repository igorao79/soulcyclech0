// Надписи, сложенные из знаков атласа по форме букв, — как «ЦИКЛ ДУШ» на главном экране.
// Маска рисуется антиквой вне экрана в три канала: R — обычный текст (холодное серебро
// с инеем), G — выбранный пункт (раскалённая кость и угли), B — бледный, недоступный.
// Тело буквы — плотные знаки, кромка и тонкие штрихи — знаки по направлению контура.
// Буквы расшифровываются из шума, строки изредка дёргаются, над выбранным поднимаются угли.
shader_type canvas_item;

const int RAMP_DENSE = 5;
const int RAMP_EDGE = 9;
const int RAMP_FLAKE = 11;

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(1440.0, 810.0);
uniform float time = 0.0;
// Секунды с открытия: по ним буквы проступают из шума.
uniform float appear = 10.0;
// Общая прозрачность (уход).
uniform float fade = 1.0;
// Прямоугольник блока (пиксели): под ним картина притушена, чтобы знаки читались.
uniform vec4 calm_rect = vec4(0.0);


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}


vec3 mask_cover(vec2 cell) {
	vec3 sum = vec3(0.0);
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 px = (cell + (vec2(float(x), float(y)) + 0.5) / 3.0) * cell_px;
			sum += texture(mask_tex, px / screen_px).rgb;
		}
	}
	return sum / 9.0;
}


float total(vec2 cell) {
	vec3 c = mask_cover(cell);
	return c.r + c.g + c.b;
}


float peak(vec2 cell) {
	float best = 0.0;
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 px = (cell + (vec2(float(x), float(y)) + 0.5) / 3.0) * cell_px;
			vec3 m = texture(mask_tex, px / screen_px).rgb;
			best = max(best, m.r + m.g + m.b);
		}
	}
	return best;
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 center = (cell + 0.5) * cell_px;
	float grain = hash21(cell);

	// Строка изредка дёргается на два знака.
	float jolt = hash21(vec2(cell.y, floor(time * 7.0)));
	float shift = jolt > 0.985 ? (hash21(vec2(cell.y, floor(time * 7.0) + 5.0)) > 0.5 ? 2.0 : -2.0) : 0.0;
	vec2 tc = cell + vec2(shift, 0.0);
	vec3 kind = mask_cover(tc);
	float cover = kind.r + kind.g + kind.b;
	if (cover <= 0.1 && peak(tc) > 0.45) {
		cover = 0.3;
	}

	// Тёмная подложка под блоком, к краям тает.
	vec2 calm_c = calm_rect.xy + calm_rect.zw * 0.5;
	vec2 calm_h = calm_rect.zw * 0.5 + vec2(1.0);
	vec2 into = max(abs(center - calm_c) / calm_h, vec2(0.0));
	float calm = (1.0 - smoothstep(0.8, 1.15, max(into.x, into.y))) * step(1.0, calm_rect.z);
	vec4 veil = vec4(0.0, 0.0, 0.012, 0.88 * calm * fade);

	int ramp = RAMP_DENSE;
	int level = 0;
	vec3 col = vec3(0.0);
	bool glyph = false;
	float heat = value_noise(tc * vec2(0.22, 0.45) + vec2(0.0, time * 1.6));
	// Чей это знак: преобладающий канал.
	bool hot = kind.g > max(kind.r, kind.b) * 0.9 && kind.g > 0.0;
	bool dim = !hot && kind.b > kind.r;
	vec3 silver = vec3(0.86, 0.90, 1.0);
	vec3 lilac = vec3(0.62, 0.58, 0.86);
	vec3 bone = vec3(0.98, 0.90, 0.80);
	vec3 ember = vec3(1.0, 0.52, 0.24);

	if (cover > 0.5) {
		glyph = true;
		ramp = RAMP_DENSE;
		level = clamp(13 + int(heat * 3.0), 13, 15);
		col = mix(silver, lilac, smoothstep(0.35, 0.95, heat) * 0.6);
		if (hot) {
			level = clamp(13 + int(heat * 3.0), 13, 15);
			col = mix(bone, ember, smoothstep(0.35, 0.95, heat) * 0.75) * (0.9 + 0.15 * sin(time * 4.0));
		}
	} else if (cover > 0.1) {
		glyph = true;
		float gx = total(tc + vec2(1.0, 0.0)) - total(tc - vec2(1.0, 0.0));
		float gy = (total(tc + vec2(0.0, 1.0)) - total(tc - vec2(0.0, 1.0))) * 1.4;
		ramp = RAMP_EDGE;
		level = int(floor(fract(atan(gy, gx) / PI + 1.0 / 8.0) * 4.0));
		col = mix(vec3(0.62, 0.68, 1.0), vec3(1.0), heat) * 1.35;
		if (hot) {
			col = mix(vec3(1.0, 0.42, 0.22), vec3(1.0, 0.80, 0.55), heat) * 1.2;
		}
	} else if (calm > 0.3) {
		// Над выбранным пунктом поднимаются угли, над остальным — иней.
		vec2 drift = vec2(cell.x + floor(sin(time * 0.8 + cell.y * 0.35) * 1.5), cell.y + floor(time * 7.0));
		vec2 tile = vec2(11.0, 8.0);
		vec2 id = floor(drift / tile);
		vec2 spot = floor(vec2(hash21(id + 3.0), hash21(id + 9.0)) * tile);
		vec3 below = mask_cover(cell + vec2(0.0, 3.0)) + mask_cover(cell + vec2(0.0, 6.0));
		if (mod(drift, tile) == spot && hash21(id + 17.0) > 0.4 && below.r + below.g > 0.2) {
			glyph = true;
			ramp = RAMP_FLAKE;
			level = hash21(id + 21.0) > 0.7 ? 5 : 0;
			col = below.g > below.r ? vec3(1.0, 0.6, 0.3) * 0.9 : vec3(0.70, 0.76, 1.0) * 0.6;
		}
	}
	if (dim && glyph) {
		col = vec3(0.56, 0.60, 0.78) * (ramp == RAMP_EDGE ? 1.0 : 0.9);
	}

	// Расшифровка из шума: каждая ячейка встаёт на место в свой момент.
	float settle = appear - 0.1 - hash21(cell + 31.0) * 0.9 - cell.y * cell_px.y / screen_px.y * 0.6;
	if (glyph && cover > 0.1 && settle < 0.0) {
		ramp = RAMP_DENSE;
		level = 4 + int(hash21(cell + floor(time * 20.0)) * 11.0);
		col = lilac * 0.8 * step(-0.6, settle);
	}

	int variant = int(hash21(cell + floor(time * (0.4 + grain * 0.6) + grain * 9.0)) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = glyph ? texelFetch(atlas_tex, atlas_px, 0).r : 0.0;
	// Под телом буквы — подложка её же цвета, чтобы буква читалась массой.
	float backing = glyph && cover > 0.5 ? 0.82 : 0.0;
	vec3 rgb = mix(col * backing, col * 1.2 + vec3(0.01), coverage);
	float alpha = max(coverage, backing) * fade;
	COLOR = vec4(mix(veil.rgb, rgb, alpha), max(veil.a, alpha));
}
