shader_type spatial;
// Triplanar world-space texture tinted by vertex colour. Used for stone, concrete, paving, bark...
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.25;
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform float tex_amount = 1.0;
uniform float wet_reflect = 0.6;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 tx = texture(albedo_tex, wpos.zy * scale).rgb;
	vec3 ty = texture(albedo_tex, wpos.xz * scale).rgb;
	vec3 tz = texture(albedo_tex, wpos.xy * scale).rgb;
	vec3 t = tx * bw.x + ty * bw.y + tz * bw.z;
	vec3 base = mix(vec3(0.75), t, tex_amount) * pow(COLOR.rgb, vec3(2.2)) * 1.25;
	float up = clamp(wnrm.y, 0.0, 1.0);
	float wet = wetness * mix(0.35, 1.0, up);
	ALBEDO = base * mix(1.0, 0.68, wet);
	ROUGHNESS = mix(rough, 0.18, wet * wet_reflect);
	METALLIC = metal;
}
