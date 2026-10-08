shader_type canvas_item;
// Camcorder footage grit as a plain overlay (it never reads the screen, so it is cheap and keeps text
// readable): faint scanlines, film-grain flicker and a soft vignette. Used on HOME's viewfinder and the
// replay's chase view. All strengths are alpha amounts, keep them small.

uniform float scan_strength : hint_range(0.0, 0.3) = 0.09;
uniform float scan_pitch_px = 3.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.07;
uniform float grain_fps = 12.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.3;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 px = floor(FRAGCOORD.xy);
	float scan = scan_strength * (0.5 - 0.5 * cos(6.2831853 * px.y / scan_pitch_px));
	float frame = floor(TIME * grain_fps);
	float g = hash(floor(px / 2.0) + frame * vec2(17.3, 7.1)) - 0.5;
	vec2 c = (UV - 0.5) * vec2(1.0, 1.1);
	float vig = smoothstep(0.35, 0.95, length(c)) * vignette;
	float dark = clamp(scan + vig + max(-g, 0.0) * grain_strength * 2.0, 0.0, 1.0);
	float light = clamp(max(g, 0.0) * grain_strength * 1.4, 0.0, 1.0);
	COLOR = vec4(vec3(light / (light + dark + 0.0001)), clamp(dark + light, 0.0, 0.6));
}
