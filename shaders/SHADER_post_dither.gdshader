shader_type canvas_item;

// Fullscreen post: chunky pixelation + 4x4 Bayer ordered-dither + palette
// LUT lookup. Each pixel snaps the sampled (and dither-offset) screen color
// to the nearest entry in a baked palette LUT.
//
// LUT format: tiled-horizontally. For LUT_LEVELS = N, the texture is
// (N*N) x N. Cell (r, g, b) in [0, N) lives at pixel (b*N + r, g) and stores
// the nearest palette color to that quantized RGB triple. Bake with
// tools/TOOL_build_palette_lut.py.

// CHUNK WIDTH IN GAME PIXELS. 1 is the shipped default, on every device: one game
// pixel (a pixel of the 1080-line frame the 3D is drawn at, `design_height`) is
// one chunk, so this pass quantises colour to the palette and dithers per game
// pixel and merges nothing. The settings menu's Pixel Density dials it up for a
// chunkier look. (The game pixel was a 720-line one until the user: "can we make
// the target res 1080p, pixel size 1, for everything? treat 1080 as 100% now".)
//
// IT WAS 2 for a while, resolving 640 x 360 (2 x 2 game pixels a chunk), to make
// the pixel a fixed object on any screen; before that it was 1, and it is 1 again
// at the user's request. The palette LUT, the nearest-filtered textures and the
// crunched art (`SCRIPT_crunch_art.gd`) carry the PlayStation look at 1; on the
// desktop the world is drawn at exactly 1080 rows anyway (`AUTOLOAD_display.gd`),
// so a game pixel is a fixed object there whatever this is.
//
// WHAT IT DOES NOT TOUCH, measured by `tests/RENDER_dither_pixel_size.gd` on a
// paused frame with only this uniform moved: the HUD and the menu panels. They
// are drawn on layers ABOVE this pass, and the numbers say so — going 1 -> 2
// changes 21.6% of a flight frame and 41.6% of the menu, but only 0.6% of the
// HUD's top-left readout box. The ring gauges DO go through it (29.1%), so the
// split is per-element rather than "all UI is safe"; the 3D frame and the
// in-world target markers take the full change. Do not reach for this uniform
// expecting it to make text chunkier — most of the text is not behind it.
//
// The DITHER MATRIX IS INDEXED PER CHUNK, not per pixel (see `cell` below), so
// raising this coarsens the Bayer pattern with the pixels rather than leaving a
// fine dither crawling underneath a coarse grid. That is the reason this is one
// uniform and not two.
uniform int pixel_size : hint_range(1, 16) = 2;
// Chunk height / width ratio. 1.0 => square chunks (the shipped default);
// 2.0 => pixels twice as tall as wide. Selectable at runtime; never 0 (a 0
// chunk size collapses the pixelation and divides by zero below).
uniform float pixel_aspect : hint_range(0.25, 4.0) = 1.0;
// LEVELS PER CHANNEL IN THE LUT'S GRID, and it MUST equal what the bake used or
// every lookup addresses the wrong cell — a frame that stays plausible with every
// colour in it wrong. `TOOL_build_palette_lut.py` bakes at 16.
//
// IT IS NOT THE NUMBER OF COLOURS IN THE PALETTE, which two dozen comments across
// this project say it is. 16 here means a 16x16x16 quantisation grid — 4096 cells,
// stored as the 256x16 image. `palette/PALETTE_ps1-soft.hex` holds FIVE HUNDRED AND TWELVE
// colours, of which this bake can reach 389; the other 123 lose their cells to a
// nearer neighbour, because the grid is coarser than the palette in places.
// Measured by `tests/TEST_palette_lock.gd`, which asserts both numbers.
//
// The qualitative argument every one of those comments is making survives intact —
// this is a quantiser, so a colour landing between two entries jumps to the nearer
// one instead of blending, which is why surfaces in this project are graded onto
// entries rather than tuned by eye. Only the count was wrong, by a factor of 32.
uniform int lut_levels : hint_range(2, 32) = 16;
// The frame height the chunk is measured in: the 3D's, `RenderQuality.DESIGN_HEIGHT`.
// See `design_k` in `fragment`.
uniform float design_height = 1080.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

// THE DESKTOP FRAME (`AUTOLOAD_display.gd`): x the screen pixels a game pixel
// is drawn as (1.5 on a 1080p panel), y and z the frame's top-left on the screen,
// w 1 while it is in use. Then a chunk is `pixel_size` GAME pixels on the frame's
// own grid, so the pass lines up with the pixels the frame draws; and at 1 the
// pass does not re-chunk at all (that would undo the frame's sharp scaling, every
// seam snapped to one side or the other): it reads every screen pixel and only
// the dither cell follows the game pixels.
global uniform vec4 display_frame;

// THE CRT (the user: "insane idea, and make it togglable, CRT effects for
// overworld and battle (does not effect ui)", then "make the CRT effect only
// affect the overworld, not battle": the fight is an LCD, takes none of this,
// and has a glow and a fringe of its own behind its cells, `LCD_PHOSPHOR` and
// `LCD_ABERRATION`). `crt_amount` is 1 while it is on, a global, so every
// scene's pass takes it at once
// (`RenderQuality.set_crt`, the Settings row CRT). It is in THIS pass because
// this pass is what the world is drawn through and the HUD is drawn over: the
// UI is never under it.
//
// EVERYTHING HERE IS SLIGHT ("all these CRT effects need to be very subtle, but
// also actually there"): each constant below is one effect's strength, and each
// is small.
//
// THE TUBE:
//   the glass      the picture itself bowed, a little (`CRT_CURVE`): the middle of
//                  each edge pushed out to the screen's edge and the corners left
//                  where they are, so the bow starts OUTSIDE the screen and none
//                  of the screen is lost to a border ("start the curvature
//                  outside the screen so no screen area is lost", and "curvature
//                  needs to subtly distort the image as well, not just a CRT
//                  border mask"). No mask at the corners at all.
//   the scanlines  a dark line between rows of the picture's own chunks, so the
//                  lines and the pixels never beat against each other;
//   the mask       RGB sub-pixels: red, green and blue stripes down the panel;
//   the falloff    a touch darker toward the corners.
//
// THE SIGNAL, as a console sends it down the aerial lead on channel 3, not over
// RCA or RGB ("the kinds of artifacts you would get from having a legacy game
// console transmitting over channel 3"):
//   chroma bleed   colour has a fraction of the bandwidth brightness has, so it
//                  smears sideways while the edges stay where they are;
//   dot crawl      the colour carrier beating on a sharp edge: a faint moving
//                  rainbow along vertical edges;
//   the ghost      a faint echo of the picture a little to the right;
//   the snow       a little noise, new every frame;
//   the hum        a slow, faint bar of brightness rolling up the picture;
//   the jitter     each line a fraction of a pixel off, never the same twice.
// And the phosphor ("phosphor bleed"): bright things spill a little light
// sideways. And the lens of the glass ("some chromatic abberation"): red and blue
// pulled apart, more toward the sides.
global uniform float crt_amount;
// EVERY STRENGTH IS A SLIDER (the user: "give me all CRT settings as separate
// sliders so i can tweak the look"): Settings, CRT Tuning
// (`SCRIPT_crt_tuner.gd`). They are four global vec4s, set and kept by
// `RenderQuality` (`CRT_PARAMS`: each one's name, range and default), and read
// here by the names they have always had.
global uniform vec4 crt_tune_a;
global uniform vec4 crt_tune_b;
global uniform vec4 crt_tune_c;
global uniform vec4 crt_tune_d;
global uniform vec4 crt_tune_e;
global uniform vec4 crt_tune_f;
#define CRT_CURVE crt_tune_a.x
#define CRT_SCAN crt_tune_a.y
#define CRT_SCAN_SIZE crt_tune_a.z
#define CRT_MASK crt_tune_a.w
#define CRT_MASK_SIZE crt_tune_b.x
#define CRT_VIGNETTE crt_tune_b.y
#define CRT_GAIN crt_tune_b.z
#define CRT_BLEED crt_tune_b.w
#define CRT_BLEED_WIDTH crt_tune_c.x
#define CRT_CRAWL crt_tune_c.y
#define CRT_CRAWL_SPEED crt_tune_c.z
#define CRT_GHOST crt_tune_c.w
#define CRT_GHOST_OFFSET crt_tune_d.x
#define CRT_NOISE crt_tune_d.y
#define CRT_HUM crt_tune_d.z
#define CRT_HUM_SPEED crt_tune_d.w
#define CRT_JITTER crt_tune_e.x
#define CRT_PHOSPHOR crt_tune_e.y
#define CRT_GLOW_THRESHOLD crt_tune_e.z
#define CRT_ABERRATION crt_tune_e.w
#define CRT_BLOOM crt_tune_f.x
#define CRT_SATURATION crt_tune_f.y
// The fight's own, behind its cells (`lcd`): not the CRT's, and not switched
// with it, but tuned on the same screen.
#define LCD_PHOSPHOR crt_tune_f.z
#define LCD_ABERRATION crt_tune_f.w

// THE LCD, the battle's (`SCRIPT_rpg_battle.gd` `_fit_lcd`, docs/DOC_battle_lcd.md),
// after `verdictzero/mewd-engine`'s pixel grid. `lcd_cell` above 0 puts everything
// under this pass on a lattice of cells `lcd_cell` PANEL pixels square, starting at
// `lcd_origin` (panel pixels too): each cell is ONE colour, the box average of
// the panel pixels it covers, dithered and snapped per cell, so whatever moves
// under it moves a whole cell at a time. Then it is drawn as a handheld's panel
// shows one:
//   lcd_mode 1, LINES: a dark gap down the left and along the top of every cell,
//     whole panel pixels wide (wider on bigger cells), the panel's black matrix;
//   lcd_mode 2, LCD: the gaps, and inside them, once a cell is six panel pixels or
//     more across, three subpixel stripes, red, green and blue, each lit by its
//     own channel (and a little of the others, so a grey stays grey), brightened
//     back up.
// `pixel_size` and `pixel_aspect` still work under it, in CELLS: a chunk of 2 is
// one colour over 2 x 2 cells, each still drawn with its own gaps.
// 0, the default, is off, and every other scene's pass is exactly as it was.
uniform float lcd_cell = 0.0;
uniform vec2 lcd_origin = vec2(0.0);
uniform int lcd_mode = 2;
// How dark the gaps are (0 none, 1 black).
uniform float lcd_gap : hint_range(0.0, 1.0) = 0.5;
// The glow and the fringe of the picture behind the cells (`LCD_PHOSPHOR`,
// `LCD_ABERRATION`, with the CRT's sliders below): see `lcd`.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
// The same screen, read linearly: one tap mixes the 2 x 2 panel pixels round it,
// so the LCD's box average takes about a quarter of the reads.
uniform sampler2D screen_lin : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D palette_lut : repeat_disable, filter_nearest;

const float bayer[16] = float[](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

vec3 palette_lookup(vec3 c) {
	float n = float(lut_levels);
	vec3 q = floor(clamp(c, 0.0, 1.0) * (n - 1.0) + 0.5);
	vec2 uv = vec2(
		(q.b * n + q.r + 0.5) / (n * n),
		(q.g + 0.5) / n);
	return textureLod(palette_lut, uv, 0.0).rgb;
}

// The LCD's pass (`lcd_cell` above). Counted in panel pixels from `lcd_origin`,
// whatever the desktop frame is doing: the cells are the panel's.
vec3 lcd(vec2 frag, vec2 px_size, vec2 ps_game) {
	float c = lcd_cell;
	vec2 rel = frag - lcd_origin;
	vec2 cell = floor(rel / c);
	vec2 in_px = rel - cell * c;
	// The chunk this cell is in, in whole cells, and the panel pixels it covers.
	vec2 per = max(floor(ps_game + 0.5), vec2(1.0));
	vec2 chunk = floor(cell / per);
	vec2 o = lcd_origin + chunk * per * c;
	vec2 span = per * c;
	// Its colour: the mean of what is under it, as mewd's filter boxes its
	// buffer down. Linear taps evenly spaced over the span, each mixing the
	// 2 x 2 pixels round it: 2 x 2 taps for a 3 or 4 px cell, at most 3 x 3.
	vec2 n = clamp(ceil(span * 0.5), vec2(1.0), vec2(3.0));
	vec3 sum = vec3(0.0);
	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 3; i++) {
			if (float(i) < n.x && float(j) < n.y) {
				vec2 at = o + span * (vec2(float(i), float(j)) + 0.5) / n;
				sum += textureLod(screen_lin, at * px_size, 0.0).rgb;
			}
		}
	}
	vec3 col = sum / (n.x * n.y);
	// BEHIND THE PIXEL FILTER (the user: "add some phosphor bleed and chromatic
	// abberation to the battle display BEHIND the pixel filter"): the picture the
	// cells are a filter over glows and fringes a little, before it is dithered,
	// snapped and gapped. Two more taps, a cell and a half either side of the
	// chunk's middle: red read from the outer side and blue from the inner, more
	// toward the sides of the screen, and what is bright there spilling in.
	vec2 mid = o + span * 0.5;
	vec2 reach = vec2(span.x * 1.5, 0.0);
	vec3 cl = textureLod(screen_lin, (mid - reach) * px_size, 0.0).rgb;
	vec3 cr = textureLod(screen_lin, (mid + reach) * px_size, 0.0).rgb;
	float side = clamp(mid.x * px_size.x * 2.0 - 1.0, -1.0, 1.0);
	float fringe = LCD_ABERRATION * (0.3 + 0.7 * abs(side));
	col.r = mix(col.r, side > 0.0 ? cr.r : cl.r, fringe);
	col.b = mix(col.b, side > 0.0 ? cl.b : cr.b, fringe);
	col += max((cl + cr) * 0.5 - 0.45, vec3(0.0)) * LCD_PHOSPHOR;
	// Dithered and snapped once per chunk: the Bayer cell is the chunk's.
	ivec2 bc = ivec2(mod(chunk, 4.0));
	float threshold = (bayer[bc.y * 4 + bc.x] + 0.5) / 16.0 - 0.5;
	col += vec3(threshold) * dither_strength / float(lut_levels - 1);
	vec3 rgb = palette_lookup(col);
	// The panel: the gaps, and the stripes where a cell is big enough for them.
	float line = max(1.0, floor(c / 6.0 + 0.001));
	float edge = (in_px.x < line || in_px.y < line) ? 1.0 : 0.0;
	if (lcd_mode == 2 && c >= 5.99) {
		float u = clamp((in_px.x - line) / max(c - line, 1.0), 0.0, 0.999);
		float k = floor(u * 3.0);
		vec3 mask = vec3(k == 0.0 ? 1.0 : 0.0, k == 1.0 ? 1.0 : 0.0, k == 2.0 ? 1.0 : 0.0);
		mask = mix(vec3(0.5), vec3(1.0), mask);
		rgb = min(rgb * mask * 1.5, vec3(1.0));
	} else if (lcd_mode == 2) {
		rgb *= 1.12;
	}
	return rgb * (1.0 - lcd_gap * edge);
}

// The pass as every other scene has it: chunks of game pixels.
//
// IN DESIGN PIXELS, NOT PANEL PIXELS. `stretch/mode` is `canvas_items`, so this
// pass runs at the panel's resolution and FRAGCOORD counts the panel's pixels: 2
// of them on a 1440p phone is 1.5 of the 1080-line frame the 3D is drawn at.
// `design_k` scales the chunk back to the frame, and rounding keeps the grid
// even — a 2.6 px chunk would alternate 2 and 3 px columns.
vec3 chunky(vec2 frag, vec2 px_size, vec2 ps_game) {
	vec2 sample_uv;
	vec2 cell_at;
	if (display_frame.w > 0.5) {
		// On the desktop frame: chunks of game pixels, on the frame's grid.
		float k = max(display_frame.x, 1e-3);
		vec2 o = display_frame.yz;
		vec2 game = floor((frag - o) / k);
		if (pixel_size <= 1 && pixel_aspect <= 1.0) {
			sample_uv = frag * px_size;
			cell_at = game;
		} else {
			vec2 chunk = floor(game / ps_game);
			sample_uv = (o + (chunk * ps_game + ps_game * 0.5) * k) * px_size;
			cell_at = chunk;
		}
	} else {
		float design_k = max(1.0, (1.0 / px_size.y) / design_height);
		if (pixel_size <= 1 && pixel_aspect <= 1.0) {
			// One game pixel: nothing merged. On a 1440p panel a game pixel is
			// 1.33 screen pixels: every screen pixel is read, and the dither cell
			// follows the game pixels (on a 1080p panel, the screen's own).
			sample_uv = frag * px_size;
			cell_at = floor(frag / design_k);
		} else {
			vec2 ps = max(round(ps_game * design_k), vec2(1.0));
			vec2 chunk_origin = floor(frag / ps) * ps;
			sample_uv = (chunk_origin + ps * 0.5) * px_size;
			cell_at = chunk_origin / ps;
		}
	}
	vec3 col = texture(screen_tex, sample_uv).rgb;

	ivec2 cell = ivec2(mod(cell_at, 4.0));
	int idx = cell.y * 4 + cell.x;
	float threshold = (bayer[idx] + 0.5) / 16.0 - 0.5;

	col += vec3(threshold) * dither_strength / float(lut_levels - 1);

	return palette_lookup(col);
}

float crt_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// The tube's face: where on the picture the glass at `frag` (panel pixels) shows.
// The corners stay put and the middle of each edge reads from a little inside,
// so the picture bulges out to the screen's edge and nothing is left black.
vec2 crt_warp(vec2 frag, vec2 res) {
	vec2 uv = frag / res * 2.0 - 1.0;
	vec2 w = uv * (1.0 + CRT_CURVE * (uv.yx * uv.yx - 1.0));
	return (w * 0.5 + 0.5) * res;
}

// The aerial lead: `rgb` (the picture at `frag`, dithered) with the signal's
// faults laid on it. The taps are the plain screen either side, read linearly:
// what bleeds is the analogue picture, not the palette's steps.
vec3 crt_signal(vec3 rgb, vec2 frag, vec2 res) {
	const vec3 W = vec3(0.299, 0.587, 0.114);
	float u = max(res.y / 1080.0, 1.0);
	vec2 px = 1.0 / res;
	vec2 uv = frag * px * 2.0 - 1.0;
	// How far the colour smears: the taps' reach, in 1080-line pixels.
	float w = u * CRT_BLEED_WIDTH;
	vec3 l1 = textureLod(screen_lin, (frag + vec2(-2.0 * w, 0.0)) * px, 0.0).rgb;
	vec3 r1 = textureLod(screen_lin, (frag + vec2(2.0 * w, 0.0)) * px, 0.0).rgb;
	vec3 l2 = textureLod(screen_lin, (frag + vec2(-5.5 * w, 0.0)) * px, 0.0).rgb;
	vec3 r2 = textureLod(screen_lin, (frag + vec2(5.0 * w, 0.0)) * px, 0.0).rgb;
	vec3 blur = (l1 + r1 + l2 + r2) * 0.25;
	// Chroma bleed: the brightness is the picture's, the colour partly its
	// neighbours'.
	float y = dot(rgb, W);
	vec3 chroma = mix(rgb - y, blur - dot(blur, W), CRT_BLEED);
	// Dot crawl: the carrier on a sharp edge, its phase turning with the line
	// and the frame.
	float edge = abs(dot(r1, W) - dot(l1, W));
	float ph = frag.x / u * 2.0944 + floor(frag.y / u) * 3.14159 + TIME * CRT_CRAWL_SPEED;
	chroma += vec3(cos(ph), cos(ph + 2.0944), cos(ph + 4.1888)) * edge * CRT_CRAWL;
	vec3 o = vec3(y) + chroma;
	// The glass's lens: red read from the outer side, blue from the inner.
	float side = clamp(uv.x, -1.0, 1.0);
	float k = CRT_ABERRATION * abs(side);
	o.r = mix(o.r, side > 0.0 ? r1.r : l1.r, k);
	o.b = mix(o.b, side > 0.0 ? l1.b : r1.b, k);
	// The ghost: what is `CRT_GHOST_OFFSET` pixels to the left, faintly, again.
	if (CRT_GHOST > 0.0005) {
		vec3 echo = textureLod(screen_lin, (frag + vec2(-CRT_GHOST_OFFSET * u, 0.0)) * px, 0.0).rgb;
		o = mix(o, echo, CRT_GHOST);
	}
	// The phosphor: bright neighbours spill sideways.
	o += max(blur - CRT_GLOW_THRESHOLD, vec3(0.0)) * CRT_PHOSPHOR;
	// The bloom: and round about, from above and below as well.
	if (CRT_BLOOM > 0.0005) {
		vec3 up = textureLod(screen_lin, (frag + vec2(0.0, -4.0 * w)) * px, 0.0).rgb;
		vec3 dn = textureLod(screen_lin, (frag + vec2(0.0, 4.0 * w)) * px, 0.0).rgb;
		vec3 round = (l2 + r2 + up + dn) * 0.25;
		o += max(round - CRT_GLOW_THRESHOLD, vec3(0.0)) * CRT_BLOOM;
	}
	// The colour knob of the set.
	o = mix(vec3(dot(o, W)), o, CRT_SATURATION);
	// The snow, and the hum bar.
	o += (crt_hash(frag + fract(TIME) * vec2(91.7, 37.3)) - 0.5) * CRT_NOISE;
	o *= 1.0 + CRT_HUM * sin(uv.y * 2.6 + TIME * CRT_HUM_SPEED);
	return o;
}

// The tube's lines, mask and falloff over `rgb`, the picture at `frag` (bowed).
// `row` is the height in panel pixels of one row of the picture's chunks.
vec3 crt_face(vec3 rgb, vec2 frag, vec2 res, float row) {
	// A scanline is whole rows of chunks, and at least `CRT_SCAN_SIZE` panel
	// pixels (three), so it can be seen and never beats against the chunks.
	float period = row * ceil(max(CRT_SCAN_SIZE, 1.0) / max(row, 1.0));
	float y = fract(frag.y / period);
	float beam = 0.5 - 0.5 * cos(y * 6.2831853);
	rgb *= mix(1.0 - CRT_SCAN, 1.0, beam);
	// The mask: RGB SUB-PIXELS (the user: "overworld, RGB sub pixels, slight
	// vignetting"). A red, a green and a blue stripe to each triad, a triad three
	// panel pixels wide on a 1080-line panel and wider with the panel, so the
	// sub-pixels can be seen on a dense one too; each stripe lets its own colour
	// through whole and holds the other two back a little.
	float sub = max(floor(res.y / 1080.0 * CRT_MASK_SIZE + 0.5), 1.0);
	float k = mod(floor(frag.x / sub), 3.0);
	vec3 mask = vec3(k == 0.0 ? 1.0 : 0.0, k == 1.0 ? 1.0 : 0.0, k == 2.0 ? 1.0 : 0.0);
	rgb *= mix(vec3(1.0 - CRT_MASK), vec3(1.0 + CRT_MASK * 0.5), mask);
	vec2 uv = frag / res * 2.0 - 1.0;
	float fall = 1.0 - CRT_VIGNETTE * pow(dot(uv, uv) * 0.5, 1.6);
	return clamp(rgb * CRT_GAIN * fall, vec3(0.0), vec3(1.0));
}

void fragment() {
	// Chunk size: width = pixel_size, height = pixel_size * pixel_aspect. The
	// shipped pair is 1 and 1.0 — one game pixel a chunk (one cell, on the LCD).
	// (This comment used to say the default aspect was 2.0 and kept a 1:2 look;
	// the uniform above has defaulted to 1.0 for as long as it has existed.)
	vec2 ps_game = vec2(float(pixel_size), max(float(pixel_size) * pixel_aspect, 1.0));
	vec2 frag = FRAGCOORD.xy;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// The overworld's, not the fight's ("make the CRT effect only affect the
	// overworld, not battle"): the fight is an LCD, and has its own glow and
	// fringe behind its cells.
	bool crt = crt_amount > 0.5 && lcd_cell <= 0.5;
	if (crt) {
		frag = crt_warp(frag, res);
		// The jitter: each line a fraction of a pixel off, new every frame.
		float u = max(res.y / 1080.0, 1.0);
		frag.x += (crt_hash(vec2(floor(frag.y / (2.0 * u)), floor(TIME * 30.0))) - 0.5) * CRT_JITTER * u;
	}
	vec3 rgb = lcd_cell > 0.5 ? lcd(frag, SCREEN_PIXEL_SIZE, ps_game)
			: chunky(frag, SCREEN_PIXEL_SIZE, ps_game);
	if (crt) {
		// One row of the picture's chunks, in panel pixels: the desktop frame's
		// game pixels, or the design's.
		float row;
		if (display_frame.w > 0.5) {
			row = max(display_frame.x, 1.0) * ps_game.y;
		} else {
			row = max(round(ps_game.y * max(1.0, res.y / design_height)), 1.0);
		}
		rgb = crt_face(crt_signal(rgb, frag, res), frag, res, row);
	}
	COLOR = vec4(rgb, 1.0);
}
