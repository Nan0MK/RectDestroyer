package src

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// A chip is a piece of the brick a ball just hit. The texture stays owned by the brick loader.
// A standing brick throws fewer chips than one this hit removes.
HIT_CHIPS :: 8
DESTROY_CHIPS :: 24
CHIP_MAX :: 256
CHIP_GRAVITY :: 280.0

Brick_Chip :: struct {
	x, y:       f32,
	vx, vy:     f32,
	life:       f32,
	max_life:   f32,
	size:       f32,
	src:        rl.Rectangle,
	tex:        rl.Texture2D,
	color:      rl.Color,
}

brick_chips: [dynamic]Brick_Chip

clear_brick_chips :: proc() {
	clear(&brick_chips)
}

free_brick_chips :: proc() {
	delete(brick_chips)
}

chip_patch :: proc(tex: rl.Texture2D) -> rl.Rectangle {
	w := int(tex.width)
	h := int(tex.height)
	if tex.id == 0 || w < 2 || h < 2 {
		return {0, 0, f32(tex.width), f32(tex.height)}
	}
	sw := w / 2
	if sw < 8 do sw = w
	sh := h / 2
	if sh < 6 do sh = h
	extra_w := sw / 2
	if extra_w < 1 do extra_w = 1
	sw = sw / 2 + rand.int_max(extra_w)
	if sw < 4 do sw = w
	if sw > w do sw = w
	extra_h := sh / 2
	if extra_h < 1 do extra_h = 1
	sh = sh / 2 + rand.int_max(extra_h)
	if sh < 4 do sh = h
	if sh > h do sh = h
	sx := 0
	if w > sw do sx = rand.int_max(w - sw + 1)
	sy := 0
	if h > sh do sy = rand.int_max(h - sh + 1)
	return {f32(sx), f32(sy), f32(sw), f32(sh)}
}

// broke throws the larger burst from all over the cell. A hit that leaves the brick
// throws the smaller burst from the face the ball struck.
spawn_brick_chips :: proc(brick: Brick, broke: bool, ball_x, ball_y: i32) {
	count := HIT_CHIPS
	speed_lo: f32 = 70
	speed_hi: f32 = 150
	life_lo: f32 = 0.22
	life_hi: f32 = 0.36
	size_lo: f32 = 5
	size_hi: f32 = 8
	if broke {
		count = DESTROY_CHIPS
		speed_lo = 120
		speed_hi = 260
		life_lo = 0.40
		life_hi = 0.65
		size_lo = 8
		size_hi = 14
	}
	for _ in 0..<count {
		for len(brick_chips) >= CHIP_MAX {
			ordered_remove(&brick_chips, 0)
		}
		x := f32(ball_x)
		y := f32(ball_y)
		if broke {
			x = f32(brick.x) + rand.float32() * f32(RECT_W)
			y = f32(brick.y) + rand.float32() * f32(RECT_H)
		} else {
			if x < f32(brick.x) do x = f32(brick.x)
			if y < f32(brick.y) do y = f32(brick.y)
			if x > f32(brick.x + RECT_W) do x = f32(brick.x + RECT_W)
			if y > f32(brick.y + RECT_H) do y = f32(brick.y + RECT_H)
			x += rand.float32_range(-4, 4)
			y += rand.float32_range(-4, 4)
		}
		dx := x - f32(brick.x + RECT_W / 2)
		dy := y - f32(brick.y + RECT_H / 2)
		dist := math.sqrt(dx * dx + dy * dy)
		if dist < 1 {
			dx = rand.float32_range(-1, 1)
			dy = rand.float32_range(-1, 1)
			dist = math.sqrt(dx * dx + dy * dy)
			if dist < 0.001 do dist = 1
		}
		dx /= dist
		dy /= dist
		dx += rand.float32_range(-0.45, 0.45)
		dy += rand.float32_range(-0.25, 0.55)
		speed := rand.float32_range(speed_lo, speed_hi)
		life := rand.float32_range(life_lo, life_hi)
		append(&brick_chips, Brick_Chip{
			x = x,
			y = y,
			vx = dx * speed,
			vy = dy * speed,
			life = life,
			max_life = life,
			size = rand.float32_range(size_lo, size_hi),
			src = chip_patch(brick.texture),
			tex = brick.texture,
			color = brick.color,
		})
	}
}

update_brick_chips :: proc(dt: f32) {
	if dt <= 0 do return
	for i := len(brick_chips) - 1; i >= 0; i -= 1 {
		chip := &brick_chips[i]
		chip.life -= dt
		if chip.life <= 0 {
			unordered_remove(&brick_chips, i)
			continue
		}
		chip.vy += CHIP_GRAVITY * dt
		chip.x += chip.vx * dt
		chip.y += chip.vy * dt
	}
}

render_brick_chips :: proc() {
	for chip in brick_chips {
		fade := chip.life / chip.max_life
		if fade < 0 do fade = 0
		if fade > 1 do fade = 1
		a := u8(fade * 255)
		scale := 0.55 + 0.45 * fade
		size := chip.size * scale
		dst := rl.Rectangle{chip.x, chip.y, size, size}
		origin := rl.Vector2{size * 0.5, size * 0.5}
		if chip.tex.id != 0 {
			rl.DrawTexturePro(chip.tex, chip.src, dst, origin, 0, {255, 255, 255, a})
		} else {
			rl.DrawRectanglePro(dst, origin, 0, {chip.color[0], chip.color[1], chip.color[2], a})
		}
	}
}
