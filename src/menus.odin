package src

import "core:c"
import "core:math"
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
	clicked := rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && button_hovered(x, y, w, h, mouse)
	if clicked do play_menu_button_click()
	return clicked
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

level_select_scroll: f32

// Debug mode: type 6767 on the main menu. Shows an indicator everywhere,
// unlocks the right-click ball reset, and adds a small X to leave debug mode.
debug_mode: bool
debug_typed: [4]rune
debug_typed_len: int

debug_x_rect :: proc() -> (x, y, w, h: i32) {
	w = px(28)
	h = px(28)
	x = SCW - w - px(8)
	y = SCH - h - px(8)
	return
}

update_debug_input :: proc(screen: Screen) {
	if screen == .MENU && !debug_mode {
		c := rl.GetCharPressed()
		for c != 0 {
			if debug_typed_len < 4 {
				debug_typed[debug_typed_len] = c
				debug_typed_len += 1
			} else {
				copy(debug_typed[:], debug_typed[1:])
				debug_typed[3] = c
			}
			if debug_typed_len == 4 && debug_typed[0] == '6' && debug_typed[1] == '7' && debug_typed[2] == '6' && debug_typed[3] == '7' {
				debug_mode = true
				debug_typed_len = 0
			}
			c = rl.GetCharPressed()
		}
	}
}

// One package owns debug state; menus and the frame loop both read it.
debug_x_clicked :: proc(mouse: rl.Vector2) -> bool {
	if !debug_mode do return false
	x, y, w, h := debug_x_rect()
	return button_clicked(x, y, w, h, mouse)
}

DEBUG_BUTTON_LABELS : [13]cstring = {
	"ADD LIFE", "REMOVE LIFE", "WIDE", "MULTIPLY", "STICK", "LIFE", "FAST", "BONUS", "BOMB",
	"DOUBLE", "EXPLODE", "TARGETING", "CLEAR POWERUPS",
}

DEBUG_ADD_LIFE :: 0
DEBUG_REMOVE_LIFE :: 1
DEBUG_WIDE :: 2
DEBUG_MULTIPLY :: 3
DEBUG_STICK :: 4
DEBUG_LIFE :: 5
DEBUG_FAST :: 6
DEBUG_BONUS :: 7
DEBUG_BOMB :: 8
DEBUG_DOUBLE :: 9
DEBUG_EXPLODE :: 10
DEBUG_TARGETING :: 11
DEBUG_CLEAR_POWERUPS :: 12

debug_button_rect :: proc(index: int) -> (x, y, w, h: i32) {
	w = px(170)
	h = px(24)
	x = px(8)
	y = px(40) + i32(index) * (h + px(4))
	return
}

debug_button_index :: proc(mouse: rl.Vector2) -> int {
	for i in 0..<len(DEBUG_BUTTON_LABELS) {
		x, y, w, h := debug_button_rect(i)
		if button_clicked(x, y, w, h, mouse) do return i
	}
	return -1
}

draw_debug_overlay :: proc() {
	if !debug_mode do return
	draw_text("DEBUG", px(8), px(8), px(20), rl.YELLOW)
	x, y, w, h := debug_x_rect()
	rl.DrawRectangle(x, y, w, h, rl.DARKGRAY)
	rl.DrawRectangleLines(x, y, w, h, rl.YELLOW)
	xw := measure_text("X", px(20))
	draw_text("X", x + (w - xw) / 2, y + 2, px(20), rl.YELLOW)
	for i in 0..<len(DEBUG_BUTTON_LABELS) {
		bx, by, bw, bh := debug_button_rect(i)
		rl.DrawRectangle(bx, by, bw, bh, rl.Color{40, 40, 40, 255})
		rl.DrawRectangleLines(bx, by, bw, bh, rl.YELLOW)
		draw_text(DEBUG_BUTTON_LABELS[i], bx + px(6), by + px(2), px(18), rl.WHITE)
	}
}

// The button grid scrolls below the title, and the BACK button caps the bottom.
level_select_view :: proc() -> (top, bottom: i32) {
	top = px(120)
	bottom = SCH - px(120)
	if bottom < top + 1 do bottom = top + 1
	return
}

level_grid_height :: proc() -> i32 {
	n := len(LEVELS)
	cols := 1
	if n > 5 do cols = 2
	if n > 10 do cols = 3
	rows := (n + cols - 1) / cols
	if rows < 1 do rows = 1
	h := px(LEVEL_BTN_H)
	gap := px(LEVEL_BTN_GAP)
	return i32(rows) * (h + gap) - gap
}

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
	y = px(130) + row * (h + gap) - i32(level_select_scroll)
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

	update_debug_input(screen)
	if debug_x_clicked(mouse) {
		debug_mode = false
		return
	}

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
			level_select_scroll = 0
		} else if button_clicked(scores_x, scores_y, scores_w, scores_h, mouse) {
			next = .SCORES
		} else if button_clicked(quit_x, quit_y, quit_w, quit_h, mouse) {
			quit = true
		}
	case .LEVEL_SELECT:
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			level_select_scroll -= wheel * f32(px(48))
		}
		top, bottom := level_select_view()
		max_scroll := px(130) + level_grid_height() - bottom
		if max_scroll < 0 do max_scroll = 0
		if level_select_scroll < 0 do level_select_scroll = 0
		if level_select_scroll > f32(max_scroll) do level_select_scroll = f32(max_scroll)
		for i in 0..<len(LEVELS) {
			x, y, w, h := level_button_rect(i)
			if y + h < top || y > bottom do continue
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
		} else if button_clicked(back_x, back_y, back_w, back_h, mouse) {
			next = .MENU
		}
	}
	return
}

// Digits for the level-clear and you-lost crawl. Held only while one of those menus is up.
// credits_overall is the raw total when the run has ended: last level cleared, or last life lost.
credits_digits: []u8
credits_overall: []u8
credits_scroll: f64
credits_for: Screen

free_digit_buf :: proc(buf: ^[]u8) {
	delete(buf^)
	buf^ = nil
}

free_end_credits :: proc() {
	free_digit_buf(&credits_digits)
	free_digit_buf(&credits_overall)
}

// Comma-grouped digits. A leading minus stays put.
comma_digits :: proc(text: string) -> []u8 {
	start := 0
	if len(text) > 0 && text[0] == '-' do start = 1
	d := len(text) - start
	if d <= 3 {
		out := make([]u8, len(text))
		copy(out, text)
		return out
	}
	commas := (d - 1) / 3
	out := make([]u8, len(text) + commas)
	n := 0
	copy(out[:start], text[:start])
	n = start
	first := d % 3
	if first == 0 do first = 3
	for i := 0; i < d; i += 1 {
		out[n] = text[start + i]
		n += 1
		done := i + 1
		if done < d && (done - first) % 3 == 0 {
			out[n] = ','
			n += 1
		}
	}
	return out
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
	dst^ = comma_digits(text)
}

// The total's digits stay ungrouped, matching the totals example.
store_raw_digits :: proc(dst: ^[]u8, score: ^big.Int) {
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

// `YYYY-MM-DD` at the start of a saved stamp, drawn as `mm/dd/yyyy`.
// `HH:MM:SS` after that is drawn as `h:mm:ss AM` or `PM`. A stamp with no clock keeps the date.
total_date_label :: proc(stamp: string, buf: ^[32]byte) -> (text: cstring, ok: bool) {
	if len(stamp) < 10 do return
	dash1 := -1
	dash2 := -1
	for i in 0..<len(stamp) {
		if stamp[i] == ' ' do break
		if stamp[i] != '-' do continue
		if dash1 < 0 do dash1 = i
		else if dash2 < 0 do dash2 = i
	}
	if dash1 < 1 || dash2 != dash1 + 3 do return
	day_end := dash2 + 3
	if day_end > len(stamp) do return
	if day_end < len(stamp) && stamp[day_end] != ' ' do return
	for i in 0..<dash1 {
		if stamp[i] < '0' || stamp[i] > '9' do return
	}
	for i in dash1 + 1 ..< dash2 {
		if stamp[i] < '0' || stamp[i] > '9' do return
	}
	for i in dash2 + 1 ..< day_end {
		if stamp[i] < '0' || stamp[i] > '9' do return
	}
	year_len := dash1
	if year_len > 6 do return
	n := 0
	buf[n] = stamp[dash1 + 1]
	n += 1
	buf[n] = stamp[dash1 + 2]
	n += 1
	buf[n] = '/'
	n += 1
	buf[n] = stamp[dash2 + 1]
	n += 1
	buf[n] = stamp[dash2 + 2]
	n += 1
	buf[n] = '/'
	n += 1
	for i in 0..<year_len {
		buf[n] = stamp[i]
		n += 1
	}
	clock_at := day_end + 1
	if day_end < len(stamp) && stamp[day_end] == ' ' && clock_at + 8 <= len(stamp) && stamp[clock_at + 2] == ':' && stamp[clock_at + 5] == ':' {
		digits := true
		offs := [6]int{0, 1, 3, 4, 6, 7}
		for off in offs {
			ch := stamp[clock_at + off]
			if ch < '0' || ch > '9' do digits = false
		}
		if digits {
			hour := int(stamp[clock_at] - '0') * 10 + int(stamp[clock_at + 1] - '0')
			minute := int(stamp[clock_at + 3] - '0') * 10 + int(stamp[clock_at + 4] - '0')
			second := int(stamp[clock_at + 6] - '0') * 10 + int(stamp[clock_at + 7] - '0')
			if hour <= 23 && minute <= 59 && second <= 59 && n + 12 < len(buf) {
				pm := hour >= 12
				h := hour
				if pm do h -= 12
				if h == 0 do h = 12
				buf[n] = ' '
				n += 1
				if h >= 10 {
					buf[n] = '1'
					n += 1
					buf[n] = u8('0' + h - 10)
					n += 1
				} else {
					buf[n] = u8('0' + h)
					n += 1
				}
				buf[n] = ':'
				n += 1
				buf[n] = u8('0' + minute / 10)
				n += 1
				buf[n] = u8('0' + minute % 10)
				n += 1
				buf[n] = ':'
				n += 1
				buf[n] = u8('0' + second / 10)
				n += 1
				buf[n] = u8('0' + second % 10)
				n += 1
				buf[n] = ' '
				n += 1
				if pm {
					buf[n] = 'P'
				} else {
					buf[n] = 'A'
				}
				n += 1
				buf[n] = 'M'
				n += 1
			}
		}
	}
	buf[n] = 0
	return cstring(&buf[0]), true
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

// The level-clear and you-lost crawl. A finished run adds the total in the totals-example order:
// STATS, the date and 12-hour time, Total Score:, MAX SCORE nX + when this level hit the cap, then the raw digits.
Credit_Kind :: enum {
	LEVEL_HEAD,
	LEVEL_DIGIT,
	BLANK,
	STATS,
	DATE,
	TOTAL_HEAD,
	MAX_LINE,
	TOTAL_DIGIT,
	STAT,
}

Credit_Row :: struct {
	kind:  Credit_Kind,
	index: int,
}

credit_row_height :: proc(kind: Credit_Kind, line_h, digit_h, stats_h: i32) -> i32 {
	if kind == .TOTAL_DIGIT do return digit_h
	if kind == .STATS do return stats_h
	return line_h
}

// Score digits wrap to the playfield. Stats follow. The block rises like credits and loops.
// The title and the buttons are drawn after this, so the crawl passes behind them.
draw_end_credits :: proc(mods: Power_Mods, balls: []Ball) {
	size := px(26)
	line_h := size + px(10)
	if line_h < 1 do line_h = 1
	digit_size := size / 2
	if digit_size < px(8) do digit_size = px(8)
	digit_h := digit_size + px(4)
	if digit_h < 1 do digit_h = 1
	stats_size := size * 3 / 2
	stats_h := stats_size + px(8)
	view_top := px(172)
	view_h := SCH - view_top
	if view_h < line_h do view_h = line_h

	level_cpl := credits_chars_per_line(size, SCW - px(32))
	if level_cpl < 1 do level_cpl = 1
	total_cpl := credits_chars_per_line(digit_size, SCW - px(32))
	if total_cpl < 1 do total_cpl = 1
	digit_lines := 1
	if len(credits_digits) > 0 {
		digit_lines = (len(credits_digits) + level_cpl - 1) / level_cpl
	}
	alive := 0
	for ball in balls {
		if ball.alive do alive += 1
	}

	date_buf: [32]byte
	date_text, has_date := total_date_label(run_total_stamp, &date_buf)
	show_total := len(credits_overall) > 0
	total_lines := 0
	if show_total {
		total_lines = 1
		if len(credits_overall) > 0 {
			total_lines = (len(credits_overall) + total_cpl - 1) / total_cpl
		}
		if total_lines < 1 do total_lines = 1
	}
	max_buf: [64]byte
	if show_total && round_max_score > 0 {
		n := append_text(&max_buf, 0, "MAX SCORE ")
		n = append_i64(&max_buf, n, round_max_score)
		n = append_text(&max_buf, n, "X +")
		max_buf[n] = 0
	}

	rows := make([dynamic]Credit_Row)
	defer delete(rows)
	append(&rows, Credit_Row{kind = .LEVEL_HEAD})
	for i in 0..<digit_lines {
		append(&rows, Credit_Row{kind = .LEVEL_DIGIT, index = i})
	}
	append(&rows, Credit_Row{kind = .BLANK})
	append(&rows, Credit_Row{kind = .STATS})
	if show_total {
		if has_date do append(&rows, Credit_Row{kind = .DATE})
		append(&rows, Credit_Row{kind = .TOTAL_HEAD})
		if round_max_score > 0 do append(&rows, Credit_Row{kind = .MAX_LINE})
		for i in 0..<total_lines {
			append(&rows, Credit_Row{kind = .TOTAL_DIGIT, index = i})
		}
	}
	for slot in 0..<8 + alive {
		append(&rows, Credit_Row{kind = .STAT, index = slot})
	}

	total_h := i32(0)
	for row in rows {
		total_h += credit_row_height(row.kind, line_h, digit_h, stats_h)
	}

	dt := f64(rl.GetFrameTime())
	if dt < 0 do dt = 0
	if dt > 0.05 do dt = 0.05
	credits_scroll += f64(px(36)) * dt
	span := f64(int(total_h) + int(view_h))
	if span < 1 do span = 1
	for credits_scroll >= span {
		credits_scroll -= span
	}

	digit_w := measure_text("0", size)
	if digit_w < 1 do digit_w = size
	block_w := i32(level_cpl) * digit_w
	digit_x := (SCW - block_w) / 2
	if digit_x < px(16) do digit_x = px(16)
	buf_cpl := level_cpl
	if total_cpl > buf_cpl do buf_cpl = total_cpl
	line_buf := make([]u8, buf_cpl + 1)
	defer delete(line_buf)

	base := f64(view_top + view_h) - credits_scroll
	y := base
	rl.BeginScissorMode(0, c.int(view_top), c.int(SCW), c.int(view_h))
	for row in rows {
		h := credit_row_height(row.kind, line_h, digit_h, stats_h)
		top := y
		y += f64(h)
		if y < f64(view_top) do continue
		if top > f64(view_top) + f64(view_h) do break
		ty := i32(top)
		switch row.kind {
		case .LEVEL_HEAD:
			if credits_for == .LEVEL_END {
				draw_centered_line("LEVEL SCORE", ty, size)
			} else {
				draw_centered_line("SCORE", ty, size)
			}
		case .LEVEL_DIGIT:
			draw_digit_line(credits_digits, row.index, level_cpl, digit_x, ty, size, line_buf)
		case .BLANK:
		case .STATS:
			draw_centered_line("STATS", ty, stats_size)
		case .DATE:
			draw_centered_line(date_text, ty, size)
		case .TOTAL_HEAD:
			draw_centered_line("Total Score:", ty, size)
		case .MAX_LINE:
			draw_centered_line(cstring(&max_buf[0]), ty, size)
		case .TOTAL_DIGIT:
			start := row.index * total_cpl
			end := start + total_cpl
			if start > len(credits_overall) do start = len(credits_overall)
			if end > len(credits_overall) do end = len(credits_overall)
			n := 0
			for k in start..<end {
				line_buf[n] = credits_overall[k]
				n += 1
			}
			if n < len(line_buf) do line_buf[n] = 0
			text := cstring(raw_data(line_buf))
			tw := measure_text(text, digit_size)
			draw_text(text, (SCW - tw) / 2, ty, digit_size, rl.WHITE)
		case .STAT:
			slot := row.index
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
			} else if slot == 7 {
				text = format_named_count(&label, "MAX SCORE ", round_max_score)
			} else {
				want := slot - 8
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
			draw_centered_line(text, ty, size)
		}
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
		// A failed save retries on a later frame. Pick up the total once that write lands.
		if run_show_overall && len(credits_overall) == 0 {
			store_raw_digits(&credits_overall, &run_overall)
		}
		return
	}
	store_digits(&credits_digits, score)
	if round_max_score > 0 {
		// The wrapped score block reads `MAX SCORE nX + <digits>` once the cap has been hit.
		prefix_buf: [32]byte
		n := 0
		for ch in "MAX SCORE " {
			prefix_buf[n] = u8(ch)
			n += 1
		}
		v := round_max_score
		tmp: [12]byte
		count := 0
		for v > 0 {
			tmp[count] = u8('0') + u8(v % 10)
			v /= 10
			count += 1
		}
		for i := count - 1; i >= 0; i -= 1 {
			prefix_buf[n] = tmp[i]
			n += 1
		}
		for ch in "X + " {
			prefix_buf[n] = u8(ch)
			n += 1
		}
		combined := make([]u8, n + len(credits_digits))
		copy(combined, prefix_buf[:n])
		copy(combined[n:], credits_digits)
		free_digit_buf(&credits_digits)
		credits_digits = combined
	}
	if run_show_overall {
		store_raw_digits(&credits_overall, &run_overall)
	} else {
		free_digit_buf(&credits_overall)
	}
	credits_scroll = 0
	credits_for = screen
}

// Each saved total is flat text in the center of the playfield: the date, Total Score:, then the raw digits. It scales from a speck to larger than the screen.
// fill is the larger of the block's width and height, as a fraction of the playfield.
// The size is multiplied by the same amount each moment, so the zoom does not rush and then crawl.
// The next score waits SCORE_POP_GAP seconds after the previous one finishes, so the zooms do not overlap.
SCORE_POP_CPL :: 48
SCORE_POP_SECONDS :: f32(6)
SCORE_POP_GAP :: f32(1)
SCORE_POP_TINY :: f32(0.05)
SCORE_POP_CLEAR :: f32(0.4)
SCORE_POP_FADE :: f32(2.05)
SCORE_POP_GIANT :: f32(2.5)
SCORE_POP_REF :: f32(100)

score_pop_t: f32

// phase 0 is the speck. phase 1 is the giant size. Equal time covers an equal ratio of sizes.
score_pop_fill :: proc(phase: f32) -> f32 {
	p := phase
	if p < 0 do p = 0
	if p > 1 do p = 1
	if SCORE_POP_TINY < 0.001 do return SCORE_POP_GIANT
	return SCORE_POP_TINY * math.pow(SCORE_POP_GIANT / SCORE_POP_TINY, p)
}

score_pop_alpha :: proc(fill: f32) -> u8 {
	in_span := SCORE_POP_CLEAR - SCORE_POP_TINY
	in_t := f32(1)
	if in_span > 0.001 {
		in_t = (fill - SCORE_POP_TINY) / in_span
	}
	if in_t < 0 do in_t = 0
	if in_t > 1 do in_t = 1
	in_t = in_t * in_t * (3 - 2 * in_t)
	out_t := f32(1)
	out_span := SCORE_POP_GIANT - SCORE_POP_FADE
	if fill > SCORE_POP_FADE && out_span > 0.001 {
		out_t = 1 - (fill - SCORE_POP_FADE) / out_span
		if out_t < 0 do out_t = 0
	}
	a := in_t * out_t * 255
	if a < 0 do a = 0
	if a > 255 do a = 255
	return u8(a + 0.5)
}

score_measure :: proc(text: cstring, size: f32) -> f32 {
	ensure_game_font()
	base := game_font.baseSize
	if base < 1 do base = 1
	if game_font.texture.id != 0 {
		return rl.MeasureTextEx(game_font, text, size, size / f32(base)).x
	}
	px := i32(size + 0.5)
	if px < 1 do px = 1
	return f32(rl.MeasureText(text, px))
}

score_draw_line :: proc(text: cstring, x, y, size: f32, color: rl.Color) {
	ensure_game_font()
	base := game_font.baseSize
	if base < 1 do base = 1
	if game_font.texture.id != 0 {
		rl.DrawTextEx(game_font, text, {x, y}, size, size / f32(base), color)
		return
	}
	px := i32(size + 0.5)
	if px < 1 do px = 1
	rl.DrawText(text, i32(x), i32(y), px, color)
}

score_digit_line :: proc(digits: string, line_i: int, buf: ^[SCORE_POP_CPL + 1]byte) -> int {
	start := line_i * SCORE_POP_CPL
	end := start + SCORE_POP_CPL
	if start > len(digits) do start = len(digits)
	if end > len(digits) do end = len(digits)
	n := 0
	for i in start ..< end {
		buf[n] = digits[i]
		n += 1
	}
	buf[n] = 0
	return n
}

// One score at a time. Its scale moves at a constant rate, then the screen stays clear for SCORE_POP_GAP.
draw_score_pops :: proc() {
	n := len(score_lines)
	if n == 0 || SCW < 1 || SCH < 1 do return
	dt := rl.GetFrameTime()
	if dt < 0 do dt = 0
	if dt > 0.05 do dt = 0.05
	slot := SCORE_POP_SECONDS + SCORE_POP_GAP
	cycle := slot * f32(n)
	if cycle < 0.001 do return
	score_pop_t += dt
	for score_pop_t >= cycle do score_pop_t -= cycle
	if score_pop_t < 0 do score_pop_t = 0

	index := int(score_pop_t / slot)
	if index < 0 do index = 0
	if index >= n do index = n - 1
	local := score_pop_t - f32(index) * slot
	if local < 0 || local >= SCORE_POP_SECONDS do return
	draw_score_pop(score_lines[index].stamp, score_lines[index].text, local / SCORE_POP_SECONDS)
}

// Date and 12-hour time, then `Total Score:`, then the raw digits at a smaller size. No commas.
draw_score_pop :: proc(stamp: string, digits: string, phase: f32) {
	fill := score_pop_fill(phase)
	alpha := score_pop_alpha(fill)
	if alpha == 0 do return

	date_buf: [32]byte
	date_text, has_date := total_date_label(stamp, &date_buf)
	digit_lines := 0
	if len(digits) > 0 {
		digit_lines = (len(digits) + SCORE_POP_CPL - 1) / SCORE_POP_CPL
	}

	head_ref := SCORE_POP_REF
	digit_ref := SCORE_POP_REF * 0.42
	head_step := head_ref * 7 / 6
	digit_step := digit_ref * 7 / 6
	max_w := score_measure("Total Score:", head_ref)
	ink_h := head_ref
	if has_date {
		w := score_measure(date_text, head_ref)
		if w > max_w do max_w = w
		ink_h = head_step + head_ref
	}
	line_buf: [SCORE_POP_CPL + 1]byte
	if digit_lines > 0 {
		ink_h += head_step - head_ref
		ink_h += digit_step * f32(digit_lines - 1) + digit_ref
		for li in 0..<digit_lines {
			if score_digit_line(digits, li, &line_buf) == 0 do continue
			w := score_measure(cstring(&line_buf[0]), digit_ref)
			if w > max_w do max_w = w
		}
	}
	limit := ink_h / f32(SCH)
	wide := max_w / f32(SCW)
	if wide > limit do limit = wide
	if limit < 0.001 do return
	scale := fill / limit
	head_size := head_ref * scale
	digit_size := digit_ref * scale
	head_pitch := head_step * scale
	digit_pitch := digit_step * scale

	color := rl.Color{255, 255, 255, alpha}
	y := (f32(SCH) - ink_h * scale) * 0.5
	if has_date {
		dw := score_measure(date_text, head_size)
		score_draw_line(date_text, (f32(SCW) - dw) * 0.5, y, head_size, color)
		y += head_pitch
	}
	tw := score_measure("Total Score:", head_size)
	score_draw_line("Total Score:", (f32(SCW) - tw) * 0.5, y, head_size, color)
	y += head_pitch
	for li in 0..<digit_lines {
		if score_digit_line(digits, li, &line_buf) == 0 do continue
		text := cstring(&line_buf[0])
		w := score_measure(text, digit_size)
		score_draw_line(text, (f32(SCW) - w) * 0.5, y, digit_size, color)
		y += digit_pitch
	}
}

// Main menu, level select, and totals fill the screen. Pause, level clear, and you lost draw over the playfield.
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
		draw_button("TOTALS", scores_x, scores_y, scores_w, scores_h, mouse)
		draw_button("QUIT", quit_x, quit_y, quit_w, quit_h, mouse)
	case .LEVEL_SELECT:
		draw_centered_text("SELECT LEVEL", px(48), px(36), rl.WHITE)
		top, bottom := level_select_view()
		rl.BeginScissorMode(0, top, SCW, bottom - top)
		for i in 0..<len(LEVELS) {
			buf: [16]byte
			label := format_level_label(i, &buf)
			x, y, w, h := level_button_rect(i)
			draw_button(label, x, y, w, h, mouse)
		}
		rl.EndScissorMode()
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
		draw_score_pops()
		draw_centered_text("TOTALS", px(48), px(36), rl.WHITE)
		if len(score_lines) == 0 {
			draw_centered_text("NO SCORES", px(220), px(32), rl.WHITE)
		}
		clear_x, clear_y, clear_w, clear_h := scores_button_rect(0)
		back_x, back_y, back_w, back_h := scores_button_rect(1)
		draw_button("CLEAR SCORES", clear_x, clear_y, clear_w, clear_h, mouse)
		draw_button("BACK", back_x, back_y, back_w, back_h, mouse)
	}
}
