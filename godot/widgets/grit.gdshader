shader_type canvas_item;
// Full-screen grit: animated film grain + a dark vignette, so every screen
// looks shot on a worn 2000s camcorder instead of rendered by a web page.
// Sits on a top CanvasLayer (game.gd); keep the amounts low.

uniform float grain = 0.025;        // grain strength
uniform float vignette = 0.35;     // corner darkening
uniform float fps = 10.0;          // grain changes this many times a second (film-like)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float frame = floor(TIME * fps);
	float n = hash(floor(FRAGCOORD.xy / 2.0) + frame * 17.0) - 0.5;   // 2 px grain
	vec2 d = UV - 0.5;
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.8)));
	// Mix toward black for the vignette, toward white/black for grain
	float dark = v * vignette;
	COLOR = vec4(vec3(n > 0.0 ? 1.0 : 0.0), abs(n) * grain * 2.0);
	COLOR = mix(COLOR, vec4(0.0, 0.0, 0.0, 1.0), dark);
}
