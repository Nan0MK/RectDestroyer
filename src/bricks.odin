package src

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

RECT_W: i32 = 70; RECT_H: i32 = 50
RECT_GAP: i32 = 5
RECT_TOP: i32 = 40
RECT_TYPES_PATH :: "src/rect_types.txt"

MAX_DROPS :: 8

// A powerup this brick type can release, with its percent chance.
Brick_Drop :: struct {
	kind:   Powerup_Kind,
	target: Powerup_Target,
	chance: i32,
}

// One row in rect_types.txt. Level characters spawn this hit-point count, color, and drops.
// texture is src/textures/<name>.png. A missing file leaves it empty and the color is drawn instead.
Rect_Type :: struct {
	symbol:     rune,
	hp:         i32,
	color:      rl.Color,
	texture:    rl.Texture2D,
	drops:      [MAX_DROPS]Brick_Drop,
	drop_count: int,
	// 0 plays hit_0 and destroy_0. 1 is strong and super. Tough stays on 0.
	sound:      i32,
	// Picture is the matching sheet in src/textures/animations instead of a flat texture.
	anim:       bool,
}

// One brick per level-file cell. Rows break on newlines. Space and '.' are empty cells.
// hp falls by 1 on each hit. The brick is gone at 0.
// sound is copied from the type. A ball hit plays that variant.
Brick :: struct {
	x, y:       i32,
	kind:       rune,
	hp, max_hp: i32,
	color:      rl.Color,
	texture:    rl.Texture2D,
	drops:      [MAX_DROPS]Brick_Drop,
	drop_count: int,
	sound:      i32,
	// Picture is the matching sheet in src/textures/animations instead of a flat texture.
	anim:       bool,
}

// Loaded once and reused across levels. The name is the rect_types.txt name.
Rect_Texture :: struct {
	name:    string,
	texture: rl.Texture2D,
}

rect_textures: [dynamic]Rect_Texture
crack_textures: [3]rl.Texture2D
crack_textures_loaded: bool

color_from_name :: proc(name: string) -> (rl.Color, bool) {
	switch name {
	case "GREEN": return rl.GREEN, true
	case "DARKGREEN": return rl.DARKGREEN, true
	case "LIME": return rl.LIME, true
	case "RED": return rl.RED, true
	case "MAROON": return rl.MAROON, true
	case "ORANGE": return rl.ORANGE, true
	case "YELLOW": return rl.YELLOW, true
	case "GOLD": return rl.GOLD, true
	case "BLUE": return rl.BLUE, true
	case "DARKBLUE": return rl.DARKBLUE, true
	case "SKYBLUE": return rl.SKYBLUE, true
	case "PURPLE": return rl.PURPLE, true
	case "DARKPURPLE": return rl.DARKPURPLE, true
	case "VIOLET": return rl.VIOLET, true
	case "PINK": return rl.PINK, true
	case "MAGENTA": return rl.MAGENTA, true
	case "GRAY", "GREY": return rl.GRAY, true
	case "DARKGRAY": return rl.DARKGRAY, true
	case "WHITE": return rl.WHITE, true
	case "BLACK": return rl.BLACK, true
	case "BEIGE": return rl.BEIGE, true
	case "BROWN": return rl.BROWN, true
	case: return {}, false
	}
}

default_rect_color :: proc(symbol: rune) -> rl.Color {
	switch symbol {
	case 'B': return rl.ORANGE
	case 'W': return rl.GREEN
	case 'O': return rl.PURPLE
	case 'I': return rl.BROWN
	case 'L': return rl.BLUE
	case 'M': return rl.PINK
	case 'T': return rl.YELLOW
	case 'S': return rl.RED
	case 'U': return rl.BLACK
	case: return rl.WHITE
	}
}

// Cells are placed on a fixed step, so a side neighbor shares one axis and differs by one step on the other.
orthogonal_bricks :: proc(a, b: Brick) -> bool {
	dx := a.x - b.x
	if dx < 0 do dx = -dx
	dy := a.y - b.y
	if dy < 0 do dy = -dy
	step_x := RECT_W + RECT_GAP
	step_y := RECT_H + RECT_GAP
	return (dx == step_x && dy == 0) || (dx == 0 && dy == step_y)
}

// Manhattan distance in grid steps. An orthogonal neighbor is 1. A diagonal is 2.
// A brick that is not on the same grid is too far to be in a blast.
brick_step_dist :: proc(a, b: Brick) -> i32 {
	dx := a.x - b.x
	if dx < 0 do dx = -dx
	dy := a.y - b.y
	if dy < 0 do dy = -dy
	step_x := RECT_W + RECT_GAP
	step_y := RECT_H + RECT_GAP
	if step_x < 1 do step_x = 1
	if step_y < 1 do step_y = 1
	if dx % step_x != 0 || dy % step_y != 0 do return max(i32)
	return dx / step_x + dy / step_y
}

skip_ws :: proc(s: string, index: int) -> int {
	i := index
	for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
		i += 1
	}
	return i
}

read_token :: proc(s: string, index: int) -> (token: string, next: int) {
	i := skip_ws(s, index)
	start := i
	for i < len(s) && s[i] != ' ' && s[i] != '\t' {
		i += 1
	}
	return s[start:i], i
}

find_rect_type :: proc(types: []Rect_Type, symbol: rune) -> (Rect_Type, bool) {
	for t in types {
		if t.symbol == symbol do return t, true
	}
	return {}, false
}

trim_space :: proc(s: string) -> string {
	a := skip_ws(s, 0)
	b := len(s)
	for b > a && (s[b - 1] == ' ' || s[b - 1] == '\t') {
		b -= 1
	}
	return s[a:b]
}

// rest is the color and the `{...}` group after the hit points.
parse_type_tail :: proc(rest: string, symbol: rune, powerups: []Powerup_Type) -> (color: rl.Color, drops: [MAX_DROPS]Brick_Drop, drop_count: int, ok: bool) {
	color = default_rect_color(symbol)
	ok = true
	text := trim_space(rest)
	if len(text) == 0 do return

	if text[0] != '{' {
		tok, next := read_token(text, 0)
		parsed, known := color_from_name(tok)
		if !known {
			fmt.eprintf("Brick type '%c' has unknown color '%s'\n", symbol, tok)
			ok = false
			return
		}
		color = parsed
		text = trim_space(text[next:])
	}
	drops, drop_count, ok = parse_drop_tail(text, powerups)
	return
}

add_rect_type :: proc(types: ^[dynamic]Rect_Type, line: string, powerups: []Powerup_Type) {
	i := skip_ws(line, 0)
	if i >= len(line) || line[i] == '#' do return

	symbol := rune(line[i])
	i = skip_ws(line, i + 1)
	if i < len(line) && line[i] == '=' {
		i += 1
	}

	name, next := read_token(line, i)
	i = next
	if len(name) == 0 {
		fmt.eprintf("Brick type '%c' is missing a name\n", symbol)
		return
	}

	hp: i32 = 1
	hp_tok, next_hp := read_token(line, i)
	i = next_hp
	if len(hp_tok) > 0 {
		value, ok := strconv.parse_int(hp_tok, 10)
		if !ok || value < 1 {
			fmt.eprintf("Brick type '%c' has invalid hit points '%s'\n", symbol, hp_tok)
			return
		}
		hp = i32(value)
	}

	color, drops, drop_count, ok := parse_type_tail(line[i:], symbol, powerups)
	if !ok do return

	if _, exists := find_rect_type(types[:], symbol); exists {
		fmt.eprintf("Duplicate brick type '%c'\n", symbol)
		return
	}
	append(types, Rect_Type{
		symbol = symbol,
		hp = hp,
		color = color,
		texture = texture_for_rect_name(name),
		drops = drops,
		drop_count = drop_count,
		sound = brick_sound_variant(name),
		anim = rect_anim_available(name),
	})
}

texture_path :: proc(name: string, buf: ^[128]byte) -> cstring {
	prefix := "src/textures/"
	suffix := ".png"
	n := 0
	for ch in prefix {
		buf[n] = u8(ch)
		n += 1
	}
	for ch in name {
		buf[n] = u8(ch)
		n += 1
	}
	for ch in suffix {
		buf[n] = u8(ch)
		n += 1
	}
	buf[n] = 0
	return cstring(&buf[0])
}

load_texture_file :: proc(path: cstring) -> rl.Texture2D {
	tex := rl.LoadTexture(path)
	if tex.id == 0 {
		fmt.eprintf("Failed to load texture '%s'\n", path)
		return {}
	}
	rl.SetTextureFilter(tex, .POINT)
	return tex
}

ensure_crack_textures :: proc() {
	if crack_textures_loaded || !rl.IsWindowReady() do return
	crack_textures_loaded = true
	crack_textures[0] = load_texture_file("src/textures/crack_0.png")
	crack_textures[1] = load_texture_file("src/textures/crack_1.png")
	crack_textures[2] = load_texture_file("src/textures/crack_2.png")
}

// The type name is the file stem: basic_rect loads src/textures/basic_rect.png.
// A missing file is cached, so a later level does not warn again. The flat color is drawn instead.
texture_for_rect_name :: proc(name: string) -> rl.Texture2D {
	ensure_crack_textures()
	if !rl.IsWindowReady() do return {}
	for entry in rect_textures {
		if entry.name == name do return entry.texture
	}
	if len(name) == 0 || len(name) > 100 do return {}

	buf: [128]byte
	tex := load_texture_file(texture_path(name, &buf))
	key := strings.clone(name) or_else ""
	append(&rect_textures, Rect_Texture{name = key, texture = tex})
	return tex
}

ink_for :: proc(c: rl.Color) -> rl.Color {
	if int(c.r) + int(c.g) + int(c.b) < 200 do return rl.WHITE
	return rl.BLACK
}

unload_rect_textures :: proc() {
	for entry in rect_textures {
		if entry.texture.id != 0 do rl.UnloadTexture(entry.texture)
		delete(entry.name)
	}
	delete(rect_textures)
	if crack_textures_loaded {
		for tex in crack_textures {
			if tex.id != 0 do rl.UnloadTexture(tex)
		}
		crack_textures = {}
		crack_textures_loaded = false
	}
}

// Nearest-neighbor scale. Brick cells, the ball, and falling drops all use this.
draw_texture_rect :: proc(tex: rl.Texture2D, x, y, w, h: i32) {
	src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
	dst := rl.Rectangle{f32(x), f32(y), f32(w), f32(h)}
	rl.DrawTexturePro(tex, src, dst, {}, 0, rl.WHITE)
}

draw_brick_texture :: proc(tex: rl.Texture2D, x, y: i32) {
	draw_texture_rect(tex, x, y, RECT_W, RECT_H)
}

// None at full health. crack_0, crack_1, then crack_2 as more of the hit points are gone.
crack_for_brick :: proc(brick: Brick) -> (rl.Texture2D, bool) {
	if !crack_textures_loaded || brick.max_hp <= 1 || brick.hp <= 0 || brick.hp >= brick.max_hp {
		return {}, false
	}
	lost_pct := int((brick.max_hp - brick.hp) * 100 / brick.max_hp)
	index := 0
	if lost_pct > 66 do index = 2
	else if lost_pct > 33 do index = 1
	tex := crack_textures[index]
	if tex.id == 0 do return {}, false
	return tex, true
}

load_rect_types :: proc(path: string, powerups: []Powerup_Type) -> [dynamic]Rect_Type {
	types := make([dynamic]Rect_Type)
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
			add_rect_type(&types, line, powerups)
			start = i + 1
		}
	}
	return types
}

brick_draw_color :: proc(brick: Brick) -> rl.Color {
	if brick.max_hp <= 1 || brick.hp >= brick.max_hp do return brick.color
	kept := int((100 * brick.hp) / brick.max_hp)
	if kept < 50 do kept = 50
	c := brick.color
	return {
		u8((int(c.r) * kept) / 100),
		u8((int(c.g) * kept) / 100),
		u8((int(c.b) * kept) / 100),
		c.a,
	}
}

format_hp :: proc(hp: i32, buf: ^[12]byte) -> cstring {
	n := hp
	if n < 0 do n = 0
	if n == 0 {
		buf[0] = '0'
		buf[1] = 0
		return cstring(&buf[0])
	}
	tmp: [12]byte
	count := 0
	for n > 0 && count < len(tmp) {
		tmp[count] = u8('0') + u8(n % 10)
		n /= 10
		count += 1
	}
	for i in 0..<count {
		buf[i] = tmp[count - 1 - i]
	}
	buf[count] = 0
	return cstring(&buf[0])
}

generateRects :: proc(level: string) -> [dynamic]Brick {
	powerups := load_powerup_types(POWERUP_TYPES_PATH)
	defer delete(powerups)
	types := load_rect_types(RECT_TYPES_PATH, powerups[:])
	defer delete(types)

	inData, err := os.read_entire_file_or_err(level, context.allocator)
	if err != nil {
		fmt.eprintf("Failed to read '%s': %v\n", level, err)
		return {}
	}
	defer delete(inData)

	text := string(inData)

	cols: i32 = 0
	col: i32 = 0
	for ch in text {
		switch ch {
		case '\n':
			if col > cols do cols = col
			col = 0
		case '\r':
		case:
			col += 1
		}
	}
	if col > cols do cols = col

	grid_w := cols * RECT_W
	if cols > 1 do grid_w += (cols - 1) * RECT_GAP
	origin_x := (SCW - grid_w) / 2
	if origin_x < 0 do origin_x = 0

	bricks := make([dynamic]Brick)
	col = 0
	row: i32 = 0
	for ch in text {
		switch ch {
		case '\n':
			col = 0
			row += 1
		case '\r':
		case ' ', '.':
			col += 1
		case:
			if t, ok := find_rect_type(types[:], ch); ok {
				append(&bricks, Brick{
					x = origin_x + col * (RECT_W + RECT_GAP),
					y = RECT_TOP + row * (RECT_H + RECT_GAP),
					kind = ch,
					hp = t.hp,
					max_hp = t.hp,
					color = t.color,
					texture = t.texture,
					drops = t.drops,
					drop_count = t.drop_count,
					sound = t.sound,
					anim = t.anim,
				})
			}
			col += 1
		}
	}
	return bricks
}

// shake moves the pictures only. Collision still uses each brick's stored x and y.
renderRects :: proc(bricks: [dynamic]Brick, shake: bool) {
	ox, oy := brick_shake_offset(shake)
	for brick in bricks {
		if brick.hp <= 0 do continue
		x := brick.x + ox
		y := brick.y + oy
		if brick.anim {
			if tex, src, ok := hyper_rect_frame(); ok {
				dst := rl.Rectangle{f32(x), f32(y), f32(RECT_W), f32(RECT_H)}
				rl.DrawTexturePro(tex, src, dst, {}, 0, rl.WHITE)
				if crack, crack_ok := crack_for_brick(brick); crack_ok {
					draw_brick_texture(crack, x, y)
				}
				continue
			}
		}
		if brick.texture.id != 0 {
			draw_brick_texture(brick.texture, x, y)
			if crack, ok := crack_for_brick(brick); ok {
				draw_brick_texture(crack, x, y)
			}
		} else {
			fill := brick_draw_color(brick)
			rl.DrawRectangle(x, y, RECT_W, RECT_H, fill)
			ink := ink_for(fill)
			// A black brick matches the background, so the outline is what shows the cell.
			if int(fill.r) + int(fill.g) + int(fill.b) < 80 {
				rl.DrawRectangleLines(x, y, RECT_W, RECT_H, rl.GRAY)
			}
			size: i32 = 24
			if brick.max_hp > 1 {
				buf: [12]byte
				text := format_hp(brick.hp, &buf)
				width := measure_text(text, size)
				draw_text(text, x + (RECT_W - width) / 2, y + (RECT_H - size) / 2, size, ink)
			} else {
				mark: [2]byte
				mark[0] = u8(brick.kind)
				mark[1] = 0
				text := cstring(&mark[0])
				width := measure_text(text, size)
				draw_text(text, x + (RECT_W - width) / 2, y + (RECT_H - size) / 2, size, ink)
			}
		}
	}
}

// Bounce the ball off the nearest brick it overlaps, then spend the ball's damage.
// That is one hit point until a double super powerup raises it.
// Side comes from the shortest way out of the brick so a top hit flips vertical speed.
// hp_before is the brick's hit points before this hit. broke is true when it reaches 0.
collideRects :: proc(bricks: ^[dynamic]Brick, ball: ^Ball) -> (hit: bool, broke: bool, hp_before: i32, brick_index: int) {
	bx := ball.x
	by := ball.y
	brick_index = -1

	hit_index := -1
	hit_dx, hit_dy: i32
	hit_dist_sq: i32

	for &brick, i in bricks {
		if brick.hp <= 0 do continue

		left := brick.x
		right := brick.x + RECT_W
		top := brick.y
		bot := brick.y + RECT_H

		closest_x := bx
		if closest_x < left do closest_x = left
		else if closest_x > right do closest_x = right
		closest_y := by
		if closest_y < top do closest_y = top
		else if closest_y > bot do closest_y = bot

		dx := bx - closest_x
		dy := by - closest_y
		dist_sq := dx*dx + dy*dy
		if dist_sq > BALL_R*BALL_R do continue
		if hit_index >= 0 && dist_sq >= hit_dist_sq do continue

		hit_index = i
		hit_dx = dx
		hit_dy = dy
		hit_dist_sq = dist_sq
	}
	if hit_index < 0 do return false, false, 0, -1

	brick := &bricks[hit_index]
	hp_before = brick.hp
	brick_index = hit_index
	left := brick.x
	right := brick.x + RECT_W
	top := brick.y
	bot := brick.y + RECT_H

	// sep < 0 means push toward the top or left of the screen.
	sep_x, sep_y: i32
	if hit_dx == 0 && hit_dy == 0 {
		dist_left := bx - left
		dist_right := right - bx
		dist_top := by - top
		dist_bot := bot - by
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
	} else if abs(hit_dx) >= abs(hit_dy) {
		sep_x = 1 if hit_dx > 0 else -1
	} else {
		sep_y = 1 if hit_dy > 0 else -1
	}

	// One pixel past the circle's edge. Sitting exactly on the face still counts as a hit,
	// so a shallow slide along that face would spend a hit point on every later step.
	if sep_x < 0 {
		ball.x = left - BALL_R - 1
		if ball.vx > 0 do ball.vx = -ball.vx
	} else if sep_x > 0 {
		ball.x = right + BALL_R + 1
		if ball.vx < 0 do ball.vx = -ball.vx
	}

	if sep_y < 0 {
		ball.y = top - BALL_R - 1
		if ball.vy > 0 do ball.vy = -ball.vy
	} else if sep_y > 0 {
		ball.y = bot + BALL_R + 1
		if ball.vy < 0 do ball.vy = -ball.vy
	}
	note_ball_velocity(ball)

	if brick.hp > 0 {
		spent := super_hit_damage()
		if spent < 1 do spent = 1
		if spent > brick.hp do spent = brick.hp
		brick.hp -= spent
	}
	return true, brick.hp <= 0, hp_before, brick_index
}
