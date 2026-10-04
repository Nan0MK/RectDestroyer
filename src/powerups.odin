package src

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strconv"
import rl "vendor:raylib"

POWERUP_TYPES_PATH :: "src/powerup_types.txt"

// "Widen pad by '1'": one caught pickup adds one step of width.
WIDE_STEP: i32 = 50
MULTIPLY_SECONDS :: 10.0
MAX_BALLS :: 32

// Slow compared with the ball, which moves one pixel per frame until fast raises it.
DROP_SPEED :: 90.0
DROP_W :: 28
DROP_H :: 16

// fast adds 1 to every living ball's faster axis on each bounce, up to MAX_BALL_SPEED.
// A paddle launch without fast stops at NORMAL_MAX_SPEED. 8 keeps the per-pixel steps short.
MAX_BALL_SPEED: i32 = 8
NORMAL_MAX_SPEED: i32 = 3

Powerup_Target :: enum {
	PAD,  // falls, and applies if the paddle catches it
	BALL, // applies as soon as the brick breaks
	RECT, // stays on the brick and runs when that brick is hit
}

Powerup_Kind :: enum {
	WIDE,
	MULTIPLY,
	BOMB,
	STICK,
	LIFE,
	FAST,
}

// Collected state for the run. A new level clears everything here except lives, when the caller asks to keep them.
Power_Mods :: struct {
	pad_w:          i32,
	multiply_until: f64,
	stick:          bool,
	fast:           bool,
	speed_bonus:    i32,
	lives:          i32,
}

Powerup_Type :: struct {
	kind:   Powerup_Kind,
	target: Powerup_Target,
}

// A PAD powerup falling from the brick that released it.
Falling_Powerup :: struct {
	x, y: f32,
	kind: Powerup_Kind,
}

powerup_kind_from_name :: proc(name: string) -> (Powerup_Kind, bool) {
	switch name {
	case "wide": return .WIDE, true
	case "multiply": return .MULTIPLY, true
	case "bomb": return .BOMB, true
	case "stick": return .STICK, true
	case "life": return .LIFE, true
	case "fast": return .FAST, true
	case: return {}, false
	}
}

find_powerup_type :: proc(types: []Powerup_Type, kind: Powerup_Kind) -> (Powerup_Type, bool) {
	for t in types {
		if t.kind == kind do return t, true
	}
	return {}, false
}

add_powerup_type :: proc(types: ^[dynamic]Powerup_Type, line: string) {
	i := skip_ws(line, 0)
	if i >= len(line) || line[i] == '#' do return

	name, next := read_token(line, i)
	target_tok, _ := read_token(line, next)
	kind, known := powerup_kind_from_name(name)
	if !known {
		fmt.eprintf("Unknown powerup '%s'\n", name)
		return
	}
	target: Powerup_Target
	switch target_tok {
	case "PAD": target = .PAD
	case "BALL": target = .BALL
	case "RECT": target = .RECT
	case:
		fmt.eprintf("Powerup '%s' has unknown target '%s'\n", name, target_tok)
		return
	}
	if _, exists := find_powerup_type(types[:], kind); exists {
		fmt.eprintf("Duplicate powerup '%s'\n", name)
		return
	}
	append(types, Powerup_Type{kind = kind, target = target})
}

load_powerup_types :: proc(path: string) -> [dynamic]Powerup_Type {
	types := make([dynamic]Powerup_Type)
	data, err := os.read_entire_file_or_err(path, context.allocator)
	if err != nil {
		fmt.eprintf("Failed to read '%s': %v\n", path, err)
		return types
	}
	defer delete(data)

	text := string(data)
	start := 0
	for i := 0; i <= len(text); i += 1 {
		if i == len(text) || text[i] == '\n' {
			line := text[start:i]
			if n := len(line); n > 0 && line[n - 1] == '\r' {
				line = line[:n - 1]
			}
			add_powerup_type(&types, line)
			start = i + 1
		}
	}
	return types
}

parse_percent :: proc(tok: string) -> (i32, bool) {
	s := tok
	if len(s) > 0 && s[len(s) - 1] == '%' {
		s = s[:len(s) - 1]
	}
	value, ok := strconv.parse_int(s, 10)
	if !ok || value < 0 do return 0, false
	if value > 100 do value = 100
	return i32(value), true
}

// text is the `{wide 5%, multiply 3%}` group from a brick type, or empty.
parse_drop_tail :: proc(text: string, powerups: []Powerup_Type) -> (drops: [MAX_DROPS]Brick_Drop, count: int, ok: bool) {
	ok = true
	body_src := trim_space(text)
	if len(body_src) == 0 do return
	if body_src[0] != '{' {
		fmt.eprintf("Broken powerup list '%s'\n", body_src)
		ok = false
		return
	}
	close := -1
	for i in 1..<len(body_src) {
		if body_src[i] == '}' {
			close = i
			break
		}
	}
	if close < 0 || trim_space(body_src[close + 1:]) != "" {
		fmt.eprintf("Broken powerup list '%s'\n", body_src)
		ok = false
		return
	}

	body := body_src[1:close]
	start := 0
	for i := 0; i <= len(body); i += 1 {
		if i < len(body) && body[i] != ',' do continue
		piece := trim_space(body[start:i])
		start = i + 1
		if len(piece) == 0 do continue
		if count >= MAX_DROPS {
			fmt.eprintf("Too many powerups in '%s'\n", piece)
			ok = false
			return
		}
		name, next := read_token(piece, 0)
		chance_tok, _ := read_token(piece, next)
		if len(name) == 0 || len(chance_tok) == 0 {
			fmt.eprintf("Powerup drop '%s' needs a name and a percent\n", piece)
			ok = false
			return
		}
		kind, known := powerup_kind_from_name(name)
		if !known {
			fmt.eprintf("Unknown powerup '%s'\n", name)
			ok = false
			return
		}
		powerup, found := find_powerup_type(powerups, kind)
		if !found {
			fmt.eprintf("Powerup '%s' is not listed in powerup_types.txt\n", name)
			ok = false
			return
		}
		chance, parsed := parse_percent(chance_tok)
		if !parsed {
			fmt.eprintf("Powerup '%s' has invalid chance '%s'\n", name, chance_tok)
			ok = false
			return
		}
		drops[count] = Brick_Drop{kind = kind, target = powerup.target, chance = chance}
		count += 1
	}
	return
}

roll_percent :: proc(chance: i32) -> bool {
	if chance <= 0 do return false
	if chance >= 100 do return true
	return rand.int_max(100) < int(chance)
}

apply_powerup :: proc(kind: Powerup_Kind, mods: ^Power_Mods) {
	switch kind {
	case .WIDE:
		mods.pad_w += WIDE_STEP
		if mods.pad_w > SCW - 40 do mods.pad_w = SCW - 40
	case .MULTIPLY:
		mods.multiply_until = rl.GetTime() + MULTIPLY_SECONDS
	case .STICK:
		mods.stick = true
	case .LIFE:
		mods.lives += 1
	case .FAST:
		mods.fast = true
	case .BOMB:
		// Bomb is a RECT effect. It runs from the hit, not from a catch.
	}
}

// Roll the brick's drop list. PAD drops start falling. BALL drops apply now. RECT effects already ran on the hit.
grant_brick_drops :: proc(brick: Brick, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods) {
	for i in 0..<brick.drop_count {
		drop := brick.drops[i]
		if drop.target == .RECT do continue
		if !roll_percent(drop.chance) do continue
		switch drop.target {
		case .PAD:
			append(falling, Falling_Powerup{
				x = f32(brick.x + RECT_W / 2) + f32(i * 16),
				y = f32(brick.y + RECT_H / 2),
				kind = drop.kind,
			})
		case .BALL:
			apply_powerup(drop.kind, mods)
		case .RECT:
		}
	}
}

bomb_chance :: proc(brick: Brick) -> (chance: i32, ok: bool) {
	for i in 0..<brick.drop_count {
		drop := brick.drops[i]
		if drop.kind == .BOMB {
			return drop.chance, true
		}
	}
	return 0, false
}

// Queue a bomb whose hit roll succeeds. Each brick explodes at most once per chain.
consider_bomb :: proc(bricks: ^[dynamic]Brick, index: int, exploded: []bool, queue: ^[dynamic]int) {
	if index < 0 || index >= len(exploded) || exploded[index] do return
	chance, is_bomb := bomb_chance(bricks[index])
	if !is_bomb do return
	if !roll_percent(chance) do return
	exploded[index] = true
	append(queue, index)
}

damage_from_blast :: proc(bricks: ^[dynamic]Brick, index: int, exploded: []bool, queue: ^[dynamic]int, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods, score: ^i64, elapsed_ns: i64) {
	brick := &bricks[index]
	if brick.hp <= 0 do return
	brick.hp -= 1
	consider_bomb(bricks, index, exploded, queue)
	if brick.hp <= 0 {
		grant_brick_drops(brick^, falling, mods)
		score^ += brick_points(elapsed_ns)
	}
}

// The hit brick explodes when its bomb roll succeeds. Orthogonal neighbors take 1 HP.
// A neighbor that is itself a bomb can explode from that hit. Diagonal bricks are left alone.
explode_from_hit :: proc(bricks: ^[dynamic]Brick, origin: int, falling: ^[dynamic]Falling_Powerup, mods: ^Power_Mods, score: ^i64, elapsed_ns: i64) {
	if origin < 0 || origin >= len(bricks) do return
	_, is_bomb := bomb_chance(bricks[origin])
	if !is_bomb do return

	exploded := make([]bool, len(bricks))
	defer delete(exploded)
	queue := make([dynamic]int)
	defer delete(queue)

	consider_bomb(bricks, origin, exploded, &queue)
	for head := 0; head < len(queue); head += 1 {
		src := queue[head]
		for j in 0..<len(bricks) {
			if j == src || bricks[j].hp <= 0 do continue
			if !orthogonal_bricks(bricks[src], bricks[j]) do continue
			damage_from_blast(bricks, j, exploded, &queue, falling, mods, score, elapsed_ns)
		}
	}
}

// Scales the velocity so the faster axis is `mag`. The angle stays.
// A ball that only has the integer speeds filled in, as the tests do, copies those in first.
set_speed_mag :: proc(ball: ^Ball, mag: i32) {
	speed := mag
	if speed < 1 do speed = 1
	if speed > MAX_BALL_SPEED do speed = MAX_BALL_SPEED
	if ball.vx == 0 && ball.vy == 0 {
		ball.vx = f32(ball.speed_x)
		ball.vy = f32(ball.speed_y)
	}
	ax := abs(ball.vx)
	ay := abs(ball.vy)
	peak := ax
	if ay > peak do peak = ay
	if peak < 0.001 {
		ball.vx = 0
		ball.vy = -f32(speed)
	} else {
		scale := f32(speed) / peak
		ball.vx *= scale
		ball.vy *= scale
	}
	note_ball_velocity(ball)
}

reset_live_speeds :: proc(balls: ^[dynamic]Ball) {
	for i in 0..<len(balls) {
		if balls[i].alive do set_speed_mag(&balls[i], 1)
	}
}

// fast shares one speed across every living ball. Losing a ball turns fast off and clears the bonus.
on_speed_bounce :: proc(balls: ^[dynamic]Ball, mods: ^Power_Mods) {
	if !mods.fast do return
	if mods.speed_bonus + 1 < MAX_BALL_SPEED do mods.speed_bonus += 1
	mag := 1 + mods.speed_bonus
	for i in 0..<len(balls) {
		if balls[i].alive do set_speed_mag(&balls[i], mag)
	}
}

lose_ball :: proc(ball: ^Ball, balls: ^[dynamic]Ball, mods: ^Power_Mods) {
	ball.alive = false
	ball.stuck = false
	mods.fast = false
	mods.speed_bonus = 0
	reset_live_speeds(balls)
}

rects_overlap :: proc(ax, ay, aw, ah, bx, by, bw, bh: i32) -> bool {
	return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
}

update_falling_powerups :: proc(drops: ^[dynamic]Falling_Powerup, pad_left, pad_top, pad_h: i32, mods: ^Power_Mods, dt: f32) {
	for i := len(drops) - 1; i >= 0; i -= 1 {
		drops[i].y += DROP_SPEED * dt
		left := i32(drops[i].x) - DROP_W / 2
		top := i32(drops[i].y) - DROP_H / 2
		if top > SCH {
			ordered_remove(drops, i)
			continue
		}
		if rects_overlap(left, top, DROP_W, DROP_H, pad_left, pad_top, mods.pad_w, pad_h) {
			apply_powerup(drops[i].kind, mods)
			ordered_remove(drops, i)
		}
	}
}

// Double the living balls. New balls leave the hit with the opposite horizontal speed.
spawn_multiplied_balls :: proc(balls: ^[dynamic]Ball, hit_x, hit_y: i32) {
	original := len(balls)
	alive := 0
	for i in 0..<original {
		if balls[i].alive do alive += 1
	}
	room := MAX_BALLS - alive
	if room <= 0 do return

	spawned := 0
	for i in 0..<original {
		if spawned >= room do return
		if !balls[i].alive do continue
		parent := balls[i]
		append(balls, Ball{
			x = hit_x + i32(spawned * 12) - 6,
			y = hit_y,
			vx = -parent.vx,
			vy = parent.vy,
			alive = true,
		})
		note_ball_velocity(&balls[len(balls) - 1])
		spawned += 1
	}
}

powerup_mark :: proc(kind: Powerup_Kind) -> (text: cstring, fill: rl.Color) {
	switch kind {
	case .WIDE: text, fill = "W", rl.GOLD
	case .MULTIPLY: text, fill = "M", rl.YELLOW
	case .BOMB: text, fill = "B", rl.PURPLE
	case .STICK: text, fill = "S", rl.BROWN
	case .LIFE: text, fill = "L", rl.SKYBLUE
	case .FAST: text, fill = "F", rl.ORANGE
	}
	return
}

render_falling_powerups :: proc(drops: [dynamic]Falling_Powerup) {
	for drop in drops {
		left := i32(drop.x) - DROP_W / 2
		top := i32(drop.y) - DROP_H / 2
		text, fill := powerup_mark(drop.kind)
		rl.DrawRectangle(left, top, DROP_W, DROP_H, fill)
		size: i32 = 16
		width := rl.MeasureText(text, size)
		rl.DrawText(text, left + (DROP_W - width) / 2, top + (DROP_H - size) / 2, size, rl.BLACK)
	}
}

format_prefixed :: proc(prefix: string, value: i32, buf: ^[24]byte) -> cstring {
	n := 0
	for ch in prefix {
		if n >= len(buf) - 1 do break
		buf[n] = u8(ch)
		n += 1
	}
	v := value
	if v < 0 do v = 0
	tmp: [12]byte
	count := 0
	if v == 0 {
		tmp[0] = '0'
		count = 1
	} else {
		for v > 0 && count < len(tmp) {
			tmp[count] = u8('0') + u8(v % 10)
			v /= 10
			count += 1
		}
	}
	for i := count - 1; i >= 0; i -= 1 {
		if n >= len(buf) - 1 do break
		buf[n] = tmp[i]
		n += 1
	}
	buf[n] = 0
	return cstring(&buf[0])
}

// Lives sit under the x2 timer. Stick and fast are drawn only while they are on.
render_power_status :: proc(mods: Power_Mods) {
	y := px(40)
	step := px(24)
	size := px(20)
	left := px(16)
	buf: [24]byte
	lives := format_prefixed("LIVES ", mods.lives, &buf)
	rl.DrawText(lives, left, y, size, rl.SKYBLUE)
	y += step
	if mods.stick {
		rl.DrawText("STICK", left, y, size, rl.BEIGE)
		y += step
	}
	if mods.fast {
		fast_buf: [24]byte
		label := format_prefixed("FAST ", 1 + mods.speed_bonus, &fast_buf)
		rl.DrawText(label, left, y, size, rl.ORANGE)
	}
}

render_multiply_timer :: proc(until: f64) {
	left := until - rl.GetTime()
	if left <= 0 do return
	secs := i32(left + 0.999)
	if secs < 1 do secs = 1
	if secs > 99 do secs = 99
	buf: [8]byte
	buf[0] = 'x'
	buf[1] = '2'
	buf[2] = ' '
	n := 3
	if secs >= 10 {
		buf[n] = u8('0') + u8(secs / 10)
		n += 1
	}
	buf[n] = u8('0') + u8(secs % 10)
	n += 1
	buf[n] = 0
	rl.DrawText(cstring(&buf[0]), px(16), px(16), px(20), rl.YELLOW)
}
