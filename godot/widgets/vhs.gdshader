shader_type canvas_item;
// The replay as a 2000s touge tape (Best Motoring / Option video): scanlines,
// a little red/blue bleed, a soft tracking band rolling down the frame, and a
// warm tape cast. Subtle on purpose: the race must stay readable.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float bleed = 1.2;          // px of red/blue offset
uniform float scanline = 0.07;      // darkening on every other line
uniform float band = 0.05;          // tracking band strength

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	// tracking band: a soft stripe drifting down, nudging pixels sideways
	float y = fract(TIME * 0.07);
	float in_band = smoothstep(0.035, 0.0, abs(uv.y - y));
	uv.x += in_band * band * 0.01 * sin(uv.y * 900.0 + TIME * 40.0);
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(bleed * px.x, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(bleed * px.x, 0.0)).b;
	col += in_band * band;
	float line = mod(floor(FRAGCOORD.y), 2.0);
	col *= 1.0 - scanline * line;
	col *= vec3(1.03, 1.0, 0.95);   // warm tape cast
	COLOR = vec4(col, 1.0);
}
