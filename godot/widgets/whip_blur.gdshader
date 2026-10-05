shader_type canvas_item;
// The camcorder's whip pan (widgets/garage_cam.gd): the picture smears along
// the direction the camera is swinging, strongest mid-pan.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;            // 0..1
uniform vec2 dir = vec2(1.0, 0.0);     // screen direction of the swing

void fragment() {
	vec2 uv = SCREEN_UV;
	if (amount <= 0.001) {
		COLOR = texture(screen_tex, uv);
	} else {
		vec3 col = vec3(0.0);
		float span = amount * 0.09;
		for (int i = 0; i < 12; i++) {
			float k = float(i) / 11.0 - 0.5;
			col += texture(screen_tex, uv + dir * k * span).rgb;
		}
		COLOR = vec4(col / 12.0, 1.0);
	}
}
