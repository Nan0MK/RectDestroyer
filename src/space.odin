package src

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// src/textures/space_bg.png on the inside of a cube. The camera stays at the center.
// The mesh faces outward, so the draw culls front faces and the inside is what shows.
// The default shader lights those outward faces, which leaves the inside black.
SPACE_CUBE :: f32(10)
SPACE_FOVY :: f32(70)
// Radians per second. The three rates stay different so the tumble is not one spin.
SPACE_SPIN_X :: f32(0.025)
SPACE_SPIN_Y :: f32(0.05)
SPACE_SPIN_Z :: f32(0.012)

SPACE_VS :: `
#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
uniform mat4 mvp;
out vec2 fragTexCoord;
void main() {
	fragTexCoord = vertexTexCoord;
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

SPACE_FS :: `
#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
	vec4 texel = texture(texture0, fragTexCoord);
	finalColor = vec4(texel.rgb, 1.0);
}
`

space_model: rl.Model
space_tex: rl.Texture2D
space_shader: rl.Shader
space_ready: bool

ensure_space_background :: proc() {
	if space_ready || !rl.IsWindowReady() do return
	space_ready = true

	tex := rl.LoadTexture("src/textures/space_bg.png")
	if tex.id == 0 {
		fmt.eprintf("Failed to load texture 'src/textures/space_bg.png'\n")
		return
	}
	rl.GenTextureMipmaps(&tex)
	rl.SetTextureFilter(tex, .TRILINEAR)
	rl.SetTextureWrap(tex, .CLAMP)

	vs, vs_err := strings.clone_to_cstring(SPACE_VS)
	fs, fs_err := strings.clone_to_cstring(SPACE_FS)
	defer delete(vs)
	defer delete(fs)

	space_model = rl.LoadModelFromMesh(rl.GenMeshCube(SPACE_CUBE, SPACE_CUBE, SPACE_CUBE))
	if space_model.meshCount < 1 || space_model.materialCount < 1 || vs_err != nil || fs_err != nil {
		rl.UnloadTexture(tex)
		if space_model.meshCount > 0 do rl.UnloadModel(space_model)
		space_model = {}
		fmt.eprintf("Failed to build the space background\n")
		return
	}

	shader := rl.LoadShaderFromMemory(vs, fs)
	if shader.id == 0 {
		rl.UnloadTexture(tex)
		rl.UnloadModel(space_model)
		space_model = {}
		fmt.eprintf("Failed to load shader for 'src/textures/space_bg.png'\n")
		return
	}

	// UnloadModel frees the mesh and the material map list. It leaves this shader and texture.
	space_shader = shader
	space_tex = tex
	space_model.materials[0].shader = space_shader
	rl.SetMaterialTexture(&space_model.materials[0], .ALBEDO, space_tex)
}

unload_space_background :: proc() {
	if space_shader.id != 0 {
		rl.UnloadShader(space_shader)
		space_shader = {}
	}
	if space_tex.id != 0 {
		rl.UnloadTexture(space_tex)
		space_tex = {}
	}
	if space_model.meshCount > 0 do rl.UnloadModel(space_model)
	space_model = {}
	space_ready = false
}

// Wall time, so pause and the menus do not stop the tumble.
draw_space_background :: proc() {
	ensure_space_background()
	if space_model.meshCount < 1 do return

	t := f32(rl.GetTime())
	space_model.transform = rl.MatrixRotateXYZ({t * SPACE_SPIN_X, t * SPACE_SPIN_Y, t * SPACE_SPIN_Z})

	rlgl.SetCullFace(.FRONT)
	defer rlgl.SetCullFace(.BACK)

	rl.BeginMode3D({
		position = {0, 0, 0},
		target = {0, 0, 1},
		up = {0, 1, 0},
		fovy = SPACE_FOVY,
		projection = .PERSPECTIVE,
	})
	rl.DrawModel(space_model, {}, 1, rl.WHITE)
	rl.EndMode3D()
}
