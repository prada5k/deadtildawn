shader_type canvas_item;
// Speed blur on a chase pane (main.gd sets it from chase3d.gd every frame):
// the picture streaks outward from where the camera car is heading (the
// focus of expansion), more toward the edges, nothing in the middle where
// the car is. amount 0 = off; it grows with the camera car's speed.

uniform float amount = 0.0;               // 0..1
uniform vec2 focus = vec2(0.5, 0.45);     // where the camera's heading, in the pane (0..1)
uniform float reach = 0.07;               // how far the longest streak samples (of the pane)
uniform float clear = 0.16;               // no blur this close to the focus

void fragment() {
	vec2 d = UV - focus;
	float edge = smoothstep(clear, clear + 0.4, length(d * vec2(1.0, 0.65)));
	float k = amount * edge * reach;
	vec4 col = vec4(0.0);
	for (int i = 0; i < 8; i++) {
		col += texture(TEXTURE, UV - d * k * float(i) / 7.0);
	}
	COLOR = col / 8.0;
}
