package game

import "../csv"
import "../util"
import "core:mem"

Terrain_Type :: struct {
	move_speed: f32,
	tile_x:     u8,
	tile_y:     u8,
	max_height: f32,
}

@(private = "file")
determine_terrain_type :: proc(types: []Terrain_Type, height: f32) -> Terrain_Type {
	for type in types {
		if height < type.max_height {
			return type
		}
	}
	return {}
}

World_Cell :: struct {
	move_speed: f32,
}

World_Map :: struct {
	size:  [2]int,
	cells: []World_Cell,
}

Heightmap :: struct {
	size:  [2]int,
	cells: []f32,
}

World_Map_Tile_Keys :: struct {
	size:  [2]int,
	cells: [][2]u8,
}

load_world_map :: proc(
	long_lived_alloc: mem.Allocator,
	short_lived_alloc: mem.Allocator,
	terrain_types_csv: csv.Table,
	heightmap: Heightmap,
) -> (
	World_Map,
	World_Map_Tile_Keys,
) {
	world_map: World_Map
	world_map.size = heightmap.size
	world_map.cells = make_slice([]World_Cell, len(heightmap.cells), long_lived_alloc)

	tile_keys: World_Map_Tile_Keys
	tile_keys.size = world_map.size
	tile_keys.cells = make_slice([][2]u8, len(heightmap.cells), short_lived_alloc)

	scratch := util.with_scratch({long_lived_alloc, short_lived_alloc})

	terrain_types := make_dynamic_array_len_cap(
		[dynamic]Terrain_Type,
		0,
		len(terrain_types_csv),
		scratch.arena,
	)

	for row in terrain_types_csv {
		tt: Terrain_Type
		row := csv.read_row(row)
		name := csv.read_text(&row)

		tt.move_speed = csv.read_num(&row)
		tt.tile_x = u8(csv.read_num(&row))
		tt.tile_y = u8(csv.read_num(&row))
		tt.max_height = csv.read_num(&row)
		append(&terrain_types, tt)
	}

	for idx in 0 ..< len(world_map.cells) {
		elevation := heightmap.cells[idx]
		tt := determine_terrain_type(terrain_types[:], elevation)

		world_map.cells[idx] = {
			move_speed = tt.move_speed,
		}
		tile_keys.cells[idx] = {tt.tile_x, tt.tile_y}
	}

	return world_map, tile_keys
}

