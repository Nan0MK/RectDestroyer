package src

import rl "vendor:raylib"

Screen :: enum {
	MENU,
	LEVEL_SELECT,
	PLAY,
	PAUSE,
	LEVEL_END,
	LOST,
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
		quit_x, quit_y, quit_w, quit_h := main_button_rect(2)
		if button_clicked(play_x, play_y, play_w, play_h, mouse) && len(LEVELS) > 0 {
			next = .PLAY
			start = true
			level_index = 0
		} else if button_clicked(levels_x, levels_y, levels_w, levels_h, mouse) {
			next = .LEVEL_SELECT
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
	case .LOST:
		menu_x, menu_y, menu_w, menu_h := main_button_rect(0)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(1)
		if button_clicked(menu_x, menu_y, menu_w, menu_h, mouse) {
			next = .MENU
		} else if button_clicked(quit_x, quit_y, quit_w, quit_h, mouse) {
			quit = true
		}
	}
	return
}

// Main menu and level select fill the screen. Pause, level clear, and you lost draw over the playfield.
draw_menus :: proc(screen: Screen, mouse: rl.Vector2, score: i64, playing_level: int) {
	switch screen {
	case .MENU:
		draw_centered_text("RECT-DESTROYER!", px(150), px(40), rl.WHITE)
		play_x, play_y, play_w, play_h := main_button_rect(0)
		levels_x, levels_y, levels_w, levels_h := main_button_rect(1)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(2)
		draw_button("PLAY", play_x, play_y, play_w, play_h, mouse)
		draw_button("LEVEL SELECT", levels_x, levels_y, levels_w, levels_h, mouse)
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
	case .PAUSE:
		rl.DrawRectangle(0, 0, SCW, SCH, rl.Color{0, 0, 0, 170})
		draw_centered_text("PAUSED", px(150), px(40), rl.WHITE)
		resume_x, resume_y, resume_w, resume_h := main_button_rect(0)
		menu_x, menu_y, menu_w, menu_h := main_button_rect(1)
		draw_button("RESUME", resume_x, resume_y, resume_w, resume_h, mouse)
		draw_button("MAIN MENU", menu_x, menu_y, menu_w, menu_h, mouse)
	case .LEVEL_END:
		rl.DrawRectangle(0, 0, SCW, SCH, rl.Color{0, 0, 0, 170})
		// Cover the playfield title so the score sits on a solid band.
		rl.DrawRectangle(0, px(105), SCW, px(300), rl.BLACK)
		draw_centered_text("LEVEL CLEAR", px(120), px(40), rl.WHITE)
		buf: [40]byte
		text := format_score_label(score, &buf)
		score_size := px(32)
		tw := measure_text(text, score_size)
		draw_text(text, (SCW - tw) / 2, px(185), score_size, rl.WHITE)
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
		rl.DrawRectangle(0, px(105), SCW, px(300), rl.BLACK)
		draw_centered_text("YOU LOST", px(120), px(40), rl.WHITE)
		buf: [40]byte
		text := format_score_label(score, &buf)
		score_size := px(32)
		tw := measure_text(text, score_size)
		draw_text(text, (SCW - tw) / 2, px(185), score_size, rl.WHITE)
		menu_x, menu_y, menu_w, menu_h := main_button_rect(0)
		quit_x, quit_y, quit_w, quit_h := main_button_rect(1)
		draw_button("MAIN MENU", menu_x, menu_y, menu_w, menu_h, mouse)
		draw_button("QUIT", quit_x, quit_y, quit_w, quit_h, mouse)
	}
}
