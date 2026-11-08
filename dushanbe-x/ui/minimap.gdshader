shader_type canvas_item;
// Circular, rotating minimap. The map texture covers the whole 10x10 km world.
uniform sampler2D map_tex : filter_linear, repeat_disable;
uniform vec2 center_uv = vec2(0.5);     // player position in map uv
uniform vec2 fwd = vec2(0.0, -1.0);     // camera forward (world x,z), screen up
uniform float radius_uv = 0.03;         // map uv covered by the minimap radius
uniform vec4 rim_color : source_color = vec4(0.97, 0.76, 0.0, 1.0);

void fragment() {
	vec2 d = UV * 2.0 - 1.0;            // -1..1, y down
	float r = length(d);
	if (r > 1.0) {
		discard;
	}
	vec2 right = vec2(-fwd.y, fwd.x);
	vec2 w = right * d.x + fwd * (-d.y);
	vec2 uv = center_uv + w * radius_uv;
	vec3 c = texture(map_tex, uv).rgb;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c = vec3(0.12, 0.14, 0.18);
	}
	c *= 0.85 + 0.15 * (1.0 - r);
	float rim = smoothstep(0.93, 0.96, r);
	COLOR = vec4(mix(c, rim_color.rgb, rim), 1.0);
}
