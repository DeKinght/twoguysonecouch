shader_type spatial;
// Woda w porcie: dwie przesuwające się mapy normalnych (fale) + odbicie nieba zależne od kąta.
// Tanie: dwie próbki tekstury na piksel, bez odbić ekranowych.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.11, 0.27, 0.34, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.2, 0.42, 0.47, 1.0);
uniform sampler2D waves_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D waves_b : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 na = texture(waves_a, uv * 0.025 + TIME * vec2(0.012, 0.007)).rgb;
	vec3 nb = texture(waves_b, uv * 0.06 - TIME * vec2(0.009, 0.015)).rgb;
	NORMAL_MAP = mix(na, nb, 0.5);
	NORMAL_MAP_DEPTH = 0.6;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(shallow_color.rgb, deep_color.rgb, facing);
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
