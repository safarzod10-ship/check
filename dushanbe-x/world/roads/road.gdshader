shader_type spatial;
// Road surface. UV.x = metres from the left edge (0 .. 2*half_width), UV.y = metres along the road.
render_mode cull_back;

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool markings = true;
uniform bool dirt_road = false;
uniform bool patchy = false;
uniform float half_width = 7.0;
uniform int lanes = 2;
uniform bool double_center = false;
global uniform float wetness;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float x, float center, float w) {
	float aa = max(fwidth(x), 0.01);
	return 1.0 - smoothstep(w - aa, w + aa, abs(x - center));
}

void fragment() {
	float x = UV.x - half_width;      // signed metres from the centre line
	float v = UV.y;
	vec3 col = texture(asphalt_tex, wpos.xz * 0.25).rgb;
	vec3 colb = texture(asphalt_tex, wpos.xz * 0.037).rgb;
	col = mix(col, colb, 0.35);
	vec4 n = texture(noise_tex, wpos.xz * 0.013);
	vec4 n2 = texture(noise_tex, wpos.xz * 0.11);
	col *= 0.86 + 0.28 * n.r;
	float paint = 0.0;
	float yellow = 0.0;
	if (dirt_road) {
		// two wheel ruts and a grassy middle
		float rut = line(abs(x), 0.95, 0.35);
		col *= mix(1.0, 0.78, rut);
		col = mix(col, vec3(0.36, 0.42, 0.2), (1.0 - smoothstep(0.15, 0.45, abs(x))) * 0.6 * n2.g);
		col = mix(col, col * vec3(0.9, 0.95, 0.85), smoothstep(half_width - 0.6, half_width, abs(x)));
	}
	if (patchy) {
		col = mix(col, col * 0.72, step(0.62, n.g) * 0.8);
		col = mix(col, col * 1.18, step(0.7, n2.b) * 0.5);
	}
	if (markings) {
		float lane_w = half_width / float(lanes / 2);
		// edge lines
		paint += line(abs(x), half_width - 0.45, 0.08);
		if (lanes >= 6) {
			// painted median: two solid lines + hatching
			paint += line(abs(x), 0.6, 0.07);
			float hatch = step(0.5, fract((v + x * 1.5) / 2.5)) * (1.0 - step(0.6, abs(x)));
			paint += hatch * 0.9;
			lane_w = (half_width - 0.6) / 3.0;
			for (int k = 1; k < 3; k++) {
				paint += line(abs(x), 0.6 + lane_w * float(k), 0.065) * step(fract(v / 12.0), 0.4);
			}
		} else if (lanes >= 4 || double_center) {
			paint += line(abs(x), 0.14, 0.06);
			for (int k = 1; k < lanes / 2; k++) {
				paint += line(abs(x), lane_w * float(k), 0.065) * step(fract(v / 12.0), 0.4);
			}
		} else {
			paint += line(x, 0.0, 0.07) * step(fract(v / 9.0), 0.45);
		}
		paint = clamp(paint, 0.0, 1.0) * smoothstep(0.15, 0.45, n2.r + 0.25);
	}
	col = mix(col, vec3(0.86, 0.86, 0.82), paint * 0.9);
	// rain: darker, glossy, puddles in dips (noise)
	float puddle = smoothstep(0.62, 0.7, n.b) * wetness * (dirt_road ? 1.0 : 0.8);
	col *= mix(1.0, dirt_road ? 0.6 : 0.5, wetness);
	col = mix(col, col * 0.6, puddle);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.82, 0.25, wetness), 0.03, puddle);
	SPECULAR = mix(0.4, 0.7, wetness);
	METALLIC = 0.0;
}
