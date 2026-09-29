package src

import "core:fmt"
import "core:math/rand"
import "core:os"
import rl "vendor:raylib"

POWERUP_TYPES_PATH :: "src/powerup_types.txt"

// "Widen pad by '1'": one caught pickup adds one step of width.
WIDE_STEP: i32 = 50
MULTIPLY_SECONDS :: 10.0
MAX_BALLS :: 32

// Slow compared with the ball, which moves one pixel per frame.
DROP_SPEED :: 90.0
DROP_W :: 28
DROP_H :: 16

Powerup_Target :: enum {
	PAD,
	BALL,
}

Powerup_Kind :: enum {
	WIDE,
	MULTIPLY,
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
	data, err := os.read_entire_file(path, context.allocator)
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

roll_percent :: proc(chance: i32) -> bool {
	if chance <= 0 do return false
	if chance >= 100 do return true
	return rand.int_max(100) < int(chance)
}

apply_powerup :: proc(kind: Powerup_Kind, pad_w: ^i32, multiply_until: ^f64) {
	switch kind {
	case .WIDE:
		pad_w^ += WIDE_STEP
		if pad_w^ > SCW - 40 do pad_w^ = SCW - 40
	case .MULTIPLY:
		multiply_until^ = rl.GetTime() + MULTIPLY_SECONDS
	}
}

// Roll the brick's drop list. PAD drops start falling. BALL drops apply now.
grant_brick_drops :: proc(brick: Brick, falling: ^[dynamic]Falling_Powerup, pad_w: ^i32, multiply_until: ^f64) {
	for i in 0..<brick.drop_count {
		drop := brick.drops[i]
		if !roll_percent(drop.chance) do continue
		switch drop.target {
		case .PAD:
			append(falling, Falling_Powerup{
				x = f32(brick.x + RECT_W / 2) + f32(i * 16),
				y = f32(brick.y + RECT_H / 2),
				kind = drop.kind,
			})
		case .BALL:
			apply_powerup(drop.kind, pad_w, multiply_until)
		}
	}
}

rects_overlap :: proc(ax, ay, aw, ah, bx, by, bw, bh: i32) -> bool {
	return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
}

update_falling_powerups :: proc(drops: ^[dynamic]Falling_Powerup, pad_left, pad_top, pad_h: i32, pad_w: ^i32, dt: f32, multiply_until: ^f64) {
	for i := len(drops) - 1; i >= 0; i -= 1 {
		drops[i].y += DROP_SPEED * dt
		left := i32(drops[i].x) - DROP_W / 2
		top := i32(drops[i].y) - DROP_H / 2
		if top > SCH {
			ordered_remove(drops, i)
			continue
		}
		if rects_overlap(left, top, DROP_W, DROP_H, pad_left, pad_top, pad_w^, pad_h) {
			apply_powerup(drops[i].kind, pad_w, multiply_until)
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
			speed_x = -parent.speed_x,
			speed_y = parent.speed_y,
			alive = true,
		})
		spawned += 1
	}
}

render_falling_powerups :: proc(drops: [dynamic]Falling_Powerup) {
	for drop in drops {
		left := i32(drop.x) - DROP_W / 2
		top := i32(drop.y) - DROP_H / 2
		rl.DrawRectangle(left, top, DROP_W, DROP_H, rl.GOLD)
		text: cstring = "W"
		if drop.kind == .MULTIPLY do text = "M"
		size: i32 = 16
		width := rl.MeasureText(text, size)
		rl.DrawText(text, left + (DROP_W - width) / 2, top + (DROP_H - size) / 2, size, rl.BLACK)
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
	rl.DrawText(cstring(&buf[0]), 16, 16, 20, rl.YELLOW)
}
