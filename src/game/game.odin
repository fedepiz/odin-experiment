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

SpriteId :: int


Game :: struct {
	long_lived_arena: mem.Arena,
	sprite_names:     map[string]SpriteId,
}

RectGradient :: [4]Color

rect_gradient_shaded :: proc(
	base: Color,
	relief, light_strength, dark_strength: f32,
) -> RectGradient {
	out := base
	if relief == 0 {return out}

	amount := clamp(relief < 0 ? -relief : relief, 0, 1)
	light_amount := light_strength * amount
	dark_amount := dark_strength * amount
	light := color_mix(base, WHITE, light_amount)
	soft_light := color_mix(base, WHITE, light_amount * 0.6)
	dark := color_mix(base, BLACK, dark_amount)
	soft_dark := color_mix(base, BLACK, dark_amount * 0.6)
	return out
}

Quad :: struct {
	bounds: Rect,
	color:  RectGradient,
	sprite: SpriteId,
}

init :: proc(alloc: mem.Allocator, game: ^Game) {
	{
		bytes, _ := mem.alloc_bytes_non_zeroed(10_000_000, allocator = alloc)
		mem.arena_init(&game.long_lived_arena, bytes)
	}

	sprites: []string = {"quad", "widget"}

	game.sprite_names = make_map(map[string]SpriteId)
	for sprite, idx in sprites {
		map_insert(&game.sprite_names, sprite, idx)
	}
}

Initialize :: struct {
	sprites: []string,
}

prepare :: proc(arena: mem.Allocator, game: ^Game) -> Initialize {
	out: Initialize
	out.sprites = make_slice([]string, len(game.sprite_names), arena)

	for name, idx in game.sprite_names {
		out.sprites[idx] = name
	}

	return out
}

update_and_render :: proc(game: ^Game) -> []Quad {
	draw_commands := make([dynamic]Quad, 0, 1024)

	sprite := game.sprite_names["widget"]

	append(
		&draw_commands,
		Quad{bounds = rect_make(10, 20, 50, 100), color = GREEN, sprite = sprite},
	)
	append(
		&draw_commands,
		Quad{bounds = rect_make(40, 40, 200, 200), color = WHITE, sprite = sprite},
	)

	append(
		&draw_commands,
		Quad {
			bounds = rect_make(200, 200, 50, 100),
			color = rect_gradient_shaded(RED, 0.5, 0.45, 0.55),
		},
	)

	append(&draw_commands, Quad{bounds = rect_make(100, 20, 50, 100), color = WHITE})

	return draw_commands[:]
}

