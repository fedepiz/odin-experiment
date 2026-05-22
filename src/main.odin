package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "vendor:stb/image"
import stbtt "vendor:stb/truetype"

import gl "vendor:OpenGL"
import "vendor:glfw"

import "game"
import "util"

import "csv"

PLATFORM: struct {
	window_size:            [2]f32,
	key_down_now:           [glfw.KEY_LAST]bool,
	key_down_prev:          [glfw.KEY_LAST]bool,
	mouse_button_down_now:  [glfw.MOUSE_BUTTON_LAST]bool,
	mouse_button_down_prev: [glfw.MOUSE_BUTTON_LAST]bool,
	mouse_pos:              [2]f32,
}

Vertex :: struct {
	xy:            [2]f32,
	uv:            [2]f32,
	st:            [2]f32,
	color:         [4]f32,
	frag_size_px:  [2]f32,
	stroke:        [4]f32,
	thickness:     f32,
	radius:        f32,
	tex_intensity: f32,
}

VERTICES_MAX :: 1024
INDICES_MAX :: 1024

Sprite :: struct {
	name:    string,
	texture: Texture,
	region:  [4]int,
}

GL: struct {
	program:       u32,
	vao:           u32,
	vbo:           u32,
	ebo:           u32,
	vertices:      [dynamic; VERTICES_MAX]Vertex,
	indices:       [dynamic; INDICES_MAX]u32,
	terrain_keys:  Texture,
	terrain_atlas: Texture,
	sprites:       [dynamic; 1024]Sprite,
	fonts:         [dynamic; 32]FontData,
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
		//
		// layout (location = 2) vec2 a_uv
		gl.EnableVertexAttribArray(2)
		gl.VertexAttribPointer(
			2, // location
			2, // 2 floats (vec2)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, st), // offset
		)

		// layout (location = 3) vec4 a_col
		gl.EnableVertexAttribArray(3)
		gl.VertexAttribPointer(
			3, // location
			4, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, color), // offset
		)
		//
		// layout (location = 4) vec4 a_col
		gl.EnableVertexAttribArray(4)
		gl.VertexAttribPointer(
			4, // location
			2, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, frag_size_px), // offset
		)
		//
		// layout (location = 5) vec4 a_col
		gl.EnableVertexAttribArray(5)
		gl.VertexAttribPointer(
			5, // location
			4, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, stroke), // offset
		)
		//
		// layout (location = 6) vec4 a_col
		gl.EnableVertexAttribArray(6)
		gl.VertexAttribPointer(
			6, // location
			1, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, thickness), // offset
		)
		//
		// layout (location = 7) vec4 a_col
		gl.EnableVertexAttribArray(7)
		gl.VertexAttribPointer(
			7, // location
			1, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, radius), // offset
		)
		//
		// layout (location = 8) vec4 a_col
		gl.EnableVertexAttribArray(8)
		gl.VertexAttribPointer(
			8, // location
			1, // 4 floats (vec4)
			gl.FLOAT,
			false, // no normalisation
			size_of(Vertex), // stride
			offset_of(Vertex, tex_intensity), // offset
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
	xy:            [4][2]f32,
	st:            [4][2]f32,
	color:         [4][4]f32,
	size:          [2]f32,
	stroke:        [4][4]f32,
	thickness:     f32,
	radius:        f32,
	tex_intensity: f32,
}

DrawCommand :: struct {
	texture: Texture,
	element: Element,
}

TextMeasurement :: struct {
	size:     [2]f32,
	baseline: f32,
}

measure_text :: proc(text: string, font: ^FontData, pixel_height: f32) -> TextMeasurement {
	out: TextMeasurement
	scale := pixel_height / f32(font.pixel_height)

	x, y, min_x, min_y, max_x, max_y: f32

	for char in text {
		q: stbtt.aligned_quad
		glyph := i32(char)

		if (glyph >= font.min_glyph && glyph < font.max_glyph) {
			glyph -= font.min_glyph
		} else {
			glyph = 0
		}

		stbtt.GetBakedQuad(raw_data(font.cdata[:]), 512, 512, glyph, &x, &y, &q, true)

		min_x = min(min_x, q.x0)
		min_y = min(min_y, q.y0)
		max_x = max(max_x, q.x1)
		max_y = max(max_y, q.y1)


	}
	out.size.x = (max_x - min_x) * scale
	out.size.y = (max_y - min_y) * scale
	out.baseline = -(min_y + max_y) * scale / 2

	return out
}

translate_draw_commands :: proc(
	alloc: mem.Allocator,
	commands: []game.Drawable,
	camera: Camera,
) -> []DrawCommand {
	out := make_dynamic_array_len_cap(
		[dynamic]DrawCommand,
		0,
		2 * len(commands),
		allocator = alloc,
	)
	for draw in commands {
		bounds := draw.bounds

		switch (draw.space) {
		case .World:
			// We need to map to world space
			xy := camera_point_world_to_screen(camera, {bounds.x, bounds.y}, PLATFORM.window_size)
			br := camera_point_world_to_screen(
				camera,
				{bounds.x + bounds.w, bounds.y + bounds.h},
				PLATFORM.window_size,
			)
			bounds = game.Rect {
				x = xy.x,
				y = xy.y,
				w = br.x - xy.x,
				h = br.y - xy.y,
			}
		case .Ui:
		}

		if bounds.w > 0 && bounds.h > 0 {
			sprite := GL.sprites[draw.sprite]
			texture := sprite.texture

			reg_pos := [2]f32{f32(sprite.region[0]), f32(sprite.region[1])}
			reg_size := [2]f32{f32(sprite.region[2]), f32(sprite.region[3])}
			reg_min := reg_pos / texture.size

			st: [4][2]f32 = ---
			switch (draw.sprite_mapping) {
			case .Stretch:
				reg_max := (reg_pos + reg_size) / texture.size
				st = {
					{reg_min.x, reg_min.y},
					{reg_max.x, reg_min.y},
					{reg_max.x, reg_max.y},
					{reg_min.x, reg_max.y},
				}
			case .Wrap:
				span := game.rect_size(bounds) / reg_size
				st = {
					{reg_min.x, reg_min.y},
					{reg_min.x + span.x, reg_min.y},
					{reg_min.x + span.x, reg_min.y + span.y},
					{reg_min.x, reg_min.y + span.y},
				}
			}

			elem := Element {
				xy            = game.rect_corners(bounds),
				st            = st,
				color         = draw.color,
				size          = game.rect_size(bounds),
				stroke        = draw.stroke,
				thickness     = draw.thickness,
				radius        = draw.radius,
				tex_intensity = draw.sprite_intensity,
			}
			append(&out, DrawCommand{element = elem, texture = texture})
		}

		if len(draw.text.content) > 0 {
			font := &GL.fonts[draw.text.font]
			scale: f32 = f32(draw.text.pixel_height) / f32(font.pixel_height)
			measure := measure_text(draw.text.content, font, draw.text.pixel_height)
			pen: [2]f32

			for char in draw.text.content {
				q: stbtt.aligned_quad
				glyph := i32(char)

				if (glyph >= font.min_glyph && glyph < font.max_glyph) {
					glyph -= font.min_glyph
				} else {
					glyph = 0
				}

				stbtt.GetBakedQuad(
					raw_data(font.cdata[:]),
					512,
					512,
					glyph,
					&pen.x,
					&pen.y,
					&q,
					true,
				)

				pos: [2]f32 = {bounds.x, bounds.y}

				switch (draw.text.pos) {
				case .Center:
					pos.x += (bounds.w - measure.size.x) / 2
					pos.y += bounds.h / 2 + measure.baseline
				case .Left:
					pos.y += bounds.h / 2 + measure.baseline
				case .Top_Left:
				}


				element := Element {
					xy            = {
						{pos.x + q.x0 * scale, pos.y + q.y0 * scale},
						{pos.x + q.x1 * scale, pos.y + q.y0 * scale},
						{pos.x + q.x1 * scale, pos.y + q.y1 * scale},
						{pos.x + q.x0 * scale, pos.y + q.y1 * scale},
					},
					st            = {{q.s0, q.t0}, {q.s1, q.t0}, {q.s1, q.t1}, {q.s0, q.t1}},
					color         = draw.text.color,
					size          = {q.x1 - q.x0, q.y1 - q.y0},
					tex_intensity = 1,
				}
				append(&out, DrawCommand{element = element, texture = font.texture})
			}
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

pos_to_ndc :: proc(pos: [2]f32, window: [2]f32) -> [2]f32 {
	return (pos / window * 2 - 1) * {1, -1}
}

draw_batch :: proc(batch: Batch) {
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

		uv: [4][2]f32 = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}
		for i := 0; i < 4; i += 1 {
			// xy is the screen position.
			xy := pos_to_ndc(elem.xy[i], PLATFORM.window_size)

			vertex := Vertex {
				xy            = xy,
				uv            = uv[i],
				st            = elem.st[i],
				color         = elem.color[i],
				frag_size_px  = elem.size,
				stroke        = elem.stroke[i],
				thickness     = elem.thickness,
				radius        = elem.radius,
				tex_intensity = elem.tex_intensity,
			}
			append(&GL.vertices, vertex)
		}
	}

	draw_call(batch.texture, 1)
}


draw_terrain :: proc(camera: Camera) {
	clear(&GL.vertices)
	clear(&GL.indices)

	terrain_tile_size: f32 = 40
	window := PLATFORM.window_size
	xy: [4][2]f32 = {{0, 0}, {window.x, 0}, {window.x, window.y}, {0, window.y}}

	key_coord: [4][2]f32
	st_coord: [4][2]f32
	for i := 0; i < 4; i += 1 {
		world_point := camera_point_screen_to_world(camera, xy[i], window)
		key_coord[i] = world_point
		st_coord[i] = terrain_point_world_to_st(camera, world_point, terrain_tile_size)
	}

	uv: [4][2]f32 = {
		(key_coord[0] + 0.5) / GL.terrain_keys.size,
		(key_coord[1] + 0.5) / GL.terrain_keys.size,
		(key_coord[2] + 0.5) / GL.terrain_keys.size,
		(key_coord[3] + 0.5) / GL.terrain_keys.size,
	}

	st: [4][2]f32 = {st_coord[0], st_coord[1], st_coord[2], st_coord[3]}

	append(&GL.indices, 0, 1, 2, 2, 3, 0)

	for i := 0; i < 4; i += 1 {
		append(
			&GL.vertices,
			Vertex{xy = pos_to_ndc(xy[i], window), uv = uv[i], st = st[i], color = game.WHITE},
		)
	}

	draw_call({}, 2)
}


draw_call :: proc(texture: Texture, mode: i32) {
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


	{
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, texture.id)
		u_texture := gl.GetUniformLocation(GL.program, "u_texture")
		gl.Uniform1i(u_texture, 0)
	}

	{
		gl.ActiveTexture(gl.TEXTURE1)
		gl.BindTexture(gl.TEXTURE_2D, GL.terrain_keys.id)
		loc := gl.GetUniformLocation(GL.program, "u_terrain_keys")
		gl.Uniform1i(loc, 1)
	}

	{
		gl.ActiveTexture(gl.TEXTURE2)
		gl.BindTexture(gl.TEXTURE_2D, GL.terrain_atlas.id)
		loc := gl.GetUniformLocation(GL.program, "u_terrain_atlas")
		gl.Uniform1i(loc, 2)
	}

	{
		loc := gl.GetUniformLocation(GL.program, "u_mode")
		gl.Uniform1i(loc, mode)
	}

	gl.DrawElements(gl.TRIANGLES, i32(len(GL.indices)), gl.UNSIGNED_INT, nil)

}

Texture :: struct {
	id:   u32,
	size: [2]f32,
}

Texture_Filter_Mode :: enum {
	Linear,
	Nearest,
}

load_texture_from_file :: proc(path: cstring, filter_mode: Texture_Filter_Mode) -> Texture {
	w, h, channels: i32
	pixels := image.load(path, &w, &h, &channels, 4)
	if pixels == nil {
		fmt.printf("Something went wrong while loading texture %s\n", path)
	}
	defer image.image_free(pixels)

	return load_texture_from_pixels(pixels, w, h, filter_mode)
}

load_texture_from_pixels :: proc(
	pixels: [^]byte,
	w: i32,
	h: i32,
	filter_mode: Texture_Filter_Mode,
) -> Texture {
	texture: Texture
	target :: gl.TEXTURE_2D

	gl.GenTextures(1, &texture.id)
	gl.BindTexture(target, texture.id)

	// Wrapping
	gl.TexParameteri(target, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(target, gl.TEXTURE_WRAP_T, gl.REPEAT)

	// Filtering
	filter: i32 = ---
	switch (filter_mode) {
	case .Linear:
		filter = gl.LINEAR
	case .Nearest:
		filter = gl.NEAREST
	}
	gl.TexParameteri(target, gl.TEXTURE_MIN_FILTER, filter)
	gl.TexParameteri(target, gl.TEXTURE_MAG_FILTER, filter)

	gl.TexImage2D(target, 0, i32(gl.RGBA8), w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels)

	gl.BindTexture(target, 0)

	texture.size = {f32(w), f32(h)}

	return texture
}

Camera :: struct {
	world_to_px: f32,
	pos:         [2]f32,
	zoom:        f32,
}

camera_point_screen_to_world :: proc(
	camera: Camera,
	screen_point_px: [2]f32,
	viewport_size_px: [2]f32,
) -> [2]f32 {
	zoom := max(camera.zoom, 0.001)
	screen_center := viewport_size_px * 0.5
	world_per_screen_px := 1.0 / (camera.world_to_px * zoom)
	return camera.pos + (screen_point_px - screen_center) * world_per_screen_px
}

camera_point_world_to_screen :: proc(
	camera: Camera,
	world_point: [2]f32,
	viewport_size_px: [2]f32,
) -> [2]f32 {
	zoom := max(camera.zoom, 0.001)
	screen_center := viewport_size_px * 0.5
	screen_per_world_px := camera.world_to_px * zoom
	return screen_center + (world_point - camera.pos) * screen_per_world_px
}

delta_screen_to_world :: proc(camera: Camera, screen_delta_px: [2]f32) -> [2]f32 {
	zoom := max(camera.zoom, 0.001)
	world_per_screen_px := 1.0 / (camera.world_to_px * zoom)
	return screen_delta_px * world_per_screen_px
}

terrain_point_world_to_st :: proc(
	camera: Camera,
	world_point: [2]f32,
	terrain_tile_size: f32,
) -> [2]f32 {
	return world_point * camera.world_to_px / terrain_tile_size
}

camera_pan :: proc(camera: ^Camera, screen_delta_px: [2]f32) {
	camera.pos += delta_screen_to_world(camera^, screen_delta_px)
}

camera_zoom_by :: proc(camera: ^Camera, factor: f32) {
	camera.zoom *= factor
	camera.zoom = clamp(camera.zoom, 0.1, 20.0)
}

main :: proc() {
	util.init_scratch(100_000_000) // Initialize scratch memory for this thread

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

	context.temp_allocator = frame_arena

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

	screen_width :: 1600
	screen_height :: 900

	window := glfw.CreateWindow(screen_width, screen_height, "Application", nil, nil)
	if window == nil {
		fmt.println("Failed to initialise window")
		return
	}

	glfw.MakeContextCurrent(window)
	glfw.SetKeyCallback(window, key_callback)
	glfw.SetMouseButtonCallback(window, mouse_callback)
	glfw.SetCursorPosCallback(window, cursor_pos_callback)

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
	gl.Viewport(0, 0, screen_width, screen_height)

	gl_init()
	defer gl_deinit()

	GL.terrain_atlas = load_texture_from_file("assets/terrain_types.png", .Linear)

	{
		// Fixed extures
		names :: []string{"quad", "widget"}
		for name in names {
			path := strings.join({"assets/", name, ".png"}, "", frame_arena)
			cpath := strings.clone_to_cstring(path, frame_arena)
			texture := load_texture_from_file(cpath, Texture_Filter_Mode.Linear)
			sprite := Sprite {
				name    = name,
				texture = texture,
				region  = {0, 0, int(texture.size.x), int(texture.size.y)},
			}
			append(&GL.sprites, sprite)
		}
	}

	{
		// Pawn atlas preparation
		atlas, loaded := sprite_atlas_load("assets/pawns.csv")
		if loaded {
			sprite_atlas_create("assets/pawns", "assets/pawns")
			a, loaded := sprite_atlas_load("assets/pawns.csv")
			if !loaded {
				fmt.println("Failed to load sprite atlas")
			}
			atlas = a
		}
		texture_path := strings.clone_to_cstring(atlas.image_path)
		texture := load_texture_from_file(texture_path, Texture_Filter_Mode.Linear)

		for region in atlas.regions {
			sprite: Sprite = {
				name    = strings.clone(region.name, root_arena),
				texture = texture,
				region  = {region.x, region.y, region.w, region.h},
			}
			append(&GL.sprites, sprite)
		}
	}

	game_state: game.Game

	{
		// Prepare the terrain
		terrain_types: csv.Table
		{
			source, err := os.read_entire_file("data/terrain_types.csv", frame_arena)
			if err != nil {
				fmt.println("ERROR: Failed to read terrain types table")
			}
			table, csv_errors := csv.parse(frame_arena, string(source))
			for err in csv_errors {
				fmt.printfln("CSV error: %s", err)
			}
			terrain_types = table
		}

		// Load the heightmap image...
		heightmap: game.Heightmap
		{
			w, h, channels: i32
			bytes := image.load("assets/britain.png", &w, &h, &channels, 1)
			defer image.image_free(bytes)

			heightmap.size = {int(w), int(h)}
			heightmap.cells = make_slice([]f32, w * h, frame_arena)
			for i in 0 ..< i32(len(heightmap.cells)) {
				height := f32(bytes[i * channels]) / 255
				heightmap.cells[i] = height
			}
		}

		// Initialise the game
		world_map_keys := game.init(
			root_arena,
			frame_arena,
			&game_state,
			game.Init_Params{terrain_types, heightmap},
		)

		{
			// Create a texture
			bytes, _ := mem.alloc_bytes_non_zeroed(
				len(world_map_keys.cells) * 4,
				allocator = frame_arena,
			)
			for i in 0 ..< len(world_map_keys.cells) {
				cell := world_map_keys.cells[i]
				bytes[i * 4] = cell.x
				bytes[i * 4 + 1] = cell.y
				bytes[i * 4 + 2] = 0
				bytes[i * 4 + 3] = 0
			}

			size := world_map_keys.size
			texture := load_texture_from_pixels(
				raw_data(bytes),
				i32(size.x),
				i32(size.y),
				.Nearest,
			)

			GL.terrain_keys = texture
		}
	}

	{
		// Load game assets and start te game
		assets: game.Assets

		// Prepare sprites
		sprites := make_dynamic_array_len_cap(
			[dynamic]game.Asset_Def,
			0,
			len(GL.sprites),
			frame_arena,
		)
		for sprite, idx in GL.sprites {
			append(&sprites, game.Asset_Def{name = sprite.name, id = u32(idx)})
		}
		assets.sprites = sprites[:]

		// Prepare fonts
		names := []string{"default"}
		fonts := make_dynamic_array_len_cap([dynamic]game.Asset_Def, 0, len(names), frame_arena)
		for name in names {
			path := strings.join({"assets/fonts/", name, ".ttf"}, "", frame_arena)
			font := load_font_from_file(path)
			id := len(GL.fonts)
			append(&GL.fonts, font)
			append(&fonts, game.Asset_Def{name = name, id = u32(id)})
		}
		assets.fonts = fonts[:]

		game.start(&game_state, assets)
	}

	camera: Camera
	camera.world_to_px = 10.0
	camera.pos = {300, 250}
	camera.zoom = 4

	current_time := glfw.GetTime()
	for !glfw.WindowShouldClose(window) {
		next_time := glfw.GetTime()
		delta := f32(next_time - current_time)
		fps := delta > 0 ? 1.0 / delta : 0

		current_time = next_time
		mem.free_all(frame_arena)

		glfw.PollEvents()

		{
			x, y := glfw.GetFramebufferSize(window)
			PLATFORM.window_size = {f32(x), f32(y)}
		}

		// Press Escape to exit
		if is_key_pressed(glfw.KEY_ESCAPE) {
			glfw.SetWindowShouldClose(window, true)
		}

		// Clear screen
		gl.ClearColor(0.1, 0.15, 0.25, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		input: game.Platform_Input = {
			mouse_pos     = PLATFORM.mouse_pos,
			mouse_clicked = is_button_pressed(glfw.MOUSE_BUTTON_LEFT),
			mouse_down    = is_button_down(glfw.MOUSE_BUTTON_LEFT),
		}

		drawables := game.update_and_render(frame_arena, &game_state, input)

		// end of frame
		PLATFORM.key_down_prev = PLATFORM.key_down_now
		PLATFORM.mouse_button_down_prev = PLATFORM.mouse_button_down_now


		{
			// Key actions
			Action :: struct {
				key: i32,
				dv:  [2]f32,
				dz:  f32,
			}

			ACTIONS := [?]Action {
				{glfw.KEY_S, {0, 1}, 0},
				{glfw.KEY_W, {0, -1}, 0},
				{glfw.KEY_A, {-1, 0}, 0},
				{glfw.KEY_D, {1, 0}, 0},
				{glfw.KEY_Q, {0, 0}, 1},
				{glfw.KEY_E, {0, 0}, -1},
			}

			dv: [2]f32
			dz: f32
			for action in ACTIONS {
				if is_key_down(action.key) {
					dv += action.dv
					dz += action.dz
				}
			}
			camera_pan(&camera, dv * 400 * delta)
			camera_zoom_by(&camera, 1.0 + dz * 2.5 * delta)
		}

		draw_terrain(camera)

		{
			elements := translate_draw_commands(frame_arena, drawables, camera)
			batches := batch_draw_commands(frame_arena, elements)
			for batch in batches {
				draw_batch(batch)
			}
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

cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x_pos, y_pos: f64) {
	PLATFORM.mouse_pos = {f32(x_pos), f32(y_pos)}
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
layout (location = 0) in vec2 a_xy;
layout (location = 1) in vec2 a_uv;
layout (location = 2) in vec2 a_st;
layout (location = 3) in vec4 a_col;
layout (location = 4) in vec2 a_frag_size_px;
layout (location = 5) in vec4 a_stroke;
layout (location = 6) in float a_thickness_px;
layout (location = 7) in float a_radius_px;
layout (location = 8) in float a_tex_intensity;

out vec2 v_uv;
out vec2 v_st;
out vec4 v_col;
out vec2 v_frag_size_px;
out vec4 v_stroke;
out float v_thickness_px;
out float v_radius_px;
out float v_tex_intensity;

void main() {
	gl_Position = vec4(a_xy, 0.0, 1.0);
	v_uv = a_uv;
	v_st = a_st;
	v_col = a_col;
	v_frag_size_px = a_frag_size_px;
	v_stroke = a_stroke;
	v_thickness_px = a_thickness_px;
	v_radius_px = a_radius_px;
	v_tex_intensity = a_tex_intensity;
}
`

FRAG_SHADER_SOURCE :: `
#version 330 core
in vec2 v_uv;
in vec2 v_st;
in vec4 v_col;
in vec2 v_frag_size_px;
in vec4 v_stroke;
in float v_thickness_px;
in float v_radius_px;
in float v_tex_intensity;

out vec4 frag_color;

uniform int u_mode;

uniform sampler2D u_texture;
uniform sampler2D u_terrain_keys;
uniform sampler2D u_terrain_atlas;

const int MODE_DEFAULT = 1;
const int MODE_TERRAIN = 2;

float RoundedBoxSDF(vec2 p, vec2 half_size, float radius) {
  vec2 q = abs(p) - half_size + vec2(radius);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec4 default_mode() {
	vec2 half_size = v_frag_size_px * 0.5;
	float radius = min(v_radius_px, min(half_size.x, half_size.y));
	vec2 p = (v_uv - 0.5) * v_frag_size_px;
	float sd = RoundedBoxSDF(p, half_size, radius);

	float aa = fwidth(sd);
	float mask_outer = 1.0 - smoothstep(0.0, aa, sd);
	float mask_inner = 1.0 - smoothstep(0.0, aa, sd + v_thickness_px);
	float stroke = mask_outer - mask_inner;

	vec4 tex = texture(u_texture, v_st);
	vec4 fill_col =  mix(v_col, tex * v_col, v_tex_intensity);
	vec4 col = fill_col * mask_inner + v_stroke * stroke;

	return col;
}

ivec2 terrain_tile_coord_from_key(ivec2 key_coord, ivec2 key_size, ivec2 atlas_tile_count) {
	ivec2 clamped_key_coord = clamp(key_coord, ivec2(0, 0), key_size - ivec2(1, 1));
	vec4 key = texelFetch(u_terrain_keys, clamped_key_coord, 0);
	ivec2 tile_coord = ivec2(round(key.rg * 255.0));
	return clamp(tile_coord, ivec2(0, 0), atlas_tile_count - ivec2(1, 1));
}

vec4 sample_terrain_tile(ivec2 tile_coord, vec2 tile_st, vec2 atlas_size, vec2 tile_size) {
	vec2 wrapped_st = fract(tile_st);
	vec2 clamped_st = clamp(wrapped_st, 0.0, 1.0);
	vec2 atlas_px = vec2(tile_coord) * tile_size + clamped_st * (tile_size - 1.0) + 0.5;
	return texture(u_terrain_atlas, atlas_px / atlas_size);
}

vec4 terrain_mode() {
	ivec2 key_size = textureSize(u_terrain_keys, 0);
	vec2 atlas_size = vec2(textureSize(u_terrain_atlas, 0));
	vec2 tile_size = vec2(256.0, 256.0);
	ivec2 atlas_tile_count = ivec2(atlas_size / tile_size);

	vec2 key_pos = v_uv * vec2(key_size) - 0.5;
	ivec2 key_base = ivec2(floor(key_pos));
	vec2 key_blend = fract(key_pos);

	vec4 c00 = sample_terrain_tile(terrain_tile_coord_from_key(key_base + ivec2(0, 0), key_size, atlas_tile_count), v_st, atlas_size, tile_size);
	vec4 c10 = sample_terrain_tile(terrain_tile_coord_from_key(key_base + ivec2(1, 0), key_size, atlas_tile_count), v_st, atlas_size, tile_size);
	vec4 c11 = sample_terrain_tile(terrain_tile_coord_from_key(key_base + ivec2(1, 1), key_size, atlas_tile_count), v_st, atlas_size, tile_size);
	vec4 c01 = sample_terrain_tile(terrain_tile_coord_from_key(key_base + ivec2(0, 1), key_size, atlas_tile_count), v_st, atlas_size, tile_size);

	vec4 cx0 = mix(c00, c10, key_blend.x);
	vec4 cx1 = mix(c01, c11, key_blend.x);
	return mix(cx0, cx1, key_blend.y);
}

void main() {
	if (u_mode == MODE_DEFAULT) {
		frag_color = default_mode();
	} else if (u_mode == MODE_TERRAIN){
		frag_color = terrain_mode();
	} else {
		frag_color = vec4(1,0,0,1);
	}
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
	scratch := util.with_scratch(nil)
	out: FontData

	image_dim: i32 = 512
	min_glyph: i32 = 32
	pixel_height := 36

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
		out.texture = load_texture_from_pixels(
			raw_data(bitmap_rgba),
			image_dim,
			image_dim,
			.Linear,
		)

		out.min_glyph = min_glyph
		out.max_glyph = min_glyph + num_glyphs
		out.pixel_height = pixel_height
	}
	return out
}

