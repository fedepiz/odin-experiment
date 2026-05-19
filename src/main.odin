package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "vendor:stb/image"

import gl "vendor:OpenGL"
import "vendor:glfw"

import core "core"
import "game"

PLATFORM: struct {
	key_down_now:           [glfw.KEY_LAST]bool,
	key_down_prev:          [glfw.KEY_LAST]bool,
	mouse_button_down_now:  [glfw.MOUSE_BUTTON_LAST]bool,
	mouse_button_down_prev: [glfw.MOUSE_BUTTON_LAST]bool,
}


Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	color: [4]f32,
}

GL: struct {
	program:      u32,
	vao:          u32,
	vbo:          u32,
	ebo:          u32,
	vertices:     [1024]Vertex,
	num_vertices: int,
	indices:      [1024]u32,
	num_indices:  int,
	textures:     [1024]Texture,
}

gl_init :: proc() {
	GL.program = create_program(VERT_SHADER_SOURCE, FRAG_SHADER_SOURCE)

	gl.GenVertexArrays(1, &GL.vao)

	gl.GenBuffers(1, &GL.vbo)

	gl.GenBuffers(1, &GL.ebo)
	{
		gl.BindVertexArray(GL.vao)
		defer gl.BindVertexArray(0)

		gl.BindBuffer(gl.ARRAY_BUFFER, GL.vbo)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, GL.ebo)

		// layout (location = 0) vec2 a_pos
		gl.EnableVertexAttribArray(0)
		gl.VertexAttribPointer(
			0, // location
			2, // 2 floats (vec2)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, pos), // offset
		)

		// layout (location = 1) vec2 a_uv
		gl.EnableVertexAttribArray(1)
		gl.VertexAttribPointer(
			1, // location
			2, // 2 floats (vec2)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, uv), // offset
		)

		// layout (location = 2) vec4 a_col
		gl.EnableVertexAttribArray(2)
		gl.VertexAttribPointer(
			2, // location
			4, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, color), // offset
		)
	}
}

gl_deinit :: proc() {
	gl.DeleteProgram(GL.program)
	gl.DeleteBuffers(1, &GL.vbo)
	gl.DeleteVertexArrays(1, &GL.vao)
	gl.DeleteBuffers(1, &GL.ebo)
}

draw_call :: proc(quads: []game.Quad, texture: Texture) {
	// Reset buffer states
	GL.num_indices = 0
	GL.num_vertices = 0

	for quad in quads {
		// Skip if buffers are full
		if GL.num_vertices + 4 >= len(GL.vertices) || GL.num_indices + 6 >= len(GL.indices) do continue

		pos := game.rect_corners(quad.bounds)
		fill := game.color_raw(quad.color)

		pos_to_ndc :: proc(pos: [2]f32) -> [2]f32 {
			return (pos / {800, 600} * 2 - 1) * {1, -1}
		}

		uvs: [4][2]f32 = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}

		for i := 0; i < 4; i += 1 {
			GL.vertices[GL.num_vertices + i] = Vertex {
				pos   = pos_to_ndc(pos[i]),
				uv    = uvs[i],
				color = fill,
			}
		}

		index_pattern: [6]int = {0, 1, 2, 2, 3, 0}
		for i := 0; i < len(index_pattern); i += 1 {
			GL.indices[GL.num_indices + i] = u32(GL.num_vertices + index_pattern[i])
		}

		GL.num_vertices += 4
		GL.num_indices += 6

	}

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(GL.program)

	gl.BindVertexArray(GL.vao)

	gl.BufferData(
		gl.ARRAY_BUFFER,
		size_of(Vertex) * GL.num_vertices,
		&GL.vertices[0],
		gl.DYNAMIC_DRAW,
	)

	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		size_of(u32) * GL.num_indices,
		&GL.indices[0],
		gl.DYNAMIC_DRAW,
	)


	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture)

	u_texture := gl.GetUniformLocation(GL.program, "u_texture")
	gl.Uniform1i(u_texture, 0)

	gl.DrawElements(gl.TRIANGLES, i32(GL.num_indices), gl.UNSIGNED_INT, nil)
}


Texture :: u32

load_texture :: proc(path: cstring) -> Texture {
	w, h, channels: i32
	pixels := image.load(path, &w, &h, &channels, 4)
	if pixels == nil {
		fmt.printf("Something went wrong while loading texture %s\n", path)
	}
	defer image.image_free(pixels)

	texture: u32
	target :: gl.TEXTURE_2D

	gl.GenTextures(1, &texture)
	gl.BindTexture(target, texture)

	// Wrapping
	gl.TexParameteri(target, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(target, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	// Filtering
	gl.TexParameteri(target, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(target, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	gl.TexImage2D(target, 0, i32(gl.RGBA8), w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels)

	gl.BindTexture(target, 0)

	return texture
}

batch_quads :: proc(alloc: mem.Allocator, quads: []game.Quad) -> [][]game.Quad {
	quad_is_compatible :: proc(q1: game.Quad, q2: game.Quad) -> bool {
		return q1.sprite == q2.sprite
	}

	batches := make([dynamic][]game.Quad, alloc)
	if len(quads) > 0 {
		batch := make_dynamic_array_len_cap([dynamic]game.Quad, 0, len(quads), alloc)
		// Alaways put the first thing in the batch
		append(&batch, quads[0])
		for quad, idx in quads {
			prev_quad := batch[idx]
			// If the quads are incompatible, start a new batch
			if !quad_is_compatible(quad, prev_quad) {
				append(&batches, batch[:])
				clear(&batch)
			}
			append(&batch, quad)
		}
		append(&batches, batch[:])
	}
	return batches[:]
}

main :: proc() {
	// Initialize scratch memory for this thread
	core.init_scratch(100_000_000)

	// Arenas
	arenas: struct {
		root:  mem.Dynamic_Arena,
		frame: mem.Arena,
	}

	{
		// Initialize arenas
		mem.dynamic_arena_init(&arenas.root)
		bytes, _ := mem.dynamic_arena_alloc_bytes(&arenas.root, 10_000_000)
		mem.arena_init(&arenas.frame, bytes)
	}

	root_arena: mem.Allocator = mem.dynamic_arena_allocator(&arenas.root)
	frame_arena: mem.Allocator = mem.arena_allocator(&arenas.frame)

	if !glfw.Init() {
		fmt.println("Failed to initialize glfw")
		return
	}
	defer glfw.Terminate()

	// Use opengl 3.3
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	// With macos compatibility
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, true)

	window := glfw.CreateWindow(800, 600, "Application", nil, nil)
	if window == nil {
		fmt.println("Failed to initialise window")
		return
	}

	glfw.MakeContextCurrent(window)
	glfw.SetKeyCallback(window, key_callback)
	glfw.SetMouseButtonCallback(window, mouse_callback)

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
	gl.Viewport(0, 0, 800, 600)

	gl_init()
	defer gl_deinit()

	test_texture := load_texture("assets/widget.png")

	game_state: game.Game
	game.init(root_arena, &game_state)

	{
		init := game.prepare(frame_arena, &game_state)

		for name, idx in init.sprites {
			path := strings.join({"assets/", name, ".png"}, "", frame_arena)
			cpath := strings.clone_to_cstring(path, frame_arena)
			fmt.printfln("Loaded %s as texture id: %d", name, idx)
			GL.textures[idx] = load_texture(cpath)
		}
	}

	for !glfw.WindowShouldClose(window) {
		mem.free_all(frame_arena)

		glfw.PollEvents()

		// Press Escape to exit
		if is_key_pressed(glfw.KEY_ESCAPE) {
			glfw.SetWindowShouldClose(window, true)
		}

		// Clear screen
		gl.ClearColor(0.1, 0.15, 0.25, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		quads := game.update_and_render(&game_state)

		// end of frame
		PLATFORM.key_down_prev = PLATFORM.key_down_now
		PLATFORM.mouse_button_down_prev = PLATFORM.mouse_button_down_now

		batches := batch_quads(frame_arena, quads)

		for batch in batches {
			// "Interpret" draw commands
			sprite_id := batch[0].sprite
			draw_call(batch, GL.textures[sprite_id])
		}

		glfw.SwapBuffers(window)
	}
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	value := PLATFORM.key_down_now[key]
	switch (action) {
	case glfw.PRESS:
		value = true
	case glfw.RELEASE:
		value = false
	case:
	}
	PLATFORM.key_down_now[key] = value
}

mouse_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	value := PLATFORM.mouse_button_down_now[button]
	switch (action) {
	case glfw.PRESS:
		value = true
	case glfw.RELEASE:
		value = false
	case:
	}
	PLATFORM.mouse_button_down_now[button] = value
}

is_key_down :: proc(key: i32) -> bool {
	return PLATFORM.key_down_now[key]
}

is_key_pressed :: proc(key: i32) -> bool {
	return PLATFORM.key_down_now[key] && !PLATFORM.key_down_prev[key]
}

is_button_down :: proc(button: i32) -> bool {
	return PLATFORM.mouse_button_down_now[button]
}

is_button_pressed :: proc(button: i32) -> bool {
	return PLATFORM.mouse_button_down_now[button] && !PLATFORM.mouse_button_down_prev[button]
}


VERT_SHADER_SOURCE :: `
#version 330 core
layout (location = 0) in vec2 a_pos;
layout (location = 1) in vec2 a_uv;
layout (location = 2) in vec4 a_col;

out vec2 v_uv;
out vec4 v_col;

void main() {
	gl_Position = vec4(a_pos, 0.0, 1.0);
	v_uv = a_uv;
	v_col = a_col;
}
`

FRAG_SHADER_SOURCE :: `
#version 330 core
in vec2 v_uv;
in vec4 v_col;
out vec4 frag_color;

uniform sampler2D u_texture;

void main() {
	frag_color = texture(u_texture, v_uv); //v_col;
}
`

compile_shader :: proc(kind: u32, source: cstring) -> u32 {
	shader := gl.CreateShader(kind)

	sources := [?]cstring{source}
	gl.ShaderSource(shader, 1, &sources[0], nil)
	gl.CompileShader(shader)

	ok: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &ok)

	if ok == 0 {
		log: [1024]u8
		log_len: i32
		gl.GetShaderInfoLog(shader, len(log), &log_len, &log[0])
		fmt.eprintln("Shader compile error:")
		fmt.eprintln(string(log[:log_len]))
	}

	return shader
}

create_program :: proc(vertex_source, fragment_source: cstring) -> u32 {
	vs := compile_shader(gl.VERTEX_SHADER, vertex_source)
	fs := compile_shader(gl.FRAGMENT_SHADER, fragment_source)

	program := gl.CreateProgram()

	gl.AttachShader(program, vs)
	gl.AttachShader(program, fs)
	gl.LinkProgram(program)

	ok: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &ok)

	if ok == 0 {
		log: [1024]u8
		log_len: i32
		gl.GetProgramInfoLog(program, len(log), &log_len, &log[0])
		fmt.eprintln("Program link error:")
		fmt.eprintln(string(log[:log_len]))
	}

	gl.DeleteShader(vs)
	gl.DeleteShader(fs)

	return program
}
