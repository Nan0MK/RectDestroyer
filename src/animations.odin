package src

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// Sheets in src/textures/animations. Magenta (255, 0, 255) is the grid.
// Those pixels are cleared, and the frames play from the bottom of the sheet toward the top.
ANIM_GRID :: rl.Color{255, 0, 255, 255}
ANIM_FRAME_DT :: 1.0 / 12.0
// Hidden at this speed and below. A still launch is 1.
TRAIL_MIN_SPEED :: f32(1.5)
// The sheet is short. Drawn at its own width it is a thin sliver, so the frame is stretched this many times wider.
TRAIL_STRETCH :: i32(3)
BALL_LOST_SCALE :: i32(3)
ANIM_PLAY_MAX :: 128

Anim_Kind :: enum {
	BALL_LOST,
	BALL_TRAIL,
	EXPLODE,
	LIFE_LOST,
	HYPER_RECT,
}

Anim_Clip :: struct {
	tex:    rl.Texture2D,
	frames: [dynamic]rl.Rectangle,
}

// One playing sheet. x, y is the anchor for that kind: the ball's x for ball_lost,
// the life icon's top-left for life_lost, and the brick's top-left for explode.
// size is the explode square, fixed when the blast starts.
// finale is the last life: drawn huge at the center while the board stays frozen.
// layered is a super explode: drawn behind the bricks, and again at half alpha in front of them.
Anim_Play :: struct {
	kind:    Anim_Kind,
	x, y:    i32,
	size:    i32,
	age:     f32,
	finale:  bool,
	layered: bool,
}

clips: [Anim_Kind]Anim_Clip
anims_loaded: bool
plays: [dynamic]Anim_Play
trail_age: f32
hyper_age: f32
// Looping frames of ball_sp_0, ball_sp_1, and ball_sp_2. Held while the board is frozen.
ball_sp_age: f32

// Rows that are mostly the grid start a frame. The returned list plays bottom to top.
anim_frame_rects :: proc(colors: []rl.Color, width, height: int) -> [dynamic]rl.Rectangle {
	frames := make([dynamic]rl.Rectangle)
	if width < 1 || height < 1 || len(colors) < width * height {
		return frames
	}

	rows := make([dynamic]int)
	defer delete(rows)
	for y in 0..<height {
		pink := 0
		row := y * width
		for x in 0..<width {
			if colors[row + x] == ANIM_GRID do pink += 1
		}
		if pink * 2 > width do append(&rows, y)
	}

	spans := make([dynamic][2]int)
	defer delete(spans)
	if len(rows) == 0 {
		append(&spans, [2]int{0, height})
	} else {
		if rows[0] > 0 do append(&spans, [2]int{0, rows[0]})
		for i in 0..<len(rows) {
			y := rows[i]
			y2 := height
			if i + 1 < len(rows) do y2 = rows[i + 1]
			if y2 > y do append(&spans, [2]int{y, y2 - y})
		}
	}

	for i := len(spans) - 1; i >= 0; i -= 1 {
		append(&frames, rl.Rectangle{
			x = 0,
			y = f32(spans[i][0]),
			width = f32(width),
			height = f32(spans[i][1]),
		})
	}
	return frames
}

// A sheet whose PNG has no magenta grid declares its cell size in the sibling `.animation` text as `WxH`.
frame_size_from_details :: proc(png_path: string) -> (w, h: int, ok: bool) {
	if len(png_path) < 5 || png_path[len(png_path) - 4:] != ".png" do return
	details := strings.concatenate({png_path[:len(png_path) - 4], ".animation"})
	defer delete(details)
	data, ok_read := os.read_entire_file(details)
	if !ok_read do return
	defer delete(data)

	text := string(data)
	for i := 0; i < len(text); {
		for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\r' || text[i] == '\n' || text[i] == '.') {
			i += 1
		}
		j := i
		for j < len(text) && text[j] != ' ' && text[j] != '\t' && text[j] != '\r' && text[j] != '\n' && text[j] != '.' {
			j += 1
		}
		tok := text[i:j]
		i = j
		if len(tok) == 0 {
			i += 1
			continue
		}
		xpos := -1
		for ci := 0; ci < len(tok); ci += 1 {
			if tok[ci] == 'x' {
				xpos = ci
				break
			}
		}
		if xpos <= 0 || xpos >= len(tok) - 1 do continue
		wv, wok := parse_positive_int(tok[:xpos])
		hv, hok := parse_positive_int(tok[xpos + 1:])
		if wok && hok {
			return wv, hv, true
		}
	}
	return
}

parse_positive_int :: proc(s: string) -> (int, bool) {
	if len(s) == 0 do return 0, false
	v := 0
	for ch in s {
		if ch < '0' || ch > '9' do return 0, false
		v = v * 10 + int(ch - '0')
	}
	return v, v > 0
}

load_anim_clip :: proc(path: cstring) -> Anim_Clip {
	img := rl.LoadImage(path)
	if img.data == nil {
		fmt.eprintf("Failed to load texture '%s'\n", path)
		return {}
	}
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)

	width := int(img.width)
	height := int(img.height)
	colors_ptr := rl.LoadImageColors(img)
	if colors_ptr == nil {
		rl.UnloadImage(img)
		fmt.eprintf("Failed to load texture '%s'\n", path)
		return {}
	}
	defer rl.UnloadImageColors(colors_ptr)
	if width < 1 || height < 1 {
		rl.UnloadImage(img)
		fmt.eprintf("Failed to load texture '%s'\n", path)
		return {}
	}

	frames := anim_frame_rects(colors_ptr[:width * height], width, height)
	// Grid-less sheets either play whole, or follow their declared frame size from the .animation text.
	anim_found := false
	for f in frames {
		if f.height < f32(height) {
			anim_found = true
			break
		}
	}
	if !anim_found {
		if fw, fh, ok := frame_size_from_details(string(path)); ok && fw == width && fh > 0 && height % fh == 0 {
			delete(frames)
			frames = make([dynamic]rl.Rectangle)
			for i in 0 ..< height / fh {
				append(&frames, rl.Rectangle{0, f32(height - (i + 1) * fh), f32(fw), f32(fh)})
			}
		}
	}
	rl.ImageColorReplace(&img, ANIM_GRID, rl.BLANK)
	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	if tex.id == 0 {
		delete(frames)
		fmt.eprintf("Failed to load texture '%s'\n", path)
		return {}
	}
	rl.SetTextureFilter(tex, .POINT)
	return {tex = tex, frames = frames}
}

ensure_animations :: proc() {
	if anims_loaded || !rl.IsWindowReady() do return
	anims_loaded = true
	clips[.BALL_LOST] = load_anim_clip("src/textures/animations/ball_lost.png")
	clips[.BALL_TRAIL] = load_anim_clip("src/textures/animations/ball_trail.png")
	clips[.EXPLODE] = load_anim_clip("src/textures/animations/explode.png")
	clips[.LIFE_LOST] = load_anim_clip("src/textures/animations/life_lost.png")
	clips[.HYPER_RECT] = load_anim_clip("src/textures/animations/hyper_rect.png")
}

unload_animations :: proc() {
	if anims_loaded {
		for kind in Anim_Kind {
			if clips[kind].tex.id != 0 do rl.UnloadTexture(clips[kind].tex)
			delete(clips[kind].frames)
		}
	}
	clips = {}
	anims_loaded = false
	delete(plays)
	plays = {}
	trail_age = 0
	hyper_age = 0
	ball_sp_age = 0
}

clear_animations :: proc() {
	clear(&plays)
	trail_age = 0
	hyper_age = 0
	ball_sp_age = 0
}

push_play :: proc(play: Anim_Play) {
	if !rl.IsWindowReady() do return
	if len(plays) >= ANIM_PLAY_MAX do ordered_remove(&plays, 0)
	append(&plays, play)
}

play_ball_lost :: proc(ball_x: i32) {
	push_play({kind = .BALL_LOST, x = ball_x})
}

play_life_lost :: proc(index: int) {
	if index < 0 do return
	x, y := life_point_origin(index)
	push_play({kind = .LIFE_LOST, x = x, y = y})
}

// The last life. The board stays frozen until this sheet finishes.
play_life_finale :: proc() {
	push_play({kind = .LIFE_LOST, finale = true})
}

// True while the last-life sheet is still on screen. Other animations stay put.
update_life_finale :: proc(dt: f32) -> bool {
	ensure_animations()
	step := dt
	if step < 0 do step = 0
	playing := false
	for i := len(plays) - 1; i >= 0; i -= 1 {
		if !plays[i].finale do continue
		plays[i].age += step
		count := len(clips[plays[i].kind].frames)
		if count < 1 || plays[i].age >= f32(count) * ANIM_FRAME_DT {
			unordered_remove(&plays, i)
			continue
		}
		playing = true
	}
	return playing
}

// Two thirds of the shorter playfield side, centered.
life_finale_box :: proc() -> (x, y, size: i32) {
	size = SCW
	if SCH < size do size = SCH
	size = size * 2 / 3
	if size < 1 do size = 1
	x = (SCW - size) / 2
	y = (SCH - size) / 2
	return
}

render_life_finale :: proc() {
	ensure_animations()
	clip := clips[.LIFE_LOST]
	count := len(clip.frames)
	if clip.tex.id == 0 || count < 1 do return
	for play in plays {
		if play.kind != .LIFE_LOST || !play.finale do continue
		src := clip.frames[anim_frame_index(play.age, count, false)]
		x, y, size := life_finale_box()
		draw_anim(clip.tex, src, x, y, size, size, 255)
	}
}

// A square a little larger than the brick. Super explode grows past this.
explode_base :: proc() -> i32 {
	return RECT_W + 16
}

// radius 0 is a bomb. A super explode passes super_explode_radius so the sheet matches that blast.
explode_span :: proc(radius: i32) -> i32 {
	span := explode_base()
	if radius > 0 {
		reach := RECT_W + radius * 2 * (RECT_W + RECT_GAP)
		if reach > span do span = reach
	}
	return span
}

play_explosion :: proc(brick_x, brick_y, radius: i32) {
	push_play({
		kind = .EXPLODE,
		x = brick_x,
		y = brick_y,
		size = explode_span(radius),
		layered = radius > 0,
	})
}

// Faint just above TRAIL_MIN_SPEED, then rising quickly, and fully opaque at MAX_BALL_SPEED.
// A straight line across that span stays nearly clear for the whole range a ball actually reaches.
trail_alpha :: proc(speed: f32) -> u8 {
	if speed <= TRAIL_MIN_SPEED do return 0
	span := f32(MAX_BALL_SPEED) - TRAIL_MIN_SPEED
	if span <= 0 do return 255
	t := (speed - TRAIL_MIN_SPEED) / span
	if t > 1 do t = 1
	t = math.pow(t, 0.35)
	a := int(t * 255 + 0.5)
	if a < 1 do a = 1
	if a > 255 do a = 255
	return u8(a)
}

// Clockwise degrees on the playfield. The sheet's right edge sits on the ball,
// so this aims that edge along the velocity and the ribbon lies behind the ball.
trail_angle :: proc(vx, vy: f32) -> f32 {
	return math.atan2(vy, vx) * 180 / math.PI
}

ball_faster_axis :: proc(ball: Ball) -> f32 {
	ax := ball.vx
	ay := ball.vy
	if ax < 0 do ax = -ax
	if ay < 0 do ay = -ay
	if ay > ax do return ay
	return ax
}

anim_frame_index :: proc(age: f32, count: int, loop: bool) -> int {
	if count < 1 do return 0
	index := int(age / ANIM_FRAME_DT)
	if index < 0 do index = 0
	if loop do return index % count
	if index >= count do return count - 1
	return index
}

update_animations :: proc(dt: f32, advance_trail: bool) {
	ensure_animations()
	step := dt
	if step < 0 do step = 0
	if advance_trail {
		trail_age += step
		ball_sp_age += step
	}
	if step == 0 do return
	hyper_age += step
	for i := len(plays) - 1; i >= 0; i -= 1 {
		plays[i].age += step
		count := len(clips[plays[i].kind].frames)
		if count < 1 || plays[i].age >= f32(count) * ANIM_FRAME_DT {
			unordered_remove(&plays, i)
		}
	}
}

draw_anim :: proc(tex: rl.Texture2D, src: rl.Rectangle, x, y, w, h: i32, alpha: u8) {
	if tex.id == 0 || w < 1 || h < 1 || alpha == 0 do return
	dst := rl.Rectangle{f32(x), f32(y), f32(w), f32(h)}
	rl.DrawTexturePro(tex, src, dst, {}, 0, {255, 255, 255, alpha})
}

render_ball_trail :: proc(ball: Ball) {
	if !ball.alive || ball.stuck do return
	alpha := trail_alpha(ball_faster_axis(ball))
	if alpha == 0 do return
	ensure_animations()
	clip := clips[.BALL_TRAIL]
	count := len(clip.frames)
	if clip.tex.id == 0 || count < 1 do return
	src := clip.frames[anim_frame_index(trail_age, count, true)]
	w := i32(src.width) * TRAIL_STRETCH
	h := i32(src.height)
	if w < 1 || h < 1 do return
	// Pivot is the right edge of the sheet, placed on the ball.
	dst := rl.Rectangle{f32(ball.x), f32(ball.y), f32(w), f32(h)}
	origin := rl.Vector2{f32(w), f32(h) * 0.5}
	rl.DrawTexturePro(clip.tex, src, dst, origin, trail_angle(ball.vx, ball.vy), {255, 255, 255, alpha})
}

// Super explode only. The opaque pass sits behind the bricks. The half-alpha pass sits in front of them.
render_layered_explosions :: proc(alpha: u8) {
	if alpha == 0 do return
	ensure_animations()
	clip := clips[.EXPLODE]
	count := len(clip.frames)
	if clip.tex.id == 0 || count < 1 do return
	for play in plays {
		if play.kind != .EXPLODE || !play.layered do continue
		src := clip.frames[anim_frame_index(play.age, count, false)]
		side := play.size
		if side < 1 do side = explode_base()
		cx := play.x + RECT_W / 2
		cy := play.y + RECT_H / 2
		draw_anim(clip.tex, src, cx - side / 2, cy - side / 2, side, side, alpha)
	}
}

render_animations :: proc() {
	ensure_animations()
	for play in plays {
		clip := clips[play.kind]
		count := len(clip.frames)
		if clip.tex.id == 0 || count < 1 do continue
		src := clip.frames[anim_frame_index(play.age, count, false)]
		switch play.kind {
		case .BALL_LOST:
			w := i32(src.width) * BALL_LOST_SCALE
			h := i32(src.height) * BALL_LOST_SCALE
			left := play.x - w / 2
			if left < 0 do left = 0
			if w < SCW && left > SCW - w do left = SCW - w
			draw_anim(clip.tex, src, left, SCH - h, w, h, 255)
		case .LIFE_LOST:
			if play.finale do continue
			draw_anim(clip.tex, src, play.x, play.y, LIFE_POINT_SIZE, LIFE_POINT_SIZE, 255)
		case .EXPLODE:
			if play.layered do continue
			side := play.size
			if side < 1 do side = explode_base()
			cx := play.x + RECT_W / 2
			cy := play.y + RECT_H / 2
			draw_anim(clip.tex, src, cx - side / 2, cy - side / 2, side, side, 255)
		case .BALL_TRAIL:
		case .HYPER_RECT:
		}
	}
}

// The looping frame of the hyper_rect sheet. Bricks of that type use it as their picture.
hyper_rect_frame :: proc() -> (tex: rl.Texture2D, src: rl.Rectangle, ok: bool) {
	ensure_animations()
	clip := clips[.HYPER_RECT]
	count := len(clip.frames)
	if clip.tex.id == 0 || count < 1 do return
	return clip.tex, clip.frames[anim_frame_index(hyper_age, count, true)], true
}

// True when this rect name declares an animated picture in src/textures/animations.
rect_anim_available :: proc(name: string) -> bool {
	if len(name) == 0 do return false
	buf: [256]byte
	n := 0
	dir := "src/textures/animations/"
	for ch in dir {
		buf[n] = u8(ch)
		n += 1
	}
	for ch in name {
		if n >= len(buf) - 10 do return false
		buf[n] = u8(ch)
		n += 1
	}
	suffix := ".animation"
	for ch in suffix {
		buf[n] = u8(ch)
		n += 1
	}
	return os.exists(string(buf[:n]))
}
