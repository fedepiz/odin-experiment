package util

import "core:mem"
import "core:os"


@(private)
@(thread_local)
SCRATCH_ARENAS: struct {
	initialised: bool,
	allocator:   mem.Allocator,
	arenas:      [2]mem.Arena,
}

ArenaTemp :: struct {
	arena: mem.Allocator,
	pos:   mem.Arena_Temp_Memory,
}

init_scratch :: proc(size: int) {
	assert(!SCRATCH_ARENAS.initialised)
	SCRATCH_ARENAS.allocator = os.heap_allocator()
	for &arena in SCRATCH_ARENAS.arenas {
		bytes, _ := mem.alloc_bytes(size, allocator = SCRATCH_ARENAS.allocator)
		mem.arena_init(&arena, bytes)
	}
	SCRATCH_ARENAS.initialised = true
}

deinit_scratch :: proc() {
	if !SCRATCH_ARENAS.initialised do return
	for &arena in SCRATCH_ARENAS.arenas {
		mem.free(&arena.data, SCRATCH_ARENAS.allocator)
	}
	mem.zero_item(&SCRATCH_ARENAS)
}

get_scratch :: proc(conflicts: []mem.Allocator) -> ArenaTemp {
	assert(SCRATCH_ARENAS.initialised)

	out: ArenaTemp

	for &arena in SCRATCH_ARENAS.arenas {
		is_ok := true
		for conflict in conflicts {
			is_ok = is_ok && &arena != conflict.data
			if !is_ok do break
		}
		if is_ok {
			out.arena = mem.arena_allocator(&arena)
			out.pos.arena = &arena
			out.pos = mem.begin_arena_temp_memory(&arena)
			break
		}
	}
	return out
}

release_scratch :: proc(arena_temp: ArenaTemp) {
	mem.end_arena_temp_memory(arena_temp.pos)
}

@(deferred_out = release_scratch)
with_scratch :: proc(conflicts: []mem.Allocator) -> ArenaTemp {
	return get_scratch(nil)
}

