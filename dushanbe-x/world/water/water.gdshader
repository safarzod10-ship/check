shader_type spatial;
// Rivers, creeks, canals, lakes and waterfalls.
// Ribbons: UV.y = metres along the flow, UV2.x = 0..1 across (edges = shore). Lakes: UV2.x = 1 at the centre, 0 at shore.
render_mode cull_disabled, specular_schlick_ggx, depth_draw_opaque;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float flow_speed = 1.4;
uniform float foam = 0.0;
uniform bool is_lake = false;
uniform vec3 deep_col : source_color = vec3(0.10, 0.30, 0.33);
uniform vec3 shallow_col : source_color = vec3(0.32, 0.52, 0.48);
global uniform float wetness;
global uniform float night_factor;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (is_lake) {
		VERTEX.y += sin(wpos.x * 0.3 + TIME * 1.1) * 0.03 + sin(wpos.z * 0.23 + TIME * 0.8) * 0.03;
	}
}

void fragment() {
	float centre;
	vec2 uv1;
	vec2 uv2;
	if (is_lake) {
		centre = UV2.x;
		uv1 = wpos.xz * 0.045 + vec2(TIME * 0.012, TIME * 0.007);
		uv2 = wpos.xz * 0.11 - vec2(TIME * 0.009, -TIME * 0.015);
	} else {
		centre = 1.0 - abs(UV2.x * 2.0 - 1.0);
		uv1 = vec2(UV.x * 0.12, UV.y * 0.05 - TIME * flow_speed * 0.05);
		uv2 = vec2(UV.x * 0.27 + 0.3, UV.y * 0.11 - TIME * flow_speed * 0.13);
	}
	vec3 n1 = texture(normal_tex, uv1).rgb;
	vec3 n2 = texture(normal_tex, uv2).rgb;
	vec3 n = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0);
	// rain ripples
	vec3 n3 = texture(normal_tex, wpos.xz * 0.6 + vec2(TIME * 0.3, 0.0)).rgb * 2.0 - 1.0;
	n = normalize(n + n3 * wetness * 0.6);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = is_lake ? 0.5 : 0.9 + foam;
	float depthf = smoothstep(0.0, 0.6, centre);
	vec3 col = mix(shallow_col, deep_col, depthf);
	// foam at the banks and on rapids/waterfalls
	float fn = texture(normal_tex, uv2 * 1.7).r;
	float fm = (1.0 - smoothstep(0.0, 0.12, centre)) * 0.6 + foam * smoothstep(0.35, 0.65, fn + foam * 0.3);
	col = mix(col, vec3(0.9, 0.94, 0.95), clamp(fm, 0.0, 1.0));
	col *= mix(1.0, 0.35, night_factor);
	ALBEDO = col;
	ALPHA = clamp(mix(0.55, 0.92, depthf) + fm * 0.4, 0.0, 1.0);
	ROUGHNESS = mix(0.03, 0.4, clamp(fm, 0.0, 1.0));
	METALLIC = 0.05;
	SPECULAR = 0.65;
}
