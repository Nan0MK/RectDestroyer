package src

import "core:fmt"
import rl "vendor:raylib"

// Two voices share one loaded clip. A second hit can overlap the first.
// A third play restarts one of them. Raylib's pool is 16 channels. Five clips use ten, and the theme uses one more.
SOUND_VOICES :: 2

// Menus play the theme at full volume. A level turns it down a little, and it stays there until a menu.
THEME_PATH :: "src/sounds/Rect_Destroyer.wav"
THEME_VOLUME :: f32(1)
LEVEL_VOLUME :: f32(0.8)

Sound_Clip :: enum {
	HIT_0,
	HIT_1,
	DESTROY_0,
	DESTROY_1,
	BOMB_EXPLODE,
}

Sound_Voice :: struct {
	sound: rl.Sound,
	alias: bool,
}

clip_voices: [Sound_Clip][SOUND_VOICES]Sound_Voice
clip_next: [Sound_Clip]int
sounds_ready: bool
theme: rl.Music
theme_loaded: bool

// The type name's first word. strong and super use the _1 clips.
// tough, basic, and every rect_* type use _0.
brick_sound_variant :: proc(name: string) -> i32 {
	head := name
	for ch, i in name {
		if ch == '_' {
			head = name[:i]
			break
		}
	}
	switch head {
	case "strong", "super":
		return 1
	}
	return 0
}

load_clip :: proc(clip: Sound_Clip, path: cstring) {
	base := rl.LoadSound(path)
	if !rl.IsSoundValid(base) {
		fmt.eprintf("Failed to load sound '%s'\n", path)
		return
	}
	clip_voices[clip][0] = {sound = base}
	for i in 1..<SOUND_VOICES {
		alias := rl.LoadSoundAlias(base)
		if !rl.IsSoundValid(alias) {
			fmt.eprintf("Failed to alias sound '%s'\n", path)
			return
		}
		clip_voices[clip][i] = {sound = alias, alias = true}
	}
}

// Loads src/sounds. A missing file is skipped. Tests have no window, so they do not open the device.
ensure_sounds :: proc() {
	if sounds_ready || !rl.IsWindowReady() do return
	sounds_ready = true
	if !rl.IsAudioDeviceReady() do rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() do return
	load_clip(.HIT_0, "src/sounds/hit_0.wav")
	load_clip(.HIT_1, "src/sounds/hit_1.wav")
	load_clip(.DESTROY_0, "src/sounds/destroy_0.wav")
	load_clip(.DESTROY_1, "src/sounds/destroy_1.wav")
	load_clip(.BOMB_EXPLODE, "src/sounds/bomb_explode.wav")

	theme = rl.LoadMusicStream(THEME_PATH)
	if !rl.IsMusicValid(theme) {
		fmt.eprintf("Failed to load music '%s'\n", THEME_PATH)
		return
	}
	theme.looping = true
	rl.SetMusicVolume(theme, THEME_VOLUME)
	rl.PlayMusicStream(theme)
	theme_loaded = true
}

unload_sounds :: proc() {
	if !sounds_ready do return
	if theme_loaded {
		rl.StopMusicStream(theme)
		rl.UnloadMusicStream(theme)
		theme = {}
		theme_loaded = false
	}
	// An alias does not own the samples. Free those before the clip they share.
	for clip in Sound_Clip {
		for i := SOUND_VOICES - 1; i >= 0; i -= 1 {
			voice := &clip_voices[clip][i]
			if !rl.IsSoundValid(voice.sound) do continue
			if voice.alias do rl.UnloadSoundAlias(voice.sound)
			else do rl.UnloadSound(voice.sound)
			voice^ = {}
		}
		clip_next[clip] = 0
	}
	sounds_ready = false
	if rl.IsAudioDeviceReady() do rl.CloseAudioDevice()
}

play_clip :: proc(clip: Sound_Clip) {
	ensure_sounds()
	if !sounds_ready do return
	for i in 0..<SOUND_VOICES {
		voice := clip_voices[clip][i].sound
		if rl.IsSoundValid(voice) && !rl.IsSoundPlaying(voice) {
			rl.PlaySound(voice)
			return
		}
	}
	start := clip_next[clip]
	for n in 0..<SOUND_VOICES {
		i := (start + n) % SOUND_VOICES
		voice := clip_voices[clip][i].sound
		if !rl.IsSoundValid(voice) do continue
		clip_next[clip] = (i + 1) % SOUND_VOICES
		rl.PlaySound(voice)
		return
	}
}

// A ball hit that leaves the brick plays hit. One that removes it plays destroy.
// variant 1 is strong and super. Tough and everything else are 0.
play_ball_brick_sound :: proc(variant: i32, broke: bool) {
	heavy := variant == 1
	if broke {
		if heavy do play_clip(.DESTROY_1)
		else do play_clip(.DESTROY_0)
		return
	}
	if heavy do play_clip(.HIT_1)
	else do play_clip(.HIT_0)
}

play_bomb_explode :: proc() {
	play_clip(.BOMB_EXPLODE)
}

// Keeps the theme looping. Menus stay at full volume. A level, including pause and its end screens, is a little quieter.
update_theme :: proc(screen: Screen) {
	if !theme_loaded do return
	rl.UpdateMusicStream(theme)
	volume := THEME_VOLUME
	switch screen {
	case .PLAY, .PAUSE, .LEVEL_END, .LAST_LIFE, .LOST:
		volume = LEVEL_VOLUME
	case .MENU, .LEVEL_SELECT, .SCORES:
		volume = THEME_VOLUME
	}
	rl.SetMusicVolume(theme, volume)
}
