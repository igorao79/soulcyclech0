// Двор в графике старой игры и его превращение в знаки: первый кадр — обычная картинка
// из вьюпорта; amount растёт от 0 до 1, и ячейки от центра одна за другой становятся символами.
// Кромка перехода горит красным шумом, как «Начать путь» на главном экране.
// reveal так же от центра выжигает сам кадр: под ним уже идёт настоящая игра.
shader_type canvas_item;
render_mode unshaded;

const int RAMP_SNOW = 0;
const int RAMP_DENSE = 5;
const int RAMP_EDGE = 9;
const vec3 LUMA = vec3(0.3, 0.55, 0.15);

uniform sampler2D scene_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(1440.0, 810.0);
uniform float time = 0.0;
uniform float amount = 0.0;
uniform float reveal = 0.0;
uniform float fade = 0.0;
// «Что-то пошло не так»: строки картинки дёргаются в стороны.
uniform float glitch = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float luma_at(vec2 cell) {
	return dot(texture(scene_tex, (cell + 0.5) * cell_px / screen_px).rgb, LUMA);
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 band = vec2(floor(screen.y / 14.0), floor(time * 16.0));
	if (hash21(band) < glitch * 0.45) {
		screen.x += (hash21(band + 3.0) - 0.5) * 90.0 * glitch;
	}
	vec3 picture = texture(scene_tex, screen / screen_px).rgb;

	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 center = (cell + 0.5) * cell_px;
	float grain = hash21(cell);
	vec2 from_middle = (center - screen_px * 0.5) / screen_px.y;
	// Порог ячейки: чем дальше от центра, тем позже, с рваным краем.
	float reach = length(from_middle) * 0.9 + grain * 0.22;
	float front = amount * 1.35 - reach;
	float burnt = reveal * 1.45 - reach;
	if (burnt > 0.0) {
		// Прогоревшая ячейка прозрачна; кромка ещё тлеет красными знаками.
		COLOR = vec4(0.0);
	} else if (front <= 0.0) {
		COLOR = vec4(picture * (1.0 - fade), 1.0);
	} else {
		vec3 s = texture(scene_tex, center / screen_px).rgb;
		float lum = dot(s, LUMA);
		vec3 col = max(mix(vec3(dot(s, LUMA)), s, 1.3), vec3(0.0));
		col = pow(col, vec3(0.8)) * 1.45;
		int ramp = RAMP_DENSE;
		int level = int(clamp(pow(lum * 1.7, 0.85) * 15.0 + (grain - 0.5) * 1.5, 0.0, 15.0));
		float backing = 0.34;
		if (lum < 0.1) {
			// Ночная тень: редкие знаки, чтобы тьма оставалась тьмой.
			ramp = RAMP_SNOW;
			level = int(clamp(lum * 90.0 + (grain - 0.5) * 3.0, 0.0, 9.0));
			backing = 0.22;
		}
		float gx = luma_at(cell + vec2(1.0, 0.0)) - luma_at(cell - vec2(1.0, 0.0));
		float gy = (luma_at(cell + vec2(0.0, 1.0)) - luma_at(cell - vec2(0.0, 1.0))) * 1.4;
		if (gx * gx + gy * gy > 0.04) {
			ramp = RAMP_EDGE;
			level = int(floor(fract(atan(gy, gx) / PI + 0.125) * 4.0));
			col = col * 1.25 + vec3(0.03);
			backing = 0.1;
		}
		// Кромка перехода сгорает красным.
		float edge = max(1.0 - smoothstep(0.0, 0.1, front), reveal > 0.0 ? smoothstep(-0.12, 0.0, burnt) : 0.0);
		col = mix(col, vec3(1.0, 0.22, 0.2) * (0.6 + grain * 0.8), edge);
		col *= 1.0 - fade;
		int variant = int(hash21(cell + floor(time * (0.3 + grain * 0.5))) * 4.0);
		ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
		float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
		COLOR = vec4(mix(col * backing, col * 1.15, coverage), 1.0);
	}
}
