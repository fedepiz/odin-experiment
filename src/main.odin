package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "vendor:stb/image"
import stbtt "vendor:stb/truetype"

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
	xy:    [2]f32,
	uv:    [2]f32,
	color: [4]f32,
}

VERTICES_MAX :: 1024
INDICES_MAX :: 1024

GL: struct {
	program:         u32,
	vao:             u32,
	vbo:             u32,
	ebo:             u32,
	vertices:        [dynamic; VERTICES_MAX]Vertex,
	indices:         [dynamic; INDICES_MAX]u32,
	sprite_textures: [dynamic; 1024]Texture,
	fonts:           [dynamic; 32]FontData,
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
			offset_of(Vertex, xy), // offset
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


Element :: struct {
	xy:    [4][2]f32,
	uv:    [4][2]f32,
	color: [4][4]f32,
}

DrawCommand :: struct {
	texture: Texture,
	element: Element,
}

translate_draw_commands :: proc(alloc: mem.Allocator, commands: []game.Drawable) -> []DrawCommand {
	out := make_dynamic_array_len_cap(
		[dynamic]DrawCommand,
		0,
		2 * len(commands),
		allocator = alloc,
	)
	for command in commands {
		if len(command.text) == 0 {
			elem := Element {
				xy    = game.rect_corners(command.bounds),
				uv    = {{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				color = command.color,
			}
			texture := GL.sprite_textures[command.sprite]
			append(&out, DrawCommand{element = elem, texture = texture})
		} else {
			assert(false)
		}
	}
	return out[:]
}

batch_draw_commands :: proc(alloc: mem.Allocator, commands: []DrawCommand) -> []Batch {
	// Copy over the elements
	elements := make_slice([]Element, len(commands), allocator = alloc)
	for i in 0 ..< len(commands) {
		elements[i] = commands[i].element
	}

	// Prepare the batches
	batches: [dynamic]Batch = make_dynamic_array([dynamic]Batch, allocator = alloc)
	batch: Batch
	start_idx := 0
	for idx := 0; idx < len(commands); idx += 1 {
		command := commands[idx]

		end_batch := idx == len(commands) - 1 || command.texture != commands[idx + 1].texture
		if end_batch {
			// add all draw commands from start index to here
			end_idx := idx + 1
			batch.elements = elements[start_idx:end_idx]
			batch.texture = commands[start_idx].texture
			append(&batches, batch)
			batch = Batch{}
			start_idx = end_idx
		}
	}

	return batches[:]
}


Batch :: struct {
	texture:  Texture,
	elements: []Element,
}

pos_to_ndc :: proc(pos: [2]f32) -> [2]f32 {
	return (pos / {800, 600} * 2 - 1) * {1, -1}
}

draw_call :: proc(batch: Batch) {
	// Reset buffer states
	clear(&GL.vertices)
	clear(&GL.indices)

	for elem in batch.elements {
		// Skip if buffers are full
		if len(GL.vertices) + 4 >= VERTICES_MAX || len(GL.indices) + 6 >= INDICES_MAX do continue

		index_pattern: [6]int = {0, 1, 2, 2, 3, 0}
		for i := 0; i < len(index_pattern); i += 1 {
			append(&GL.indices, u32(len(GL.vertices) + index_pattern[i]))
		}

		for i := 0; i < 4; i += 1 {
			vertex := Vertex {
				xy    = pos_to_ndc(elem.xy[i]),
				uv    = elem.uv[i],
				color = game.color_raw(elem.color[i]),
			}
			append(&GL.vertices, vertex)
		}
	}

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(GL.program)

	gl.BindVertexArray(GL.vao)

	gl.BufferData(
		gl.ARRAY_BUFFER,
		size_of(Vertex) * len(GL.vertices),
		raw_data(GL.vertices[:]),
		gl.DYNAMIC_DRAW,
	)

	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		size_of(u32) * len(GL.indices),
		raw_data(GL.indices[:]),
		gl.DYNAMIC_DRAW,
	)


	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, batch.texture)

	u_texture := gl.GetUniformLocation(GL.program, "u_texture")
	gl.Uniform1i(u_texture, 0)

	gl.DrawElements(gl.TRIANGLES, i32(len(GL.indices)), gl.UNSIGNED_INT, nil)
}

Texture :: u32

load_texture_from_file :: proc(path: cstring) -> Texture {
	w, h, channels: i32
	pixels := image.load(path, &w, &h, &channels, 4)
	if pixels == nil {
		fmt.printf("Something went wrong while loading texture %s\n", path)
	}
	defer image.image_free(pixels)

	return load_texture_from_pixels(pixels, w, h)
}

load_texture_from_pixels :: proc(pixels: [^]byte, w: i32, h: i32) -> Texture {
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
		mem.dynamic_arena_init(&arenas.root, alignment = 64)
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

	game_state: game.Game
	game.init(root_arena, &game_state)

	font := load_font_from_file("assets/fonts/default.ttf")

	{
		asset_reqs := game.asset_request(frame_arena)
		assets: game.Assets

		for name in asset_reqs.sprites {
			path := strings.join({"assets/", name, ".png"}, "", frame_arena)
			cpath := strings.clone_to_cstring(path, frame_arena)
			texture := load_texture_from_file(cpath)
			id := len(GL.sprite_textures)
			append(&GL.sprite_textures, texture)

			sprites := make_dynamic_array_len_cap(
				[dynamic]game.Asset_Def,
				0,
				len(asset_reqs.sprites),
				frame_arena,
			)

			append(&sprites, game.Asset_Def{name = name, id = u32(id)})

			assets.sprites = sprites[:]
		}

		for name in asset_reqs.fonts {
			path := strings.join({"assets/fonts/", name, ".ttf"}, "", frame_arena)
			font := load_font_from_file(path)
			id := len(GL.fonts)
			append(&GL.fonts, font)

			fonts := make_dynamic_array_len_cap(
				[dynamic]game.Asset_Def,
				0,
				len(asset_reqs.fonts),
				frame_arena,
			)

			append(&fonts, game.Asset_Def{name = name, id = u32(id)})
			assets.fonts = fonts[:]
		}

		game.start(&game_state, assets)
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

		drawables := game.update_and_render(frame_arena, &game_state)

		// end of frame
		PLATFORM.key_down_prev = PLATFORM.key_down_now
		PLATFORM.mouse_button_down_prev = PLATFORM.mouse_button_down_now

		batches := batch_draw_commands(
			frame_arena,
			translate_draw_commands(frame_arena, drawables),
		)

		for batch in batches {
			// "Interpret" draw commands
			draw_call(batch)
		}

		batch := text_to_batch(frame_arena, "Hello, World!", game.BLACK, &font, {100, 100}, 24)
		draw_call(batch)

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
	frag_color = texture(u_texture, v_uv) * v_col;
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

FontData :: struct {
	cdata:        [96]stbtt.bakedchar,
	texture:      Texture,
	min_glyph:    i32,
	max_glyph:    i32,
	pixel_height: int,
}

grayscale_to_rgba :: proc(arena: mem.Allocator, grayscale: []byte) -> []byte {
	img_rgba, _ := mem.alloc_bytes_non_zeroed(len(grayscale) * 4, allocator = arena)
	for i := 0; i < len(grayscale); i += 1 {
		img_rgba[i * 4] = 255
		img_rgba[i * 4 + 1] = 255
		img_rgba[i * 4 + 2] = 255
		img_rgba[i * 4 + 3] = grayscale[i]
	}
	return img_rgba
}

load_font_from_file :: proc(path: string) -> FontData {
	scratch := core.with_scratch(nil)
	out: FontData

	image_dim: i32 = 512
	min_glyph: i32 = 32
	pixel_height := 18

	bytes, error := os.read_entire_file_from_path(path, scratch.arena)
	if error != os.ERROR_NONE {
		os.print_error(os.stdout, error, "File error")
	} else {
		bitmap_gray, _ := mem.alloc_bytes(int(image_dim * image_dim), allocator = scratch.arena)

		num_glyphs: i32 = len(out.cdata)

		stbtt.BakeFontBitmap(
			raw_data(bytes),
			0,
			f32(pixel_height),
			raw_data(bitmap_gray),
			image_dim,
			image_dim,
			min_glyph,
			num_glyphs,
			raw_data(out.cdata[:]),
		)

		bitmap_rgba := grayscale_to_rgba(scratch.arena, bitmap_gray)
		out.texture = load_texture_from_pixels(raw_data(bitmap_rgba), image_dim, image_dim)

		out.min_glyph = min_glyph
		out.max_glyph = min_glyph + num_glyphs
		out.pixel_height = pixel_height
	}
	return out
}

text_to_batch :: proc(
	alloc: mem.Allocator,
	text: string,
	color: game.Color,
	font: ^FontData,
	pos: [2]f32,
	pixel_size: f32,
) -> Batch {
	scale: f32 = pixel_size / f32(font.pixel_height)
	pen: [2]f32

	elements := make_dynamic_array_len_cap([dynamic]Element, 0, len(text), alloc)

	for char in text {
		q: stbtt.aligned_quad
		glyph := i32(char)

		if (glyph >= font.min_glyph && glyph < font.max_glyph) {
			glyph -= font.min_glyph
		} else {
			glyph = 0
		}

		stbtt.GetBakedQuad(raw_data(font.cdata[:]), 512, 512, glyph, &pen.x, &pen.y, &q, true)

		element := Element {
			xy    = {
				{pos.x + q.x0 * scale, pos.y + q.y0 * scale},
				{pos.x + q.x1 * scale, pos.y + q.y0 * scale},
				{pos.x + q.x1 * scale, pos.y + q.y1 * scale},
				{pos.x + q.x0 * scale, pos.y + q.y1 * scale},
			},
			uv    = {{q.s0, q.t0}, {q.s1, q.t0}, {q.s1, q.t1}, {q.s0, q.t1}},
			color = color,
		}
		append(&elements, element)
	}

	batch: Batch = {
		elements = elements[:],
		texture  = font.texture,
	}

	return batch
}

