# RECT-DESTROYER

Odin + raylib brickbreaker. One package, `package src`, built from the repo root:

```
odin check src
odin run src
```

Level and config paths are relative to that working directory (`src/levels/`, `src/rect_types.txt`, `src/powerup_types.txt`). The window opens at 800×600 and can be resized. The playfield is at least 800×600 and grows so the largest level fits, with 24 pixels of side margin and a 220-pixel lane under the lowest brick row. Each frame is drawn at that size and fitted uniformly into the window, with black bars when the aspect ratios differ. The mouse is mapped back through that fit. Target FPS is 500. Each level and each life sticks the ball to the paddle until left click. A still paddle sends it straight up at 1 pixel per frame. Paddle movement sets the launch angle and adds speed. That launch stays at 3 pixels per frame or under until `fast` is on. `fast` raises a slower ball's faster axis on each bounce, up to 267, and a ball already faster keeps its speed. A ball that leaves the screen leaves the others at that speed. `fast` ends when the last ball is gone.

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
| `src/particles.odin` | Chips thrown when a ball hits a brick. A destroy throws more than a hit |
| `src/animations.odin` | Sprite sheets in `src/textures/animations`. Strips the magenta grid and plays frames from the bottom of the sheet upward |
| `src/space.odin` | `src/textures/space_bg.png` on the inside of a cube. The view sits at the center, and the cube keeps turning on X, Y, and Z |
| `src/powerups.odin` | Powerup types, `{...}` drop lists (`parse_drop_tail`), falling drops, bomb blasts, stick, lives, fast, multiply |
| `src/font.odin` | Sprite font from `src/textures/font.png`. Draws and measures menus, the score, the HUD, and textureless brick labels |
| `.gitignore` | Build output (`*.exe`, `*.pdb`, and the other binary extensions) and `resume.cmd`, `resume.ps1`, `resume.sh` |
| `src/levels/` | Every `.txt` file. Sorted by the number at the end of the filename, so `lvl2` stays before `lvl10`. One character per cell, newline starts a row. Space and `.` are empty. |
| `src/textures/animations/` | `ball_lost`, `ball_trail`, `explode`, and `life_lost`. Each `.png` is a vertical sheet with a magenta grid. The matching `.animation` file says where it plays. |
| `src/rect_types.txt` | Brick types. The name is the texture file stem. |
| `src/textures/` | Brick art is 35×25 (`basic_rect`, `tough_rect`, `strong_rect`, `super_rect`, `rect_wide`, `rect_bomb`, `rect_stick`, `rect_life`, `rect_multiply`, `rect_fast`) and damage overlays (`crack_0`, `crack_1`, `crack_2`). Falling drops and the ball are 16×16 (`powerup_wide`, `powerup_stick`, `powerup_life`, `powerup_bomb`, `powerup_multiply`, `powerup_fast`, `ball`). `life_point.png` is 16×16 and is drawn at 48×48, one copy per life, along the lower left behind the board. `font.png` is the 100×340 sprite font. Source art is `rects.pdn`, `powerup_rects.pdn`, and `powerup.pdn`. A missing PNG falls back to the flat color. |
| `src/powerup_types.txt` | Powerup names and whether they are `PAD`, `BALL`, or `RECT` |

At startup the game reads every `.txt` in `src/levels` and sorts that list by the number in the filename. That list is the level order. The game opens on a main menu. PLAY loads the first file. LEVEL SELECT lists one button per file, and choosing one loads that file. BACK returns to the main menu. QUIT closes the window. An empty folder does not start play. When no brick has hit points left, the board freezes and a level-clear menu shows that level's score. NEXT LEVEL loads the next file, clears falling drops, brick chips, and animations, resets the paddle width, the multiply timer, stick, fast, and the score, and sticks one ball to the paddle. Lives carry into that next path. MAIN MENU returns to the main menu. The last level has no next path, so that menu only has MAIN MENU. When every ball is gone and no lives remain, the board freezes and a you-lost menu shows that level's score, MAIN MENU, and QUIT. Escape during play opens the pause menu. RESUME and Escape continue that board. MAIN MENU returns to the main menu. Starting from PLAY or LEVEL SELECT sets lives to 1. A new level and a spent life both stick the ball to the paddle until left click.

## Config

`rect_types.txt`:

```
symbol = name hitpoints COLOR {powerup chance%, ...}
```

`{}` means no drops. `parse_drop_tail` in `powerups.odin` reads that group. Chances are independent. `PAD` and `BALL` chances roll when the brick breaks. A `RECT` chance rolls when that brick is hit. The name loads `src/textures/<name>.png`. Colors are raylib names (`GREEN`, `ORANGE`, `RED`, and the other names in `color_from_name`) and are the fallback when that file is missing. A textureless 1 HP brick draws its symbol. A textureless dark brick draws a gray outline, and its label is white. Current types:

- `B` basic_rect, 1 HP, orange, no drops
- `W` rect_wide, 1 HP, green, `wide` 100%
- `O` rect_bomb, 1 HP, purple, `bomb` 100%
- `I` rect_stick, 1 HP, brown, `stick` 100%
- `L` rect_life, 1 HP, blue, `life` 100%
- `M` rect_multiply, 1 HP, pink, `multiply` 100%
- `F` rect_fast, 1 HP, gray, `fast` 100%
- `T` tough_rect, 2 HP, yellow, `stick` 45% and `life` 20%
- `S` strong_rect, 3 HP, red, `wide` 50% and `multiply` 30%
- `U` super_rect, 10 HP, black, no drops

`powerup_types.txt` is `name PAD`, `name BALL`, or `name RECT`. Comments under each name describe the effect. A new name needs both a line in that file and a case in code. The target decides delivery. The kind decides the effect. `PAD` falls and applies on a paddle catch. `BALL` applies as soon as the roll succeeds. `RECT` stays on the brick.

## What works

- The game opens on a main menu. PLAY starts the first file in `src/levels`. That folder is `lvl1.txt` through `lvl15.txt`. LEVEL SELECT shows one button for each `.txt` file there, in number order. Choosing a level starts there. BACK returns to the main menu. QUIT closes the window. With no level files, PLAY does nothing.
- Menus, the score, the lives, stick, fast, and multiply labels, and textureless brick labels use `src/textures/font.png`. The sheet is five columns of 19×20 cells. In order it is A–Z, a–z, three blanks, 0–9, `.` `"` `'` `,` `!`, `?` `-` `_` `/` `\`, `:`, `^`, a downward chevron, `>`, `<`. Black and the pink divider (255, 0, 110) are transparent, and the texture uses nearest-neighbor filtering. Space is the first blank after z. The letter v is the one drawn for v. One scaled divider pixel sits between characters. A missing file keeps raylib's default font.
- The playfield grows to the widest and tallest level and stays at least 800×600. The paddle top is 30 pixels above the bottom of that playfield. The frame is letterboxed into the window. Menus, the score, and the lives, stick, fast, and multiply labels scale with the playfield. Bricks, the paddle, the ball, and the playfield title stay at their original pixel sizes.
- Clearing a board freezes play and opens a level-clear menu. The menu shows that level's score. A one-shot animation already on screen keeps playing. NEXT LEVEL starts the next path at score 0 and keeps the remaining lives. MAIN MENU returns to the main menu. The last level's menu has MAIN MENU only.
- When every ball is gone and no lives remain, the board freezes and a you-lost menu shows that level's score, MAIN MENU, and QUIT. A one-shot animation already on screen keeps playing. MAIN MENU returns to the main menu. QUIT closes the window. A cleared board still opens the level-clear menu when the last brick and the last ball go on the same frame.
- Escape during play opens the pause menu and freezes the board, the balls, the falling drops, the brick chips, the animations, the paddle, and the multiply timer. The space cube keeps turning. RESUME and Escape continue the same board. MAIN MENU returns to the main menu.
- The paddle follows the mouse. Its top is 30 pixels above the bottom of the playfield, its height is 20, and its width starts at 150. Right-click clears every ball, clears the fast speed bonus, and sticks one ball to the middle of the paddle. It does not spend a life, and `fast` stays on if it was already on.
- The ball leaves the top of the paddle in a new direction. Paddle movement is the average horizontal change over the last 16 play frames, and a jump bigger than 24 pixels in one frame counts as 24. A still paddle sends the ball straight up. A moving paddle aims the ball in that direction and raises its speed. The straight-up speed is 1 pixel per frame, or the current `fast` speed. Without `fast`, the faster axis of a paddle launch stays at 3 or under. With `fast`, it can reach 267. Side hits on the paddle push the ball out and reverse horizontal speed. Walls and bricks reflect the axis that was hit, so the angle continues. The hit shape is a circle of radius 12. `src/textures/ball.png` is drawn in that circle's 24×24 box with nearest-neighbor filtering. A missing file draws a red circle. The paddle hitbox is the drawn rectangle. A ball already past the underside keeps falling. The ball does not bounce off the bottom of the screen. Once its center passes the bottom of the playfield it is removed. Movement is one pixel at a time, and a fraction of a pixel carries into a later frame. A new level, a spent life, and right-click place the ball stuck on the paddle. Left click launches it.
- Each level character with a known type becomes one brick. The grid is centered. Cells are 70×50 with a 5-pixel gap, first row at y=40. The cell is drawn with that type's texture, scaled from the 35×25 file with nearest-neighbor filtering.
- A hit spends 1 HP and bounces off the face that was struck. The ball is placed one pixel outside that face, so a graze spends one hit point and does not keep spending them while the ball travels along the brick. The brick is gone at 0. Full health has no crack. Lost health picks an overlay: `crack_0` through a third gone, `crack_1` through two thirds, and `crack_2` after that. A 1 HP brick never shows a crack. A type with no texture file still draws its flat color. A 1 HP brick shows its symbol. One with more hit points dims as it loses them and shows the remaining points. A dark brick gets a gray outline and a white label.
- A ball hit throws chips of that brick. A hit that leaves it standing throws 8 from the face the ball struck. A hit that removes it throws 24 from across the cell. Each chip is a patch of that brick's texture. A brick with no texture throws squares of its color. Chips drift outward, fall, and fade. At most 256 are alive, and a new burst drops the oldest. Pause, the level-clear menu, and the you-lost menu freeze them. Starting a level clears them. A bomb blast does not throw chips.
- Destroying a brick adds `1 * (6000000000000 / elapsed_ns - elapsed_ns / 60000000000)`. `elapsed_ns` is nanoseconds since this level started, and at least 1. Pause time is not counted. The multiplier is not clamped. A 10-nanosecond break is 600 billion. The multiplier is 0 around 10 minutes and -27 at 30 minutes, so that brick is worth -27. The score resets when a level starts. `SCORE` is drawn at the top right during play and pause. The level-clear menu and the you-lost menu show the same total for that level.
- `PAD` powerups fall from the broken brick at 90 pixels per second. They apply only if the drawn paddle overlaps them. A miss leaves the screen and does nothing. Each drop draws `src/textures/powerup_<name>.png` at 32×32, which is the 16×16 file at 2× with nearest-neighbor filtering. That rectangle is the catch box. A missing file draws the old colored letter: `wide` gold with `W`, `stick` brown with `S`, `life` blue with `L`, `multiply` yellow with `M`, `bomb` purple with `B`, and `fast` orange with `F`.
- `wide` adds 50 pixels per catch, up to 40 pixels short of the screen width. That 50-pixel step is the "widen by 1" note in `powerup_types.txt`.
- `BALL` powerups apply as soon as the roll succeeds. `multiply` lasts 10 seconds. While it is active, a hit on a brick that still has more than 1 HP doubles the living balls from that spot, up to 32. New balls reverse horizontal speed. The timer is the `x2` label at the top left. Extra balls stay after the timer ends. Pause does not drain that timer.
- `bomb` runs when its brick is hit and the chance roll succeeds. The brick's orthogonal neighbors each lose 1 HP. A bomb neighbor can explode from that hit, once per chain. Diagonal bricks are not hit. Bricks destroyed by the blast score and roll their own drops. The ball's own hit is what scores the bomb brick.
- `stick` arms one landing. A ball moving downward that lands on the top half of the paddle sticks to that spot and follows the paddle, and the arm turns off. The `STICK` label goes away then, including while that ball is still stuck. Left click launches it one pixel clear of the paddle. A still paddle sends it straight up at the current fast speed. A moving paddle aims that launch and speeds it up. If two balls land on the same frame, the first sticks and the other bounces. A side hit still bounces. Another `stick` catch arms one more landing. A new level and a spent life also place the ball on the paddle, with `stick` still off, so the label stays off and the next landing bounces.
- `life` adds one life per catch. The count starts at 1. That 1 is the life in play. The `LIVES` label under the multiply timer shows the count. `src/textures/life_point.png` is drawn once for each life along the lower left, before the paddle, the ball, the bricks, the chips, and the drops, so those cover it. A missing file draws a blue square of the same size. When every ball is gone, one life is removed. If any remain, a new ball sticks to the paddle on the same board. Paddle width, stick, multiply, and the bricks stay. `fast` and its speed bonus end with that last ball. Reaching 0 opens the you-lost menu, and that last life does not serve another ball. NEXT LEVEL keeps the remaining lives. PLAY and LEVEL SELECT start the count at 1.
- `fast` lasts while any ball is still in play. Each bounce adds 1 to a shared speed bonus. That bonus is a floor: a living ball slower than `1 + bonus` is raised to it, up to 267 pixels per frame, and keeps its angle. A ball already faster, including one a moving paddle just launched, keeps that speed when any ball bounces. A ball that leaves the screen leaves the others at their current speed, with `fast` and the bonus still on. `fast` turns off and the bonus returns to 0 when the last ball is gone. Catching `fast` again is what turns it back on. A paddle launch without `fast` keeps its faster axis at 3 or under. The `FAST` label shows `1 + bonus` while it is on.
- `src/textures/space_bg.png` covers the inside of a cube drawn behind the playfield, the menus, and the HUD. The camera stays at the center of that cube. The cube turns on X, Y, and Z together, from the time since the window opened, so the main menu, pause, the level-clear menu, and the you-lost menu do not stop it. The letterbox bars stay black. A missing file leaves the black background.
- `src/textures/animations` holds `ball_lost`, `ball_trail`, `explode`, and `life_lost`. Each sheet is split by a magenta grid (255, 0, 255). That grid is not drawn. Frames play from the bottom of the sheet to the top, 12 per second, with nearest-neighbor filtering. `ball_lost` plays once at the bottom of the playfield, centered on a ball whose center passes that edge. `life_lost` plays once in the 48×48 slot of the life icon that just disappeared. `explode` plays once on a bomb brick when that brick explodes. The frame is scaled by 2, then its width is stretched to the 70-pixel brick and centered on that cell. `ball_trail` loops with the sheet's right edge on a ball whose faster axis is above 1.5. The frame is stretched to three times its width and points opposite the ball's movement, over the bricks. A stuck ball does not show it. Just above 1.5 the trail is faint, and it is fully opaque at 267. Pause freezes every animation. The level-clear menu and the you-lost menu keep a one-shot playing and hold the trail on its current frame. Starting a level clears them.

## Not built yet

The header in `main.odin` still calls for sounds. There is no win screen.

## Quirks worth leaving alone unless asked

- During play, `RECT-DESTROYER!` is drawn in the playfield every frame.
- During play, a mouse-position string is formatted every frame and not drawn.
- Same-package files see each other's types. Do not add an import between them.
- When adding levels, create only new files. Do not overwrite a `.txt` file that is already in `src/levels`.
