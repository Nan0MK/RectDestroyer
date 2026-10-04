///RECT-DESTROYER!
// A Brickbreaker clone with:
// 10 levels,
// 5 powerups,
// main menu,
// sounds,
// mouse controls,
// @___________________________________________@
// 1. Movable bouncepad, with mouse controls. (CHECK! 7/10/2026)
// 2. Ball that can bounce off pad and walls, except for bottom wall. (CHECK! 7/15/2026)

package src
import "core:fmt"
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
PADW: i32 = 150
PADH: i32 = 20
BOTTOM_MARGIN :: 30
PAD_TOP: i32 = WINDOW_H - BOTTOM_MARGIN

// Room around the largest grid. The lane under the bricks is open space for the paddle and the ball.
SIDE_MARGIN :: 24
PLAY_LANE :: 220

// Menus and the status labels use this. Bricks, the paddle, the ball, and the playfield title do not.
ui_scale: f32 = 1

// Ball
BALL_R :: 10

// One destroyed brick adds BRICK_SCORE * multiplier. All of it is integer.
// multiplier = SCORE_SCALE / elapsed_ns - elapsed_ns / NS_PER_MINUTE.
// Elapsed is nanoseconds since this level started, pause time not counted, and at least 1 so the division is defined.
// There is no clamp. 10 ns is 600 billion. The multiplier is 0 around 10 minutes and -27 at 30 minutes.
BRICK_SCORE :: i64(1)
SCORE_SCALE :: i64(6_000_000_000_000)
NS_PER_MINUTE :: i64(60_000_000_000)

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

draw_playfield :: proc(bricks: [dynamic]Brick, balls: [dynamic]Ball, falling: [dynamic]Falling_Powerup, pad_left: i32, mods: Power_Mods) {
	rl.DrawText("RECT-DESTROYER!", 190, 200, 20, rl.WHITE)
	rl.DrawRectangle(pad_left, PAD_TOP, mods.pad_w, PADH, rl.WHITE)
	// rl.DrawRectangle(PAD_LEFT, PAD_TOP, 12, 12, rl.GREEN)
	// rl.DrawRectangle(PAD_RIGHT, PAD_TOP, 12, 12, rl.GREEN)
	// rl.DrawRectangle(PAD_LEFT, PAD_BOT, 12, 12, rl.GREEN)
	// rl.DrawRectangle(PAD_RIGHT, PAD_BOT, 12, 12, rl.GREEN)

	for ball in balls {
		if !ball.alive do continue
		rl.DrawCircle(ball.x, ball.y, BALL_R, rl.RED)
	}

	renderRects(bricks)
	render_falling_powerups(falling)
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

// The frame is stored upside down. A negative source height flips it into the letterboxed rectangle.
present_game :: proc(target: rl.RenderTexture2D) {
	x, y, w, h := frame_fit()
	src := rl.Rectangle{0, 0, f32(target.texture.width), -f32(target.texture.height)}
	dst := rl.Rectangle{x, y, w, h}
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

format_score_label :: proc(score: i64, buf: ^[40]byte) -> cstring {
	prefix := "SCORE "
	n := 0
	for ch in prefix {
		buf[n] = u8(ch)
		n += 1
	}
	value := score
	if value < 0 {
		buf[n] = '-'
		n += 1
		value = -value
	}
	tmp: [20]byte
	count := 0
	if value == 0 {
		tmp[0] = '0'
		count = 1
	} else {
		for value > 0 && count < len(tmp) {
			tmp[count] = u8('0') + u8(value % 10)
			value /= 10
			count += 1
		}
	}
	for i := count - 1; i >= 0; i -= 1 {
		buf[n] = tmp[i]
		n += 1
	}
	buf[n] = 0
	return cstring(&buf[0])
}

draw_score :: proc(score: i64) {
	buf: [40]byte
	text := format_score_label(score, &buf)
	size := px(20)
	margin := px(16)
	width := rl.MeasureText(text, size)
	rl.DrawText(text, SCW - width - margin, margin, size, rl.WHITE)
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
step_ball :: proc(ball: ^Ball, balls: ^[dynamic]Ball, bricks: ^[dynamic]Brick, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods, score: ^i64, elapsed_ns: i64, pad_left: i32, pad_vx: f32) {
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
			on_speed_bounce(balls, mods)
			collide_pad(ball, pad_left, PAD_TOP, mods.pad_w, PADH, pad_vx, ball_base_speed(mods^), pad_launch_limit(mods^))
		}

		hit, broke, hp_before, brick_index := collideRects(bricks, ball)
		if hit {
			if hp_before > 1 && rl.GetTime() < mods.multiply_until {
				spawn_multiplied_balls(balls, ball.x, ball.y)
			}
			explode_from_hit(bricks, brick_index, falling, mods, score, elapsed_ns)
			// Neighbors broken by the blast are scored there. This scores the brick the ball itself finished.
			if broke {
				grant_brick_drops(bricks[brick_index], falling, mods)
				score^ += brick_points(elapsed_ns)
			}
			on_speed_bounce(balls, mods)
		}

		if wall || falling_onto_pad || side_hit || hit do return
	}
}

// Load one LEVELS path and stick a ball to the paddle. The level-clear menu loads the next path.
// Lives carry into that next path. A start from the menu clears them.
start_level :: proc(index: int, bricks: ^[dynamic]Brick, balls: ^[dynamic]Ball, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods, reset_lives: bool, pad_left: i32) {
	if index < 0 || index >= len(LEVELS) do return
	delete(bricks^)
	bricks^ = generateRects(LEVELS[index])
	clear(falling)
	lives := mods.lives
	mods^ = {}
	mods.pad_w = PADW
	if !reset_lives do mods.lives = lives
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
	score: i64 = 0
	level_started: time.Time
	skipped_ns: i64 = 0
	pause_started: time.Time

	for !rl.WindowShouldClose() {
		mouse := game_mouse()

		next, start, picked_level, quit := update_menus(screen, mouse, level_index)
		if quit do break
		if start {
			level_index = picked_level
			score = 0
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

			// The clear menu shows this level's score. Next Level is what loads the following path.
			if bricks_left(bricks) == 0 {
				next = .LEVEL_END
			} else {
				if !any_ball_alive(balls) {
					if mods.lives > 0 {
						mods.lives -= 1
						mods.speed_bonus = 0
						serve_ball(&balls, pad_left, mods.pad_w)
					} else {
						next = .LOST
					}
				}
				if next == .PLAY {
					pad_left = i32(mouse.x) - mods.pad_w / 2
					update_falling_powerups(&falling, pad_left, PAD_TOP, PADH, &mods, rl.GetFrameTime())
					pad_left = i32(mouse.x) - mods.pad_w / 2
				}
			}
		} else if next == screen && (screen == .PAUSE || screen == .LEVEL_END || screen == .LOST) && mods.multiply_until > rl.GetTime() {
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

		// ___
		rl.BeginTextureMode(game_target)
		rl.ClearBackground(rl.BLACK)

		if screen == .PLAY || screen == .PAUSE || screen == .LEVEL_END || screen == .LOST {
			if screen == .PLAY {
				mouseLocationText := fmt.tprintf("  X = %v, Y = %v", mouse.x, mouse.y)
				_ = mouseLocationText
				// rl.DrawText(fmt.caprintf(mouseLocationText), i32(mouse.x), i32(mouse.y), 35, rl.RED)
			}
			draw_playfield(bricks, balls, falling, pad_left, mods)
			if screen == .PLAY || screen == .PAUSE {
				draw_score(score)
			}
		}
		draw_menus(screen, mouse, score, level_index)
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		present_game(game_target)
		rl.EndDrawing()
	}
	delete(bricks)
	unload_rect_textures()
	rl.UnloadRenderTexture(game_target)
	rl.CloseWindow()
}


main :: proc() {
	fmt.printf("%v", os.get_current_directory(context.allocator))
	fmt.println("RECT-DESTROYER!")
	game()
}
