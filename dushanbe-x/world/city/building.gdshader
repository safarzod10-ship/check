shader_type spatial;
// Procedural facades. UV = metres on the wall (u along, v down from the top edge of the wall quad).
// UV2.x = facade style + seed (fraction), UV2.y = wall height. Vertex colour = wall colour (sRGB).
render_mode cull_back;

global uniform float night_factor;
global uniform float wetness;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float style = floor(UV2.x + 0.001);
	float seed = fract(UV2.x);
	float H = UV2.y;
	float u = UV.x;
	float yu = H - UV.y;                       // metres above the bottom of this wall
	vec3 wall = pow(COLOR.rgb, vec3(2.2));
	float sx = 3.2;
	float fh = 3.0;
	vec2 win = vec2(0.22, 0.78);                // horizontal extent inside the cell
	vec2 winy = vec2(0.32, 0.82);               // vertical extent inside the cell
	float ground_shop = 0.0;
	if (style < 0.5) { sx = 3.0; fh = 2.8; }
	else if (style < 1.5) { sx = 3.2; fh = 2.8; win = vec2(0.18, 0.82); }
	else if (style < 2.5) { sx = 1.6; fh = 3.4; win = vec2(0.04, 0.96); winy = vec2(0.06, 0.94); ground_shop = 1.0; }
	else if (style < 3.5) { sx = 3.6; fh = 3.8; win = vec2(0.28, 0.72); winy = vec2(0.25, 0.85); }
	else if (style < 4.5) { sx = 3.4; fh = 3.6; ground_shop = 1.0; }
	else if (style < 5.5) { sx = 3.8; fh = 3.0; win = vec2(0.3, 0.7); winy = vec2(0.3, 0.8); }
	else if (style < 6.5) { sx = 3.4; fh = 3.6; win = vec2(0.12, 0.88); winy = vec2(0.25, 0.85); }
	else { sx = 4.2; fh = 2.9; win = vec2(0.36, 0.64); winy = vec2(0.35, 0.78); }

	vec2 cell = vec2(u / sx, yu / fh);
	vec2 id = floor(cell);
	vec2 lc = fract(cell);
	float aa = 0.04;
	float wx = smoothstep(win.x - aa, win.x, lc.x) * (1.0 - smoothstep(win.y, win.y + aa, lc.x));
	float wy = smoothstep(winy.x - aa, winy.x, lc.y) * (1.0 - smoothstep(winy.y, winy.y + aa, lc.y));
	float is_win = wx * wy;
	// no windows in the plinth and at the very top
	is_win *= step(0.75, yu) * step(yu, H - 0.4);
	// shops: large shopfront glass on the ground floor
	float shop = ground_shop * step(yu, fh) * step(0.3, yu);
	if (shop > 0.5) {
		float sfx = fract(u / 6.0);
		is_win = smoothstep(0.03, 0.06, sfx) * (1.0 - smoothstep(0.94, 0.97, sfx)) * step(0.35, yu) * step(yu, fh - 0.5);
	}
	vec4 nz = texture(noise_tex, vec2(u, yu) * 0.05 + seed * 7.0);
	// wall detailing: panel joints / brick courses / plaster stains
	if (style < 0.5 && seed < 0.45) {
		float course = step(0.88, fract(yu / 0.25)) + step(0.94, fract(u / 0.5 + floor(yu / 0.25) * 0.5)) ;
		wall *= 1.0 - clamp(course, 0.0, 1.0) * 0.12;
	} else if (style < 1.5) {
		float joint = step(0.985, fract(u / 3.2)) + step(0.975, fract(yu / 2.8));
		wall *= 1.0 - clamp(joint, 0.0, 1.0) * 0.25;
	}
	wall *= 0.9 + nz.r * 0.2;
	wall *= mix(0.8, 1.0, smoothstep(0.0, 0.8, yu));          // darker plinth
	wall *= 1.0 - (1.0 - smoothstep(0.0, 3.0, H - yu)) * nz.g * 0.15;  // roof-edge dirt streaks

	// window appearance
	float h1 = hash(id + seed * 31.0);
	float h2 = hash(id * 1.7 + seed * 13.0);
	vec3 glass = mix(vec3(0.06, 0.08, 0.1), vec3(0.18, 0.26, 0.32), h1 * 0.6);
	if (style > 1.5 && style < 2.5) {
		glass = mix(vec3(0.08, 0.18, 0.26), vec3(0.1, 0.3, 0.3), seed);
	}
	vec3 curtain = mix(vec3(0.55, 0.45, 0.3), vec3(0.75, 0.7, 0.6), h2);
	glass = mix(glass, curtain * 0.35, step(0.7, h2) * 0.6);
	// frame
	float frame = (1.0 - is_win) * wx * wy;
	vec3 col = mix(wall, glass, is_win);
	col = mix(col, vec3(0.85), frame * 0.4 * step(0.5, 1.0 - ground_shop));
	// night: some windows are lit
	float lit = step(1.0 - (0.35 + 0.25 * seed), h1) * is_win;
	lit = max(lit, shop * is_win * 0.9);
	vec3 lamp_col = mix(vec3(1.0, 0.72, 0.4), vec3(0.85, 0.9, 1.0), step(0.75, h2));
	EMISSION = lamp_col * lit * night_factor * 2.2;
	float wet = wetness * 0.5;
	ALBEDO = col * mix(1.0, 0.8, wet);
	ROUGHNESS = mix(mix(0.9, 0.12, is_win), 0.3, wet * (1.0 - is_win));
	METALLIC = is_win * 0.35;
	SPECULAR = mix(0.4, 0.8, is_win);
}
