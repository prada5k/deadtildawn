shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// A dust mote: a soft round camera-facing dot (CPUParticles3D billboard). It is brightest near the light (the
// "beam" region) and only a ghost of itself far from it, so dust shows around the tubes instead of as uniform
// snow. A tiny slow wobble keeps it from drifting in a dead-straight line.

uniform vec3 light_pos = vec3(0.35, 2.3, 0.1);
uniform float reach_near = 1.2;
uniform float reach_far = 4.8;
uniform float base_alpha = 0.5;
uniform float far_alpha = 0.14;
uniform vec3 tint = vec3(0.86, 0.92, 1.0);

varying float glow;
varying float fade;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	glow = mix(far_alpha, 1.0, 1.0 - smoothstep(reach_near, reach_far, distance(center, light_pos)));
	fade = COLOR.a;
	float size = length(MODEL_MATRIX[0].xyz);
	// face the camera, keep the particle's own scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec3 wobble = vec3(sin(TIME * 0.7 + center.x * 13.0), sin(TIME * 0.9 + center.y * 7.0), 0.0) * 0.012;   // ~1 cm
	VERTEX += wobble;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float soft = 1.0 - smoothstep(0.25, 1.0, d);
	ALBEDO = tint;
	ALPHA = soft * glow * base_alpha * fade;
}
