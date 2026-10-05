package src

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// Main menu and level select. The playfield is cleared black, then these sheets fly at the camera.
// PNG alpha is left alone. The tint only fades a sheet in from black while it is still far away.
STAR_A_COUNT :: 10
STAR_B_SLOTS :: 3
STAR_A_FAR :: f32(50)
STAR_B_FAR :: f32(80)
STAR_BEHIND :: f32(0.3)
STAR_A_SPEED :: f32(8)
STAR_B_SPEED :: f32(10)
STAR_B_EVERY :: f64(4)
STAR_A_CLEAR :: f32(38)
STAR_B_CLEAR :: f32(62)
STAR_SIZE :: f32(100)
STAR_SPREAD :: f32(24)

Star_Sheet :: struct {
	x, y, z: f32,
	rot:     f32,
	alive:   bool,
}

star_a_tex: rl.Texture2D
star_b_tex: rl.Texture2D
star_a: [STAR_A_COUNT]Star_Sheet
star_b: [STAR_B_SLOTS]Star_Sheet
star_b_next: f64
starfield_ready: bool

load_star_texture :: proc(path: cstring) -> rl.Texture2D {
	tex := rl.LoadTexture(path)
	if tex.id == 0 {
		fmt.eprintf("Failed to load texture '%s'\n", path)
		return {}
	}
	rl.SetTextureFilter(tex, .BILINEAR)
	rl.SetTextureWrap(tex, .CLAMP)
	return tex
}

place_star :: proc(sheet: ^Star_Sheet, z: f32) {
	sheet.x = rand.float32_range(-STAR_SPREAD, STAR_SPREAD)
	sheet.y = rand.float32_range(-STAR_SPREAD, STAR_SPREAD)
	sheet.z = z
	sheet.rot = rand.float32_range(0, 360)
	sheet.alive = true
}

ensure_starfield :: proc() {
	if starfield_ready || !rl.IsWindowReady() do return
	starfield_ready = true

	star_a_tex = load_star_texture("src/textures/starfield_a.png")
	star_b_tex = load_star_texture("src/textures/starfield_b.png")

	// Spread through the lane, with the nearest already well in front of the camera.
	start_near: f32 = 18
	span := STAR_A_FAR - start_near
	for i in 0 ..< STAR_A_COUNT {
		place_star(&star_a[i], start_near + (f32(i) + 0.5) * span / f32(STAR_A_COUNT))
	}
	star_b_next = rl.GetTime() + STAR_B_EVERY
}

unload_starfield :: proc() {
	if star_a_tex.id != 0 do rl.UnloadTexture(star_a_tex)
	if star_b_tex.id != 0 do rl.UnloadTexture(star_b_tex)
	star_a_tex = {}
	star_b_tex = {}
	starfield_ready = false
}

// 0 at the far spawn, 255 once the sheet is still far but clear of the fog.
star_fog :: proc(z, far, clear_at: f32) -> u8 {
	if z <= clear_at do return 255
	if z >= far do return 0
	span := far - clear_at
	if span < 0.001 do return 255
	t := (far - z) / span
	t = t * t * (3 - 2 * t)
	return u8(t * 255 + 0.5)
}

advance_star_a :: proc(sheet: ^Star_Sheet, dt: f32) {
	sheet.z -= STAR_A_SPEED * dt
	for sheet.z <= STAR_BEHIND {
		sheet.z += STAR_A_FAR - STAR_BEHIND
		place_star(sheet, sheet.z)
	}
}

spawn_star_b :: proc() {
	for &sheet in star_b {
		if sheet.alive do continue
		place_star(&sheet, STAR_B_FAR)
		return
	}
}

update_starfield :: proc(dt: f32) {
	if dt > 0 {
		for &sheet in star_a {
			advance_star_a(&sheet, dt)
		}
		for &sheet in star_b {
			if !sheet.alive do continue
			sheet.z -= STAR_B_SPEED * dt
			if sheet.z <= STAR_BEHIND do sheet.alive = false
		}
	}
	now := rl.GetTime()
	if now >= star_b_next {
		spawn_star_b()
		star_b_next = now + STAR_B_EVERY
	}
}

draw_star_sheet :: proc(camera: rl.Camera3D, tex: rl.Texture2D, sheet: Star_Sheet, alpha: u8) {
	if tex.id == 0 || alpha == 0 do return
	source := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
	size := rl.Vector2{STAR_SIZE, STAR_SIZE}
	rl.DrawBillboardPro(
		camera,
		tex,
		source,
		{sheet.x, sheet.y, sheet.z},
		{0, 1, 0},
		size,
		{STAR_SIZE * 0.5, STAR_SIZE * 0.5},
		sheet.rot,
		{255, 255, 255, alpha},
	)
}

// Far sheets first, so a nearer sheet's transparent pixels do not hide the ones behind it.
draw_starfield :: proc() {
	ensure_starfield()
	dt := rl.GetFrameTime()
	if dt < 0 do dt = 0
	if dt > 0.05 do dt = 0.05
	update_starfield(dt)

	cam := rl.Camera3D{
		position   = {0, 0, 0},
		target     = {0, 0, 1},
		up         = {0, 1, 0},
		fovy       = 70,
		projection = .PERSPECTIVE,
	}

	rl.BeginMode3D(cam)
	rlgl.DisableDepthTest()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()

	drawn: [STAR_A_COUNT + STAR_B_SLOTS]int
	n := 0
	for i in 0 ..< STAR_A_COUNT {
		drawn[n] = i
		n += 1
	}
	for i in 0 ..< STAR_B_SLOTS {
		if !star_b[i].alive do continue
		drawn[n] = STAR_A_COUNT + i
		n += 1
	}
	for i in 1 ..< n {
		key := drawn[i]
		j := i
		for j > 0 && star_draw_z(drawn[j - 1]) < star_draw_z(key) {
			drawn[j] = drawn[j - 1]
			j -= 1
		}
		drawn[j] = key
	}
	for i in 0 ..< n {
		id := drawn[i]
		if id < STAR_A_COUNT {
			sheet := star_a[id]
			draw_star_sheet(cam, star_a_tex, sheet, star_fog(sheet.z, STAR_A_FAR, STAR_A_CLEAR))
		} else {
			sheet := star_b[id - STAR_A_COUNT]
			draw_star_sheet(cam, star_b_tex, sheet, star_fog(sheet.z, STAR_B_FAR, STAR_B_CLEAR))
		}
	}

	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
	rlgl.EnableDepthTest()
	rl.EndMode3D()
}

star_draw_z :: proc(id: int) -> f32 {
	if id < STAR_A_COUNT do return star_a[id].z
	return star_b[id - STAR_A_COUNT].z
}
