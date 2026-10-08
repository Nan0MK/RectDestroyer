package src

import big "core:math/big"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_powerup_and_rect_config :: proc(t: ^testing.T) {
	powerups := load_powerup_types(POWERUP_TYPES_PATH)
	defer delete(powerups)
	testing.expect_value(t, len(powerups), 7)

	wide, wide_ok := find_powerup_type(powerups[:], .WIDE)
	multiply, multiply_ok := find_powerup_type(powerups[:], .MULTIPLY)
	bomb, bomb_ok := find_powerup_type(powerups[:], .BOMB)
	stick, stick_ok := find_powerup_type(powerups[:], .STICK)
	life, life_ok := find_powerup_type(powerups[:], .LIFE)
	fast, fast_ok := find_powerup_type(powerups[:], .FAST)
	bonus, bonus_ok := find_powerup_type(powerups[:], .BONUS)
	testing.expect(t, wide_ok && wide.target == .PAD)
	testing.expect(t, multiply_ok && multiply.target == .BALL)
	testing.expect(t, bomb_ok && bomb.target == .RECT)
	testing.expect(t, stick_ok && stick.target == .PAD)
	testing.expect(t, life_ok && life.target == .PAD)
	testing.expect(t, fast_ok && fast.target == .BALL)
	testing.expect(t, bonus_ok && bonus.target == .BALL)

	types := load_rect_types(RECT_TYPES_PATH, powerups[:])
	defer delete(types)
	testing.expect_value(t, len(types), 10)

	expect_rect(t, types[:], 'B', 1, rl.ORANGE, {})
	expect_rect(t, types[:], 'W', 1, rl.GREEN, {{kind = .WIDE, target = .PAD, chance = 100}})
	expect_rect(t, types[:], 'O', 1, rl.PURPLE, {{kind = .BOMB, target = .RECT, chance = 100}, {kind = .BONUS, target = .BALL, chance = 10}})
	expect_rect(t, types[:], 'I', 1, rl.BROWN, {{kind = .STICK, target = .PAD, chance = 100}})
	expect_rect(t, types[:], 'L', 1, rl.BLUE, {{kind = .LIFE, target = .PAD, chance = 100}})
	expect_rect(t, types[:], 'M', 1, rl.PINK, {{kind = .MULTIPLY, target = .BALL, chance = 100}})
	expect_rect(t, types[:], 'T', 2, rl.YELLOW, {
		{kind = .STICK, target = .PAD, chance = 45},
		{kind = .LIFE, target = .PAD, chance = 20},
	})
	expect_rect(t, types[:], 'S', 3, rl.RED, {
		{kind = .WIDE, target = .PAD, chance = 50},
		{kind = .MULTIPLY, target = .BALL, chance = 30},
	})
	expect_rect(t, types[:], 'U', 10, rl.BLACK, {})
	expect_rect(t, types[:], 'X', 10000, rl.WHITE, {{kind = .BONUS, target = .BALL, chance = 100}})
}

@(test)
test_orthogonal_and_bomb_chain :: proc(t: ^testing.T) {
	a := Brick{x = 0, y = 0}
	right := Brick{x = RECT_W + RECT_GAP, y = 0}
	below := Brick{x = 0, y = RECT_H + RECT_GAP}
	diag := Brick{x = RECT_W + RECT_GAP, y = RECT_H + RECT_GAP}
	far := Brick{x = 2 * (RECT_W + RECT_GAP), y = 0}
	testing.expect(t, orthogonal_bricks(a, right))
	testing.expect(t, orthogonal_bricks(a, below))
	testing.expect(t, !orthogonal_bricks(a, diag))
	testing.expect(t, !orthogonal_bricks(a, far))
	testing.expect(t, !orthogonal_bricks(a, a))

	bomb := Brick_Drop{kind = .BOMB, target = .RECT, chance = 100}
	bricks := make([dynamic]Brick)
	defer delete(bricks)
	// The ball already spent the origin's last hit point. The blast still leaves that brick.
	append(&bricks, bomb_brick(0, 0, 0, bomb))
	append(&bricks, bomb_brick(RECT_W + RECT_GAP, 0, 1, bomb))
	append(&bricks, bomb_brick(0, RECT_H + RECT_GAP, 1, bomb))
	append(&bricks, Brick{x = RECT_W + RECT_GAP, y = RECT_H + RECT_GAP, hp = 5, max_hp = 5})
	append(&bricks, Brick{x = 2 * (RECT_W + RECT_GAP), y = 0, hp = 4, max_hp = 4})

	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	mods: Power_Mods
	score: big.Int
	defer big.destroy(&score)
	big.set(&score, 0)
	explode_from_hit(&bricks, 0, &falling, &mods, &score, 1)

	testing.expect_value(t, bricks[0].hp, i32(0))
	testing.expect_value(t, bricks[1].hp, i32(0))
	testing.expect_value(t, bricks[2].hp, i32(0))
	// Diagonal of the origin, and a side of both chained bombs, so it takes two hits.
	testing.expect_value(t, bricks[3].hp, i32(3))
	// Two steps to the right. Only the first bomb's chain reaches it.
	testing.expect_value(t, bricks[4].hp, i32(3))
	testing.expect_value(t, len(falling), 0)
	expect_score_i64(t, &score, brick_points(1) * 2)

	plain := make([dynamic]Brick)
	defer delete(plain)
	append(&plain, Brick{x = 0, y = 0, hp = 1, max_hp = 1})
	append(&plain, Brick{x = RECT_W + RECT_GAP, y = 0, hp = 4, max_hp = 4})
	explode_from_hit(&plain, 0, &falling, &mods, &score, 1)
	testing.expect_value(t, plain[1].hp, i32(4))

	dud := bomb
	dud.chance = 0
	quiet := make([dynamic]Brick)
	defer delete(quiet)
	append(&quiet, bomb_brick(0, 0, 1, dud))
	append(&quiet, Brick{x = RECT_W + RECT_GAP, y = 0, hp = 4, max_hp = 4})
	explode_from_hit(&quiet, 0, &falling, &mods, &score, 1)
	testing.expect_value(t, quiet[0].hp, i32(1))
	testing.expect_value(t, quiet[1].hp, i32(4))
}

@(test)
test_graze_spends_one_hit_point :: proc(t: ^testing.T) {
	bricks := make([dynamic]Brick)
	defer delete(bricks)
	append(&bricks, Brick{x = 0, y = 0, hp = 10, max_hp = 10})

	// Exactly on the right face, with a shallow velocity into the brick.
	ball := Ball{
		x = RECT_W + BALL_R,
		y = RECT_H / 2,
		vx = -0.2,
		vy = 1,
		alive = true,
	}
	hit, broke, hp_before, index := collideRects(&bricks, &ball)
	testing.expect(t, hit)
	testing.expect(t, !broke)
	testing.expect_value(t, hp_before, i32(10))
	testing.expect_value(t, bricks[0].hp, i32(9))
	testing.expect_value(t, index, 0)
	testing.expect(t, ball.x >= RECT_W + BALL_R + 1)

	for y: i32 = 0; y <= RECT_H; y += 1 {
		ball.y = y
		hit, _, _, _ = collideRects(&bricks, &ball)
		testing.expect(t, !hit)
	}
	testing.expect_value(t, bricks[0].hp, i32(9))

	// One pixel of overlap is still a single hit, then the ball is clear.
	ball.x = RECT_W + BALL_R - 1
	ball.y = RECT_H / 2
	ball.vx = -0.2
	hit, broke, _, _ = collideRects(&bricks, &ball)
	testing.expect(t, hit)
	testing.expect(t, !broke)
	testing.expect_value(t, bricks[0].hp, i32(8))
	hit, _, _, _ = collideRects(&bricks, &ball)
	testing.expect(t, !hit)
	testing.expect_value(t, bricks[0].hp, i32(8))
}

@(test)
test_fast_stick_and_life :: proc(t: ^testing.T) {
	mods: Power_Mods
	apply_powerup(.LIFE, &mods, nil)
	apply_powerup(.LIFE, &mods, nil)
	apply_powerup(.STICK, &mods, nil)
	apply_powerup(.FAST, &mods, nil)
	apply_powerup(.WIDE, &mods, nil)
	testing.expect_value(t, mods.lives, i32(2))
	testing.expect(t, mods.stick)
	testing.expect(t, mods.fast)
	testing.expect_value(t, mods.pad_w, WIDE_STEP)

	balls := make([dynamic]Ball)
	defer delete(balls)
	append(&balls, Ball{speed_x = 1, speed_y = 1, alive = true})
	append(&balls, Ball{speed_x = -1, speed_y = 1, alive = true})
	on_speed_bounce(&balls, &mods)
	testing.expect_value(t, mods.speed_bonus, i32(1))
	testing.expect_value(t, balls[0].speed_x, i32(2))
	testing.expect_value(t, balls[0].speed_y, i32(2))
	testing.expect_value(t, balls[1].speed_x, i32(-2))
	testing.expect_value(t, balls[1].speed_y, i32(2))

	lose_ball(&balls[0], &balls, &mods)
	testing.expect(t, !balls[0].alive)
	testing.expect(t, mods.fast)
	testing.expect_value(t, mods.speed_bonus, i32(1))
	testing.expect_value(t, balls[1].speed_x, i32(-2))
	testing.expect_value(t, balls[1].speed_y, i32(2))

	mods.fast = true
	mods.speed_bonus = 0
	for _ in 0..<int(MAX_BALL_SPEED) {
		on_speed_bounce(&balls, &mods)
	}
	testing.expect_value(t, balls[1].speed_y, MAX_BALL_SPEED)
	testing.expect(t, mods.speed_bonus < MAX_BALL_SPEED)

	// A paddle hit can outrun the shared floor. Another ball's bounce must leave that speed alone.
	kept := make([dynamic]Ball)
	defer delete(kept)
	mods.fast = true
	mods.speed_bonus = 5
	append(&kept, Ball{vx = 40, vy = -10, alive = true})
	append(&kept, Ball{vx = 1, alive = true})
	on_speed_bounce(&kept, &mods)
	testing.expect_value(t, mods.speed_bonus, i32(6))
	testing.expect_value(t, kept[0].vx, f32(40))
	testing.expect_value(t, kept[0].vy, f32(-10))
	testing.expect_value(t, kept[1].speed_x, i32(7))
	testing.expect_value(t, kept[1].speed_y, i32(0))

	lose_ball(&kept[1], &kept, &mods)
	testing.expect(t, mods.fast)
	testing.expect_value(t, mods.speed_bonus, i32(6))
	testing.expect_value(t, kept[0].vx, f32(40))
	testing.expect_value(t, kept[0].vy, f32(-10))
	lose_ball(&kept[0], &kept, &mods)
	testing.expect(t, !mods.fast)
	testing.expect_value(t, mods.speed_bonus, i32(0))

	brick := Brick{x = 10, y = 20, drop_count = 1}
	brick.drops[0] = {kind = .WIDE, target = .PAD, chance = 100}
	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	before := mods.pad_w
	grant_brick_drops(brick, &falling, &mods, nil)
	testing.expect_value(t, len(falling), 1)
	testing.expect(t, falling[0].kind == .WIDE)
	testing.expect_value(t, mods.pad_w, before)

	bomb_only := Brick{drop_count = 1}
	bomb_only.drops[0] = {kind = .BOMB, target = .RECT, chance = 100}
	grant_brick_drops(bomb_only, &falling, &mods, nil)
	testing.expect_value(t, len(falling), 1)
}

bomb_brick :: proc(x, y, hp: i32, drop: Brick_Drop) -> Brick {
	brick := Brick{x = x, y = y, hp = hp, max_hp = hp, drop_count = 1}
	if hp < 1 do brick.max_hp = 1
	brick.drops[0] = drop
	return brick
}

@(test)
test_anim_frames_and_trail :: proc(t: ^testing.T) {
	testing.expect_value(t, trail_alpha(TRAIL_MIN_SPEED), u8(0))
	testing.expect_value(t, trail_alpha(TRAIL_MIN_SPEED - 1), u8(0))
	testing.expect_value(t, trail_alpha(f32(MAX_BALL_SPEED)), u8(255))
	testing.expect(t, trail_alpha(f32(MAX_BALL_SPEED) + 4) == 255)
	low := trail_alpha(TRAIL_MIN_SPEED + 1)
	mid := trail_alpha((TRAIL_MIN_SPEED + f32(MAX_BALL_SPEED)) * 0.5)
	testing.expect(t, low > 0 && low < mid && mid < 255)
	// A ball at this speed already crosses the board in a flash. The trail has to read there.
	testing.expect(t, trail_alpha(24) > 80)
	near := proc(a, b: f32) -> bool {
		d := a - b
		if d < 0 do d = -d
		return d < 0.1
	}
	testing.expect(t, near(trail_angle(1, 0), 0))
	testing.expect(t, near(trail_angle(-1, 0), 180))
	testing.expect(t, near(trail_angle(0, 1), 90))
	testing.expect(t, near(trail_angle(0, -1), -90))

	// Two grid rows in a 4×6 sheet. Playback starts at the lower band.
	width := 4
	height := 6
	colors := make([]rl.Color, width * height)
	defer delete(colors)
	for i in 0..<len(colors) do colors[i] = rl.Color{0, 0, 0, 255}
	for x in 0..<width {
		colors[x] = ANIM_GRID
		colors[3 * width + x] = ANIM_GRID
	}
	frames := anim_frame_rects(colors, width, height)
	defer delete(frames)
	testing.expect_value(t, len(frames), 2)
	testing.expect_value(t, frames[0].y, f32(3))
	testing.expect_value(t, frames[0].height, f32(3))
	testing.expect_value(t, frames[0].width, f32(width))
	testing.expect_value(t, frames[1].y, f32(0))
	testing.expect_value(t, frames[1].height, f32(3))
}

@(test)
test_settle_round_score :: proc(t: ^testing.T) {
	mods := Power_Mods{pad_w = PADW + WIDE_STEP, lives = 2}
	balls := make([dynamic]Ball)
	defer delete(balls)
	append(&balls, Ball{speed_x = 3, speed_y = -1, alive = true})
	append(&balls, Ball{alive = true, stuck = true})
	append(&balls, Ball{speed_x = 9, speed_y = 9, alive = false})
	// 100 + 2, times 10, + 20, - 15, + 200, times 300, then + 30 for the faster ball.
	expect_settled(t, 100, mods, balls[:], 1, 1, 0, "SCORE 367530")

	lost := Power_Mods{pad_w = PADW, lives = 0}
	expect_settled(t, 50, lost, nil, 0, 2, 1, "SCORE -480")

	plain := Power_Mods{pad_w = PADW, lives = 1}
	stuck := make([dynamic]Ball)
	defer delete(stuck)
	append(&stuck, Ball{alive = true, stuck = true})
	// 5 + 10 for the stuck ball, + 100 for the life, times 150. The stuck ball has no speed.
	expect_settled(t, 5, plain, stuck[:], 0, 0, 0, "SCORE 17250")

	// Two extra lengths multiply twice. A life was lost, so the perfect-life term stays off.
	twice := Power_Mods{pad_w = PADW + WIDE_STEP * 2, lives = 0}
	expect_settled(t, 4, twice, nil, 0, 0, 1, "SCORE -100")

	// A leftover under one 50-pixel step is not an extra length.
	partial := Power_Mods{pad_w = PADW + WIDE_STEP - 1, lives = 0}
	expect_settled(t, 4, partial, nil, 0, 0, 1, "SCORE -496")

	// Lives still held, but one was spent, so the score is not multiplied by lives * 150.
	spent := Power_Mods{pad_w = PADW, lives = 3}
	expect_settled(t, 10, spent, nil, 0, 0, 1, "SCORE -190")
	kept := Power_Mods{pad_w = PADW, lives = 3}
	expect_settled(t, 10, kept, nil, 0, 0, 0, "SCORE 139500")

	angled := Power_Mods{pad_w = PADW, lives = 0}
	one := make([dynamic]Ball)
	defer delete(one)
	append(&one, Ball{speed_x = -4, speed_y = 2, alive = true})
	expect_settled(t, 0, angled, one[:], 0, 0, 0, "SCORE 50")

	// Past either end of i64. One extra paddle length, then the ball penalty.
	past := Power_Mods{pad_w = PADW + WIDE_STEP, lives = 0}
	expect_settled(t, 9_223_372_036_854_775_807, past, nil, 0, 1, 0, "SCORE 92233720368547758055")
	expect_settled(t, ~i64(9_223_372_036_854_775_807), past, nil, 0, 0, 0, "SCORE -92233720368547758080")

	// One fast brick times 10, forty times, then the life penalty. This does not fit in i128.
	wide := Power_Mods{pad_w = PADW + WIDE_STEP * 40, lives = 0}
	expect_settled(t, 6_000_000_000_000, wide, nil, 0, 0, 1, "SCORE 59999999999999999999999999999999999999999999999999500")
}

@(test)
test_score_trip :: proc(t: ^testing.T) {
	score: big.Int
	defer big.destroy(&score)
	big.set(&score, 100)
	ball: Ball

	// The first brick after a launch has no bounce behind it.
	note_score_trip_brick(&ball, &score)
	expect_score_i64(t, &score, 100)
	testing.expect(t, ball.from_bounce)

	// The next brick doubles, and that hit starts another trip.
	note_score_trip_brick(&ball, &score)
	expect_score_i64(t, &score, 200)
	note_score_trip_lost(&ball, &score)
	expect_score_i64(t, &score, 100)
	testing.expect(t, !ball.from_bounce)

	// A loss with no open trip leaves the score alone.
	note_score_trip_lost(&ball, &score)
	expect_score_i64(t, &score, 100)

	expect_half(t, 5, 3)
	expect_half(t, 4, 2)
	expect_half(t, 1, 1)
	expect_half(t, 0, 0)
	expect_half(t, -5, -3)
	expect_half(t, -4, -2)
	expect_half(t, -1, -1)

	wide: big.Int
	defer big.destroy(&wide)
	big.set(&wide, "100000000000000000001")
	score_div2_nearest(&wide)
	expect_label(t, &wide, "SCORE 50000000000000000001")
}

@(test)
test_run_overall :: proc(t: ^testing.T) {
	saved_max := round_max_score
	defer round_max_score = saved_max
	round_max_score = 0
	reset_run_score()
	defer reset_run_score()

	first: big.Int
	second: big.Int
	defer big.destroy(&first, &second)
	big.set(&first, 10)
	big.set(&second, -3)
	bank_level_score(&first)
	level_banked = false
	bank_level_score(&second)
	bank_level_score(&second)
	testing.expect_value(t, run_count, 2)
	testing.expect(t, compute_run_overall(&run_overall))
	// (10 + -3) * 2
	expect_score_i64(t, &run_overall, 14)

	reset_run_score()
	testing.expect(t, compute_run_overall(&run_overall))
	expect_score_i64(t, &run_overall, 0)

	// A lost level is banked like a clear, and its cap hits stay on the run.
	round_max_score = 4
	lost: big.Int
	defer big.destroy(&lost)
	big.set(&lost, 25)
	bank_level_score(&lost)
	testing.expect_value(t, run_count, 1)
	testing.expect_value(t, run_max_score, i64(4))
	testing.expect(t, compute_run_overall(&run_overall))
	expect_score_i64(t, &run_overall, 25)

	level_banked = false
	round_max_score = 3
	next: big.Int
	defer big.destroy(&next)
	big.set(&next, 2)
	bank_level_score(&next)
	testing.expect_value(t, run_max_score, i64(7))
	testing.expect(t, compute_run_overall(&run_overall))
	// (25 + 2) * 2
	expect_score_i64(t, &run_overall, 54)
}

@(test)
test_saved_score_line :: proc(t: ^testing.T) {
	old, ok := parse_saved_score_line("2026-10-07 15:04:05=12345")
	defer delete(old.text)
	defer delete(old.stamp)
	testing.expect(t, ok && !old.detailed)
	testing.expect_value(t, old.text, "12345")
	testing.expect_value(t, old.max_score, i64(-1))

	bare, bare_ok := parse_saved_score_line("-7")
	defer delete(bare.text)
	defer delete(bare.stamp)
	testing.expect(t, bare_ok && bare.text == "-7" && !bare.detailed)

	full, full_ok := parse_saved_score_line("2026-10-07 15:04:05=0;17;40;L")
	defer delete(full.text)
	defer delete(full.stamp)
	testing.expect(t, full_ok && full.detailed && full.result == .LOST)
	testing.expect_value(t, full.text, "0")
	testing.expect_value(t, full.max_score, i64(17))
	testing.expect_value(t, full.level, 40)

	won, won_ok := parse_saved_score_line("9;2;100;W")
	defer delete(won.text)
	defer delete(won.stamp)
	testing.expect(t, won_ok && won.result == .WON)
	testing.expect_value(t, won.max_score, i64(2))
	testing.expect_value(t, won.level, 100)

	_, bad := parse_saved_score_line("12;1;2;X")
	testing.expect(t, !bad)
	_, junk := parse_saved_score_line("nope")
	testing.expect(t, !junk)
}

expect_half :: proc(t: ^testing.T, start, want: i64) {
	score: big.Int
	defer big.destroy(&score)
	big.set(&score, start)
	score_div2_nearest(&score)
	expect_score_i64(t, &score, want)
}

expect_settled :: proc(t: ^testing.T, start: i64, mods: Power_Mods, balls: []Ball, powerups, balls_lost, lives_lost: i64, want: string) {
	score: big.Int
	defer big.destroy(&score)
	big.set(&score, start)
	settle_round_score(&score, mods, balls, powerups, balls_lost, lives_lost)
	expect_label(t, &score, want)
}

expect_score_i64 :: proc(t: ^testing.T, score: ^big.Int, want: i64) {
	other: big.Int
	defer big.destroy(&other)
	big.set(&other, want)
	same, err := big.int_equals(score, &other)
	testing.expect(t, err == big.Error.None && same)
}

expect_label :: proc(t: ^testing.T, score: ^big.Int, want: string) {
	_, backing := format_score_label(score)
	defer delete(backing)
	ok := len(backing) == len(want) + 1 && backing[len(want)] == 0
	if ok {
		for i in 0..<len(want) {
			if backing[i] != u8(want[i]) {
				ok = false
				break
			}
		}
	}
	testing.expect(t, ok)
}

@(test)
test_round_powerup_and_ball_tallies :: proc(t: ^testing.T) {
	round_powerups = 0
	mods: Power_Mods
	apply_powerup(.WIDE, &mods, nil)
	apply_powerup(.LIFE, &mods, nil)
	testing.expect_value(t, round_powerups, i64(0))

	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	ball_drop := Brick{drop_count = 2}
	ball_drop.drops[0] = {kind = .FAST, target = .BALL, chance = 100}
	ball_drop.drops[1] = {kind = .LIFE, target = .BALL, chance = 100}
	grant_brick_drops(ball_drop, &falling, &mods, nil)
	testing.expect_value(t, round_powerups, i64(2))

	pad_drop := Brick{drop_count = 1}
	pad_drop.drops[0] = {kind = .WIDE, target = .PAD, chance = 100}
	grant_brick_drops(pad_drop, &falling, &mods, nil)
	testing.expect_value(t, round_powerups, i64(2))
	testing.expect_value(t, len(falling), 1)

	bomb_drop := Brick{drop_count = 1}
	bomb_drop.drops[0] = {kind = .BOMB, target = .RECT, chance = 100}
	grant_brick_drops(bomb_drop, &falling, &mods, nil)
	testing.expect_value(t, round_powerups, i64(2))

	mods.pad_w = 80
	falling[0].x = 16
	falling[0].y = 16
	update_falling_powerups(&falling, 0, 0, 20, &mods, 0, nil)
	testing.expect_value(t, round_powerups, i64(3))
	testing.expect_value(t, len(falling), 0)

	before := round_balls_lost
	balls := make([dynamic]Ball)
	defer delete(balls)
	append(&balls, Ball{alive = true})
	lose_ball(&balls[0], &balls, &mods)
	testing.expect_value(t, round_balls_lost, before + 1)
	lose_ball(&balls[0], &balls, &mods)
	testing.expect_value(t, round_balls_lost, before + 1)
	serve_ball(&balls, 0, PADW)
	testing.expect_value(t, round_balls_lost, before + 1)
}

@(test)
test_brick_sound_variant :: proc(t: ^testing.T) {
	testing.expect_value(t, brick_sound_variant("basic_rect"), i32(0))
	testing.expect_value(t, brick_sound_variant("rect_wide"), i32(0))
	testing.expect_value(t, brick_sound_variant("rect_bomb"), i32(0))
	testing.expect_value(t, brick_sound_variant("rect_stick"), i32(0))
	testing.expect_value(t, brick_sound_variant("rect_life"), i32(0))
	testing.expect_value(t, brick_sound_variant("rect_multiply"), i32(0))
	testing.expect_value(t, brick_sound_variant("rect_fast"), i32(0))
	testing.expect_value(t, brick_sound_variant("tough_rect"), i32(0))
	testing.expect_value(t, brick_sound_variant("strong_rect"), i32(1))
	testing.expect_value(t, brick_sound_variant("super_rect"), i32(1))
	testing.expect_value(t, brick_sound_variant("tough"), i32(0))
	testing.expect_value(t, brick_sound_variant(""), i32(0))
}

@(test)
test_super_powerups :: proc(t: ^testing.T) {
	saved := run_super_count
	defer {
		run_super_count = saved
		brick_shake_left = 0
	}
	clear_super_powerups()
	ensure_super_powerups()
	testing.expect_value(t, len(super_bands), 3)

	double_band: Super_Band
	explode_band: Super_Band
	targeting_band: Super_Band
	for band in super_bands {
		switch band.kind {
		case .DOUBLE: double_band = band
		case .EXPLODE: explode_band = band
		case .TARGETING: targeting_band = band
		}
	}
	testing.expect_value(t, double_band.from_x, i32(1))
	testing.expect_value(t, double_band.to_x, i32(50))
	testing.expect_value(t, explode_band.from_x, i32(4))
	testing.expect_value(t, explode_band.to_x, i32(12))
	testing.expect_value(t, targeting_band.from_x, i32(5))
	testing.expect_value(t, targeting_band.to_x, i32(10))
	testing.expect_value(t, targeting_band.chance, i32(10))
	testing.expect_value(t, targeting_band.chance_step, i32(5))

	testing.expect_value(t, super_hit_damage(), i32(1))
	testing.expect_value(t, super_explode_radius(), i32(0))
	testing.expect(t, !super_targeting_active())

	add_super_powerup()
	testing.expect_value(t, run_super_count, i32(1))
	testing.expect_value(t, super_hit_damage(), i32(2))
	add_super_powerup()
	testing.expect_value(t, super_hit_damage(), i32(4))
	run_super_count = 3
	testing.expect_value(t, super_hit_damage(), i32(8))
	run_super_count = 4
	testing.expect_value(t, super_hit_damage(), i32(16))
	testing.expect_value(t, super_explode_radius(), i32(1))
	testing.expect(t, !super_targeting_active())
	run_super_count = 5
	testing.expect(t, super_targeting_active())
	testing.expect_value(t, super_targeting_chance(), i32(10))
	testing.expect_value(t, super_explode_radius(), i32(2))
	testing.expect_value(t, super_hit_damage(), i32(32))
	run_super_count = 7
	testing.expect_value(t, super_explode_radius(), i32(4))
	testing.expect_value(t, super_targeting_chance(), i32(10))
	run_super_count = 10
	testing.expect_value(t, super_targeting_chance(), i32(10))
	testing.expect_value(t, super_explode_radius(), i32(7))
	run_super_count = 11
	testing.expect_value(t, super_targeting_chance(), i32(15))
	testing.expect_value(t, super_explode_radius(), i32(8))
	run_super_count = 12
	testing.expect_value(t, super_explode_radius(), i32(9))
	testing.expect_value(t, super_targeting_chance(), i32(20))
	run_super_count = 13
	testing.expect_value(t, super_explode_radius(), i32(9))
	testing.expect_value(t, super_targeting_chance(), i32(25))
	run_super_count = 28
	testing.expect_value(t, super_targeting_chance(), i32(100))
	saturated := i32(1) << 30
	run_super_count = 30
	testing.expect_value(t, super_hit_damage(), saturated)
	run_super_count = 50
	testing.expect_value(t, super_hit_damage(), saturated)
	testing.expect_value(t, super_explode_radius(), i32(9))
	testing.expect_value(t, super_targeting_chance(), i32(100))
	run_super_count = 51
	testing.expect_value(t, super_hit_damage(), saturated)
	clear_super_powerups()
	testing.expect_value(t, run_super_count, i32(0))
	testing.expect_value(t, super_hit_damage(), i32(1))

	step := RECT_W + RECT_GAP
	rise := RECT_H + RECT_GAP
	origin := Brick{x = 0, y = 0, hp = 10}
	right := Brick{x = step, y = 0, hp = 5}
	far := Brick{x = step * 2, y = 0, hp = 5}
	diag := Brick{x = step, y = rise, hp = 5}
	testing.expect_value(t, brick_step_dist(origin, right), i32(1))
	testing.expect_value(t, brick_step_dist(origin, far), i32(2))
	testing.expect_value(t, brick_step_dist(origin, diag), i32(2))
	testing.expect_value(t, brick_step_dist(origin, origin), i32(0))

	bricks := make([dynamic]Brick)
	defer delete(bricks)
	append(&bricks, Brick{x = 0, y = 0, hp = 10, max_hp = 10})
	append(&bricks, Brick{x = step, y = 0, hp = 5, max_hp = 5})
	append(&bricks, Brick{x = step * 2, y = 0, hp = 5, max_hp = 5})
	append(&bricks, Brick{x = step, y = rise, hp = 5, max_hp = 5})
	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	mods: Power_Mods
	run_super_count = 4
	super_blast(&bricks, 0, &falling, &mods, nil, 1)
	testing.expect_value(t, bricks[0].hp, i32(10))
	testing.expect_value(t, bricks[1].hp, i32(4))
	testing.expect_value(t, bricks[2].hp, i32(5))
	testing.expect_value(t, bricks[3].hp, i32(5))
	run_super_count = 5
	super_blast(&bricks, 0, &falling, &mods, nil, 1)
	testing.expect_value(t, bricks[0].hp, i32(10))
	testing.expect_value(t, bricks[1].hp, i32(3))
	testing.expect_value(t, bricks[2].hp, i32(4))
	testing.expect_value(t, bricks[3].hp, i32(4))

	run_super_count = 1
	one := make([dynamic]Brick)
	defer delete(one)
	append(&one, Brick{x = 0, y = 0, hp = 10, max_hp = 10})
	ball := Ball{x = RECT_W / 2, y = RECT_H / 2, vx = 1, vy = -1, alive = true}
	_, broke, before, _ := collideRects(&one, &ball)
	testing.expect(t, !broke)
	testing.expect_value(t, before, i32(10))
	testing.expect_value(t, one[0].hp, i32(8))

	clear_super_powerups()
	grant_debug_super(.DOUBLE)
	testing.expect_value(t, run_super_count, i32(1))
	testing.expect_value(t, super_hit_damage(), i32(2))
	grant_debug_super(.DOUBLE)
	grant_debug_super(.DOUBLE)
	grant_debug_super(.DOUBLE)
	testing.expect_value(t, run_super_count, i32(4))
	testing.expect_value(t, super_hit_damage(), i32(16))

	clear_super_powerups()
	grant_debug_super(.EXPLODE)
	testing.expect_value(t, run_super_count, i32(4))
	testing.expect_value(t, super_hit_damage(), i32(16))
	testing.expect_value(t, super_explode_radius(), i32(1))
	testing.expect(t, !super_targeting_active())
	grant_debug_super(.EXPLODE)
	testing.expect_value(t, run_super_count, i32(5))
	testing.expect_value(t, super_explode_radius(), i32(2))
	testing.expect(t, super_targeting_active())
	testing.expect_value(t, super_targeting_chance(), i32(10))

	clear_super_powerups()
	grant_debug_super(.TARGETING)
	testing.expect_value(t, run_super_count, i32(5))
	testing.expect(t, super_targeting_active())
	testing.expect_value(t, super_targeting_chance(), i32(10))
	testing.expect_value(t, super_explode_radius(), i32(2))
	testing.expect_value(t, super_hit_damage(), i32(32))
	grant_debug_super(.TARGETING)
	testing.expect_value(t, run_super_count, i32(6))
	testing.expect_value(t, super_targeting_chance(), i32(10))
	run_super_count = 10
	grant_debug_super(.TARGETING)
	testing.expect_value(t, run_super_count, i32(11))
	testing.expect_value(t, super_targeting_chance(), i32(15))
	run_super_count = 28
	grant_debug_super(.TARGETING)
	testing.expect_value(t, run_super_count, i32(28))
	testing.expect_value(t, super_targeting_chance(), i32(100))
}

// A targeting success aims along the straight line to the brick and keeps speed.
// A ball still touching the pad does not aim back into it. A shallow angle still advances,
// because the fractional carry is kept.
@(test)
test_targeting_bounce_keeps_leaving :: proc(t: ^testing.T) {
	pad_left: i32 = 300
	pad_w: i32 = 200
	// The pad center sits back inside the surface the ball is touching.
	pad_x := pad_left + pad_w / 2
	pad_y := PAD_TOP

	centered := Ball {
		x = pad_x,
		y = PAD_TOP - BALL_R,
		vx = 0,
		vy = -1,
		alive = true,
	}
	aim_ball_at_point(&centered, pad_x, pad_y, 0, -1, pad_left, pad_w)
	testing.expect(t, centered.vy <= -1 + 0.01)
	testing.expect(t, abs(centered.vx) < 0.01)

	// Beside the pad, the line to the pad center is the heading, including a downward component.
	off := Ball{x = 40, y = PAD_TOP - BALL_R, vx = 0.2, vy = -1, alive = true}
	aim_ball_at_point(&off, pad_x, pad_y, 0.2, -1, pad_left, pad_w)
	testing.expect(t, off.vx > 0.9)
	testing.expect(t, off.vy > 0 && off.vy < 0.1)

	ceiling := Ball{x = 40, y = -1, vx = 0, vy = 1, alive = true}
	aim_ball_at_point(&ceiling, pad_x, pad_y, 0, 1, pad_left, pad_w)
	testing.expect(t, ceiling.vx > 0.4)
	testing.expect(t, ceiling.vy > 0.7 && ceiling.vy < 1)

	left := Ball{x = -1, y = 80, vx = 1, vy = -0.25, alive = true}
	aim_ball_at_point(&left, pad_x, pad_y, 1, -0.25, pad_left, pad_w)
	testing.expect(t, left.vx > 0.5)
	testing.expect(t, left.vy > 0.6)

	right := Ball{x = SCREEN_RIGHT + 1, y = 80, vx = -1, vy = 0.4, alive = true}
	aim_ball_at_point(&right, pad_x, pad_y, -1, 0.4, pad_left, pad_w)
	testing.expect(t, right.vx < -0.5)
	testing.expect(t, right.vy > 0.6)

	diag := Ball{x = 40, y = 80, vx = 0.6, vy = -0.8, alive = true}
	aim_ball_at_point(&diag, pad_x, pad_y, 0.6, -0.8, pad_left, pad_w)
	speed_sq := diag.vx * diag.vx + diag.vy * diag.vy
	testing.expect(t, speed_sq > 0.96 && speed_sq < 1.04)
	testing.expect(t, diag.vx > 0.5)
	testing.expect(t, diag.vy > 0.7)

	// Open space turns onto the line, even when that reverses the old velocity.
	free := Ball{x = 100, y = 100, vx = 1, vy = 0, alive = true}
	aim_ball_at_point(&free, 100, 40, 1, 0, pad_left, pad_w)
	testing.expect(t, free.vy < -0.9)
	testing.expect(t, abs(free.vx) < 0.1)

	across := Ball{x = 200, y = 200, vx = 1, vy = 0, alive = true}
	aim_ball_at_point(&across, 80, 80, 1, 0, pad_left, pad_w)
	testing.expect(t, across.vx < -0.6)
	testing.expect(t, across.vy < -0.6)

	// Still touching: steering may not slow the leaving axis.
	on_ceiling := Ball{x = 10, y = -1, vx = 0, vy = 1}
	_, held_vy := hold_targeting_departure(on_ceiling, 0.2, 0.2, pad_left, pad_w)
	testing.expect(t, held_vy >= 1 - 0.001)

	on_pad := Ball{x = 400, y = PAD_TOP - BALL_R, vx = 0, vy = -1}
	_, held_up := hold_targeting_departure(on_pad, 0, 1, pad_left, pad_w)
	testing.expect(t, held_up <= -1 + 0.001)

	on_left := Ball{x = -1, y = 80, vx = 1, vy = 0}
	held_right, _ := hold_targeting_departure(on_left, -0.5, 0.5, pad_left, pad_w)
	testing.expect(t, held_right >= 1 - 0.001)

	open := Ball{x = 400, y = 200, vx = 0, vy = -1}
	_, turned := hold_targeting_departure(open, 0.2, 0.4, pad_left, pad_w)
	testing.expect(t, turned == 0.4)

	// Two frames of a sub-pixel axis move one pixel when nothing clears the carry.
	shallow := Ball{vx = 0.6, vy = -0.6}
	mx0, my0 := consume_ball_motion(&shallow)
	mx1, my1 := consume_ball_motion(&shallow)
	testing.expect_value(t, mx0, i32(0))
	testing.expect_value(t, my0, i32(0))
	testing.expect_value(t, mx1, i32(1))
	testing.expect_value(t, my1, i32(-1))
}

@(test)
test_total_stamp_label :: proc(t: ^testing.T) {
	buf: [32]byte
	text, ok := total_date_label("2026-10-07 00:05:09", &buf)
	testing.expect(t, ok)
	testing.expect_value(t, string(text), "10/07/2026 12:05:09 AM")
	text, ok = total_date_label("2026-10-07 12:00:00", &buf)
	testing.expect(t, ok)
	testing.expect_value(t, string(text), "10/07/2026 12:00:00 PM")
	text, ok = total_date_label("2026-10-07 15:04:05", &buf)
	testing.expect(t, ok)
	testing.expect_value(t, string(text), "10/07/2026 3:04:05 PM")
	text, ok = total_date_label("2026-01-02 01:02:03", &buf)
	testing.expect(t, ok)
	testing.expect_value(t, string(text), "01/02/2026 1:02:03 AM")
	text, ok = total_date_label("2026-10-07 23:59:59", &buf)
	testing.expect(t, ok)
	testing.expect_value(t, string(text), "10/07/2026 11:59:59 PM")
	text, ok = total_date_label("2026-10-07", &buf)
	testing.expect(t, ok)
	testing.expect_value(t, string(text), "10/07/2026")
	_, ok = total_date_label("", &buf)
	testing.expect(t, !ok)
}

expect_rect :: proc(t: ^testing.T, types: []Rect_Type, symbol: rune, hp: i32, color: rl.Color, drops: []Brick_Drop) {
	got, ok := find_rect_type(types, symbol)
	testing.expectf(t, ok, "missing rect %c", symbol)
	if !ok do return
	testing.expectf(t, got.hp == hp, "%c hp %v", symbol, got.hp)
	testing.expectf(t, got.color == color, "%c color", symbol)
	testing.expectf(t, got.drop_count == len(drops), "%c drops %v", symbol, got.drop_count)
	n := got.drop_count
	if len(drops) < n do n = len(drops)
	for i in 0..<n {
		drop := got.drops[i]
		want := drops[i]
		testing.expectf(t, drop.kind == want.kind && drop.target == want.target && drop.chance == want.chance, "%c drop %v", symbol, i)
	}
}
