shader_type sky;
// The 3 a.m. sky over the replay's chase view (widgets/chase3d.gd): a deep
// blue dome fading to a faint glow at the horizon, a field of stars (fewer
// near the horizon, where the haze is), and the moon with a soft halo.

uniform vec3 top_color : source_color = vec3(0.008, 0.012, 0.04);
uniform vec3 horizon_color : source_color = vec3(0.075, 0.06, 0.12);
uniform vec3 moon_dir = vec3(-0.8, 0.3, -0.35);
uniform vec3 moon_color : source_color = vec3(0.85, 0.88, 1.0);
uniform float star_cells = 300.0;     // stars per radian, roughly: smaller cells = smaller stars

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(up, 0.4));
	if (d.y < 0.0) {
		col = horizon_color * 0.35;          // below the horizon: the dark land beyond the fog
	}
	vec3 cell = floor(d * star_cells);
	float star = step(0.9972, hash(cell)) * smoothstep(0.03, 0.3, d.y);
	col += vec3(star) * (0.35 + 0.65 * hash(cell + 7.0));
	float m = dot(d, normalize(moon_dir));
	col += moon_color * smoothstep(0.99935, 0.99965, m) * 1.8;     // the disc
	col += moon_color * pow(max(m, 0.0), 240.0) * 0.22;           // its halo
	COLOR = col;
}
