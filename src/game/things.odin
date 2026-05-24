#+private
package game

import "core:mem"
import "core:strings"

thing_id_is_valid :: proc(id: ThingId) -> bool {
	return id.idx > 0 && id.generation % 2 == 1
}

ThingId :: struct {
	idx:        u16,
	generation: u16,
}

NIL_ID :: ThingId{0, 0}

// Concept: the seq_num.
// Each spawned thing, progressively, gets a sequence number (seq num).
// This is used to pre-associate a spawn (and other commands) with the future spawn-ed id.
// This is becasue at the time of a spawn, we do not yet know the target id.
// So the ways to identify an entity are:
// By id (allows fast random access)
// By seq_num (no fast access)

Thing :: struct {
	id:      ThingId,
	seq_num: u64,
	name:    string,
	sprite:  Asset_Id,
	pos:     [2]f32,
	size:    f32,
}

Things :: struct {
	blobs:        [2][BLOB_SIZE_MB * 1_000_000]byte,
	arenas:       [2]mem.Arena,
	entries:      [2][NUM_THINGS]Thing,
	last_seq_num: u64,
}


things_init :: proc(game: ^Game) {
	Entity :: struct {
		name:   string,
		sprite: string,
		pos:    [2]f32,
		size:   f32,
	}

	entities: []Entity = {
		{name = "Caer Ligualid", sprite = "celtic_town", pos = {300, 254}, size = 3},
		{name = "Anava", sprite = "celtic_village", pos = {302, 248}, size = 2},
		{name = "Test", sprite = "soldier", pos = {305, 248}, size = 1},
	}

	pass := make_pass(game)

	for entity, idx in entities {
		thing := &pass.new_things[idx + 1]
		thing.id.generation += 1
		assert(thing_id_is_valid(thing.id))

		thing.name = strings.clone(entity.name, pass.alloc)
		thing.sprite = game.sprites_by_name[entity.sprite]
		thing.pos = entity.pos
		thing.size = entity.size
	}
}

Pass :: struct {
	alloc:      mem.Allocator,
	old_things: []Thing,
	new_things: []Thing,
}

make_pass :: proc(game: ^Game) -> Pass {
	out: Pass
	active_idx := game.tick_num % 2
	arena := &game.things.arenas[active_idx]
	mem.arena_free_all(arena)
	out.alloc = mem.arena_allocator(arena)
	out.new_things = game.things.entries[active_idx][:]
	out.old_things = game.things.entries[1 - active_idx][:]
	return out
}

tick :: proc(game: ^Game) {
	game.tick_num += 1

	pass := make_pass(game)

	// Write step
	for idx in 1 ..< len(pass.new_things) {
		old := pass.old_things[idx]
		new := &pass.new_things[idx]
		// Clone over parts that need to be copied
		new.id = old.id
		// Body
		new.pos = old.pos
		new.size = old.size
		// Name & stuff
		new.name = strings.clone(old.name, pass.alloc)
		new.sprite = old.sprite
	}
}

