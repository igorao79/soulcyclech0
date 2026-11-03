// Второй проход комнаты храма: ячейки первого прохода — в знаки атласа.
// Пробуждение: веки (lids 0 — закрыты, 1 — открыты) смыкаются дугами сверху и снизу,
// ресницы — тёмная бахрома по кромке; пока взгляд не сфокусирован (blur), знаки крупнее
// и плывут. fade — уход в темноту.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D scene_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec2 screen_px = vec2(1440.0, 810.0);
uniform float time = 0.0;
uniform float lids = 1.0;
uniform float blur = 0.0;
uniform float fade = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	ivec2 grid = textureSize(scene_tex, 0);
	// Расфокус: соседние ячейки сливаются в крупные пятна, пятна покачиваются.
	float block = 1.0 + floor(blur * 5.0);
	vec2 sway = vec2(sin(time * 1.3), cos(time * 0.9)) * blur * 2.0;
	vec2 src = floor((cell + sway) / block) * block + floor(block * 0.5);
	ivec2 c = clamp(ivec2(src), ivec2(0), grid - 1);
	vec4 s = texelFetch(scene_tex, c, 0);
	int code = int(s.a * 255.0 + 0.5);
	int ramp = code >> 4;
	int level = code & 15;
	vec3 col = s.rgb * (1.0 - blur * 0.35);

	// Веки: верхнее и нижнее дугой; сквозь щель видно комнату.
	vec2 p = (screen - screen_px * 0.5) / screen_px.y;
	// Открытые глаза уже не режут кадр: веки уходят за край.
	float open = lids * 0.62 + smoothstep(0.85, 1.0, lids) * 0.7;
	float upper = open * (1.0 - pow(abs(p.x) / 1.05, 2.0) * 0.55) + 0.02 * sin(p.x * 30.0 + time);
	float lower = open * 0.8 * (1.0 - pow(abs(p.x) / 1.05, 2.0) * 0.6);
	float edge = min(upper - (-p.y), lower - p.y);
	if (edge < 0.0) {
		col = vec3(0.0);
		level = 0;
	} else if (edge < 0.035 && lids < 0.98) {
		// Кромка века: тёмная бахрома ресниц, сквозь которую пробивается свет.
		ramp = 9;
		level = hash21(cell) > 0.5 ? 0 : 1;
		col *= 0.35;
	}
	col *= 1.0 - fade;

	int variant = int(hash21(cell + floor(time * (0.3 + hash21(cell) * 0.5))) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	// Штрихи (ряд 9) без плашки под знаком: иначе светлая линия становится серым квадратом.
	vec3 bg = col * (ramp == 9 ? 0.1 : 0.38) + vec3(0.006, 0.002, 0.003) * (1.0 - fade);
	COLOR = vec4(mix(bg, col * 1.2, coverage), 1.0);
}
