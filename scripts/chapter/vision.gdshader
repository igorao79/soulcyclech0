// Видение за столом: двойник Безымянного — чёрное тело в белых полосах — парит в пустой тьме.
// Иллюстрация пересобрана из знаков атласа, как главный экран. Глаза рисуются кодом:
// в каждом звёздная вспышка — лучи медленно вращаются и пульсируют, вокруг мерцают искры.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

const int RAMP_SNOW = 0;
const int RAMP_DENSE = 5;
const int RAMP_EDGE = 9;
const int RAMP_GLOW = 10;
const int RAMP_FLAKE = 11;
const vec3 LUMA = vec3(0.3, 0.55, 0.15);

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform sampler2D art_tex : filter_linear, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(1440.0, 810.0);
uniform float art_aspect = 1.5;
uniform float time = 0.0;
// 0 — темнота, 1 — видно всё.
uniform float reveal = 1.0;
// Глаза открываются отдельно: 0 — закрыты, 1 — горят.
uniform float eyes = 1.0;
// Медленный наезд камеры: 1 — весь кадр, больше — ближе к лицу.
uniform float zoom = 1.0;
// Центры и полуоси глаз в долях картинки.
uniform vec4 eye_left = vec4(0.5652, 0.2900, 0.025, 0.028);
uniform vec4 eye_right = vec4(0.6530, 0.2520, 0.030, 0.036);


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


// Картинка заполняет экран; наезд идёт к точке между глаз.
vec2 art_uv(vec2 px) {
	float height = max(screen_px.x / art_aspect, screen_px.y);
	vec2 size = vec2(height * art_aspect, height);
	vec2 uv = (px - (screen_px - size) * 0.5) / size;
	vec2 focus = (eye_left.xy + eye_right.xy) * 0.5 + vec2(0.0, 0.05);
	return focus + (uv - focus) / zoom;
}


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


float luma_at(vec2 cell) {
	return dot(texture(art_tex, art_uv((cell + 0.5) * cell_px)).rgb, LUMA);
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 center = (cell + 0.5) * cell_px;
	float grain = hash21(cell);

	vec3 col = cell_color(cell);
	float lum = dot(col, LUMA);
	// Картинка очень тёмная (медиана яркости ~0.07): в знаках её вытягиваем до полной шкалы,
	// иначе фигура сольётся с фоном.
	float lift = clamp((lum - 0.018) / 0.21, 0.0, 1.0);
	col = pow(clamp(col / 0.24, vec3(0.0), vec3(1.6)), vec3(0.8)) * 0.72;
	col = max(mix(vec3(dot(col, LUMA)), col, 1.3), vec3(0.0));
	// Белые полосы на теле — самое светлое в кадре: чуть выбелены и холоднее.
	col = mix(col, vec3(0.92, 0.94, 1.0) * 1.15, smoothstep(0.22, 0.6, lum) * 0.5);
	vec2 uv = art_uv(center);

	int ramp = RAMP_DENSE;
	int level = int(clamp(pow(lift, 0.8) * 15.0 + (grain - 0.5) * 1.5, 0.0, 15.0));
	float backing = 0.42;
	if (lum < 0.04) {
		ramp = RAMP_SNOW;
		level = int(clamp(lift * 30.0 + (grain - 0.5) * 3.0, 0.0, 9.0));
		backing = 0.34;
	}
	float gx = luma_at(cell + vec2(1.0, 0.0)) - luma_at(cell - vec2(1.0, 0.0));
	float gy = (luma_at(cell + vec2(0.0, 1.0)) - luma_at(cell - vec2(0.0, 1.0))) * 1.4;
	if (gx * gx + gy * gy > 0.006 && lum > 0.05) {
		ramp = RAMP_EDGE;
		level = int(floor(fract(atan(gy, gx) / PI + 1.0 / 8.0) * 4.0));
		col = col * 1.25 + vec3(0.03, 0.03, 0.06);
	}
	// Звёздная пыль в бархате кресла и в воздухе: яркие одиночные точки мерцают.
	if (lum > 0.12 && luma_at(cell + vec2(1.0, 0.0)) < lum * 0.6 && luma_at(cell - vec2(1.0, 0.0)) < lum * 0.6) {
		col *= 0.6 + 0.6 * sin(time * (1.1 + grain * 3.0) + grain * 40.0);
	}
	// Свечи дрожат.
	if (col.r > col.b * 1.4 && lum > 0.3) {
		col *= 0.9 + 0.12 * sin(time * 8.0 + grain * 6.0) * sin(time * 3.3 + grain * 2.0);
	}

	// Глаза: звёздная вспышка самой картины, но каждый луч — знаком по направлению от центра.
	// По лучам медленно бежит волна, ядро пульсирует, на тёмном дне мерцают искры.
	bool eye_cell = false;
	for (int e = 0; e < 2; e++) {
		vec4 eye = e == 0 ? eye_left : eye_right;
		vec2 q = (uv - eye.xy) / eye.zw;
		float r = length(q);
		if (r < 1.25) {
			float bright = clamp((lum - 0.12) / 0.5, 0.0, 1.0);
			float angle = atan(-q.y * eye.w, q.x * eye.z);
			float wave = 0.75 + 0.35 * sin(angle * 11.0 - time * 1.1 + float(e) * 2.0) * sin(r * 9.0 - time * 2.3);
			float pulse = 0.85 + 0.15 * sin(time * 1.6 + float(e));
			if (bright > 0.12) {
				eye_cell = true;
				ramp = RAMP_EDGE;
				level = int(floor(fract(angle / PI + 1.0 / 8.0) * 4.0));
				col = mix(vec3(0.62, 0.64, 0.92), vec3(1.0), bright) * (0.55 + bright * 0.8) * wave * eyes;
				backing = 0.5;
				if (r < 0.28 && bright > 0.5) {
					ramp = RAMP_GLOW;
					level = 12 + int(pulse * 3.0);
					col = vec3(1.0) * 1.2 * pulse * eyes;
				}
			} else if (r < 0.95 && hash21(cell + floor(time * 1.5 + grain * 7.0)) > 0.9) {
				eye_cell = true;
				ramp = RAMP_FLAKE;
				level = grain > 0.5 ? 5 : 6;
				col = vec3(0.82, 0.86, 1.0) * eyes;
			}
		}
	}

	// Проявление из темноты: глаза видны раньше остального.
	vec2 p = (center - screen_px * 0.5) / screen_px.y;
	float vignette = smoothstep(1.1, 0.3, length(p * vec2(0.85, 1.2)));
	float shown = eye_cell ? 1.0 : reveal;
	col *= mix(0.3, 1.0, vignette) * shown;

	int variant = int(hash21(cell + floor(time * (0.2 + grain * 0.4) + grain * 9.0)) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	vec3 bg = col * backing * 0.55 + vec3(0.004, 0.003, 0.010) * shown;
	COLOR = vec4(mix(bg, col * 1.15, coverage), 1.0);
}
