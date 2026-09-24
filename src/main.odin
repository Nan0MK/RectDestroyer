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
import "core:os"
import rl "vendor:raylib"

// Screen
SCW: i32 = 800; SCH: i32 = 600
SCREEN_TOP: = SCH - SCH; SCREEN_BOT: = SCH
SCREEN_LEFT: = SCW - SCW; SCREEN_RIGHT: = SCW

// Pad
PADW: i32 = 150; PADH: i32 = 20
PAD_TOP: i32 = SCREEN_BOT - (PADH + PADH); PAD_BOT: i32 = SCREEN_BOT - PADH

// Brick
RECT_W: i32 = 70; RECT_H: i32 = 50
RECT_COLOR: rl.Color = rl.GREEN
generateRects :: proc(level : string) -> [dynamic]rune {
    //Read from text file to place rects in the level.
    inData, err := os.read_entire_file(level, context.allocator)

    // if err != nil {
    //     fmt.eprintf("Failed to read '%s': %v\n", level, err)
    // }

    rects := string(inData)
    // fmt.printf("___\nRECTS:\n%s\n___\n", rects)
    delete(inData)

    levelData := [dynamic]rune {}
    for rect in rects {
   		append(&levelData, rect)
    }
    return levelData
}
renderRects :: proc(levelData : [dynamic]rune){
	wid : i32 = 7
	i : i32 = 0
	j : i32 = 0
	for data in levelData {
		for i < wid {
			switch data {
			case 'B':
				rl.DrawRectangle(10 + ((RECT_W + 5) * (i + 2)), -400 + ((RECT_H + 5) * j), RECT_W, RECT_H, rl.RED)
			}
			i += 1
		}
		i = 0
		if i == 0 {
			j+=1
		}
	}
}
collideRects :: proc(levelData : ^[dynamic]rune, ballPosX : ^i32, ballPosY : ^i32){
	for data in levelData {
		// This could be a problem lol.
	}
}


game :: proc() {
	rl.InitWindow(SCW, SCH, "RECT-DESTROYER!")

	rl.SetTargetFPS(500)
	level1 := generateRects("src/lvl1.txt")

	ballPosX : i32 = SCW/2; ballPosY : i32 = SCH/2
	ballSpeedX: i32 = 1; ballSpeedY: i32 = 1

	for !rl.WindowShouldClose() {
		// ___ Live data updates
		padPos : f32 = rl.GetMousePosition().x

		PAD_LEFT: i32 = (i32(padPos) + PADW/2) - (PADW - PADW); PAD_RIGHT: i32 = (i32(padPos) + PADW/2) - PADW

		mouseLocation := rl.GetMousePosition()

		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
			ballPosX = SCW/2; ballPosY = SCH/2
		}


		ballPosY += ballSpeedY
		ballPosX += ballSpeedX
		// if ballPosY > SCREEN_BOT {
		// 	ballSpeedY = -ballSpeedY
		// }
		if ballPosY < SCREEN_TOP {
			ballSpeedY = -ballSpeedY
		}
		if ballPosX > SCREEN_RIGHT {
			ballSpeedX = -ballSpeedX
		}
		if ballPosX < SCREEN_LEFT {
			ballSpeedX = -ballSpeedX
		}
		if ballPosX > PAD_RIGHT && ballPosX < PAD_LEFT && ballPosY < PAD_BOT {
			if ballPosY > PAD_TOP {
				ballSpeedY = -ballSpeedY
				// fmt.printf("Collided with pad")
			}
		}
		if ballPosY < PAD_BOT && ballPosY > PAD_TOP {
			if ballPosX > PAD_LEFT {
				ballSpeedX = -ballSpeedX
				// ballSpeedY = 1
			}
			if ballPosY < PAD_RIGHT {
				ballSpeedX = -ballSpeedX
				// ballSpeedY = 1
			}
		}
		// RECT COLLISION HERE


		// ___
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)
		rl.DrawText("RECT-DESTROYER!", 190, 200, 20, rl.WHITE)

		mouseLocationText : string = fmt.tprintf("  X = %v, Y = %v", mouseLocation.x, mouseLocation.y)
		// rl.DrawText(fmt.caprintf(mouseLocationText), i32(mouseLocation.x), i32(mouseLocation.y), 35, rl.RED)

		rl.DrawRectangle(i32(padPos) - (PADW/2), 570.0, PADW, PADH, rl.WHITE)
		// rl.DrawRectangle(PAD_LEFT, PAD_TOP, 12, 12, rl.GREEN)
		// rl.DrawRectangle(PAD_RIGHT, PAD_TOP, 12, 12, rl.GREEN)
		// rl.DrawRectangle(PAD_LEFT, PAD_BOT, 12, 12, rl.GREEN)
		// rl.DrawRectangle(PAD_RIGHT, PAD_BOT, 12, 12, rl.GREEN)

		rl.DrawCircle(ballPosX, ballPosY, 10, rl.RED)

		renderRects(level1)

		rl.EndDrawing()
	}
	rl.CloseWindow()
}


main :: proc() {
	fmt.printf("%v", os.get_working_directory(context.allocator))
	fmt.println("RECT-DESTROYER!")
	game()
}
