package game

import "core:mem"

Terrain_Type :: struct {
	traverse_speed: f32,
	tile_x:         int,
	tile_y:         int,
	max_height:     f32,
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

WorldCell :: struct {
	traverse_speed: f32,
}

WorldMap :: struct {
	width:     int,
	height:    int,
	map_key:   Asset_Id,
	map_atlas: Asset_Id,
	cells:     []WorldCell,
}


load_world_map :: proc(alloc: mem.Allocator) -> WorldMap {
	world_map: WorldMap
	return world_map
}

