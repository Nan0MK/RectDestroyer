package src

import "core:c"
import big "core:math/big"
import rl "vendor:raylib"

Screen :: enum {
	MENU,
	LEVEL_SELECT,
	PLAY,
	PAUSE,
	LEVEL_END,
	LAST_LIFE,
	LOST,
	SCORES,
}

// "LEVEL SELECT" is 12 cells in the sprite font at 24px, which needs this width.
MENU_BTN_W: i32 = 320
MENU_BTN_H: i32 = 56
MENU_BTN_GAP: i32 = 20
LEVEL_BTN_H: i32 = 52
LEVEL_BTN_GAP: i32 = 16

button_hovered :: proc(x, y, w, h: i32, mouse: rl.Vector2) -> bool {
	return mouse.x >= f32(x) && mouse.x < f32(x + w) && mouse.y >= f32(y) && mouse.y < f32(y + h)
}

button_clicked :: proc(x, y, w, h: i32, mouse: rl.Vector2) -> bool {
	return rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && button_hovered(x, y, w, h, mouse)
}

draw_button :: proc(label: cstring, x, y, w, h: i32, mouse: rl.Vector2) {
	hot := button_hovered(x, y, w, h, mouse)
	fill := rl.DARKGRAY
	ink := rl.WHITE
	if hot {
		fill = rl.WHITE
		ink = rl.BLACK
	}
	rl.DrawRectangle(x, y, w, h, fill)
	rl.DrawRectangleLines(x, y, w, h, rl.WHITE)
	size := px(24)
	tw := measure_text(label, size)
	draw_text(label, x + (w - tw) / 2, y + (h - size) / 2, size, ink)
}

draw_centered_text :: proc(text: cstring, y, size: i32, color: rl.Color) {
	tw := measure_text(text, size)
	draw_text(text, (SCW - tw) / 2, y, size, color)
}

main_button_rect :: proc(index: int) -> (x, y, w, h: i32) {
	w = px(MENU_BTN_W)
	h = px(MENU_BTN_H)
	x = (SCW - w) / 2
	y = px(260) + i32(index) * (h + px(MENU_BTN_GAP))
	return
}

// One button per LEVELS entry. Two columns after 5, three after 10, so each one stays on screen.
level_button_rect :: proc(index: int) -> (x, y, w, h: i32) {
	n := len(LEVELS)
	cols := 1
	if n > 5 do cols = 2
	if n > 10 do cols = 3
	w = px(MENU_BTN_W)
	if cols >= 2 do w = px(240)
	h = px(LEVEL_BTN_H)
	gap := px(LEVEL_BTN_GAP)
	grid_w := i32(cols) * w + i32(cols - 1) * gap
	x0 := (SCW - grid_w) / 2
	col := i32(index % cols)
	row := i32(index / cols)
	x = x0 + col * (w + gap)
	y = px(130) + row * (h + gap)
	return
}

// CLEAR above BACK, both sitting on the bottom of the past-scores list.
scores_button_rect :: proc(index: int) -> (x, y, w, h: i32) {
	w = px(MENU_BTN_W)
	h = px(MENU_BTN_H)
	x = (SCW - w) / 2
	back_y := SCH - px(88)
	y = back_y - i32(1 - index) * (h + px(MENU_BTN_GAP))
	return
}

back_button_rect :: proc() -> (x, y, w, h: i32) {
	w = px(MENU_BTN_W)
	h = px(MENU_BTN_H)
	x = (SCW - w) / 2
	y = SCH - px(88)
	return
}

format_level_label :: proc(index: int, buf: ^[16]byte) -> cstring {
	label := "LEVEL "
	n := 0
	for ch in label {
		buf[n] = u8(ch)
		n += 1
	}
	num := index + 1
	tmp: [8]byte
	count := 0
	for num > 0 && count < len(tmp) {
		tmp[count] = u8('0') + u8(num % 10)
		num /= 10
		count += 1
	}
	for i := count - 1; i >= 0; i -= 1 {
		buf[n] = tmp[i]
		n += 1
	}
	buf[n] = 0
	return cstring(&buf[0])
}

// Menu input for this frame. start is set when PLAY, a level button, or NEXT LEVEL should load level_index.
// Play simulation stays in the frame loop. Escape during play only requests the pause screen.
// quit asks the frame loop to close the window after cleanup.
update_menus :: proc(screen: Screen, mouse: rl.Vector2, playing_level: int) -> (next: Screen, start: bool, level_index: int, quit: bool) {
	next = screen
	level_index = -1

	switch screen {
	case .MENU:
		play_x, play_y, play_w, play_h := main_button_rect(0)
		levels_x, levels_y, levels_w, levels_h := main_button_rect(1)
		scores_x, scores_y, scores_w, scores_h := main_button_rect(2)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(3)
		if button_clicked(play_x, play_y, play_w, play_h, mouse) && len(LEVELS) > 0 {
			next = .PLAY
			start = true
			level_index = 0
		} else if button_clicked(levels_x, levels_y, levels_w, levels_h, mouse) {
			next = .LEVEL_SELECT
		} else if button_clicked(scores_x, scores_y, scores_w, scores_h, mouse) {
			next = .SCORES
		} else if button_clicked(quit_x, quit_y, quit_w, quit_h, mouse) {
			quit = true
		}
	case .LEVEL_SELECT:
		for i in 0..<len(LEVELS) {
			x, y, w, h := level_button_rect(i)
			if button_clicked(x, y, w, h, mouse) {
				next = .PLAY
				start = true
				level_index = i
				return
			}
		}
		bx, by, bw, bh := back_button_rect()
		if button_clicked(bx, by, bw, bh, mouse) {
			next = .MENU
		}
	case .PLAY:
		if rl.IsKeyPressed(.ESCAPE) {
			next = .PAUSE
		}
	case .PAUSE:
		resume_x, resume_y, resume_w, resume_h := main_button_rect(0)
		menu_x, menu_y, menu_w, menu_h := main_button_rect(1)
		if rl.IsKeyPressed(.ESCAPE) || button_clicked(resume_x, resume_y, resume_w, resume_h, mouse) {
			next = .PLAY
		} else if button_clicked(menu_x, menu_y, menu_w, menu_h, mouse) {
			next = .MENU
		}
	case .LEVEL_END:
		if playing_level + 1 < len(LEVELS) {
			next_x, next_y, next_w, next_h := main_button_rect(0)
			menu_x, menu_y, menu_w, menu_h := main_button_rect(1)
			if button_clicked(next_x, next_y, next_w, next_h, mouse) {
				next = .PLAY
				start = true
				level_index = playing_level + 1
			} else if button_clicked(menu_x, menu_y, menu_w, menu_h, mouse) {
				next = .MENU
			}
		} else {
			menu_x, menu_y, menu_w, menu_h := main_button_rect(0)
			if button_clicked(menu_x, menu_y, menu_w, menu_h, mouse) {
				next = .MENU
			}
		}
	case .LAST_LIFE:
	case .LOST:
		menu_x, menu_y, menu_w, menu_h := main_button_rect(0)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(1)
		if button_clicked(menu_x, menu_y, menu_w, menu_h, mouse) {
			next = .MENU
		} else if button_clicked(quit_x, quit_y, quit_w, quit_h, mouse) {
			quit = true
		}
	case .SCORES:
		clear_x, clear_y, clear_w, clear_h := scores_button_rect(0)
		back_x, back_y, back_w, back_h := scores_button_rect(1)
		if button_clicked(clear_x, clear_y, clear_w, clear_h, mouse) {
			clear_saved_scores()
			scores_scroll = 0
		} else if button_clicked(back_x, back_y, back_w, back_h, mouse) {
			next = .MENU
		}
	}
	return
}

// Digits for the level-clear and you-lost crawl. Held only while one of those menus is up.
// credits_overall is set when the run has ended: last level cleared, or last life lost.
credits_digits: []u8
credits_overall: []u8
credits_scroll: f64
credits_for: Screen
scores_scroll: f64
scores_for: Screen

free_digit_buf :: proc(buf: ^[]u8) {
	delete(buf^)
	buf^ = nil
}

free_end_credits :: proc() {
	free_digit_buf(&credits_digits)
	free_digit_buf(&credits_overall)
}

store_digits :: proc(dst: ^[]u8, score: ^big.Int) {
	free_digit_buf(dst)
	text, err := big.itoa(score)
	defer delete(text)
	if err != big.Error.None || len(text) == 0 {
		dst^ = make([]u8, 1)
		dst^[0] = '0'
		return
	}
	dst^ = make([]u8, len(text))
	copy(dst^, text)
}

credits_chars_per_line :: proc(size, max_w: i32) -> int {
	w := measure_text("0", size)
	if w < 1 do w = size
	if w < 1 do w = 1
	span := max_w
	if span < w do span = w
	return int(span / w)
}

append_text :: proc(buf: ^[64]byte, n: int, text: string) -> int {
	i := n
	for ch in text {
		if i >= 63 do break
		buf[i] = u8(ch)
		i += 1
	}
	return i
}

append_i64 :: proc(buf: ^[64]byte, n: int, value: i64) -> int {
	tmp: [20]byte
	count := 0
	x := value
	if x < 0 do x = 0
	if x == 0 {
		tmp[0] = '0'
		count = 1
	} else {
		for x > 0 && count < len(tmp) {
			tmp[count] = u8('0') + u8(x % 10)
			x /= 10
			count += 1
		}
	}
	i := n
	for d := count - 1; d >= 0; d -= 1 {
		if i >= 63 do break
		buf[i] = tmp[d]
		i += 1
	}
	return i
}

append_2digits :: proc(buf: ^[64]byte, n: int, value: i64) -> int {
	v := value
	if v < 0 do v = 0
	if v > 99 do v = v % 100
	i := n
	if i < 63 {
		buf[i] = u8('0') + u8(v / 10)
		i += 1
	}
	if i < 63 {
		buf[i] = u8('0') + u8(v % 10)
		i += 1
	}
	return i
}

// TIME m:ss, or h:mm:ss once an hour has passed. The clock stops when the round is scored.
format_time_label :: proc(buf: ^[64]byte, elapsed_ns: i64) -> cstring {
	ns := elapsed_ns
	if ns < 0 do ns = 0
	sec := ns / 1_000_000_000
	h := sec / 3600
	m := (sec % 3600) / 60
	s := sec % 60
	n := append_text(buf, 0, "TIME ")
	if h > 0 {
		n = append_i64(buf, n, h)
		n = append_text(buf, n, ":")
		n = append_2digits(buf, n, m)
	} else {
		n = append_i64(buf, n, m)
	}
	n = append_text(buf, n, ":")
	n = append_2digits(buf, n, s)
	buf[n] = 0
	return cstring(&buf[0])
}

format_named_count :: proc(buf: ^[64]byte, label: string, value: i64) -> cstring {
	n := append_text(buf, 0, label)
	n = append_i64(buf, n, value)
	buf[n] = 0
	return cstring(&buf[0])
}

draw_centered_line :: proc(text: cstring, y, size: i32) {
	tw := measure_text(text, size)
	x := (SCW - tw) / 2
	if x < px(8) do x = px(8)
	draw_text(text, x, y, size, rl.WHITE)
}

// Score digits wrap to the playfield. Stats follow. The block rises like credits and loops.
// The title and the buttons are drawn after this, so the crawl passes behind them.
draw_end_credits :: proc(mods: Power_Mods, balls: []Ball) {
	size := px(26)
	line_h := size + px(10)
	if line_h < 1 do line_h = 1
	view_top := px(172)
	view_h := SCH - view_top
	if view_h < line_h do view_h = line_h

	cpl := credits_chars_per_line(size, SCW - px(32))
	if cpl < 1 do cpl = 1
	digit_lines := 1
	if len(credits_digits) > 0 {
		digit_lines = (len(credits_digits) + cpl - 1) / cpl
	}
	alive := 0
	for ball in balls {
		if ball.alive do alive += 1
	}
	// Header, digit lines, then on a finished run a blank, OVERALL, and those digits.
	// A blank, STATS, seven counts, and one speed line per living ball follow.
	extra := 0
	overall_lines := 0
	if len(credits_overall) > 0 {
		overall_lines = (len(credits_overall) + cpl - 1) / cpl
		if overall_lines < 1 do overall_lines = 1
		extra = 2 + overall_lines
	}
	lead := 1 + digit_lines + extra
	total := digit_lines + extra + 10 + alive

	dt := f64(rl.GetFrameTime())
	if dt < 0 do dt = 0
	if dt > 0.05 do dt = 0.05
	credits_scroll += f64(px(36)) * dt
	span := f64(total * int(line_h) + int(view_h))
	if span < 1 do span = 1
	for credits_scroll >= span {
		credits_scroll -= span
	}

	base := f64(view_top + view_h) - credits_scroll
	first := int((f64(view_top) - base) / f64(line_h))
	if first < 0 do first = 0
	if first > total do first = total
	last := first + int(view_h / line_h) + 3
	if last > total do last = total
	if first > last do first = last

	digit_w := measure_text("0", size)
	if digit_w < 1 do digit_w = size
	block_w := i32(cpl) * digit_w
	digit_x := (SCW - block_w) / 2
	if digit_x < px(16) do digit_x = px(16)
	line_buf := make([]u8, cpl + 1)
	defer delete(line_buf)

	rl.BeginScissorMode(0, c.int(view_top), c.int(SCW), c.int(view_h))
	for i in first ..< last {
		y := i32(base + f64(i) * f64(line_h))
		if i == 0 {
			if credits_for == .LEVEL_END {
				draw_centered_line("LEVEL SCORE", y, size)
			} else {
				draw_centered_line("SCORE", y, size)
			}
			continue
		}
		if i >= 1 && i < 1 + digit_lines {
			draw_digit_line(credits_digits, i - 1, cpl, digit_x, y, size, line_buf)
			continue
		}
		if extra > 0 && i < lead {
			rel := i - (1 + digit_lines)
			if rel == 0 do continue
			if rel == 1 {
				draw_centered_line("OVERALL", y, size)
				continue
			}
			draw_digit_line(credits_overall, rel - 2, cpl, digit_x, y, size, line_buf)
			continue
		}
		if i == lead do continue
		if i == lead + 1 {
			draw_centered_line("STATS", y, size)
			continue
		}
		slot := i - (lead + 2)
		label: [64]byte
		text: cstring
		if slot == 0 {
			text = format_time_label(&label, round_elapsed_ns)
		} else if slot == 1 {
			text = format_named_count(&label, "POWERUPS ", round_powerups)
		} else if slot == 2 {
			text = format_named_count(&label, "BALLS LOST ", round_balls_lost)
		} else if slot == 3 {
			text = format_named_count(&label, "BALLS LEFT ", i64(alive))
		} else if slot == 4 {
			lives := mods.lives
			if lives < 0 do lives = 0
			text = format_named_count(&label, "LIVES ", i64(lives))
		} else if slot == 5 {
			text = format_named_count(&label, "LIVES LOST ", round_lives_lost)
		} else if slot == 6 {
			text = format_named_count(&label, "PAD ", i64(mods.pad_w))
		} else {
			want := slot - 7
			seen := 0
			speed: i32
			for ball in balls {
				if !ball.alive do continue
				if seen == want {
					speed = ball_score_speed(ball)
					break
				}
				seen += 1
			}
			n := append_text(&label, 0, "BALL ")
			n = append_i64(&label, n, i64(want + 1))
			n = append_text(&label, n, " SPEED ")
			n = append_i64(&label, n, i64(speed))
			label[n] = 0
			text = cstring(&label[0])
		}
		draw_centered_line(text, y, size)
	}
	rl.EndScissorMode()
}

draw_digit_line :: proc(digits: []u8, line_i, cpl: int, x, y, size: i32, line_buf: []u8) {
	start := line_i * cpl
	end := start + cpl
	if start > len(digits) do start = len(digits)
	if end > len(digits) do end = len(digits)
	n := end - start
	for k in 0 ..< n {
		line_buf[k] = digits[start + k]
	}
	if n < len(line_buf) do line_buf[n] = 0
	draw_text(cstring(raw_data(line_buf)), x, y, size, rl.WHITE)
}

draw_digit_text :: proc(digits: string, line_i, cpl: int, x, y, size: i32, line_buf: []u8) {
	start := line_i * cpl
	end := start + cpl
	if start > len(digits) do start = len(digits)
	if end > len(digits) do end = len(digits)
	n := 0
	for i in start ..< end {
		line_buf[n] = digits[i]
		n += 1
	}
	if n < len(line_buf) do line_buf[n] = 0
	draw_text(cstring(raw_data(line_buf)), x, y, size, rl.WHITE)
}

prepare_end_credits :: proc(screen: Screen, score: ^big.Int) {
	if screen != .LEVEL_END && screen != .LOST {
		if len(credits_digits) > 0 || len(credits_overall) > 0 {
			free_end_credits()
			credits_scroll = 0
		}
		credits_for = screen
		return
	}
	if credits_for == screen {
		// A failed save retries on a later frame. Pick up OVERALL once that write lands.
		if run_show_overall && len(credits_overall) == 0 {
			store_digits(&credits_overall, &run_overall)
		}
		return
	}
	store_digits(&credits_digits, score)
	if run_show_overall {
		store_digits(&credits_overall, &run_overall)
	} else {
		free_digit_buf(&credits_overall)
	}
	credits_scroll = 0
	credits_for = screen
}

// One saved overall score: a "SCORE n" header, its wrapped digits, then a gap.
saved_line_count :: proc(cpl: int) -> int {
	total := 0
	for line in score_lines {
		lines := 1
		if len(line) > 0 do lines = (len(line) + cpl - 1) / cpl
		total += 2 + lines
	}
	return total
}

// kind 0 is the header, 1 is a digit line, 2 is the gap under that score.
locate_saved_line :: proc(index, cpl: int) -> (which, kind, offset: int) {
	at := 0
	for s in 0 ..< len(score_lines) {
		n := len(score_lines[s])
		lines := 1
		if n > 0 do lines = (n + cpl - 1) / cpl
		if index < at + 1 do return s, 0, 0
		if index < at + 1 + lines do return s, 1, index - (at + 1)
		if index < at + 2 + lines do return s, 2, 0
		at += 2 + lines
	}
	return 0, 2, 0
}

// Past scores rise like the end-of-round crawl so a long number can be read.
draw_saved_scores :: proc() {
	if len(score_lines) == 0 {
		draw_centered_text("NO SCORES", px(220), px(32), rl.WHITE)
		return
	}

	size := px(26)
	line_h := size + px(8)
	if line_h < 1 do line_h = 1
	_, clear_y, _, _ := scores_button_rect(0)
	view_top := px(110)
	view_h := clear_y - px(16) - view_top
	if view_h < line_h do view_h = line_h

	cpl := credits_chars_per_line(size, SCW - px(32))
	if cpl < 1 do cpl = 1
	total := saved_line_count(cpl)
	if total < 1 do return

	dt := f64(rl.GetFrameTime())
	if dt < 0 do dt = 0
	if dt > 0.05 do dt = 0.05
	scores_scroll += f64(px(36)) * dt
	span := f64(total * int(line_h) + int(view_h))
	if span < 1 do span = 1
	for scores_scroll >= span {
		scores_scroll -= span
	}

	base := f64(view_top + view_h) - scores_scroll
	first := int((f64(view_top) - base) / f64(line_h))
	if first < 0 do first = 0
	if first > total do first = total
	last := first + int(view_h / line_h) + 3
	if last > total do last = total
	if first > last do first = last

	digit_w := measure_text("0", size)
	if digit_w < 1 do digit_w = size
	block_w := i32(cpl) * digit_w
	digit_x := (SCW - block_w) / 2
	if digit_x < px(16) do digit_x = px(16)
	line_buf := make([]u8, cpl + 1)
	defer delete(line_buf)

	rl.BeginScissorMode(0, c.int(view_top), c.int(SCW), c.int(view_h))
	for i in first ..< last {
		y := i32(base + f64(i) * f64(line_h))
		which, kind, offset := locate_saved_line(i, cpl)
		if kind == 2 do continue
		if kind == 0 {
			label: [64]byte
			n := append_text(&label, 0, "SCORE ")
			n = append_i64(&label, n, i64(which + 1))
			label[n] = 0
			draw_centered_line(cstring(&label[0]), y, size)
			continue
		}
		draw_digit_text(score_lines[which], offset, cpl, digit_x, y, size, line_buf)
	}
	rl.EndScissorMode()
}

// Main menu, level select, and past scores fill the screen. Pause, level clear, and you lost draw over the playfield.
draw_menus :: proc(screen: Screen, mouse: rl.Vector2, score: ^big.Int, playing_level: int, mods: Power_Mods, balls: []Ball) {
	prepare_end_credits(screen, score)
	switch screen {
	case .MENU:
		draw_centered_text("RECT-DESTROYER!", px(150), px(40), rl.WHITE)
		play_x, play_y, play_w, play_h := main_button_rect(0)
		levels_x, levels_y, levels_w, levels_h := main_button_rect(1)
		scores_x, scores_y, scores_w, scores_h := main_button_rect(2)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(3)
		draw_button("PLAY", play_x, play_y, play_w, play_h, mouse)
		draw_button("LEVEL SELECT", levels_x, levels_y, levels_w, levels_h, mouse)
		draw_button("PAST SCORES", scores_x, scores_y, scores_w, scores_h, mouse)
		draw_button("QUIT", quit_x, quit_y, quit_w, quit_h, mouse)
	case .LEVEL_SELECT:
		draw_centered_text("SELECT LEVEL", px(48), px(36), rl.WHITE)
		for i in 0..<len(LEVELS) {
			buf: [16]byte
			label := format_level_label(i, &buf)
			x, y, w, h := level_button_rect(i)
			draw_button(label, x, y, w, h, mouse)
		}
		bx, by, bw, bh := back_button_rect()
		draw_button("BACK", bx, by, bw, bh, mouse)
	case .PLAY:
	case .LAST_LIFE:
	case .PAUSE:
		rl.DrawRectangle(0, 0, SCW, SCH, rl.Color{0, 0, 0, 170})
		draw_centered_text("PAUSED", px(150), px(40), rl.WHITE)
		resume_x, resume_y, resume_w, resume_h := main_button_rect(0)
		menu_x, menu_y, menu_w, menu_h := main_button_rect(1)
		draw_button("RESUME", resume_x, resume_y, resume_w, resume_h, mouse)
		draw_button("MAIN MENU", menu_x, menu_y, menu_w, menu_h, mouse)
	case .LEVEL_END:
		rl.DrawRectangle(0, 0, SCW, SCH, rl.Color{0, 0, 0, 170})
		draw_end_credits(mods, balls)
		draw_centered_text("LEVEL CLEAR", px(120), px(40), rl.WHITE)
		if playing_level + 1 < len(LEVELS) {
			next_x, next_y, next_w, next_h := main_button_rect(0)
			menu_x, menu_y, menu_w, menu_h := main_button_rect(1)
			draw_button("NEXT LEVEL", next_x, next_y, next_w, next_h, mouse)
			draw_button("MAIN MENU", menu_x, menu_y, menu_w, menu_h, mouse)
		} else {
			menu_x, menu_y, menu_w, menu_h := main_button_rect(0)
			draw_button("MAIN MENU", menu_x, menu_y, menu_w, menu_h, mouse)
		}
	case .LOST:
		rl.DrawRectangle(0, 0, SCW, SCH, rl.Color{0, 0, 0, 170})
		draw_end_credits(mods, balls)
		draw_centered_text("YOU LOST", px(120), px(40), rl.WHITE)
		menu_x, menu_y, menu_w, menu_h := main_button_rect(0)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(1)
		draw_button("MAIN MENU", menu_x, menu_y, menu_w, menu_h, mouse)
		draw_button("QUIT", quit_x, quit_y, quit_w, quit_h, mouse)
	case .SCORES:
		if scores_for != .SCORES do scores_scroll = 0
		scores_for = .SCORES
		draw_centered_text("PAST SCORES", px(48), px(36), rl.WHITE)
		draw_saved_scores()
		clear_x, clear_y, clear_w, clear_h := scores_button_rect(0)
		back_x, back_y, back_w, back_h := scores_button_rect(1)
		draw_button("CLEAR SCORES", clear_x, clear_y, clear_w, clear_h, mouse)
		draw_button("BACK", back_x, back_y, back_w, back_h, mouse)
	}
	if screen != .SCORES do scores_for = screen
}
