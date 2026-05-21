package game

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

color_mix :: proc(c1: Color, c2: Color, t: f32) -> Color {
	t := clamp(t, 0, 1)
	// Lerp every colour
	result := c1 + (c2 - c1) * t
	// But carry the alpha of the source
	result.a = c1.a
	return result
}

WHITE: Color = {1, 1, 1, 1}
BLACK: Color = {0, 0, 0, 1}
RED: Color = {1, 0, 0, 1}
GREEN: Color = {0, 1, 0, 1}
BLUE: Color = {0, 0, 1, 1}

Game :: struct {
	long_lived_arena: mem.Arena,
	sprite_names:     map[string]Asset_Id,
	font_names:       map[string]Asset_Id,
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
	Top_Left,
}

DrawableText :: struct {
	content:      string,
	font:         Asset_Id,
	pixel_height: f32,
	color:        Color,
	pos:          DrawTextPos,
}

SpriteMapping :: enum {
	Stretch,
	Wrap,
}

Drawable :: struct {
	bounds:         Rect,
	color:          Rect_Gradient,
	stroke:         Rect_Gradient,
	thickness:      f32,
	radius:         f32,
	sprite:         Asset_Id,
	sprite_mapping: SpriteMapping,
	text:           DrawableText,
}

Assets_Request :: struct {
	sprites: []string,
	fonts:   []string,
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

// Prepare the game struct, preparing the various allocators etc
init :: proc(alloc: mem.Allocator, game: ^Game) {
	bytes, _ := mem.alloc_bytes_non_zeroed(10_000_000, allocator = alloc)
	mem.arena_init(&game.long_lived_arena, bytes)
	long_lived_alloc := mem.arena_allocator(&game.long_lived_arena)
	// Initialize the sprite map
	game.sprite_names = make_map(map[string]Asset_Id, long_lived_alloc)
	game.font_names = make_map(map[string]Asset_Id, long_lived_alloc)
}

// Asks the game what assets it may need
asset_request :: proc(alloc: mem.Allocator) -> Assets_Request {
	sprites := make_dynamic_array([dynamic]string, alloc)
	fonts := make_dynamic_array([dynamic]string, alloc)

	append(&sprites, "quad", "widget")
	append(&fonts, "default")

	return Assets_Request{sprites = sprites[:], fonts = fonts[:]}
}

// Provide the assets to the game and start in full
start :: proc(game: ^Game, assets: Assets) {
	for sprite in assets.sprites {
		map_insert(&game.sprite_names, sprite.name, sprite.id)
	}
	for font in assets.fonts {
		map_insert(&game.font_names, font.name, font.id)
	}
}

Platform_Input :: struct {
	mouse_pos:     V2,
	mouse_clicked: bool,
	mouse_down:    bool,
}

update_and_render :: proc(arena: mem.Allocator, game: ^Game, input: Platform_Input) -> []Drawable {
	draw_commands: [dynamic]Drawable = make([dynamic]Drawable, 0, 1024, allocator = arena)

	{
		base_color := color_rgba8(207, 185, 151, 255)
		ui_set_style_var(.UnitW, 80)
		ui_set_style_var(.UnitH, 40)
		ui_set_style_var(.WidgetBaseColor, base_color)
		ui_set_style_var(.WidgetHoverColor, BLUE)
		ui_set_style_var(.WidgetHeldColor, RED)
		ui_set_style_var(.WidgetTextColor, BLACK)
		ui_set_style_var(.WidgetTextSize, 24)
		ui_set_style_var(.WidgetBorderColor, color_mix(base_color, BLACK, 0.5))
		ui_set_style_var(.WidgetBorderRadius, 10)
		ui_set_style_var(.WidgetBorderThickness, 5)
		ui_set_style_var(.PanelColor, WHITE)

		sprite := game.sprite_names["widget"]
		ui_begin(input)

		{
			ui_panel(.Vertical)
			ui_box_set_background(sprite)

			if ui_button("Hello", 2, 1) {
				fmt.println("Hello")
			}

			ui_vspace()

			if ui_button("Goodbye", 2, 1) {
				fmt.println("Goodbye")
			}
		}

		commands := ui_end()
		for command in commands {
			append(&draw_commands, command)
		}
	}

	return draw_commands[:]
}

