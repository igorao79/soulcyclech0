// Второй проход: разворачивает ячейки первого прохода в символы атласа.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

const int RAMP_SOLID = 7;
const int RAMP_BODY = 8;
const int RAMP_EDGE = 9;
const int RAMP_GRASS = 2;
const int RAMP_GLOW = 10;
const int RAMP_FLAKE = 11;
const int RAMP_FIGURE = 14;
const int RAMP_WATER = 3;
const int RAMP_MIRROR = 4;
const int RAMP_RIPPLE = 13;
const int RAMP_SNOW = 0;
const int RAMP_PATH = 1;

uniform sampler2D scene_tex : filter_nearest, repeat_disable;
uniform sampler2D figure_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform sampler2D grass_bend : filter_linear, repeat_enable;
uniform vec2 cell_world = vec2(0.05, 0.08);
uniform float cam_sin = 0.67;
uniform vec2 cell_px = vec2(8.0, 16.0);
uniform vec2 screen_px = vec2(1280.0, 720.0);
uniform vec2 cam_cell = vec2(0.0);
// Сдвиг сетки мира в пикселях: мир едет плавно, а не прыгает на целый символ.
uniform vec2 scroll_px = vec2(0.0);
uniform vec2 figure_origin = vec2(0.0);
uniform int hero_root_row = 0;
uniform float scramble = 0.0;
uniform float time = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


#include "res://scripts/ascii/ascii_grass.gdshaderinc"


// Частицы считаются частью фигуры, иначе вокруг снежинки на балахоне появится обводка.
float figure_at(sampler2D tex, ivec2 c) {
	int r = int(texelFetch(tex, c, 0).a * 255.0 + 0.5) >> 4;
	return r >= RAMP_FIGURE || r == RAMP_GLOW || r == RAMP_FLAKE ? 1.0 : 0.0;
}


// Фигура: плотная масса с точным контуром из ячеек, свет луны падает слева сверху.
vec3 figure_pixel(sampler2D tex, ivec2 c, ivec2 grid, vec2 sub) {
	vec4 s = texelFetch(tex, c, 0);
	int code = int(s.a * 255.0 + 0.5);
	int ramp = min(code >> 4, RAMP_FIGURE);
	int level = code & 15;
	bool fill = ramp == RAMP_FIGURE;
	float rim = -1.0;
	if (fill && c.x > 0 && c.y > 0 && c.x < grid.x - 1 && c.y < grid.y - 1) {
		float left = figure_at(tex, c + ivec2(-1, 0));
		float right = figure_at(tex, c + ivec2(1, 0));
		float up = figure_at(tex, c + ivec2(0, -1));
		float down = figure_at(tex, c + ivec2(0, 1));
		if (left + right + up + down < 3.5) {
			float gx = (right - left) * 2.0 + figure_at(tex, c + ivec2(1, -1)) + figure_at(tex, c + ivec2(1, 1))
				- figure_at(tex, c + ivec2(-1, -1)) - figure_at(tex, c + ivec2(-1, 1));
			float gy = (down - up) * 2.0 + figure_at(tex, c + ivec2(-1, 1)) + figure_at(tex, c + ivec2(1, 1))
				- figure_at(tex, c + ivec2(-1, -1)) - figure_at(tex, c + ivec2(1, -1));
			vec2 outward = -vec2(gx, gy);
			if (dot(outward, outward) > 0.5) {
				outward = normalize(outward);
				rim = clamp(dot(outward, vec2(-0.7, -0.7)) * 0.5 + 0.5, 0.0, 1.0);
				ramp = RAMP_EDGE;
				level = int(floor(fract(atan(outward.y, outward.x) / 3.14159265 + 1.0 / 8.0) * 4.0));
			}
		}
	}
	float coverage = texelFetch(atlas_tex, ivec2(level * 4, ramp) * ivec2(cell_px) + ivec2(sub), 0).r;
	vec3 glyph = s.rgb * 1.25 + vec3(0.012, 0.014, 0.022);
	if (rim >= 0.0) {
		glyph = s.rgb * (1.2 + rim) + vec3(0.66, 0.70, 0.82) * mix(0.06, 0.42, rim);
	}
	vec3 bg = s.rgb * (fill ? 0.72 : 0.3) + vec3(0.012, 0.014, 0.024);
	return mix(bg, glyph, coverage);
}


float luma_at(ivec2 c) {
	return dot(texelFetch(scene_tex, c, 0).rgb, vec3(0.3, 0.55, 0.15));
}


void fragment() {
	vec2 screen = UV * screen_px;
	vec2 px = screen + scroll_px;
	vec2 cell = floor(px / cell_px);
	ivec2 c = ivec2(cell);
	ivec2 grid = textureSize(scene_tex, 0);
	c = clamp(c, ivec2(0), grid - ivec2(1));
	vec2 sub = px - cell * cell_px;
	vec4 s = texelFetch(scene_tex, c, 0);

	int code = int(s.a * 255.0 + 0.5);
	int ramp = code >> 4;
	int level = code & 15;

	// Силуэты фигур и построек обводятся символами по направлению контура.
	if (ramp == RAMP_SOLID && c.x > 0 && c.y > 0 && c.x < grid.x - 1 && c.y < grid.y - 1) {
		float gx = luma_at(c + ivec2(1, 0)) - luma_at(c - ivec2(1, 0));
		float gy = (luma_at(c + ivec2(0, 1)) - luma_at(c - ivec2(0, 1))) * 1.5;
		if (gx * gx + gy * gy > 0.32) {
			float angle = atan(gy, gx);
			int bucket = int(floor(fract(angle / 3.14159265 + 1.0 / 8.0) * 4.0));
			ramp = RAMP_EDGE;
			level = bucket;
		}
	}

	vec3 fg = s.rgb;
	if (scramble > 0.0) {
		float noise = hash21(cell + vec2(floor(time * 24.0)));
		if (noise < scramble) {
			ramp = int(hash21(cell + 3.0) * 8.0);
			level = int(noise / max(scramble, 0.001) * 15.0);
			fg = mix(fg, vec3(0.75, 0.15, 0.22), scramble);
		}
	}

	// Четыре варианта знака на каждую яркость, выбор закреплён за точкой мира.
	vec2 world_cell = cell - floor(vec2(grid) * 0.5) + cam_cell;
	int variant = int(hash21(world_cell + vec2(17.0, 5.0)) * 4.0);
	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	if (ramp == RAMP_GRASS) {
		coverage = 0.0;
	}
	// Яркий символ на еле заметной подложке того же цвета, чтобы массы читались.
	vec3 fg_bright = fg * 1.25 + vec3(0.012, 0.014, 0.022);
	float backing = ramp == RAMP_BODY ? 0.22 : 0.08;
	vec3 under = fg;
	if (ramp == RAMP_FLAKE) {
		// Частица висит над миром: подложку берём у более тёмного соседа, а не свою.
		vec3 left = texelFetch(scene_tex, clamp(c - ivec2(1, 0), ivec2(0), grid - ivec2(1)), 0).rgb;
		vec3 right = texelFetch(scene_tex, clamp(c + ivec2(1, 0), ivec2(0), grid - ivec2(1)), 0).rgb;
		under = dot(left, vec3(1.0)) < dot(right, vec3(1.0)) ? left : right;
	} else if (ramp == RAMP_WATER || ramp == RAMP_MIRROR || ramp == RAMP_RIPPLE) {
		backing = 0.05;
	} else if (ramp == RAMP_SNOW || ramp == RAMP_PATH) {
		// Снег чуть светится сам: фигуры и ёлки ложатся на него тёмными силуэтами.
		backing = 0.07;
	}
	vec3 bg = under * backing + vec3(0.012, 0.014, 0.024);
	vec3 result = ramp == RAMP_FIGURE ? figure_pixel(scene_tex, c, grid, sub) : mix(bg, fg_bright, coverage);

	// Штрихи травы ложатся поверх мира, а частицы — поверх штрихов.
	vec4 strokes = grass_strokes(px, c, grid, -1);
	if (ramp == RAMP_FLAKE) {
		result = mix(mix(bg, strokes.rgb, strokes.a), fg_bright, coverage);
	} else {
		result = mix(result, strokes.rgb, strokes.a);
	}

	// Герой всегда поверх мира. Если его заслоняет постройка или дерево, он просвечивает.
	vec2 hero_px = screen - figure_origin;
	ivec2 hero_cell = ivec2(floor(hero_px / cell_px));
	ivec2 hero_grid = textureSize(figure_tex, 0);
	if (hero_px.x >= 0.0 && hero_px.y >= 0.0 && hero_cell.x < hero_grid.x && hero_cell.y < hero_grid.y) {
		vec4 hero = texelFetch(figure_tex, hero_cell, 0);
		if (hero.a > 0.0) {
			vec3 hero_color = figure_pixel(figure_tex, hero_cell, hero_grid, hero_px - vec2(hero_cell) * cell_px);
			if (int(hero.a * 255.0 + 0.5) >> 4 > RAMP_FIGURE) {
				result = mix(result, hero_color + vec3(0.05, 0.06, 0.08), 0.8);
			} else {
				result = hero_color;
				// Только трава перед ногами закрывает героя.
				vec4 front = grass_strokes(px, c, grid, hero_root_row);
				result = mix(result, front.rgb, front.a);
			}
		}
	}
	COLOR = vec4(result, 1.0);
}
