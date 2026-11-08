shader_type spatial;
// DUSHANBE-X terrain: splat map + slope/height rules + crop fields + rain wetness.
render_mode cull_back;

uniform sampler2D splat_map : filter_linear, repeat_disable;     // R dirt, G farmland, B urban, A gravel/sand
uniform sampler2D field_map : filter_nearest, repeat_disable;    // crop code * 30
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dry : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_paving : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rows : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 world_rect = vec4(-5000.0, -5000.0, 10000.0, 10000.0);

global uniform float wetness;
global uniform float snow_line;

varying vec3 wpos;
varying vec3 wnrm;
varying float vdist;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdist = length((VIEW_MATRIX * vec4(wpos, 1.0)).xyz);
}

vec3 tri_rock(vec3 p, vec3 n) {
	vec3 bw = pow(abs(n), vec3(3.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 a = texture(tex_rock, p.zy * 0.06).rgb;
	vec3 b = texture(tex_rock, p.xz * 0.06).rgb;
	vec3 c = texture(tex_rock, p.xy * 0.06).rgb;
	return a * bw.x + b * bw.y + c * bw.z;
}

void fragment() {
	vec2 muv = (wpos.xz - world_rect.xy) / world_rect.zw;
	vec4 sp = texture(splat_map, muv);
	float code = floor(texture(field_map, muv).r * 255.0 / 30.0 + 0.5);
	vec4 nz = texture(tex_noise, wpos.xz * 0.0017);
	vec4 nz2 = texture(tex_noise, wpos.xz * 0.011);
	float far = smoothstep(150.0, 900.0, vdist);

	vec2 uv = wpos.xz * 0.22;
	vec2 uvb = wpos.xz * 0.031;
	// two scales to hide tiling; far away only the large scale is used
	vec3 grass = mix(texture(tex_grass, uv).rgb, texture(tex_grass, uvb).rgb, 0.35 + far * 0.6);
	vec3 dry = mix(texture(tex_dry, uv * 0.9).rgb, texture(tex_dry, uvb).rgb, 0.35 + far * 0.6);
	float h = wpos.y;
	float dryness = clamp(smoothstep(0.38, 0.72, nz.r) * 0.85 + (1.0 - smoothstep(60.0, 400.0, h)) * 0.25 - smoothstep(600.0, 1200.0, h) * 0.35, 0.0, 1.0);
	vec3 col = mix(grass, dry, dryness * 0.75);
	// alpine meadows: lusher and a little bluish green
	col = mix(col, col * vec3(0.85, 1.05, 0.9), smoothstep(800.0, 1300.0, h) * 0.6);
	// slight macro colour variation
	col *= 0.86 + nz2.g * 0.28;

	// farmland
	if (sp.g > 0.02 && code > 0.5) {
		vec3 soil = texture(tex_soil, wpos.xz * vec2(0.18, 0.18)).rgb;
		vec3 rows = texture(tex_rows, wpos.xz * vec2(0.45, 0.06)).rgb;
		vec3 crop = soil;
		if (code < 1.5) {        // wheat
			crop = mix(soil, vec3(0.80, 0.67, 0.32), rows.r * 0.95);
		} else if (code < 2.5) { // cotton
			crop = mix(soil, vec3(0.33, 0.48, 0.22), rows.r);
			crop = mix(crop, vec3(0.92), step(0.86, nz2.a) * rows.r * 0.6);
		} else if (code < 3.5) { // ploughed
			crop = soil * 0.92;
		} else if (code < 4.5) { // alfalfa
			crop = mix(soil, vec3(0.24, 0.48, 0.16), 0.55 + rows.r * 0.45);
		} else if (code < 5.5) { // fallow
			crop = dry;
		} else if (code < 6.5) { // orchard ground
			crop = mix(grass, soil, 0.25);
		} else {                 // vineyard rows
			crop = mix(soil, vec3(0.30, 0.42, 0.20), rows.r * 0.5);
		}
		col = mix(col, crop, clamp(sp.g * 1.4, 0.0, 1.0));
	}
	vec3 dirt = texture(tex_dirt, wpos.xz * 0.2).rgb;
	col = mix(col, dirt, clamp(sp.r * 1.2, 0.0, 1.0));
	// city ground between buildings: courtyard lawns, trodden earth, worn concrete; tiles only in patches
	vec3 concrete = texture(tex_gravel, wpos.xz * 0.12).rgb * vec3(0.9, 0.9, 0.88);
	vec3 urban = mix(grass * 0.95, dirt * 0.95, smoothstep(0.45, 0.7, nz2.b));
	urban = mix(urban, concrete, smoothstep(0.55, 0.75, nz.a) * 0.8);
	urban = mix(urban, texture(tex_paving, wpos.xz * 0.25).rgb * 0.9, smoothstep(0.78, 0.86, nz2.a) * 0.7);
	col = mix(col, urban, clamp(sp.b * 1.3, 0.0, 1.0) * 0.85);
	vec3 gravel = texture(tex_gravel, wpos.xz * 0.25).rgb;
	col = mix(col, gravel, sp.a);

	// rock on steep slopes
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float rock_f = smoothstep(0.30, 0.48, slope + (nz2.r - 0.5) * 0.16);
	rock_f = max(rock_f, smoothstep(1650.0, 1900.0, h + nz.g * 200.0) * 0.6);
	vec3 rock = tri_rock(wpos, wnrm) * mix(vec3(1.08, 0.98, 0.86), vec3(1.0, 0.92, 0.8), nz.b);
	col = mix(col, rock, rock_f);

	// snow
	float snow_f = smoothstep(snow_line - 60.0, snow_line + 60.0, h + (nz.g - 0.5) * 300.0);
	snow_f *= 1.0 - smoothstep(0.45, 0.62, slope);
	vec3 snow = texture(tex_snow, wpos.xz * 0.1).rgb;
	col = mix(col, snow, snow_f);

	// rain wetness: darker, shinier (less on steep and snowy surfaces)
	float wet = wetness * (1.0 - snow_f) * (0.55 + 0.45 * (1.0 - slope));
	col *= mix(1.0, 0.62, wet);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.75, snow_f), 0.35, wet * (0.4 + sp.b * 0.6));
	SPECULAR = 0.35 + snow_f * 0.2;
}
