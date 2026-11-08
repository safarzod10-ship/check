shader_type spatial;
// Fountain / pool water used by landmarks: animated ripples, glossy, slightly transparent.
render_mode cull_disabled, depth_draw_opaque;

uniform vec3 deep : source_color = vec3(0.10, 0.32, 0.40);

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r1 = sin(wp.x * 2.3 + TIME * 2.1) * cos(wp.z * 1.9 - TIME * 1.7);
	float r2 = sin((wp.x + wp.z) * 3.7 - TIME * 3.0);
	vec3 n = normalize(vec3(r1 * 0.08 + r2 * 0.04, 1.0, r2 * 0.06 - r1 * 0.03));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(deep, COLOR.rgb, 0.45);
	ROUGHNESS = 0.04;
	METALLIC = 0.1;
	SPECULAR = 0.9;
	ALPHA = 0.88;
}
