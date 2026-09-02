shader_type canvas_item;

// The sea the board floats on.
//
// Six sine waves and a smoothstep. It is a shader rather than a `_draw` for one
// reason: the board redraws when something changes, and water has to move when
// nothing is changing — a fight at 4x, a planning phase where the player is
// reading, an idle window. Animating this from GDScript would mean redrawing the
// whole board panel sixty times a second forever, on a phone, to move some blue.
// Here the swell costs the same whether the game is running or paused.
//
// Everything is in a board-space `field` rather than in UV, so the waves stay
// the same size when the panel changes shape — which it does on every rotation.

uniform vec4 deep_color : source_color = vec4(0.02, 0.07, 0.11, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.06, 0.20, 0.30, 1.0);
uniform vec4 foam_color : source_color = vec4(0.50, 0.89, 1.00, 1.0);
uniform vec2 field = vec2(6.0, 6.0);
uniform float speed = 0.35;
uniform float foam_strength = 0.10;

float swell(vec2 p, vec2 dir, float freq, float phase) {
	return sin(dot(p, normalize(dir)) * freq + phase);
}

void fragment() {
	vec2 p = UV * field;
	float t = TIME * speed;

	// A slow warp of the sample point before anything is measured from it. Three
	// straight sine trains sum into a regular diagonal weave that reads as
	// quilting rather than as water; bending the space they are sampled in is
	// two more sines and is the whole difference.
	p += vec2(sin(p.y * 0.9 + t * 0.6), cos(p.x * 0.7 - t * 0.5)) * 0.8;

	// Three crossing trains at unrelated speeds, so the surface never visibly
	// repeats. A single train reads as a moving stripe.
	float h = swell(p, vec2(1.0, 0.35), 3.1, t) * 0.50
		+ swell(p, vec2(-0.4, 1.0), 5.3, t * 1.37) * 0.31
		+ swell(p, vec2(0.8, -0.6), 8.7, t * 0.83) * 0.19;
	h = h * 0.5 + 0.5;

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.15, 0.95, h));

	// Foam only on the very top of a swell, which is what makes it read as a
	// crest breaking rather than as noise laid over the whole surface.
	col += foam_color.rgb * smoothstep(0.86, 0.99, h) * foam_strength;

	COLOR = vec4(col, 1.0);
}
