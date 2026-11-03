// Рамка меню паузы на весь экран: арка из двух зимних деревьев, гравюра пересобрана из знаков
// атласа, как главный экран. Ветви и корни плотными знаками, контуры знаками по направлению,
// середина пустая и прозрачная: под ней притушенный мир и меню. Падает снег, звёзды мерцают,
// при открытии рамка проступает из шума от краёв к середине.
shader_type canvas_item;

// Ряды атласа, см. RAMPS в ascii_font_atlas.gd.
const int RAMP_SNOW = 0;
const int RAMP_DENSE = 5;
const int RAMP_EDGE = 9;
const int RAMP_FLAKE = 11;

uniform sampler2D atlas_tex : filter_nearest, repeat_disable;
uniform sampler2D art_tex : filter_linear, repeat_disable;
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform float art_aspect = 1.5;
uniform float time = 0.0;
// 0 — рамки нет, 1 — проступила целиком.
uniform float reveal = 1.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


// Картинка заполняет экран. Если пропорции экрана другие, гравюра немного сжимается,
// а остаток обрезается — больше снизу, чтобы луна и колокол наверху остались целыми.
vec2 art_uv(vec2 px, vec2 screen_px) {
	float aspect = mix(art_aspect, screen_px.x / screen_px.y, 0.5);
	float height = max(screen_px.x / aspect, screen_px.y);
	vec2 size = vec2(height * aspect, height);
	vec2 overflow = screen_px - size;
	return (px - vec2(overflow.x * 0.5, overflow.y * 0.3)) / size;
}


float art_luma(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(art_tex, uv).r;
}


float cell_luma(vec2 cell, vec2 screen_px) {
	float sum = 0.0;
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 px = (cell + (vec2(float(x), float(y)) + 0.5) / 3.0) * cell_px;
			sum += art_luma(art_uv(px, screen_px));
		}
	}
	return sum / 9.0;
}


float centre_luma(vec2 cell, vec2 screen_px) {
	return art_luma(art_uv((cell + 0.5) * cell_px, screen_px));
}


void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 screen = UV * screen_px;
	vec2 cell = floor(screen / cell_px);
	vec2 sub = screen - cell * cell_px;
	vec2 center = (cell + 0.5) * cell_px;
	vec2 p = (center - screen_px * 0.5) / screen_px.y;
	float grain = hash21(cell);

	float lum = cell_luma(cell, screen_px);
	vec2 uv = art_uv(center, screen_px);
	// Гравюра светлая на чёрном: в знаках её линии чуть вытягиваем, чтобы тонкие ветки не пропали.
	float ink = pow(clamp((lum - 0.04) * 1.7, 0.0, 1.0), 0.8);

	int ramp = RAMP_DENSE;
	int level = int(clamp(ink * 15.0 + (grain - 0.5) * 1.5, 0.0, 15.0));
	// Холодное серебро: тени ветвей сиреневые, снег на них почти белый.
	vec3 col = mix(vec3(0.46, 0.48, 0.76), vec3(0.92, 0.95, 1.0), smoothstep(0.15, 0.85, ink)) * (0.65 + ink * 0.8);
	float backing = 0.22;
	float alpha = smoothstep(0.05, 0.1, lum);

	if (lum < 0.1 && lum >= 0.05) {
		// Тонкие веточки и дымка: редкие лёгкие знаки.
		ramp = RAMP_SNOW;
		level = int(clamp((lum - 0.05) * 160.0 + 2.0 + (grain - 0.5) * 3.0, 0.0, 9.0));
	}

	// Контуры стволов и ветвей: знак по направлению края.
	float gx = centre_luma(cell + vec2(1.0, 0.0), screen_px) - centre_luma(cell - vec2(1.0, 0.0), screen_px);
	float gy = (centre_luma(cell + vec2(0.0, 1.0), screen_px) - centre_luma(cell - vec2(0.0, 1.0), screen_px)) * 1.4;
	if (gx * gx + gy * gy > 0.05 && lum > 0.12 && lum < 0.75) {
		ramp = RAMP_EDGE;
		level = int(floor(fract(atan(gy, gx) / PI + 1.0 / 8.0) * 4.0));
		col *= 1.15;
	}

	// Звёзды и снежинки картинки — яркие одиночные точки — подмигивают каждая в своём ритме.
	float around = max(
		max(centre_luma(cell + vec2(1.0, 0.0), screen_px), centre_luma(cell - vec2(1.0, 0.0), screen_px)),
		max(centre_luma(cell + vec2(0.0, 1.0), screen_px), centre_luma(cell - vec2(0.0, 1.0), screen_px))
	);
	if (lum > 0.25 && around < lum * 0.55) {
		col *= 0.7 + 0.5 * sin(time * (1.3 + grain * 3.0) + grain * 40.0);
	}

	// Луна дышит и чуть теплее остального.
	vec2 moon = vec2(0.5, 0.12);
	float near_moon = 1.0 - smoothstep(0.02, 0.07, length((uv - moon) * vec2(1.5, 1.0)));
	col = mix(col, vec3(1.0, 0.92, 0.78) * (0.95 + 0.12 * sin(time * 0.8)), near_moon * smoothstep(0.3, 0.6, ink));

	// Знаки медленно перебирают свои варианты: рамка живёт, не меняя рисунка.
	int variant = int(hash21(cell + floor(time * (0.25 + grain * 0.5) + grain * 9.0)) * 4.0);

	// Падающий снег по всему экрану, редкий и тихий, в середине бледнее.
	bool flake = false;
	vec3 flake_col = vec3(0.0);
	int flake_level = 0;
	for (int i = 2; i >= 0; i--) {
		float layer = float(i);
		vec2 tile = vec2(9.0 + layer * 3.0, 7.0 + layer * 2.0);
		float gust = sin(time * 0.35 + layer) * 3.0;
		vec2 v = cell + vec2(floor(time * (1.0 + layer) + gust), -floor(time * (2.0 + layer * 3.0)));
		vec2 id = floor(v / tile);
		vec2 spot = floor(vec2(hash21(id + layer), hash21(id + layer + 11.0)) * tile);
		if (mod(v, tile) == spot && hash21(id + layer + 23.0) > 0.45) {
			flake = true;
			flake_level = i == 2 ? 6 : (i == 1 ? 5 : 0);
			float centre_fade = mix(0.45, 1.0, smoothstep(0.25, 0.7, length(p * vec2(0.75, 1.0))));
			flake_col = vec3(0.80, 0.85, 0.98) * mix(0.35, 0.9, layer / 2.0) * centre_fade;
			break;
		}
	}

	// Проявление: фронт идёт от краёв экрана к середине, на фронте знаки мечутся.
	float r = 1.0 - length(p * vec2(0.62, 1.0)) / 0.95;
	float front = reveal * 1.15 - 0.1;
	bool hidden = r > front;
	bool on_front = !hidden && r > front - 0.08 && reveal < 1.0;

	if (flake && alpha < 0.5) {
		ramp = RAMP_FLAKE;
		level = flake_level;
		col = flake_col;
		alpha = 1.0;
		backing = 0.0;
	}
	if (on_front && alpha > 0.0) {
		ramp = RAMP_DENSE;
		level = 4 + int(hash21(cell + floor(time * 20.0)) * 11.0);
		col = vec3(0.55, 0.50, 0.85);
	}
	if (hidden) {
		alpha = 0.0;
	}

	ivec2 atlas_px = ivec2(level * 4 + variant, ramp) * ivec2(cell_px) + ivec2(sub);
	float coverage = texelFetch(atlas_tex, atlas_px, 0).r;
	if (backing <= 0.0) {
		// Снежинка в пустой середине: только сам знак, без подложки.
		COLOR = vec4(col, coverage * alpha);
	} else {
		vec3 bg = col * backing * ink + vec3(0.004, 0.004, 0.012);
		COLOR = vec4(mix(bg, col * 1.1, coverage), alpha);
	}
}
