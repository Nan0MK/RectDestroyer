///RECT-DESTROYER!
// A Brickbreaker clone with:
// 15 levels,
// 5 powerups,
// main menu,
// sounds,
// mouse controls,
// @___________________________________________@
// 1. Movable bouncepad, with mouse controls. (CHECK! 7/10/2026)
// 2. Ball that can bounce off pad and walls, except for bottom wall. (CHECK! 7/15/2026)

package src
import "core:fmt"
import "core:math"
import big "core:math/big"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// The window opens at this size. The playfield grows to fit the largest level, then this window letterboxes it.
WINDOW_W :: 800
WINDOW_H :: 600

SCW: i32 = WINDOW_W
SCH: i32 = WINDOW_H
SCREEN_TOP :: i32(0)
SCREEN_BOT: i32 = WINDOW_H
SCREEN_LEFT :: i32(0)
SCREEN_RIGHT: i32 = WINDOW_W

// Pad. Draw, powerup catches, and ball collision all use this rectangle.
PADW: i32 = 200
PADH: i32 = 20
BOTTOM_MARGIN :: 30
PAD_TOP: i32 = WINDOW_H - BOTTOM_MARGIN

// Room around the largest grid. The lane under the bricks is open space for the paddle and the ball.
SIDE_MARGIN :: 24
PLAY_LANE :: 220

// Menus and the status labels use this. Bricks, the paddle, the ball, and the life icons do not.
ui_scale: f32 = 1

// Ball. The drawn box is this diameter, and the hit shape is the circle inside it.
BALL_R :: 12

// One destroyed brick adds BRICK_SCORE * multiplier. All of it is integer.
// multiplier = SCORE_SCALE / elapsed_ns - elapsed_ns / NS_PER_MINUTE.
// Elapsed is nanoseconds since this level started, pause time not counted, and at least 1 so the division is defined.
// There is no clamp. 10 ns is 1.2 trillion. The multiplier is 0 at 14 minutes and -24 at 30 minutes.
// That running total is the score during play. settle_round_score adds the round terms once, at the end.
// The total is an arbitrary-precision integer. The end-of-round multiplies are not capped.
BRICK_SCORE :: i64(1)
SCORE_SCALE :: i64(12_000_000_000_000)
NS_PER_MINUTE :: i64(60_000_000_000)

// Tallies for the level in play. start_level clears them. The score reads them once, when the round ends.
round_powerups: i64
round_balls_lost: i64
round_lives_lost: i64
round_elapsed_ns: i64
round_score_settled: bool

// vx, vy are pixels per frame. speed_x, speed_y mirror them for whole pixels.
// carry holds the fraction so a shallow angle still moves, one pixel at a time.
Ball :: struct {
	x, y:             i32,
	vx, vy:           f32,
	carry_x, carry_y: f32,
	speed_x, speed_y: i32,
	alive:            bool,
	stuck:            bool,
	stuck_dx:         i32,
	// Set by a paddle or brick bounce. The next brick doubles the score. Falling off halves it.
	from_bounce:      bool,
}

// Paddle aim. The game runs at 500 FPS, so one frame of mouse motion is mostly noise.
// The launch uses the average of the last few play frames. A still paddle is straight up.
PAD_AIM :: f32(1.25)
PAD_BOOST :: f32(0.4)
PAD_VX_DEADZONE :: f32(0.12)
PAD_VX_SAMPLES :: 16
PAD_VX_SAMPLE_CAP :: i32(24)

Pad_Motion :: struct {
	samples:   [PAD_VX_SAMPLES]i32,
	index:     int,
	prev_left: i32,
	live:      bool,
}

// Every .txt in this folder, sorted by the number at the end of the filename. Filled in load_levels.
LEVELS: [dynamic]string
LEVELS_DIR :: "src/levels"

// Digits at the end of the filename, so lvl2 stays before lvl10. A name with no digits sorts as 0.
level_number :: proc(name: string) -> int {
	base := name
	if strings.has_suffix(base, ".txt") {
		base = base[:len(base) - len(".txt")]
	}
	end := len(base)
	start := end
	for start > 0 {
		c := base[start - 1]
		if c < '0' || c > '9' do break
		start -= 1
	}
	if start == end do return 0
	n := 0
	for i in start..<end {
		n = n * 10 + int(base[i] - '0')
	}
	return n
}

level_name_less :: proc(a, b: string) -> bool {
	an := level_number(a)
	bn := level_number(b)
	if an != bn do return an < bn
	return a < b
}

// Columns and rows the same way generateRects walks the file. A blank line counts. An empty file is 0×0.
level_grid_size :: proc(path: string) -> (cols, rows: i32) {
	data, err := os.read_entire_file_or_err(path, context.allocator)
	if err != nil do return
	defer delete(data)

	col: i32 = 0
	newlines: i32 = 0
	for ch in string(data) {
		switch ch {
		case '\n':
			if col > cols do cols = col
			col = 0
			newlines += 1
		case '\r':
		case:
			col += 1
		}
	}
	if col > cols do cols = col
	if cols == 0 do return
	rows = newlines
	if col > 0 do rows += 1
	return
}

load_levels :: proc() -> (max_cols, max_rows: i32) {
	fd, open_err := os.open(LEVELS_DIR)
	if open_err != nil {
		fmt.eprintf("Failed to open '%s': %v\n", LEVELS_DIR, open_err)
		return
	}
	defer os.close(fd)

	infos, read_err := os.read_dir(fd, 0)
	if read_err != nil {
		fmt.eprintf("Failed to read '%s': %v\n", LEVELS_DIR, read_err)
		os.file_info_slice_delete(infos)
		return
	}
	defer os.file_info_slice_delete(infos)

	names := make([dynamic]string)
	defer {
		for name in names do delete(name)
		delete(names)
	}
	for info in infos {
		if info.is_dir do continue
		if !strings.has_suffix(info.name, ".txt") do continue
		name := strings.clone(info.name) or_else ""
		if len(name) == 0 do continue
		append(&names, name)
	}
	slice.sort_by(names[:], level_name_less)

	for name in names {
		path := strings.concatenate({LEVELS_DIR, "/", name}) or_else ""
		if len(path) == 0 do continue
		cols, rows := level_grid_size(path)
		if cols > max_cols do max_cols = cols
		if rows > max_rows do max_rows = rows
		append(&LEVELS, path)
	}
	return
}

// One playfield for every level. Small levels keep the old 800×600 board when nothing is larger.
fit_world :: proc(cols, rows: i32) {
	grid_w: i32 = 0
	if cols > 0 {
		grid_w = cols * RECT_W
		if cols > 1 do grid_w += (cols - 1) * RECT_GAP
	}
	grid_h: i32 = 0
	if rows > 0 {
		grid_h = rows * RECT_H
		if rows > 1 do grid_h += (rows - 1) * RECT_GAP
	}
	width := grid_w + SIDE_MARGIN * 2
	if width < WINDOW_W do width = WINDOW_W
	height := RECT_TOP + grid_h + PLAY_LANE
	if height < WINDOW_H do height = WINDOW_H
	SCW = width
	SCH = height
	SCREEN_BOT = SCH
	SCREEN_RIGHT = SCW
	PAD_TOP = SCH - BOTTOM_MARGIN
	ui_scale = f32(SCW) / f32(WINDOW_W)
	height_scale := f32(SCH) / f32(WINDOW_H)
	if height_scale < ui_scale do ui_scale = height_scale
}

px :: proc(n: i32) -> i32 {
	v := i32(f32(n) * ui_scale + 0.5)
	if n > 0 && v < 1 do v = 1
	return v
}

bricks_left :: proc(bricks: [dynamic]Brick) -> int {
	n := 0
	for brick in bricks {
		if brick.hp > 0 do n += 1
	}
	return n
}

round_i32 :: proc(v: f32) -> i32 {
	if v >= 0 do return i32(v + 0.5)
	return i32(v - 0.5)
}

note_ball_velocity :: proc(ball: ^Ball) {
	ball.carry_x = 0
	ball.carry_y = 0
	ball.speed_x = round_i32(ball.vx)
	ball.speed_y = round_i32(ball.vy)
}

// Whole pixels to move this frame. The leftover fraction stays in the carry.
consume_ball_motion :: proc(ball: ^Ball) -> (mx, my: i32) {
	ball.carry_x += ball.vx
	ball.carry_y += ball.vy
	mx = i32(ball.carry_x)
	my = i32(ball.carry_y)
	ball.carry_x -= f32(mx)
	ball.carry_y -= f32(my)
	return
}

// Straight up at `speed` when the paddle is still. Paddle movement aims the same way and adds speed.
// limit_speed caps the faster axis: NORMAL_MAX_SPEED without fast, MAX_BALL_SPEED while fast is on.
launch_from_pad :: proc(ball: ^Ball, pad_vx: f32, speed, limit_speed: i32) {
	base := speed
	cap := limit_speed
	if cap < 1 do cap = 1
	if base < 1 do base = 1
	if base > cap do base = cap
	swing := pad_vx
	if swing < PAD_VX_DEADZONE && swing > -PAD_VX_DEADZONE do swing = 0
	base_f := f32(base)
	ball.vx = swing * PAD_AIM * base_f
	ball.vy = -base_f * (1 + abs(swing) * PAD_BOOST)
	peak := abs(ball.vx)
	up := abs(ball.vy)
	if up > peak do peak = up
	limit := f32(cap)
	if peak > limit {
		scale := limit / peak
		ball.vx *= scale
		ball.vy *= scale
	}
	note_ball_velocity(ball)
}

ball_base_speed :: proc(mods: Power_Mods) -> i32 {
	speed := 1 + mods.speed_bonus
	if speed < 1 do speed = 1
	if speed > MAX_BALL_SPEED do speed = MAX_BALL_SPEED
	return speed
}

pad_launch_limit :: proc(mods: Power_Mods) -> i32 {
	if mods.fast do return MAX_BALL_SPEED
	return NORMAL_MAX_SPEED
}

pad_motion_reset :: proc(motion: ^Pad_Motion, pad_left: i32) {
	motion^ = {}
	motion.prev_left = pad_left
}

// Pixels per frame, averaged. The first sample after a pause is zero so the resume does not fling the ball.
pad_motion_sample :: proc(motion: ^Pad_Motion, pad_left: i32) -> f32 {
	delta: i32 = 0
	if motion.live {
		delta = pad_left - motion.prev_left
		if delta > PAD_VX_SAMPLE_CAP do delta = PAD_VX_SAMPLE_CAP
		if delta < -PAD_VX_SAMPLE_CAP do delta = -PAD_VX_SAMPLE_CAP
	}
	motion.samples[motion.index] = delta
	motion.index += 1
	if motion.index >= PAD_VX_SAMPLES do motion.index = 0
	motion.prev_left = pad_left
	motion.live = true
	sum: i32 = 0
	for sample in motion.samples do sum += sample
	return f32(sum) / f32(PAD_VX_SAMPLES)
}

// Clears the balls and sticks one to the middle of the paddle. Left click launches it.
serve_ball :: proc(balls: ^[dynamic]Ball, pad_left, pad_w: i32) {
	clear(balls)
	dx := pad_w / 2
	append(balls, Ball {
		x = pad_left + dx,
		y = PAD_TOP - BALL_R,
		alive = true,
		stuck = true,
		stuck_dx = dx,
	})
}

// Separation the bounce would use. active is false on a miss, or when the center is already past the underside.
pad_resolve :: proc(ball: Ball, pad_left, pad_top, pad_w, pad_h: i32) -> (active: bool, sep_x, sep_y: i32) {
	right := pad_left + pad_w
	bot := pad_top + pad_h

	closest_x := ball.x
	if closest_x < pad_left do closest_x = pad_left
	else if closest_x > right do closest_x = right
	closest_y := ball.y
	if closest_y < pad_top do closest_y = pad_top
	else if closest_y > bot do closest_y = bot

	dx := ball.x - closest_x
	dy := ball.y - closest_y
	if dx * dx + dy * dy > BALL_R * BALL_R do return

	if dx == 0 && dy == 0 {
		dist_left := ball.x - pad_left
		dist_right := right - ball.x
		dist_top := ball.y - pad_top
		dist_bot := bot - ball.y
		min_d := dist_left
		sep_x = -1
		if dist_right < min_d {
			min_d = dist_right
			sep_x = 1
		}
		if dist_top < min_d {
			min_d = dist_top
			sep_x = 0
			sep_y = -1
		}
		if dist_bot < min_d {
			sep_x = 0
			sep_y = 1
		}
	} else if abs(dx) >= abs(dy) {
		sep_x = 1 if dx > 0 else -1
	} else {
		sep_y = 1 if dy > 0 else -1
	}

	// The ball is removed once its center passes the bottom of the playfield, so an underside bounce has nowhere to go.
	if sep_y > 0 {
		if ball.y > bot do return
		sep_x = 0
		sep_y = -1
	}
	active = true
	return
}

// Bounce off the drawn paddle. The ball is a circle, so contact is the circle against that rectangle.
// A downward hit on the top relaunches from the paddle's movement. A side hit reflects horizontally.
collide_pad :: proc(ball: ^Ball, pad_left, pad_top, pad_w, pad_h: i32, pad_vx: f32, speed, limit_speed: i32) {
	active, sep_x, sep_y := pad_resolve(ball^, pad_left, pad_top, pad_w, pad_h)
	if !active do return
	right := pad_left + pad_w

	if sep_y < 0 {
		if ball.vy <= 0 do return
		if sep_x < 0 do ball.x = pad_left - BALL_R
		else if sep_x > 0 do ball.x = right + BALL_R
		ball.y = pad_top - BALL_R
		launch_from_pad(ball, pad_vx, speed, limit_speed)
		return
	}

	if sep_x < 0 {
		ball.x = pad_left - BALL_R
		if ball.vx > 0 do ball.vx = -ball.vx
	} else if sep_x > 0 {
		ball.x = right + BALL_R
		if ball.vx < 0 do ball.vx = -ball.vx
	}
	note_ball_velocity(ball)
}

// src/textures/ball.png, drawn across the collision circle. A missing file keeps the red circle.
ball_tex: rl.Texture2D
ball_tex_loaded: bool

ensure_ball_texture :: proc() {
	if ball_tex_loaded || !rl.IsWindowReady() do return
	ball_tex_loaded = true
	ball_tex = load_texture_file("src/textures/ball.png")
}

unload_ball_texture :: proc() {
	if ball_tex.id != 0 do rl.UnloadTexture(ball_tex)
	ball_tex = {}
	ball_tex_loaded = false
}

draw_ball :: proc(ball: Ball) {
	ensure_ball_texture()
	if ball_tex.id != 0 {
		size: i32 = BALL_R * 2
		draw_texture_rect(ball_tex, ball.x - BALL_R, ball.y - BALL_R, size, size)
		return
	}
	rl.DrawCircle(ball.x, ball.y, BALL_R, rl.RED)
}

// src/textures/pad_center.png tiles across the paddle. src/textures/pad_end.png caps both ends, on top of the center.
// A missing center keeps the white rectangle. The hit box stays the rectangle.
pad_center_tex: rl.Texture2D
pad_end_tex: rl.Texture2D
pad_tex_loaded: bool

ensure_pad_textures :: proc() {
	if pad_tex_loaded || !rl.IsWindowReady() do return
	pad_tex_loaded = true
	pad_center_tex = load_texture_file("src/textures/pad_center.png")
	pad_end_tex = load_texture_file("src/textures/pad_end.png")
}

unload_pad_textures :: proc() {
	if pad_center_tex.id != 0 do rl.UnloadTexture(pad_center_tex)
	if pad_end_tex.id != 0 do rl.UnloadTexture(pad_end_tex)
	pad_center_tex = {}
	pad_end_tex = {}
	pad_tex_loaded = false
}

// One horizontal repeat. The last slice is clipped to the paddle's right edge.
draw_pad_center :: proc(left, width: i32) {
	tex := pad_center_tex
	tile_w := tex.width
	tile_h := tex.height
	if tile_w < 1 || tile_h < 1 do return
	x := left
	remain := width
	for remain > 0 {
		slice := tile_w
		if slice > remain do slice = remain
		src := rl.Rectangle{0, 0, f32(slice), f32(tile_h)}
		dst := rl.Rectangle{f32(x), f32(PAD_TOP), f32(slice), f32(PADH)}
		rl.DrawTexturePro(tex, src, dst, {}, 0, rl.WHITE)
		x += slice
		remain -= slice
	}
}

// flip mirrors the cap so the right end faces outward.
draw_pad_end :: proc(x: i32, flip: bool) {
	tex := pad_end_tex
	w := tex.width
	h := tex.height
	if w < 1 || h < 1 do return
	src := rl.Rectangle{0, 0, f32(w), f32(h)}
	if flip {
		src.x = f32(w)
		src.width = -f32(w)
	}
	dst := rl.Rectangle{f32(x), f32(PAD_TOP), f32(w), f32(h)}
	rl.DrawTexturePro(tex, src, dst, {}, 0, rl.WHITE)
}

draw_paddle :: proc(left, width: i32) {
	ensure_pad_textures()
	if pad_center_tex.id == 0 {
		rl.DrawRectangle(left, PAD_TOP, width, PADH, rl.WHITE)
	} else {
		draw_pad_center(left, width)
	}
	if pad_end_tex.id == 0 || width < 1 do return
	draw_pad_end(left, false)
	right := left + width - pad_end_tex.width
	if right < left do right = left
	draw_pad_end(right, true)
}

draw_playfield :: proc(bricks: [dynamic]Brick, balls: [dynamic]Ball, falling: [dynamic]Falling_Powerup, pad_left: i32, mods: Power_Mods, shake_bricks: bool) {
	render_life_points(mods.lives, 255)
	draw_paddle(pad_left, mods.pad_w)
	// rl.DrawRectangle(PAD_LEFT, PAD_TOP, 12, 12, rl.GREEN)
	// rl.DrawRectangle(PAD_RIGHT, PAD_TOP, 12, 12, rl.GREEN)
	// rl.DrawRectangle(PAD_LEFT, PAD_BOT, 12, 12, rl.GREEN)
	// rl.DrawRectangle(PAD_RIGHT, PAD_BOT, 12, 12, rl.GREEN)

	renderRects(bricks, shake_bricks)
	render_life_points(mods.lives, LIFE_POINT_OVER_ALPHA)
	for ball in balls {
		if !ball.alive do continue
		render_ball_trail(ball)
		draw_ball(ball)
	}
	render_brick_chips()
	render_falling_powerups(falling)
	render_animations()
	render_multiply_timer(mods.multiply_until)
	render_power_status(mods)
}

// Uniform fit of the playfield in the window. Black bars take the leftover space. Mouse outside the frame lands outside the world.
frame_fit :: proc() -> (x, y, w, h: f32) {
	ww := f32(rl.GetScreenWidth())
	wh := f32(rl.GetScreenHeight())
	if ww < 1 do ww = 1
	if wh < 1 do wh = 1
	scale := ww / f32(SCW)
	if f32(SCH) * scale > wh {
		scale = wh / f32(SCH)
	}
	w = f32(SCW) * scale
	h = f32(SCH) * scale
	x = (ww - w) * 0.5
	y = (wh - h) * 0.5
	return
}

game_mouse :: proc() -> rl.Vector2 {
	window := rl.GetMousePosition()
	x, y, w, h := frame_fit()
	if w < 1 do w = 1
	if h < 1 do h = 1
	return {(window.x - x) * f32(SCW) / w, (window.y - y) * f32(SCH) / h}
}

// A spent life jitters the picture. The last life slams it until that animation ends.
// The offset is in window pixels, so the jolt stays the same size when the board is letterboxed.
SHAKE_TIME :: f32(0.34)
SHAKE_PIXELS :: f32(8)
SHAKE_FINALE_PIXELS :: f32(48)
shake_left: f32
shake_span: f32 = SHAKE_TIME
shake_pixels: f32 = SHAKE_PIXELS

start_screen_shake :: proc() {
	shake_left = SHAKE_TIME
	shake_span = SHAKE_TIME
	shake_pixels = SHAKE_PIXELS
}

// Runs for the whole life_lost sheet, which is what the last-life screen waits on.
start_finale_shake :: proc() {
	ensure_animations()
	span := f32(len(clips[.LIFE_LOST].frames)) * ANIM_FRAME_DT
	if span < SHAKE_TIME do span = SHAKE_TIME
	shake_left = span
	shake_span = span
	shake_pixels = SHAKE_FINALE_PIXELS
}

update_screen_shake :: proc(dt: f32) {
	step := dt
	if step < 0 do step = 0
	if shake_left <= 0 do return
	shake_left -= step
	if shake_left < 0 do shake_left = 0
}

shake_pixel :: proc(v: f32) -> f32 {
	if v >= 0 do return f32(i32(v + 0.5))
	return f32(i32(v - 0.5))
}

// The brick grid only. Hit boxes stay put. A few playfield pixels, shorter than a lost life.
BRICK_SHAKE_TIME :: f32(0.15)
BRICK_SHAKE_PIXELS :: f32(4)
brick_shake_left: f32

start_brick_shake :: proc() {
	brick_shake_left = BRICK_SHAKE_TIME
}

update_brick_shake :: proc(dt: f32) {
	step := dt
	if step < 0 do step = 0
	if brick_shake_left <= 0 do return
	brick_shake_left -= step
	if brick_shake_left < 0 do brick_shake_left = 0
}

// Added to every brick's draw position. Zero while the board is not in play, so pause holds the timer without showing the shift.
brick_shake_offset :: proc(show: bool) -> (x, y: i32) {
	if !show || brick_shake_left <= 0 do return 0, 0
	amp := BRICK_SHAKE_PIXELS * (brick_shake_left / BRICK_SHAKE_TIME)
	age := BRICK_SHAKE_TIME - brick_shake_left
	x = i32(shake_pixel(math.sin(age * 72) * amp))
	y = i32(shake_pixel(math.cos(age * 55) * amp))
	return
}

// Whole window pixels. The strength falls off until the timer ends.
screen_shake_offset :: proc() -> (x, y: f32) {
	if shake_left <= 0 || shake_span <= 0 do return 0, 0
	amp := shake_pixels * (shake_left / shake_span)
	age := shake_span - shake_left
	x = shake_pixel(math.sin(age * 54) * amp)
	y = shake_pixel(math.cos(age * 41) * amp)
	return
}

// The frame is stored upside down. A negative source height flips it into the letterboxed rectangle.
// shake moves that rectangle. Pause leaves it still and keeps the remaining time.
present_game :: proc(target: rl.RenderTexture2D, shake: bool) {
	x, y, w, h := frame_fit()
	ox, oy: f32
	if shake {
		ox, oy = screen_shake_offset()
	}
	src := rl.Rectangle{0, 0, f32(target.texture.width), -f32(target.texture.height)}
	dst := rl.Rectangle{x + ox, y + oy, w, h}
	rl.DrawTexturePro(target.texture, src, dst, {}, 0, rl.WHITE)
}

arm_level_clock :: proc(started: ^time.Time, skipped_ns: ^i64) {
	started^ = time.now()
	skipped_ns^ = 0
}

level_elapsed_ns :: proc(started: time.Time, skipped_ns: i64) -> i64 {
	ns := time.duration_nanoseconds(time.since(started)) - skipped_ns
	if ns < 1 do ns = 1
	return ns
}

brick_points :: proc(elapsed_ns: i64) -> i64 {
	ns := elapsed_ns
	if ns < 1 do ns = 1
	multiplier := SCORE_SCALE / ns - ns / NS_PER_MINUTE
	return BRICK_SCORE * multiplier
}

note_powerup_collected :: proc() {
	round_powerups += 1
}

note_ball_lost :: proc() {
	round_balls_lost += 1
}

note_life_lost :: proc() {
	round_lives_lost += 1
}

// Exact add. A failed allocation leaves the total unchanged.
score_add_i64 :: proc(score: ^big.Int, delta: i64) {
	if delta == 0 do return
	term: big.Int
	sum: big.Int
	defer big.destroy(&term, &sum)
	if big.set(&term, delta) != big.Error.None do return
	if big.add(&sum, score, &term) != big.Error.None do return
	big.copy(score, &sum)
}

// Half, rounded to the nearest integer. A remainder of 0.5 rounds away from zero.
// The live total is replaced only after the division succeeds.
score_div2_nearest :: proc(score: ^big.Int) {
	zero, zerr := big.is_zero(score)
	if zerr != big.Error.None || zero do return
	neg, nerr := big.is_negative(score)
	if nerr != big.Error.None do return

	adjusted: big.Int
	two: big.Int
	quot: big.Int
	defer big.destroy(&adjusted, &two, &quot)
	if big.copy(&adjusted, score) != big.Error.None do return
	nudge: i64 = 1
	if neg do nudge = -1
	score_add_i64(&adjusted, nudge)
	if big.set(&two, 2) != big.Error.None do return
	if big.div(&quot, &adjusted, &two) != big.Error.None do return
	big.copy(score, &quot)
}

// The trip from the previous paddle or brick bounce reached another brick.
note_score_trip_brick :: proc(ball: ^Ball, score: ^big.Int) {
	if ball.from_bounce {
		score_mul_i64(score, 2)
	}
	ball.from_bounce = true
}

// The trip ended at the bottom of the playfield.
note_score_trip_lost :: proc(ball: ^Ball, score: ^big.Int) {
	if !ball.from_bounce do return
	ball.from_bounce = false
	score_div2_nearest(score)
}

// Exact multiply. A failed allocation leaves the total unchanged.
score_mul_i64 :: proc(score: ^big.Int, factor: i64) {
	if factor == 1 do return
	term: big.Int
	product: big.Int
	defer big.destroy(&term, &product)
	if big.set(&term, factor) != big.Error.None do return
	if big.mul(&product, score, &term) != big.Error.None do return
	big.copy(score, &product)
}

// Whole-pixel faster axis. A stuck ball with no velocity is 0.
ball_score_speed :: proc(ball: Ball) -> i32 {
	ax := ball.speed_x
	ay := ball.speed_y
	if ax < 0 do ax = -ax
	if ay < 0 do ay = -ay
	if ay > ax do return ay
	return ax
}

// Once, when the board clears or the last life is lost. Order matches the round rules,
// so each multiply sees the score as it stands at that step. Speed is added last.
settle_round_score :: proc(score: ^big.Int, mods: Power_Mods, balls: []Ball, powerups, balls_lost, lives_lost: i64) {
	score_add_i64(score, powerups * 2)

	extra := (mods.pad_w - PADW) / WIDE_STEP
	if extra > 0 {
		for _ in 0..<extra {
			score_mul_i64(score, 10)
		}
	}

	alive: i64 = 0
	for ball in balls {
		if ball.alive do alive += 1
	}
	score_add_i64(score, alive * 10)
	score_add_i64(score, balls_lost * -15)

	lives := i64(mods.lives)
	if lives < 0 do lives = 0
	score_add_i64(score, lives * 100)
	score_add_i64(score, lives_lost * -500)
	// A loss leaves no lives, and multiplying by zero would wipe the brick total.
	if lives_lost == 0 && lives > 0 {
		score_mul_i64(score, lives * 150)
	}

	for ball in balls {
		if !ball.alive do continue
		score_add_i64(score, i64(ball_score_speed(ball)) * 10)
	}
}

// Caller frees backing. The cstring points into it, including the trailing zero.
format_score_label :: proc(score: ^big.Int) -> (text: cstring, backing: []u8) {
	digits, err := big.itoa(score)
	defer delete(digits)
	shown := digits
	if err != big.Error.None || len(digits) == 0 {
		shown = "0"
	}
	prefix := "SCORE "
	backing = make([]u8, len(prefix) + len(shown) + 1)
	for ch, i in prefix {
		backing[i] = u8(ch)
	}
	for ch, i in shown {
		backing[len(prefix) + i] = u8(ch)
	}
	backing[len(backing) - 1] = 0
	return cstring(raw_data(backing)), backing
}

draw_score :: proc(score: ^big.Int) {
	text, backing := format_score_label(score)
	defer delete(backing)
	size := px(20)
	margin := px(16)
	width := measure_text(text, size)
	draw_text(text, SCW - width - margin, margin, size, rl.WHITE)
}

any_ball_alive :: proc(balls: [dynamic]Ball) -> bool {
	for ball in balls {
		if ball.alive do return true
	}
	return false
}

// Left click releases every ball sitting on the paddle. A still paddle sends them straight up.
launch_stuck_balls :: proc(balls: ^[dynamic]Ball, pad_left: i32, mods: Power_Mods, pad_vx: f32) {
	speed := ball_base_speed(mods)
	limit := pad_launch_limit(mods)
	for i in 0..<len(balls) {
		ball := &balls[i]
		if !ball.alive || !ball.stuck do continue
		ball.stuck = false
		ball.x = pad_left + ball.stuck_dx
		if ball.x < BALL_R do ball.x = BALL_R
		if ball.x > SCW - BALL_R do ball.x = SCW - BALL_R
		// One pixel clear of the top face, so the launch does not count as another landing.
		ball.y = PAD_TOP - BALL_R - 1
		launch_from_pad(ball, pad_vx, speed, limit)
	}
}

// One pixel at a time, so a fast ball still hits the brick it would otherwise jump.
// A bounce ends the rest of this frame's steps. Fractions of a pixel wait in the carry.
step_ball :: proc(ball: ^Ball, balls: ^[dynamic]Ball, bricks: ^[dynamic]Brick, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods, score: ^big.Int, elapsed_ns: i64, pad_left: i32, pad_vx: f32) {
	if !ball.alive do return
	if ball.stuck {
		ball.x = pad_left + ball.stuck_dx
		if ball.x < BALL_R do ball.x = BALL_R
		if ball.x > SCW - BALL_R do ball.x = SCW - BALL_R
		ball.y = PAD_TOP - BALL_R
		return
	}

	mx, my := consume_ball_motion(ball)
	ax: i32 = 0
	ay: i32 = 0
	if mx > 0 do ax = 1
	else if mx < 0 do ax = -1
	if my > 0 do ay = 1
	else if my < 0 do ay = -1
	steps_x := mx
	if steps_x < 0 do steps_x = -steps_x
	steps_y := my
	if steps_y < 0 do steps_y = -steps_y
	steps := steps_x
	if steps_y > steps do steps = steps_y
	if steps < 1 do return

	for s in 0..<steps {
		if s < steps_x do ball.x += ax
		if s < steps_y do ball.y += ay

		if ball.y > SCH {
			note_score_trip_lost(ball, score)
			play_ball_lost(ball.x)
			lose_ball(ball, balls, mods)
			return
		}

		wall := false
		if ball.y < SCREEN_TOP && ball.vy < 0 {
			ball.vy = -ball.vy
			wall = true
		}
		if ball.x > SCREEN_RIGHT && ball.vx > 0 {
			ball.vx = -ball.vx
			wall = true
		}
		if ball.x < SCREEN_LEFT && ball.vx < 0 {
			ball.vx = -ball.vx
			wall = true
		}
		if wall {
			note_ball_velocity(ball)
			on_speed_bounce(balls, mods)
		}

		active, sep_x, sep_y := pad_resolve(ball^, pad_left, PAD_TOP, mods.pad_w, PADH)
		landed := ball.y <= PAD_TOP + PADH / 2
		if active && mods.stick && sep_y < 0 && ball.vy > 0 && landed {
			ball.stuck = true
			ball.stuck_dx = ball.x - pad_left
			ball.y = PAD_TOP - BALL_R
			// One landing spends it. A second ball on this frame bounces, and the label goes away while this ball is still stuck.
			mods.stick = false
			return
		}
		falling_onto_pad := active && sep_y < 0 && ball.vy > 0
		side_hit := active && sep_y == 0 && sep_x != 0
		if falling_onto_pad || side_hit {
			ball.from_bounce = true
			on_speed_bounce(balls, mods)
			collide_pad(ball, pad_left, PAD_TOP, mods.pad_w, PADH, pad_vx, ball_base_speed(mods^), pad_launch_limit(mods^))
		}

		hit, broke, hp_before, brick_index := collideRects(bricks, ball)
		if hit {
			note_score_trip_brick(ball, score)
			start_brick_shake()
			spawn_brick_chips(bricks[brick_index], broke, ball.x, ball.y)
			if hp_before > 1 && rl.GetTime() < mods.multiply_until {
				spawn_multiplied_balls(balls, ball.x, ball.y)
			}
			explode_from_hit(bricks, brick_index, falling, mods, score, elapsed_ns)
			// Neighbors broken by the blast are scored there. This scores the brick the ball itself finished.
			if broke {
				grant_brick_drops(bricks[brick_index], falling, mods)
				score_add_i64(score, brick_points(elapsed_ns))
			}
			on_speed_bounce(balls, mods)
		}

		if wall || falling_onto_pad || side_hit || hit do return
	}
}

// Load one LEVELS path and stick a ball to the paddle. The level-clear menu loads the next path.
// Lives carry into that next path. A start from the menu sets them to 1.
start_level :: proc(index: int, bricks: ^[dynamic]Brick, balls: ^[dynamic]Ball, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods, reset_lives: bool, pad_left: i32) {
	if index < 0 || index >= len(LEVELS) do return
	delete(bricks^)
	bricks^ = generateRects(LEVELS[index])
	clear(falling)
	clear_brick_chips()
	clear_animations()
	shake_left = 0
	brick_shake_left = 0
	round_powerups = 0
	round_balls_lost = 0
	round_lives_lost = 0
	round_elapsed_ns = 0
	round_score_settled = false
	level_banked = false
	if reset_lives do reset_run_score()
	lives := mods.lives
	mods^ = {}
	mods.pad_w = PADW
	if reset_lives {
		mods.lives = START_LIVES
	} else {
		mods.lives = lives
	}
	serve_ball(balls, pad_left, mods.pad_w)
}

game :: proc() {
	cols, rows := load_levels()
	fit_world(cols, rows)
	defer {
		for path in LEVELS do delete(path)
		delete(LEVELS)
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(WINDOW_W, WINDOW_H, "RECT-DESTROYER!")
	// Escape opens the pause menu. Raylib would otherwise close the window.
	rl.SetExitKey(.KEY_NULL)
	game_target := rl.LoadRenderTexture(SCW, SCH)
	rl.SetTextureFilter(game_target.texture, .BILINEAR)

	rl.SetTargetFPS(500)
	rand.reset(u64(time.to_unix_nanoseconds(time.now())))
	screen := Screen.MENU
	level_index := 0
	bricks := make([dynamic]Brick)

	balls := make([dynamic]Ball)
	defer delete(balls)

	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	mods := Power_Mods{pad_w = PADW}
	pad_left := SCW / 2 - mods.pad_w / 2
	pad_motion: Pad_Motion
	pad_motion_reset(&pad_motion, pad_left)
	score: big.Int
	big.set(&score, 0)
	defer big.destroy(&score)
	init_saved_scores()
	defer shutdown_saved_scores()
	level_started: time.Time
	skipped_ns: i64 = 0
	pause_started: time.Time

	for !rl.WindowShouldClose() {
		if screen == .PLAY || screen == .LAST_LIFE {
			update_screen_shake(rl.GetFrameTime())
		} else if screen != .PAUSE {
			shake_left = 0
		}
		if screen == .PLAY {
			update_brick_shake(rl.GetFrameTime())
		} else if screen != .PAUSE {
			brick_shake_left = 0
		}
		mouse := game_mouse()

		next, start, picked_level, quit := update_menus(screen, mouse, level_index)
		if quit do break
		if start {
			level_index = picked_level
			big.set(&score, 0)
			arm_level_clock(&level_started, &skipped_ns)
			// Play does not run until the next frame, so place the stuck ball before the first draw.
			pad_left = i32(mouse.x) - PADW / 2
			start_level(level_index, &bricks, &balls, &falling, &mods, screen != .LEVEL_END, pad_left)
		}

		if screen == .PLAY && next == .PLAY {
			// ___ Live data updates
			pad_left = i32(mouse.x) - mods.pad_w / 2
			pad_vx := pad_motion_sample(&pad_motion, pad_left)

			if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
				mods.speed_bonus = 0
				serve_ball(&balls, pad_left, mods.pad_w)
			}

			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				launch_stuck_balls(&balls, pad_left, mods, pad_vx)
			}

			elapsed := level_elapsed_ns(level_started, skipped_ns)
			ball_count := len(balls)
			for i in 0..<ball_count {
				step_ball(&balls[i], &balls, &bricks, &falling, &mods, &score, elapsed, pad_left, pad_vx)
			}
			update_brick_chips(rl.GetFrameTime())

			// The clear menu shows this level's score. Next Level is what loads the following path.
			if bricks_left(bricks) == 0 {
				next = .LEVEL_END
			} else {
				if !any_ball_alive(balls) {
					// The life in play is one of the count. 0 is a loss, so the last life does not serve another ball.
					mods.lives -= 1
					note_life_lost()
					if mods.lives > 0 {
						play_life_lost(int(mods.lives))
						start_screen_shake()
						mods.speed_bonus = 0
						serve_ball(&balls, pad_left, mods.pad_w)
					} else {
						mods.lives = 0
						play_life_finale()
						start_finale_shake()
						next = .LAST_LIFE
					}
				}
				if next == .PLAY {
					pad_left = i32(mouse.x) - mods.pad_w / 2
					update_falling_powerups(&falling, pad_left, PAD_TOP, PADH, &mods, rl.GetFrameTime())
					pad_left = i32(mouse.x) - mods.pad_w / 2
				}
			}
			// Clear wins over a life loss on the same frame, so the life count is already final here.
			if (next == .LEVEL_END || next == .LAST_LIFE) && !round_score_settled {
				settle_round_score(&score, mods, balls[:], round_powerups, round_balls_lost, round_lives_lost)
				round_elapsed_ns = elapsed
				round_score_settled = true
			}
		} else if next == screen && (screen == .PAUSE || screen == .LEVEL_END || screen == .LAST_LIFE || screen == .LOST) && mods.multiply_until > rl.GetTime() {
			// Keep the x2 countdown from draining while the board is frozen.
			mods.multiply_until += f64(rl.GetFrameTime())
		}
		if screen == .PLAY && next == .PAUSE {
			pause_started = time.now()
		}
		if screen == .PAUSE && next != .PAUSE {
			skipped_ns += time.duration_nanoseconds(time.since(pause_started))
		}
		screen = next
		if screen != .PLAY do pad_motion_reset(&pad_motion, pad_left)
		if screen == .LAST_LIFE {
			if !update_life_finale(rl.GetFrameTime()) {
				screen = .LOST
			}
		} else if screen == .PLAY || screen == .LEVEL_END || screen == .LOST {
			update_animations(rl.GetFrameTime(), screen == .PLAY)
		}
		// The level score stays on screen while LEVEL_END is up, so a failed bank can retry.
		// A loss does not count the level that was still in play.
		if screen == .LEVEL_END && !level_banked {
			bank_level_score(&score)
		}
		if screen == .LOST || (screen == .LEVEL_END && level_index + 1 >= len(LEVELS)) {
			finish_run()
		}

		// ___
		rl.BeginTextureMode(game_target)
		rl.ClearBackground(rl.BLACK)
		if screen == .MENU || screen == .LEVEL_SELECT || screen == .SCORES {
			draw_starfield()
		} else {
			draw_space_background()
		}

		if screen == .PLAY || screen == .PAUSE || screen == .LEVEL_END || screen == .LAST_LIFE || screen == .LOST {
			if screen == .PLAY {
				mouseLocationText := fmt.tprintf("  X = %v, Y = %v", mouse.x, mouse.y)
				_ = mouseLocationText
				// rl.DrawText(fmt.caprintf(mouseLocationText), i32(mouse.x), i32(mouse.y), 35, rl.RED)
			}
			draw_playfield(bricks, balls, falling, pad_left, mods, screen == .PLAY)
			if screen == .PLAY || screen == .PAUSE || screen == .LAST_LIFE {
				draw_score(&score)
			}
			render_life_finale()
		}
		draw_menus(screen, mouse, &score, level_index, mods, balls[:])
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		present_game(game_target, screen == .PLAY || screen == .LAST_LIFE)
		rl.EndDrawing()
	}
	delete(bricks)
	free_end_credits()
	free_brick_chips()
	unload_rect_textures()
	unload_powerup_textures()
	unload_ball_texture()
	unload_pad_textures()
	unload_life_point_texture()
	unload_animations()
	unload_space_background()
	unload_starfield()
	unload_game_font()
	rl.UnloadRenderTexture(game_target)
	rl.CloseWindow()
}


main :: proc() {
	fmt.printf("%v", os.get_current_directory(context.allocator))
	fmt.println("RECT-DESTROYER!")
	game()
}
