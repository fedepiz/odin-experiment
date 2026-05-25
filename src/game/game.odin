package game

import "../csv"
import "core:fmt"
import "core:mem"
V2 :: [2]f32

Rect :: struct {
	x: f32,
	y: f32,
	w: f32,
	h: f32,
}

rect_make :: proc(x, y, w, h: f32) -> Rect {
	return Rect{x, y, w, h}
}

rect_corners :: proc(rect: Rect) -> [4][2]f32 {
	return {
		{rect.x, rect.y},
		{rect.x + rect.w, rect.y},
		{rect.x + rect.w, rect.y + rect.h},
		{rect.x, rect.y + rect.h},
	}
}

rect_contains_point :: proc(rect: Rect, point: V2) -> bool {
	return(
		point.x >= rect.x &&
		point.y >= rect.y &&
		point.x <= rect.x + rect.w &&
		point.y <= rect.y + rect.h \
	)
}

rect_size :: proc(rect: Rect) -> V2 {return {rect.w, rect.h}}

Color :: [4]f32

color_raw :: proc(color: Color) -> [4]f32 {
	return cast([4]f32)color
}

color_rgba8 :: proc(r, g, b, a: u8) -> Color {
	vec: [4]u8 = {r, g, b, a}
	return cast([4]f32)(vec) / 255
}

color_with_alpha :: proc(c: Color, a: f32) -> Color {
	c := c
	c.a = a
	return c
}

color_mix :: proc(c1: Color, c2: Color, t: f32) -> Color {
	t := clamp(t, 0, 1)
	// Lerp every colour
	result := c1 + (c2 - c1) * t
	// But carry the alpha of the source
	result.a = c1.a
	return result
}

TRANSPARENT: Color = {}
WHITE: Color = {1, 1, 1, 1}
BLACK: Color = {0, 0, 0, 1}
RED: Color = {1, 0, 0, 1}
GREEN: Color = {0, 1, 0, 1}
BLUE: Color = {0, 0, 1, 1}
YELLOW: Color = {1, 1, 0, 1}

NUM_THINGS :: 32000
STATIC_SIZE_MB :: 10
BLOB_SIZE_MB :: 10

GameStaticMemory :: struct {
	buffer: [10 * 1_000_000]byte,
	arena:  mem.Arena,
	alloc:  mem.Allocator,
}

Game :: struct {
	static_memory:   GameStaticMemory,
	sprites_by_name: map[string]Asset_Id,
	font_names:      map[string]Asset_Id,
	world_map:       World_Map,
	tick_num:        u64,
	things:          Things,
	selected_id:     ThingId,
}

Rect_Gradient :: [4]Color

rect_gradient_shaded :: proc(
	base: Color,
	relief: f32,
	light_strength: f32 = 0.45,
	dark_strength: f32 = 0.55,
) -> Rect_Gradient {
	if relief == 0 {return base}

	amount := clamp(relief < 0 ? -relief : relief, 0, 1)
	light_amount := light_strength * amount
	dark_amount := dark_strength * amount
	light := color_mix(base, WHITE, light_amount)
	soft_light := color_mix(base, WHITE, light_amount * 0.6)
	dark := color_mix(base, BLACK, dark_amount)
	soft_dark := color_mix(base, BLACK, dark_amount * 0.6)

	if relief < 0 {
		return {dark, soft_dark, light, soft_light}
	} else {
		return {light, soft_light, dark, soft_dark}
	}
}

DrawTextPos :: enum {
	Center,
	Left,
	Top_Center,
	Top_Left,
}

DrawableText :: struct {
	content:      string,
	font:         Asset_Id,
	pixel_height: f32,
	color:        Color,
	pos:          DrawTextPos,
	background:   Color,
	padding:      [2]f32,
}

SpriteMapping :: enum {
	Stretch,
	Wrap,
}

DrawableSpace :: enum {
	World,
	Ui,
}

Drawable :: struct {
	space:            DrawableSpace,
	bounds:           Rect,
	color:            Rect_Gradient,
	stroke:           Rect_Gradient,
	thickness:        f32,
	radius:           f32,
	sprite:           Asset_Id,
	sprite_mapping:   SpriteMapping,
	sprite_intensity: f32,
	rim_color:        Color,
	rim_thickness_px: f32,
	text:             DrawableText,
}

@(private = "file")
Click_Box :: struct {
	id:     ThingId,
	bounds: Rect,
}

Asset_Id :: u32

Asset_Def :: struct {
	name: string,
	id:   Asset_Id,
}

Assets :: struct {
	sprites: []Asset_Def,
	fonts:   []Asset_Def,
}

Init_Params :: struct {
	terrain_types: csv.Table,
	heightmap:     Heightmap,
}

// Prepare the game struct, preparing the various allocators etc
init :: proc(
	long_alloc: mem.Allocator,
	short_alloc: mem.Allocator,
	game: ^Game,
	params: Init_Params,
) -> World_Map_Tile_Keys {
	// Initialize arena
	mem.arena_init(&game.static_memory.arena, game.static_memory.buffer[:])
	game.static_memory.alloc = mem.arena_allocator(&game.static_memory.arena)
	// Initialize the sprite map
	game.sprites_by_name = make_map(map[string]Asset_Id, game.static_memory.alloc)
	game.font_names = make_map(map[string]Asset_Id, game.static_memory.alloc)

	world_map, world_keys := load_world_map(
		game.static_memory.alloc,
		short_alloc,
		params.terrain_types,
		params.heightmap,
	)

	game.world_map = world_map

	// Initialize things
	for &thing, idx in game.things.entries[0] {
		thing.id = ThingId{u16(idx), 0}
	}
	game.things.entries[1] = game.things.entries[0]
	for i in 0 ..< 2 {
		mem.arena_init(&game.things.arenas[i], game.things.blobs[i][:])
	}

	return world_keys
}

// Provide the assets to the game and start in full
start :: proc(game: ^Game, assets: Assets) {
	for sprite in assets.sprites {
		map_insert(&game.sprites_by_name, sprite.name, sprite.id)
	}
	for font in assets.fonts {
		map_insert(&game.font_names, font.name, font.id)
	}

	things_init(game)
}

Platform_Input :: struct {
	mouse_pos_screen: V2,
	mouse_pos_world:  V2,
	mouse_clicked:    bool,
	mouse_down:       bool,
	fps:              f32,
}

update_and_render :: proc(arena: mem.Allocator, game: ^Game, input: Platform_Input) -> []Drawable {
	tick(game, {})

	click_boxes: [dynamic]Click_Box = make([dynamic]Click_Box, 0, 1024, arena)
	drawables: [dynamic]Drawable = make([dynamic]Drawable, 0, 4096, arena)
	draw_world(game, &drawables, &click_boxes)

	build_ui(arena, game, input, &drawables)

	if !ui_is_mouse_over_area() && input.mouse_clicked {
		game.selected_id = {}
		for idx := len(click_boxes); idx > 0; idx -= 1 {
			click_box := click_boxes[idx - 1]
			if rect_contains_point(click_box.bounds, input.mouse_pos_world) {
				game.selected_id = click_box.id
			}
		}
	}

	return drawables[:]
}

show_ui := true

@(private = "file")
draw_world :: proc(game: ^Game, drawables: ^[dynamic]Drawable, click_boxes: ^[dynamic]Click_Box) {
	actve_idx := game.tick_num % 2
	for &this in game.things.entries[actve_idx][1:] {
		if !thing_id_is_valid(this.id) {continue}


		pos := this.pos
		size := this.size

		drawable: Drawable

		bounds: Rect = {pos.x - size / 2, pos.y - size / 2, size, size}

		drawable = Drawable {
			space            = .World,
			bounds           = bounds,
			sprite           = this.sprite,
			sprite_intensity = 1,
			color            = WHITE,
			rim_color        = YELLOW,
			rim_thickness_px = game.selected_id == this.id ? 6 : 0,
		}
		append(drawables, drawable)
		append(click_boxes, Click_Box{this.id, bounds})


		drawable = Drawable {
			space = .World,
			bounds = {pos.x, pos.y + size / 2 + 0.25, 0, 0},
			text = DrawableText {
				content = this.name,
				font = 0,
				pixel_height = 24,
				color = game.selected_id == this.id ? YELLOW : WHITE,
				pos = .Center,
				background = color_with_alpha(BLACK, 0.5),
				padding = 4,
			},
		}
		append(drawables, drawable)
	}
}

@(private = "file")
build_ui :: proc(
	arena: mem.Allocator,
	game: ^Game,
	input: Platform_Input,
	drawables: ^[dynamic]Drawable,
) {
	base_color := color_rgba8(207, 185, 151, 255)
	// Basic
	ui_set_style_number(.UnitW, 20)
	ui_set_style_number(.UnitH, 20)
	// Widget
	ui_set_style_color(.WidgetBaseColor, base_color)
	ui_set_style_color(.WidgetHoverColor, GREEN)
	ui_set_style_color(.WidgetHeldColor, RED)
	ui_set_style_color(.WidgetTextColor, BLACK)
	ui_set_style_number(.WidgetTextSize, 26)
	ui_set_style_color(.WidgetBorderColor, color_mix(base_color, BLACK, 0.5))
	ui_set_style_number(.WidgetBorderRadius, 8)
	ui_set_style_number(.WidgetBorderThickness, 5)
	ui_set_style_number(.WidgetThinBorderThickness, 2)
	ui_set_style_color(.ToggleOnColor, GREEN)
	ui_set_style_color(.ToggleHoverColor, RED)
	// Panels
	ui_set_style_color(.PanelColor, base_color)
	ui_set_style_color(.PanelBorderColor, color_mix(base_color, BLACK, 0.5))
	ui_set_style_number(.PanelBorderRadius, 8)
	ui_set_style_number(.PanelBorderThickness, 5)

	sprite := game.sprites_by_name["widget"]
	ui_begin(input)

	if show_ui {
		ui_panel(.Vertical)
		ui_box_set_background(sprite, 0.2)

		ui_vspace()

		{
			ui_row()
			ui_heading("This is a heading!", 16)
			show_ui = !ui_toggle("###CLOSE", false)
			ui_hspace()
		}


		{
			ui_row()
			ui_hspace()
			if ui_button("Hello", 6) {
				fmt.println("Hello")
			}
			ui_hspace()
		}

		ui_vspace()

		{
			ui_row()
			ui_hspace()
			if ui_button("Goodbye", 6) {
				fmt.println("Goodbye")
			}
			ui_hspace()
		}

		// ui_vspace()

		// {
		// 	ui_row()
		// 	ui_hspace()
		// 	sb := strings.builder_make(arena)
		// 	fmt.sbprintf(&sb, "FPS: %d", int(input.fps))
		// 	text := strings.to_string(sb)
		// 	ui_label(text, 6)
		// 	ui_hspace()
		// }

		ui_vspace()
	}

	ui_end(drawables)
}
