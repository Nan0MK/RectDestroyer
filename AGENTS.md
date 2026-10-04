# RECT-DESTROYER

Odin + raylib brickbreaker. One package, `package src`, built from the repo root:

```
odin check src
odin run src
```

Level and config paths are relative to that working directory (`src/levels/`, `src/rect_types.txt`, `src/powerup_types.txt`). The window opens at 800×600 and can be resized. The playfield is at least 800×600 and grows so the largest level fits, with 24 pixels of side margin and a 220-pixel lane under the lowest brick row. Each frame is drawn at that size and fitted uniformly into the window, with black bars when the aspect ratios differ. The mouse is mapped back through that fit. Target FPS is 500. Each level and each life sticks the ball to the paddle until left click. A still paddle sends it straight up at 1 pixel per frame. Paddle movement sets the launch angle and adds speed. That launch stays at 3 pixels per frame or under until `fast` is on. `fast` raises the faster axis on each bounce, up to 8, and ends when a ball is lost.

## Session resume

When you work on this project, leave a script in the repo root that resumes your Grok session. Use `resume.ps1` on Windows, or `resume.sh` on Linux and Mac. It should `cd` to the repo root and run `grok --resume` with the id of the session you are in. That id is the directory name under `~/.grok/sessions/` for this repo.

Add that filename to `.gitignore` if it is not already listed. Do not commit the script.

## Keep this file current

When you make progress, update this file before you finish. Change `Layout` if a file's job moved. Change `What works` and `Not built yet` so they describe the game as it is now. Write the current behavior. Do not append a history of the edit.

## Layout

| File | Role |
|---|---|
| `src/main.odin` | Window, paddle, ball list, score, frame loop. Loads `src/levels` into `LEVELS` and sizes the playfield |
| `src/menus.odin` | Main menu, level select, pause menu, level-clear menu, you-lost menu |
| `src/bricks.odin` | Level grid, brick types, hit points, drawing, bounce |
| `src/powerups.odin` | Powerup types, `{...}` drop lists (`parse_drop_tail`), falling drops, bomb blasts, stick, lives, fast, multiply |
| `.gitignore` | Build output (`*.exe`, `*.pdb`, and the other binary extensions) and `resume.cmd`, `resume.ps1`, `resume.sh` |
| `src/levels/` | Every `.txt` file. Sorted by the number at the end of the filename, so `lvl2` stays before `lvl10`. One character per cell, newline starts a row. Space and `.` are empty. |
| `src/rect_types.txt` | Brick types. The name is the texture file stem. |
| `src/textures/` | Brick art (`basic_rect.png`, `tough_rect.png`, `strong_rect.png`) and damage overlays (`crack_0.png`, `crack_1.png`, `crack_2.png`). `rects.pdn` is the source art. A rect name with no PNG draws its config color. |
| `src/powerup_types.txt` | Powerup names and whether they are `PAD`, `BALL`, or `RECT` |

At startup the game reads every `.txt` in `src/levels` and sorts that list by the number in the filename. That list is the level order. The game opens on a main menu. PLAY loads the first file. LEVEL SELECT lists one button per file, and choosing one loads that file. BACK returns to the main menu. QUIT closes the window. An empty folder does not start play. When no brick has hit points left, the board freezes and a level-clear menu shows that level's score. NEXT LEVEL loads the next file, clears falling drops, resets the paddle width, the multiply timer, stick, fast, and the score, and sticks one ball to the paddle. Lives carry into that next path. MAIN MENU returns to the main menu. The last level has no next path, so that menu only has MAIN MENU. When every ball is gone and no lives remain, the board freezes and a you-lost menu shows that level's score, MAIN MENU, and QUIT. Escape during play opens the pause menu. RESUME and Escape continue that board. MAIN MENU returns to the main menu. Starting from PLAY or LEVEL SELECT clears lives. A new level and a spent life both stick the ball to the paddle until left click.

## Config

`rect_types.txt`:

```
symbol = name hitpoints COLOR {powerup chance%, ...}
```

`{}` means no drops. `parse_drop_tail` in `powerups.odin` reads that group. Chances are independent. `PAD` and `BALL` chances roll when the brick breaks. A `RECT` chance rolls when that brick is hit. The name loads `src/textures/<name>.png`. Colors are raylib names (`GREEN`, `ORANGE`, `RED`, and the other names in `color_from_name`) and are the fallback when that file is missing. A textureless 1 HP brick draws its symbol. A textureless dark brick draws a gray outline, and its label is white. Current types:

- `B` basic_rect, 1 HP, orange, no drops
- `W` powerup_rect_wide, 1 HP, green, `wide` 100%
- `O` powerup_rect_bomb, 1 HP, purple, `bomb` 100%
- `I` powerup_rect_stick, 1 HP, brown, `stick` 100%
- `L` powerup_rect_life, 1 HP, blue, `life` 100%
- `M` powerup_rect_multiply, 1 HP, pink, `multiply` 100%
- `T` tough_rect, 2 HP, yellow, `stick` 45% and `life` 20%
- `S` strong_rect, 3 HP, red, `wide` 50% and `multiply` 30%
- `U` super_rect, 10 HP, black, no drops

`powerup_types.txt` is `name PAD`, `name BALL`, or `name RECT`. Comments under each name describe the effect. A new name needs both a line in that file and a case in code. The target decides delivery. The kind decides the effect. `PAD` falls and applies on a paddle catch. `BALL` applies as soon as the roll succeeds. `RECT` stays on the brick.

## What works

- The game opens on a main menu. PLAY starts the first file in `src/levels`. LEVEL SELECT shows one button for each `.txt` file there, in number order. Choosing a level starts there. BACK returns to the main menu. QUIT closes the window. With no level files, PLAY does nothing.
- The playfield grows to the widest and tallest level and stays at least 800×600. The paddle top is 30 pixels above the bottom of that playfield. The frame is letterboxed into the window. Menus, the score, and the lives, stick, fast, and multiply labels scale with the playfield. Bricks, the paddle, the ball, and the playfield title stay at their original pixel sizes.
- Clearing a board freezes it and opens a level-clear menu. The menu shows that level's score. NEXT LEVEL starts the next path at score 0 and keeps the remaining lives. MAIN MENU returns to the main menu. The last level's menu has MAIN MENU only.
- When every ball is gone and no lives remain, the board freezes and a you-lost menu shows that level's score, MAIN MENU, and QUIT. MAIN MENU returns to the main menu. QUIT closes the window. A cleared board still opens the level-clear menu when the last brick and the last ball go on the same frame.
- Escape during play opens the pause menu and freezes the board, the balls, the falling drops, the paddle, and the multiply timer. RESUME and Escape continue the same board. MAIN MENU returns to the main menu.
- The paddle follows the mouse. Its top is 30 pixels above the bottom of the playfield, its height is 20, and its width starts at 150. Right-click clears every ball, clears the fast speed bonus, and sticks one ball to the middle of the paddle. It does not spend a life, and `fast` stays on if it was already on.
- The ball leaves the top of the paddle in a new direction. Paddle movement is the average horizontal change over the last 16 play frames, and a jump bigger than 24 pixels in one frame counts as 24. A still paddle sends the ball straight up. A moving paddle aims the ball in that direction and raises its speed. The straight-up speed is 1 pixel per frame, or the current `fast` speed. Without `fast`, the faster axis of a paddle launch stays at 3 or under. With `fast`, it can reach 8. Side hits on the paddle push the ball out and reverse horizontal speed. Walls and bricks reflect the axis that was hit, so the angle continues. The ball is a circle of radius 10, and the paddle hitbox is the drawn rectangle. A ball already past the underside keeps falling. The ball does not bounce off the bottom of the screen. Once its center passes the bottom of the playfield it is removed. Movement is one pixel at a time, and a fraction of a pixel carries into a later frame. A new level, a spent life, and right-click place the ball stuck on the paddle. Left click launches it.
- Each level character with a known type becomes one brick. The grid is centered. Cells are 70×50 with a 5-pixel gap, first row at y=40. The cell is drawn with that type's texture, scaled from the 35×25 file with nearest-neighbor filtering.
- A hit spends 1 HP and bounces off the face that was struck. The brick is gone at 0. Full health has no crack. Lost health picks an overlay: `crack_0` through a third gone, `crack_1` through two thirds, and `crack_2` after that. A 1 HP brick never shows a crack. A type with no texture file still draws its flat color. A 1 HP brick shows its symbol. One with more hit points dims as it loses them and shows the remaining points. A dark brick gets a gray outline and a white label.
- Destroying a brick adds `1 * (6000000000000 / elapsed_ns - elapsed_ns / 60000000000)`. `elapsed_ns` is nanoseconds since this level started, and at least 1. Pause time is not counted. The multiplier is not clamped. A 10-nanosecond break is 600 billion. The multiplier is 0 around 10 minutes and -27 at 30 minutes, so that brick is worth -27. The score resets when a level starts. `SCORE` is drawn at the top right during play and pause. The level-clear menu and the you-lost menu show the same total for that level.
- `PAD` powerups fall from the broken brick at 90 pixels per second. They apply only if the drawn paddle overlaps them. A miss leaves the screen and does nothing. `wide` is gold with `W`, `stick` is brown with `S`, and `life` is blue with `L`.
- `wide` adds 50 pixels per catch, up to 40 pixels short of the screen width. That 50-pixel step is the "widen by 1" note in `powerup_types.txt`.
- `BALL` powerups apply as soon as the roll succeeds. `multiply` lasts 10 seconds. While it is active, a hit on a brick that still has more than 1 HP doubles the living balls from that spot, up to 32. New balls reverse horizontal speed. The timer is the `x2` label at the top left. Extra balls stay after the timer ends. Pause does not drain that timer.
- `bomb` runs when its brick is hit and the chance roll succeeds. The brick's orthogonal neighbors each lose 1 HP. A bomb neighbor can explode from that hit, once per chain. Diagonal bricks are not hit. Bricks destroyed by the blast score and roll their own drops. The ball's own hit is what scores the bomb brick.
- `stick` arms one landing. A ball moving downward that lands on the top half of the paddle sticks to that spot and follows the paddle, and the arm turns off. The `STICK` label goes away then, including while that ball is still stuck. Left click launches it one pixel clear of the paddle. A still paddle sends it straight up at the current fast speed. A moving paddle aims that launch and speeds it up. If two balls land on the same frame, the first sticks and the other bounces. A side hit still bounces. Another `stick` catch arms one more landing. A new level and a spent life also place the ball on the paddle, with `stick` still off, so the label stays off and the next landing bounces.
- `life` adds one life per catch. The count starts at 0 and is the `LIVES` label under the multiply timer. When every ball is gone and at least one life remains, one life is spent and a new ball sticks to the paddle on the same board. Paddle width, stick, multiply, and the bricks stay. `fast` ends with the lost ball. When no lives remain, the you-lost menu opens. NEXT LEVEL keeps the remaining lives. PLAY and LEVEL SELECT start the count over.
- `fast` lasts until any ball is lost. Each bounce adds 1 to a shared speed bonus. Every living ball keeps its angle, and its faster axis becomes `1 + bonus`, up to 8 pixels per frame. Losing any ball turns `fast` off, sets the bonus back to 0, and sets the survivors' faster axis back to 1. Catching `fast` again is what turns it back on. A paddle launch without `fast` keeps its faster axis at 3 or under. The `FAST` label shows the current speed while it is on.

## Not built yet

The header in `main.odin` still calls for 10 levels and sounds. There is no win screen. Item 3 in that header is not marked done. `powerup_rect_wide`, `powerup_rect_bomb`, `powerup_rect_stick`, `powerup_rect_life`, `powerup_rect_multiply`, and `super_rect` have no PNG, so those bricks use their config color.

## Quirks worth leaving alone unless asked

- During play, `RECT-DESTROYER!` is drawn in the playfield every frame.
- During play, a mouse-position string is formatted every frame and not drawn.
- Same-package files see each other's types. Do not add an import between them.
