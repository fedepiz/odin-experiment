#+private
package game

import "../util"
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
SpawnSeqNum :: distinct u32

Thing :: struct {
	id:       ThingId,
	seq_num:  SpawnSeqNum,
	name:     string,
	sprite:   Asset_Id,
	pos:      [2]f32,
	size:     f32,
	movement: Movement,
}

Movement :: struct {
	active: bool,
	target: ThingId,
	pos:    V2,
}

Things :: struct {
	blobs:        [2][BLOB_SIZE_MB * 1_000_000]byte,
	arenas:       [2]mem.Arena,
	entries:      [2][NUM_THINGS]Thing,
	last_seq_num: SpawnSeqNum,
}


things_init :: proc(game: ^Game) {
	scratch := util.with_scratch(nil)

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

	commands: [dynamic]Tick_Command = make(
		[dynamic]Tick_Command,
		0,
		len(entities) * 5,
		scratch.arena,
	)
	for entity, idx in entities {
		target := SpawnSeqNum(idx + 1)
		append(&commands, Tick_Command{kind = .Spawn})
		append(&commands, Tick_Command{kind = .SetName, subject = target, string = entity.name})
		append(
			&commands,
			Tick_Command{kind = .SetSprite, subject = target, string = entity.sprite},
		)
		append(&commands, Tick_Command{kind = .SetPos, subject = target, nums = entity.pos})
		append(&commands, Tick_Command{kind = .SetSize, subject = target, nums = {entity.size, 0}})
	}

	tick(game, commands[:])
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

pass_get_old :: proc(pass: ^Pass, id: ThingId) -> ^Thing {
	thing := &pass.old_things[id.generation]
	return thing.id.generation == id.generation ? thing : &pass.old_things[0]
}

Tick_Command :: struct {
	kind:    Tick_Command_Kind,
	subject: Tick_Command_ThingRef,
	// Arguments, if any
	target:  Tick_Command_ThingRef,
	string:  string,
	nums:    [2]f32,
}

Tick_Command_Kind :: enum {
	Spawn,
	SetName,
	SetSprite,
	SetPos,
	SetSize,
}

No_Target :: struct {}

Tick_Command_ThingRef :: union {
	No_Target,
	ThingId,
	SpawnSeqNum,
}


tick :: proc(game: ^Game, commands: []Tick_Command) {
	game.tick_num += 1

	pass := make_pass(game)

	// Pre-process commands (to count spawns, primarily)
	num_spawns := 0
	for &command in commands {
		if command.kind == .Spawn {
			num_spawns += 1
		}
	}

	// Write step
	for idx in 1 ..< NUM_THINGS {
		old := &pass.old_things[idx]
		new := &pass.new_things[idx]
		// Clone over parts that need to be copied
		new.id = old.id
		if !thing_id_is_valid(new.id) {
			// We are done if we are not spawned, and there are no spawns
			if num_spawns <= 0 do continue
			num_spawns -= 1
			// Increase the generation, as we are now spawned
			new.id.generation += 1
			assert(thing_id_is_valid(new.id))
			// Set & bump the sequence number
			game.things.last_seq_num += 1
			new.seq_num = game.things.last_seq_num
		}

		new_name := old.name

		new.sprite = old.sprite
		// Body
		new.pos = old.pos
		new.size = old.size

		// Copy over movement
		new.movement = old.movement

		// Apply commands
		for &cmd in commands {
			targets_me := false
			switch v in cmd.subject {
			case No_Target:
			case ThingId:
				targets_me = new.id == v
			case SpawnSeqNum:
				targets_me = new.seq_num == v
			}
			// Skip if I am not targeted
			if !targets_me do continue
			switch cmd.kind {
			case .Spawn:
				assert(false)
			case .SetName:
				new_name = cmd.string
			case .SetSprite:
				new.sprite = game.sprites_by_name[cmd.string]
			case .SetPos:
				new.pos = cmd.nums
			case .SetSize:
				new.size = cmd.nums[0]
			}
		}

		// Name & stuff
		new.name = strings.clone(new_name, pass.alloc)

		// Update position/movement
		if new.movement.active {
			// Update target movement position
			if new.movement.target != NIL_ID {
				new.movement.pos = pass_get_old(&pass, new.movement.target).pos
			}

			diff := new.movement.pos - new.pos
			mag := v2_magnitude(diff)
			norm := diff / mag
			dv := norm * 1.0
			new.pos += dv
		}
	}
}

