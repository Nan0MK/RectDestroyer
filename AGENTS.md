# RECT-DESTROYER

Odin + raylib brickbreaker. One package, `package src`, built from the repo root:

```
odin check src
odin run src
```

Level and config paths are relative to that working directory (`src/lvl1.txt`, `src/rect_types.txt`, `src/powerup_types.txt`). The window is 800×600. Target FPS is 500. The ball moves 1 pixel per frame.

## Session resume

When you work on this project, leave a script in the repo root that resumes your Grok session. Use `resume.ps1` on Windows, or `resume.sh` on Linux and Mac. It should `cd` to the repo root and run `grok --resume` with the id of the session you are in. That id is the directory name under `~/.grok/sessions/` for this repo.

Add that filename to `.gitignore` if it is not already listed. Do not commit the script.

## Layout

| File | Role |
|---|---|
| `src/main.odin` | Window, paddle, ball list, frame loop |
| `src/bricks.odin` | Level grid, brick types, hit points, bounce |
| `src/powerups.odin` | Powerup definitions, falling drops, multiply |
| `src/lvl1.txt` | The only level. One character per cell, newline starts a row. Space and `.` are empty. |
| `src/rect_types.txt` | Brick types |
| `src/powerup_types.txt` | Powerup names and whether they are `PAD` or `BALL` |

`src/lvl1.txt` is a 9-by-6 grid of `B`, `T`, and `S`. The game loads that path only. There is no level select.

## Config

`rect_types.txt`:

```
symbol = name hitpoints COLOR {powerup chance%, ...}
```

`{}` means no drops. Chances are independent and roll when the brick breaks. Colors are raylib names (`GREEN`, `ORANGE`, `RED`, and the other names in `color_from_name`). Current types:

- `B` basic, 1 HP, green, no drops
- `T` tough, 3 HP, orange, `multiply` 20%
- `S` strong, 10 HP, red, `wide` 50% and `multiply` 30%

`powerup_types.txt` is `name PAD` or `name BALL`. Comments under each name describe the effect. A new name needs both a line in that file and a case in code. The target (`PAD` or `BALL`) decides delivery. The kind decides the effect.

## What works

- The paddle follows the mouse. Right-click clears every ball and puts one back at the center with speed `(1, 1)`.
- The ball bounces off the left, right, and top edges, and off the paddle. It does not bounce off the bottom. Once its center passes y=600 it is removed.
- Each level character with a known type becomes one brick. The grid is centered. Cells are 70×50 with a 5-pixel gap, first row at y=40.
- A hit spends 1 HP and bounces off the face that was struck. The brick is gone at 0. Multi-HP bricks show the remaining points and dim as they lose them.
- `PAD` powerups fall from the broken brick at 90 pixels per second. They apply only if the drawn paddle overlaps them. A miss leaves the screen and does nothing.
- `wide` adds 50 pixels per catch, up to 40 pixels short of the screen width. That 50-pixel step is the "widen by 1" note in `powerup_types.txt`.
- `BALL` powerups apply as soon as the roll succeeds. `multiply` lasts 10 seconds. While it is active, a hit on a brick that still has more than 1 HP doubles the living balls from that spot, up to 32. New balls reverse horizontal speed. The timer is the `x2` label at the top left. Extra balls stay after the timer ends.

## Not built yet

The header in `main.odin` still calls for 10 levels, 5 powerups, a main menu, and sounds. Only `wide` and `multiply` exist. There is no score, lives, or win state. Item 3 in that header is not marked done.

## Quirks worth leaving alone unless asked

- The paddle is drawn at y=570 with height 20. `PAD_TOP` / `PAD_BOT` are 560 and 580, and the side-bounce tests are loose. Ball collision uses the live paddle width for the horizontal span.
- `RECT-DESTROYER!` is drawn in the playfield every frame.
- A mouse-position string is formatted every frame and not drawn.
- Same-package files see each other's types. Do not add an import between them.
