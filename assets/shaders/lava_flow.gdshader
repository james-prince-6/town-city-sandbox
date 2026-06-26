// lava_flow.gdshader
// Animated, self-contained molten lava — domain-warped fbm noise drives glowing
// cracks between cooled crust. No textures required. Perfect for lava pools,
// fountains, rivers and the volcano caldera.
//
// Apply via res://assets/materials/LavaFlowMaterial.tres on any MeshInstance3D
// (a flat CylinderMesh/PlaneMesh works great for a lava surface).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley;

uniform vec3 hot_color : source_color = vec3(1.0, 0.85, 0.25);
uniform vec3 mid_color : source_color = vec3(0.95, 0.25, 0.03);
uniform vec3 cool_color : source_color = vec3(0.12, 0.02, 0.0);
uniform float flow_speed = 0.08;
uniform float crack_scale = 3.0;
uniform float emission_strength : hint_range(0.0, 8.0) = 3.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1, 0));
	float c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * crack_scale;
	float t = TIME * flow_speed;
	// domain warp gives that slow churning molten look
	vec2 warp = vec2(fbm(uv + t), fbm(uv - t + 5.2));
	float n = fbm(uv + warp * 1.5);
	float cracks = pow(n, 2.2);

	vec3 col = mix(cool_color, mid_color, smoothstep(0.20, 0.60, cracks));
	col = mix(col, hot_color, smoothstep(0.60, 0.95, cracks));

	ALBEDO = col;
	ROUGHNESS = 0.85;
	float glow = smoothstep(0.45, 1.0, cracks);
	EMISSION = col * glow * emission_strength;
}
