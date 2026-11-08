shader_type spatial;
// Grass blades: bend with wind, fade out with distance, colour varies per instance (INSTANCE_CUSTOM).
render_mode cull_disabled, diffuse_lambert_wrap;
global uniform float wind_strength;
global uniform vec3 player_pos;
uniform float fade_dist = 50.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying float hgt;
varying vec4 cust;

void vertex() {
	hgt = VERTEX.y;
	cust = INSTANCE_CUSTOM;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(w, player_pos);
	// shrink with distance so the edge of the field is invisible
	float fade = 1.0 - smoothstep(fade_dist * 0.6, fade_dist, distance(w.xz, CAMERA_POSITION_WORLD.xz));
	VERTEX.y *= fade;
	float t = TIME * (1.5 + wind_strength * 2.0);
	float n = texture(noise_tex, w.xz * 0.02 + vec2(t * 0.03, t * 0.02)).r;
	float bend = (sin(t + w.x * 0.4 + w.z * 0.3) * 0.15 + (n - 0.5) * 0.9) * (0.25 + wind_strength);
	VERTEX.x += bend * hgt * hgt * 1.2;
	VERTEX.z += bend * hgt * hgt * 0.7;
	// push away from the player
	vec2 away = w.xz - player_pos.xz;
	float push = (1.0 - smoothstep(0.0, 1.2, length(away))) * hgt;
	VERTEX.xz += normalize(away + vec2(0.001)) * push * 0.6;
	wp = w;
}

void fragment() {
	vec3 base = mix(vec3(0.16, 0.30, 0.07), vec3(0.42, 0.45, 0.16), cust.r);
	vec3 tip = mix(vec3(0.42, 0.58, 0.2), vec3(0.72, 0.68, 0.36), cust.r);
	vec3 c = mix(base, tip, clamp(hgt * 1.6, 0.0, 1.0));
	// flower heads: vertex colour alpha marks the flower part
	c = mix(c, pow(COLOR.rgb, vec3(2.2)), COLOR.a);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.4;
}
