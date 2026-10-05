package src

import "core:fmt"
import "core:os"
import "core:strings"
import big "core:math/big"

// One finished run per line. The working directory is the repo root, same as the level files.
SCORES_PATH :: "scores.txt"

// Levels cleared this run, not counting the level where the last life was lost.
// The overall score is that sum times the number of levels cleared.
// It is saved when the last life is lost, or when the last level is cleared.
run_sum: big.Int
run_overall: big.Int
run_count: i64
run_recorded: bool
run_show_overall: bool
level_banked: bool

// Digit text of each saved overall score, oldest first.
score_lines: [dynamic]string

score_add_big :: proc(dst, src: ^big.Int) -> bool {
	sum: big.Int
	defer big.destroy(&sum)
	if big.add(&sum, dst, src) != big.Error.None do return false
	return big.copy(dst, &sum) == big.Error.None
}

// A new run from the main menu or level select. Next Level does not call this.
reset_run_score :: proc() {
	big.set(&run_sum, 0)
	big.set(&run_overall, 0)
	run_count = 0
	run_recorded = false
	run_show_overall = false
	level_banked = false
}

// Once per cleared level. The settled level score is still in score.
bank_level_score :: proc(score: ^big.Int) {
	if level_banked do return
	if !score_add_big(&run_sum, score) do return
	run_count += 1
	level_banked = true
}

// (sum of cleared level scores) * (levels cleared). Zero cleared levels is 0.
compute_run_overall :: proc(dst: ^big.Int) -> bool {
	if run_count <= 0 {
		return big.set(dst, 0) == big.Error.None
	}
	if big.copy(dst, &run_sum) != big.Error.None do return false
	if run_count != 1 do score_mul_i64(dst, run_count)
	return true
}

score_line_ok :: proc(line: string) -> bool {
	if len(line) == 0 do return false
	start := 0
	if line[0] == '-' {
		if len(line) == 1 do return false
		start = 1
	}
	for i in start ..< len(line) {
		if line[i] < '0' || line[i] > '9' do return false
	}
	return true
}

free_score_lines :: proc() {
	for line in score_lines do delete(line)
	clear(&score_lines)
}

load_saved_scores :: proc() {
	free_score_lines()
	data, err := os.read_entire_file_or_err(SCORES_PATH, context.allocator)
	if err != nil do return
	defer delete(data)

	i := 0
	for i < len(data) {
		j := i
		for j < len(data) && data[j] != '\n' do j += 1
		line := string(data[i:j])
		if len(line) > 0 && line[len(line) - 1] == '\r' {
			line = line[:len(line) - 1]
		}
		if score_line_ok(line) {
			append(&score_lines, strings.clone(line))
		}
		i = j + 1
	}
}

write_saved_scores :: proc() -> bool {
	b: strings.Builder
	if strings.builder_init(&b) == nil do return false
	defer strings.builder_destroy(&b)
	for line in score_lines {
		strings.write_string(&b, line)
		strings.write_string(&b, "\n")
	}
	if !os.write_entire_file(SCORES_PATH, b.buf[:]) {
		fmt.eprintf("Failed to write '%s'\n", SCORES_PATH)
		return false
	}
	return true
}

append_saved_score :: proc(score: ^big.Int) -> bool {
	text, err := big.itoa(score)
	defer delete(text)
	if err != big.Error.None || len(text) == 0 || !score_line_ok(text) do return false
	append(&score_lines, strings.clone(text))
	if write_saved_scores() do return true
	if len(score_lines) > 0 {
		dropped := pop(&score_lines)
		delete(dropped)
	}
	return false
}

// Once per finished run. Later frames leave the saved line alone.
finish_run :: proc() {
	if run_recorded do return
	if !compute_run_overall(&run_overall) do return
	if !append_saved_score(&run_overall) do return
	run_recorded = true
	run_show_overall = true
}

clear_saved_scores :: proc() {
	kept := score_lines
	score_lines = {}
	if !write_saved_scores() {
		score_lines = kept
		return
	}
	for line in kept do delete(line)
	delete(kept)
}

init_saved_scores :: proc() {
	big.set(&run_sum, 0)
	big.set(&run_overall, 0)
	load_saved_scores()
}

shutdown_saved_scores :: proc() {
	free_score_lines()
	delete(score_lines)
	big.destroy(&run_sum)
	big.destroy(&run_overall)
}
