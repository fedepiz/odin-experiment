package game

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

Color :: [4]f32

color_raw :: proc(color: Color) -> [4]f32 {
	return cast([4]f32)color
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
	sprite_names:     map[string]AssetId,
	font_names:       map[string]AssetId,
}

RectGradient :: [4]Color

rect_gradient_shaded :: proc(
	base: Color,
	relief, light_strength, dark_strength: f32,
) -> RectGradient {
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

Drawable :: struct {
	bounds:       Rect,
	color:        RectGradient,
	sprite:       AssetId,
	text:         string,
	font:         AssetId,
	pixel_height: int,
}

AssetsRequest :: struct {
	sprites: []string,
	fonts:   []string,
}

AssetId :: u32

AssetDef :: struct {
	name: string,
	id:   AssetId,
}

Assets :: struct {
	sprites: []AssetDef,
	fonts:   []AssetDef,
}

// Prepare the game struct, preparing the various allocators etc
init :: proc(alloc: mem.Allocator, game: ^Game) {
	bytes, _ := mem.alloc_bytes_non_zeroed(10_000_000, allocator = alloc)
	mem.arena_init(&game.long_lived_arena, bytes)
	long_lived_alloc := mem.arena_allocator(&game.long_lived_arena)
	// Initialize the sprite map
	game.sprite_names = make_map(map[string]AssetId, long_lived_alloc)
	game.font_names = make_map(map[string]AssetId, long_lived_alloc)
}

// Asks the game what assets it may need
asset_request :: proc(alloc: mem.Allocator) -> AssetsRequest {
	sprites := make_dynamic_array([dynamic]string, alloc)
	fonts := make_dynamic_array([dynamic]string, alloc)

	append(&sprites, "quad", "widget")
	append(&fonts, "default")

	return AssetsRequest{sprites = sprites[:], fonts = fonts[:]}
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

update_and_render :: proc(arena: mem.Allocator, game: ^Game) -> []Drawable {
	draw_commands: [dynamic]Drawable = make([dynamic]Drawable, 0, 1024, allocator = arena)

	sprite := game.sprite_names["widget"]

	append(
		&draw_commands,
		Drawable{bounds = rect_make(10, 20, 50, 100), color = GREEN, sprite = sprite},
	)
	append(
		&draw_commands,
		Drawable{bounds = rect_make(40, 40, 200, 200), color = WHITE, sprite = sprite},
	)

	append(
		&draw_commands,
		Drawable {
			bounds = rect_make(200, 200, 50, 100),
			color = rect_gradient_shaded(RED, 1.0, 0.45, 0.55),
		},
	)

	append(&draw_commands, Drawable{bounds = rect_make(100, 20, 50, 100), color = WHITE})

	return draw_commands[:]
}
