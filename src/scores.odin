package src

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import big "core:math/big"

// One finished run per line. The working directory is the repo root, same as the level files.
SCORES_PATH :: "scores.txt"

// Levels cleared this run, not counting the level where the last life was lost.
// The total score is that sum times the number of levels cleared.
// It is saved when the last life is lost, or when the last level is cleared.
run_sum: big.Int
run_overall: big.Int
run_count: i64
run_recorded: bool
run_show_overall: bool
level_banked: bool
// Stamp of the total just saved, `YYYY-MM-DD HH:MM:SS`. Empty when this run wrote no line.
run_total_stamp: string

// Each saved run, oldest first. text is the integer; stamp is when it ended.
Saved_Score :: struct {
	text:  string,
	stamp: string,
}
score_lines: [dynamic]Saved_Score
// Bumped when that list changes, so the past-scores cards rebuild.
score_list_rev: int

score_add_big :: proc(dst, src: ^big.Int) -> bool {
	sum: big.Int
	defer big.destroy(&sum)
	if big.add(&sum, dst, src) != big.Error.None do return false
	return big.copy(dst, &sum) == big.Error.None
}

clear_run_total_stamp :: proc() {
	if len(run_total_stamp) > 0 do delete(run_total_stamp)
	run_total_stamp = ""
}

// A new run from the main menu or level select. Next Level does not call this.
reset_run_score :: proc() {
	big.set(&run_sum, 0)
	big.set(&run_overall, 0)
	run_count = 0
	run_recorded = false
	run_show_overall = false
	level_banked = false
	clear_run_total_stamp()
}

// Once per cleared level. The settled level score is still in score.
bank_level_score :: proc(score: ^big.Int) {
	if level_banked do return
	if !score_add_big(&run_sum, score) do return
	clamp_score(&run_sum)
	run_count += 1
	level_banked = true
}

// (sum of cleared level scores) * (levels cleared). Zero cleared levels is 0.
compute_run_overall :: proc(dst: ^big.Int) -> bool {
	if run_count <= 0 {
		return big.set(dst, 0) == big.Error.None
	}
	if big.copy(dst, &run_sum) != big.Error.None do return false
	if run_count != 1 {
		factor: big.Int
		defer big.destroy(&factor)
		product: big.Int
		defer big.destroy(&product)
		if big.set(&factor, run_count) != big.Error.None do return false
		if big.mul(&product, dst, &factor) != big.Error.None do return false
		big.copy(dst, &product)
	}
	clamp_score(dst)
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
	for entry in score_lines {
		delete(entry.text)
		delete(entry.stamp)
	}
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
		stamp := ""
		text := line
		// Old lines were a bare number. New lines are `<stamp>=<score>`.
		if eq := strings.index(line, "="); eq >= 0 {
			stamp = line[:eq]
			text = line[eq + 1:]
		}
		if score_line_ok(text) {
			append(&score_lines, Saved_Score{
				text  = strings.clone(text),
				stamp = strings.clone(stamp),
			})
		}
		i = j + 1
	}
	score_list_rev += 1
}

write_saved_scores :: proc() -> bool {
	b: strings.Builder
	if strings.builder_init(&b) == nil do return false
	defer strings.builder_destroy(&b)
	for entry in score_lines {
		if len(entry.stamp) > 0 {
			strings.write_string(&b, entry.stamp)
			strings.write_byte(&b, '=')
		}
		strings.write_string(&b, entry.text)
		strings.write_string(&b, "\n")
	}
	if !os.write_entire_file(SCORES_PATH, b.buf[:]) {
		fmt.eprintf("Failed to write '%s'\n", SCORES_PATH)
		return false
	}
	return true
}

append_saved_score :: proc(score: ^big.Int) -> bool {
	if zero, zerr := big.is_zero(score); zerr == big.Error.None && zero {
		return true
	}
	text, err := big.itoa(score)
	defer delete(text)
	if err != big.Error.None || len(text) == 0 || !score_line_ok(text) do return false
	now := time.now()
	year, month, day := time.date(now)
	hour, min, sec := time.clock(now)
	stamp := fmt.aprintf("%d-%02d-%02d %02d:%02d:%02d", year, int(month), day, hour, min, sec)
	append(&score_lines, Saved_Score{
		text  = strings.clone(text),
		stamp = stamp,
	})
	if write_saved_scores() {
		clear_run_total_stamp()
		run_total_stamp = strings.clone(stamp)
		score_list_rev += 1
		return true
	}
	if len(score_lines) > 0 {
		dropped := pop(&score_lines)
		delete(dropped.text)
		delete(dropped.stamp)
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
	for entry in kept {
		delete(entry.text)
		delete(entry.stamp)
	}
	delete(kept)
	score_list_rev += 1
}

init_saved_scores :: proc() {
	big.set(&run_sum, 0)
	big.set(&run_overall, 0)
	load_saved_scores()
}

shutdown_saved_scores :: proc() {
	free_score_lines()
	delete(score_lines)
	clear_run_total_stamp()
	big.destroy(&run_sum)
	big.destroy(&run_overall)
}
