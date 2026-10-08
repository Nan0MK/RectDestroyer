package src

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import big "core:math/big"

// One finished run per line. The working directory is the repo root, same as the level files.
SCORES_PATH :: "scores.txt"

// Levels finished this run. A clear and the level where the last life is lost both count.
// The total score is that sum times the number of levels finished.
// It is saved when the last life is lost, or when the last level is cleared.
run_sum: big.Int
run_overall: big.Int
run_count: i64
// Cap hits from every finished level in this run. The total shows this, not one level's count.
run_max_score: i64
// Highest level number reached this run. 0 until a level starts.
run_level: int
run_result: Run_Result
run_recorded: bool
run_show_overall: bool
level_banked: bool
// Stamp of the total just saved, `YYYY-MM-DD HH:MM:SS`. Empty when this run wrote no line.
run_total_stamp: string

// WON is the last level cleared. LOST is the last life. UNKNOWN is an older saved line.
Run_Result :: enum {
	UNKNOWN,
	WON,
	LOST,
}

// Each saved run, oldest first. text is the integer; stamp is when it ended.
// detailed lines also keep the run's max-score count, the highest level, and the result.
Saved_Score :: struct {
	text:      string,
	stamp:     string,
	max_score: i64,
	level:     int,
	result:    Run_Result,
	detailed:  bool,
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
	run_max_score = 0
	run_level = 0
	run_result = .UNKNOWN
	run_recorded = false
	run_show_overall = false
	level_banked = false
	clear_run_total_stamp()
}

// The furthest level number this run has loaded. Next Level only moves forward.
note_run_level :: proc(level: int) {
	if level > run_level do run_level = level
}

// Once per finished level, clear or loss. The settled level score is still in score.
// That level's cap hits join the run total here, so a later level does not replace them.
bank_level_score :: proc(score: ^big.Int) {
	if level_banked do return
	if !score_add_big(&run_sum, score) do return
	clamp_score(&run_sum)
	run_count += 1
	run_max_score += round_max_score
	level_banked = true
}

// (sum of finished level scores) * (levels finished). Nothing finished is 0.
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

// Digits only. Used for the max-score count and the level number on a saved line.
parse_nonneg :: proc(text: string) -> (value: i64, ok: bool) {
	if len(text) == 0 do return
	n: i64 = 0
	for ch in text {
		if ch < '0' || ch > '9' do return
		n = n * 10 + i64(ch - '0')
	}
	return n, true
}

write_nonneg :: proc(b: ^strings.Builder, value: i64) {
	v := value
	if v < 0 do v = 0
	if v == 0 {
		strings.write_byte(b, '0')
		return
	}
	tmp: [20]byte
	count := 0
	for v > 0 && count < len(tmp) {
		tmp[count] = u8('0') + u8(v % 10)
		v /= 10
		count += 1
	}
	for d := count - 1; d >= 0; d -= 1 {
		strings.write_byte(b, tmp[d])
	}
}

// `<stamp>=<score>`, a bare score, or `<stamp>=<score>;<max>;<level>;<W|L>`.
// text and stamp are cloned. A bad detail tail is rejected so a broken line is skipped.
parse_saved_score_line :: proc(line: string) -> (entry: Saved_Score, ok: bool) {
	body := line
	stamp := ""
	if eq := strings.index(line, "="); eq >= 0 {
		stamp = line[:eq]
		body = line[eq + 1:]
	}
	score := body
	rest := ""
	detailed := false
	if semi := strings.index(body, ";"); semi >= 0 {
		score = body[:semi]
		rest = body[semi + 1:]
		detailed = true
	}
	if !score_line_ok(score) do return
	entry.text = strings.clone(score)
	entry.stamp = strings.clone(stamp)
	entry.max_score = -1
	entry.level = -1
	if !detailed {
		ok = true
		return
	}
	semi1 := strings.index(rest, ";")
	if semi1 < 0 {
		delete(entry.text)
		delete(entry.stamp)
		entry = {}
		return
	}
	tail := rest[semi1 + 1:]
	semi2 := strings.index(tail, ";")
	if semi2 < 0 {
		delete(entry.text)
		delete(entry.stamp)
		entry = {}
		return
	}
	max_score, max_ok := parse_nonneg(rest[:semi1])
	level, level_ok := parse_nonneg(tail[:semi2])
	mark := tail[semi2 + 1:]
	if !max_ok || !level_ok || (mark != "W" && mark != "L") {
		delete(entry.text)
		delete(entry.stamp)
		entry = {}
		return
	}
	entry.max_score = max_score
	entry.level = int(level)
	entry.result = .LOST
	if mark == "W" do entry.result = .WON
	entry.detailed = true
	ok = true
	return
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
		entry, ok := parse_saved_score_line(line)
		if ok {
			append(&score_lines, entry)
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
		if entry.detailed {
			strings.write_byte(&b, ';')
			write_nonneg(&b, entry.max_score)
			strings.write_byte(&b, ';')
			write_nonneg(&b, i64(entry.level))
			strings.write_byte(&b, ';')
			mark: u8 = 'L'
			if entry.result == .WON do mark = 'W'
			strings.write_byte(&b, mark)
		}
		strings.write_string(&b, "\n")
	}
	if !os.write_entire_file(SCORES_PATH, b.buf[:]) {
		fmt.eprintf("Failed to write '%s'\n", SCORES_PATH)
		return false
	}
	return true
}

append_saved_score :: proc(score: ^big.Int, max_score: i64, level: int, won: bool) -> bool {
	text, err := big.itoa(score)
	defer delete(text)
	shown := text
	if err != big.Error.None || len(text) == 0 do shown = "0"
	if !score_line_ok(shown) do return false
	now := time.now()
	year, month, day := time.date(now)
	hour, min, sec := time.clock(now)
	stamp := fmt.aprintf("%d-%02d-%02d %02d:%02d:%02d", year, int(month), day, hour, min, sec)
	result := Run_Result.LOST
	if won do result = .WON
	append(&score_lines, Saved_Score{
		text      = strings.clone(shown),
		stamp     = stamp,
		max_score = max_score,
		level     = level,
		result    = result,
		detailed  = true,
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
// won is the last level cleared. A last-life loss passes false.
finish_run :: proc(won: bool) {
	if run_recorded do return
	run_result = .LOST
	if won do run_result = .WON
	if !compute_run_overall(&run_overall) do return
	if !append_saved_score(&run_overall, run_max_score, run_level, won) do return
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
