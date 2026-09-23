shader_type canvas_item;

// Menu backdrop: two drifting aurora ribbons over a very dark base, a faint
// grid and a strong vignette. Everything procedural - no textures.

uniform float speed : hint_range(0.0, 2.0) = 0.2;
uniform float grid_scale = 46.0;
uniform vec4 deep_color : source_color = vec4(0.014, 0.026, 0.045, 1.0);
uniform vec4 teal_color : source_color = vec4(0.06, 0.55, 0.62, 1.0);
uniform vec4 pink_color : source_color = vec4(0.42, 0.16, 0.38, 1.0);
uniform vec4 amber_color : source_color = vec4(0.62, 0.46, 0.16, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;

	float n1 = fbm(uv * vec2(2.0, 1.1) + vec2(t * 0.30, -t * 0.08));
	float n2 = fbm(uv * vec2(1.4, 2.3) - vec2(t * 0.16, t * 0.20));
	float n3 = fbm(uv * vec2(3.2, 1.8) + vec2(-t * 0.22, t * 0.12));
	float ribbon1 = smoothstep(0.46, 0.72, n1) * (1.0 - smoothstep(0.72, 0.96, n1));
	float ribbon2 = smoothstep(0.54, 0.80, n2) * (1.0 - smoothstep(0.80, 1.02, n2));
	float sparkle = smoothstep(0.80, 0.94, n3);

	vec3 col = deep_color.rgb * 0.85;
	col += teal_color.rgb * ribbon1 * 0.34;
	col += pink_color.rgb * ribbon2 * 0.20;
	col += amber_color.rgb * sparkle * 0.10;
	col += teal_color.rgb * smoothstep(0.85, 0.05, abs(uv.y - 0.60)) * 0.045;

	vec2 g = fract(uv * vec2(1152.0, 648.0) / grid_scale);
	float line = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y));
	col += vec3(0.09, 0.17, 0.19) * (1.0 - smoothstep(0.0, 0.05, line)) * 0.4;

	vec2 c = uv - vec2(0.5, 0.52);
	col *= mix(0.32, 1.0, smoothstep(1.0, 0.30, length(c * vec2(1.05, 1.35))));

	COLOR = vec4(col, 1.0);
}
