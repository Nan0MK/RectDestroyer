package src

import "core:c"
import "core:fmt"
import "core:mem"
import rl "vendor:raylib"

// src/textures/font.png is 100×340. Five columns, sixteen rows. Cells are 19×20.
// A 1px line of FONT_KEY separates them: columns at x = 19, 39, 59, 79, 99 and rows at y = 20, 41, ...
// There is no key line on the top or the left, and y = 336..339 is leftover past the last line.
// Reading order, including the blank cells:
//   A–Z, a–z, blank, blank, blank, 0–9, . " ' , !, ? - _ / \, : ^ v > <
// The downward chevron shares v with the letter. The letter comes first, so that is the one drawn.
// Space is the first blank after z.
FONT_IMAGE_W :: 100
FONT_IMAGE_H :: 340
FONT_COLS :: 5
FONT_ROWS :: 16
FONT_GLYPHS :: FONT_COLS * FONT_ROWS
FONT_CELL_W :: 19
FONT_CELL_H :: 20
FONT_COL_PITCH :: 20
FONT_ROW_PITCH :: 21
FONT_KEY :: rl.Color{255, 0, 110, 255}
FONT_PAPER :: rl.Color{0, 0, 0, 255}

FONT_RUNES := [FONT_GLYPHS]rune{
	'A', 'B', 'C', 'D', 'E',
	'F', 'G', 'H', 'I', 'J',
	'K', 'L', 'M', 'N', 'O',
	'P', 'Q', 'R', 'S', 'T',
	'U', 'V', 'W', 'X', 'Y',
	'Z', 'a', 'b', 'c', 'd',
	'e', 'f', 'g', 'h', 'i',
	'j', 'k', 'l', 'm', 'n',
	'o', 'p', 'q', 'r', 's',
	't', 'u', 'v', 'w', 'x',
	'y', 'z', ' ', 0, 0,
	'0', '1', '2', '3', '4',
	'5', '6', '7', '8', '9',
	'.', '"', '\'', ',', '!',
	'?', '-', '_', '/', '\\',
	':', '^', 'v', '>', '<',
}

game_font: rl.Font
game_font_ready: bool

// One source pixel of the divider, scaled with the glyph. Draw and measure both use this.
font_spacing :: proc(size: i32) -> f32 {
	base := game_font.baseSize
	if base < 1 do base = 1
	return f32(size) / f32(base)
}

ensure_game_font :: proc() {
	if game_font_ready || !rl.IsWindowReady() do return
	game_font_ready = true
	game_font = load_game_font()
}

unload_game_font :: proc() {
	// UnloadFont ignores the default font. A failed load leaves this empty.
	if game_font.texture.id != 0 {
		rl.UnloadFont(game_font)
	}
	game_font = {}
	game_font_ready = false
}

draw_text :: proc(text: cstring, x, y, size: i32, color: rl.Color) {
	ensure_game_font()
	if game_font.texture.id != 0 {
		rl.DrawTextEx(game_font, text, {f32(x), f32(y)}, f32(size), font_spacing(size), color)
		return
	}
	rl.DrawText(text, x, y, size, color)
}

measure_text :: proc(text: cstring, size: i32) -> i32 {
	ensure_game_font()
	if game_font.texture.id != 0 {
		width := rl.MeasureTextEx(game_font, text, f32(size), font_spacing(size))
		return i32(width.x + 0.5)
	}
	return rl.MeasureText(text, size)
}

// Glyph rectangles stay inside the cells, so the divider is not part of a character.
// Paper and the divider become transparent so a tint colors the white strokes only.
load_game_font :: proc() -> rl.Font {
	img := rl.LoadImage("src/textures/font.png")
	if img.data == nil {
		fmt.eprintf("Failed to load texture 'src/textures/font.png'\n")
		return {}
	}
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	if img.width != FONT_IMAGE_W || img.height != FONT_IMAGE_H {
		fmt.eprintf("Font texture is %v by %v\n", img.width, img.height)
		rl.UnloadImage(img)
		return {}
	}
	rl.ImageColorReplace(&img, FONT_PAPER, rl.BLANK)
	rl.ImageColorReplace(&img, FONT_KEY, rl.BLANK)

	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	if tex.id == 0 {
		fmt.eprintf("Failed to load texture 'src/textures/font.png'\n")
		return {}
	}
	rl.SetTextureFilter(tex, .POINT)

	glyph_bytes := FONT_GLYPHS * size_of(rl.GlyphInfo)
	rec_bytes := FONT_GLYPHS * size_of(rl.Rectangle)
	glyphs := cast([^]rl.GlyphInfo)rl.MemAlloc(c.uint(glyph_bytes))
	recs := cast([^]rl.Rectangle)rl.MemAlloc(c.uint(rec_bytes))
	if glyphs == nil || recs == nil {
		if glyphs != nil do rl.MemFree(glyphs)
		if recs != nil do rl.MemFree(recs)
		rl.UnloadTexture(tex)
		fmt.eprintf("Failed to load texture 'src/textures/font.png'\n")
		return {}
	}
	// UnloadFont frees these with the raylib allocator and unloads each glyph image.
	mem.zero(rawptr(glyphs), glyph_bytes)
	mem.zero(rawptr(recs), rec_bytes)

	for i in 0..<FONT_GLYPHS {
		col := i % FONT_COLS
		row := i / FONT_COLS
		rec := &recs[i]
		rec.x = f32(col * FONT_COL_PITCH)
		rec.y = f32(row * FONT_ROW_PITCH)
		rec.width = FONT_CELL_W
		rec.height = FONT_CELL_H
		glyph := &glyphs[i]
		glyph.value = FONT_RUNES[i]
	}

	return {
		baseSize = FONT_CELL_H,
		glyphCount = FONT_GLYPHS,
		glyphPadding = 0,
		texture = tex,
		recs = recs,
		glyphs = glyphs,
	}
}
