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

Quad :: struct {
	bounds: Rect,
	color:  Color,
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

	append(&draw_commands, Quad{bounds = rect_make(100, 20, 50, 100), color = WHITE})

	return draw_commands[:]
}

