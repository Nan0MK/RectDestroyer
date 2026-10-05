package src

import big "core:math/big"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_powerup_and_rect_config :: proc(t: ^testing.T) {
	powerups := load_powerup_types(POWERUP_TYPES_PATH)
	defer delete(powerups)
	testing.expect_value(t, len(powerups), 6)

	wide, wide_ok := find_powerup_type(powerups[:], .WIDE)
	multiply, multiply_ok := find_powerup_type(powerups[:], .MULTIPLY)
	bomb, bomb_ok := find_powerup_type(powerups[:], .BOMB)
	stick, stick_ok := find_powerup_type(powerups[:], .STICK)
	life, life_ok := find_powerup_type(powerups[:], .LIFE)
	fast, fast_ok := find_powerup_type(powerups[:], .FAST)
	testing.expect(t, wide_ok && wide.target == .PAD)
	testing.expect(t, multiply_ok && multiply.target == .BALL)
	testing.expect(t, bomb_ok && bomb.target == .RECT)
	testing.expect(t, stick_ok && stick.target == .PAD)
	testing.expect(t, life_ok && life.target == .PAD)
	testing.expect(t, fast_ok && fast.target == .BALL)

	types := load_rect_types(RECT_TYPES_PATH, powerups[:])
	defer delete(types)
	testing.expect_value(t, len(types), 9)

	expect_rect(t, types[:], 'B', 1, rl.ORANGE, {})
	expect_rect(t, types[:], 'W', 1, rl.GREEN, {{kind = .WIDE, target = .PAD, chance = 100}})
	expect_rect(t, types[:], 'O', 1, rl.PURPLE, {{kind = .BOMB, target = .RECT, chance = 100}})
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
	apply_powerup(.LIFE, &mods)
	apply_powerup(.LIFE, &mods)
	apply_powerup(.STICK, &mods)
	apply_powerup(.FAST, &mods)
	apply_powerup(.WIDE, &mods)
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
	grant_brick_drops(brick, &falling, &mods)
	testing.expect_value(t, len(falling), 1)
	testing.expect(t, falling[0].kind == .WIDE)
	testing.expect_value(t, mods.pad_w, before)

	bomb_only := Brick{drop_count = 1}
	bomb_only.drops[0] = {kind = .BOMB, target = .RECT, chance = 100}
	grant_brick_drops(bomb_only, &falling, &mods)
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
	apply_powerup(.WIDE, &mods)
	apply_powerup(.LIFE, &mods)
	testing.expect_value(t, round_powerups, i64(0))

	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	ball_drop := Brick{drop_count = 2}
	ball_drop.drops[0] = {kind = .FAST, target = .BALL, chance = 100}
	ball_drop.drops[1] = {kind = .LIFE, target = .BALL, chance = 100}
	grant_brick_drops(ball_drop, &falling, &mods)
	testing.expect_value(t, round_powerups, i64(2))

	pad_drop := Brick{drop_count = 1}
	pad_drop.drops[0] = {kind = .WIDE, target = .PAD, chance = 100}
	grant_brick_drops(pad_drop, &falling, &mods)
	testing.expect_value(t, round_powerups, i64(2))
	testing.expect_value(t, len(falling), 1)

	bomb_drop := Brick{drop_count = 1}
	bomb_drop.drops[0] = {kind = .BOMB, target = .RECT, chance = 100}
	grant_brick_drops(bomb_drop, &falling, &mods)
	testing.expect_value(t, round_powerups, i64(2))

	mods.pad_w = 80
	falling[0].x = 16
	falling[0].y = 16
	update_falling_powerups(&falling, 0, 0, 20, &mods, 0)
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
