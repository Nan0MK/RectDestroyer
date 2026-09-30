///RECT-DESTROYER!
// A Brickbreaker clone with:
// 10 levels,
// 5 powerups,
// main menu,
// sounds,
// mouse controls,
// @___________________________________________@
// 1. Movable bouncepad, with mouse controls. (CHECK! 7/10/2026)
// 2. Ball that can bounce off pad and walls, except for bottom wall. (CHECK! 7/15/2026)
// 3. Breakable bricks, with ball physics.
//

package src
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:time"
import rl "vendor:raylib"

// Screen
SCW: i32 = 800; SCH: i32 = 600
SCREEN_TOP: = SCH - SCH; SCREEN_BOT: = SCH
SCREEN_LEFT: = SCW - SCW; SCREEN_RIGHT: = SCW

// Pad
PADW: i32 = 150; PADH: i32 = 20
PAD_TOP: i32 = SCREEN_BOT - (PADH + PADH); PAD_BOT: i32 = SCREEN_BOT - PADH

// Ball
BALL_R :: 10

Ball :: struct {
	x, y:            i32,
	speed_x, speed_y: i32,
	alive:           bool,
}

// Played in order. Add a file here when a new level exists.
LEVELS := [?]string{
	"src/levels/lvl1.txt",
	"src/levels/lvl2.txt",
	"src/levels/lvl3.txt",
}

bricks_left :: proc(bricks: [dynamic]Brick) -> int {
	n := 0
	for brick in bricks {
		if brick.hp > 0 do n += 1
	}
	return n
}

serve_ball :: proc(balls: ^[dynamic]Ball) {
	clear(balls)
	append(balls, Ball{x = SCW / 2, y = SCH / 2, speed_x = 1, speed_y = 1, alive = true})
}

game :: proc() {
	rl.InitWindow(SCW, SCH, "RECT-DESTROYER!")

	rl.SetTargetFPS(500)
	rand.reset(u64(time.to_unix_nanoseconds(time.now())))
	level_index := 0
	bricks := generateRects(LEVELS[level_index])

	balls := make([dynamic]Ball)
	defer delete(balls)
	serve_ball(&balls)

	falling := make([dynamic]Falling_Powerup)
	defer delete(falling)
	pad_w := PADW
	multiply_until: f64 = 0

	for !rl.WindowShouldClose() {
		// ___ Live data updates
		padPos : f32 = rl.GetMousePosition().x
		mouseLocation := rl.GetMousePosition()

		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
			serve_ball(&balls)
		}

		pad_left := i32(padPos) - pad_w / 2
		pad_right := i32(padPos) + pad_w / 2

		ball_count := len(balls)
		for i in 0..<ball_count {
			ball := &balls[i]
			if !ball.alive do continue

			ball.y += ball.speed_y
			ball.x += ball.speed_x
			// if ball.y > SCREEN_BOT {
			// 	ball.speed_y = -ball.speed_y
			// }
			if ball.y > SCH {
				ball.alive = false
				continue
			}
			if ball.y < SCREEN_TOP do ball.speed_y = -ball.speed_y
			if ball.x > SCREEN_RIGHT do ball.speed_x = -ball.speed_x
			if ball.x < SCREEN_LEFT do ball.speed_x = -ball.speed_x
			if ball.x > pad_left && ball.x < pad_right && ball.y < PAD_BOT {
				if ball.y > PAD_TOP {
					ball.speed_y = -ball.speed_y
					// fmt.printf("Collided with pad")
				}
			}
			if ball.y < PAD_BOT && ball.y > PAD_TOP {
				if ball.x > pad_right {
					ball.speed_x = -ball.speed_x
					// ball.speed_y = 1
				}
				if ball.y < pad_left {
					ball.speed_x = -ball.speed_x
					// ball.speed_y = 1
				}
			}

			hit, broke, hp_before, brick_index := collideRects(&bricks, ball)
			if hit && hp_before > 1 && rl.GetTime() < multiply_until {
				spawn_multiplied_balls(&balls, ball.x, ball.y)
			}
			if broke {
				grant_brick_drops(bricks[brick_index], &falling, &pad_w, &multiply_until)
			}
		}

		// Next file when this board is empty. The last level just stays cleared.
		if bricks_left(bricks) == 0 && level_index + 1 < len(LEVELS) {
			level_index += 1
			delete(bricks)
			bricks = generateRects(LEVELS[level_index])
			clear(&falling)
			pad_w = PADW
			multiply_until = 0
			serve_ball(&balls)
		}

		update_falling_powerups(&falling, pad_left, 570, PADH, &pad_w, rl.GetFrameTime(), &multiply_until)


		// ___
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)
		rl.DrawText("RECT-DESTROYER!", 190, 200, 20, rl.WHITE)

		mouseLocationText : string = fmt.tprintf("  X = %v, Y = %v", mouseLocation.x, mouseLocation.y)
		// rl.DrawText(fmt.caprintf(mouseLocationText), i32(mouseLocation.x), i32(mouseLocation.y), 35, rl.RED)

		rl.DrawRectangle(pad_left, 570, pad_w, PADH, rl.WHITE)
		// rl.DrawRectangle(PAD_LEFT, PAD_TOP, 12, 12, rl.GREEN)
		// rl.DrawRectangle(PAD_RIGHT, PAD_TOP, 12, 12, rl.GREEN)
		// rl.DrawRectangle(PAD_LEFT, PAD_BOT, 12, 12, rl.GREEN)
		// rl.DrawRectangle(PAD_RIGHT, PAD_BOT, 12, 12, rl.GREEN)

		for ball in balls {
			if !ball.alive do continue
			rl.DrawCircle(ball.x, ball.y, BALL_R, rl.RED)
		}

		renderRects(bricks)
		render_falling_powerups(falling)
		render_multiply_timer(multiply_until)

		rl.EndDrawing()
	}
	delete(bricks)
	rl.CloseWindow()
}


main :: proc() {
	fmt.printf("%v", os.get_working_directory(context.allocator))
	fmt.println("RECT-DESTROYER!")
	game()
}
