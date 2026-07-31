package game

import rl "vendor:raylib"

//region Entity

MAX_ENTITIES :: 1000

// 0 is reserved to mean "no entity" - entity_create hands out 1, 2, 3, ...
Entity_Id :: distinct u32

Entity_Kind :: enum {
	Bird,
	Pipe_Top,
	Pipe_Bottom,
}

Entity :: struct {
	id:       Entity_Id,
	kind:     Entity_Kind,
	rec:      rl.Rectangle,
	velocity: f32,
	scored:   bool, // Pipe_Top only: has the bird already passed this pipe?
}

entity_create :: proc(kind: Entity_Kind, rec: rl.Rectangle) -> Entity_Id {
	g_mem.next_entity_id += 1
	id := g_mem.next_entity_id

	appended := append(&g_mem.entities, Entity{id = id, kind = kind, rec = rec})
	assert(appended == 1, "hit MAX_ENTITIES, can't create another entity")
	return id
}

// Swaps the last entity into the removed slot instead of shifting everything
// down - order doesn't matter for us, and it keeps this O(1).
entity_destroy :: proc(id: Entity_Id) {
	for e, i in g_mem.entities {
		if e.id == id {
			unordered_remove(&g_mem.entities, i)
			return
		}
	}
}

// Returned pointer is only valid until the next entity_create/entity_destroy
// call, since either can move or reallocate the backing array. Don't hold on
// to it across a frame boundary - look the entity up again instead.
entity_get :: proc(id: Entity_Id) -> ^Entity {
	for &e in g_mem.entities {
		if e.id == id {
			return &e
		}
	}
	return nil
}

//endregion

//region Pipes

PIPE_WIDTH :: 60
PIPE_GAP :: 160 // vertical opening the bird flies through
PIPE_SPEED :: -200 // pixels / second, negative = moving left
PIPE_SPAWN_INTERVAL :: 1.6 // seconds between pipe pairs
PIPE_MARGIN :: 40 // keep the gap at least this far from the top/bottom edge

pipe_spawn :: proc() {
	min_gap_y := i32(PIPE_MARGIN)
	max_gap_y := g_mem.screen_height - i32(PIPE_GAP) - i32(PIPE_MARGIN)
	gap_y := f32(rl.GetRandomValue(min_gap_y, max_gap_y))

	top_id := entity_create(.Pipe_Top, {f32(g_mem.screen_width), 0, PIPE_WIDTH, gap_y})
	entity_get(top_id).velocity = PIPE_SPEED

	bottom_id := entity_create(
		.Pipe_Bottom,
		{
			f32(g_mem.screen_width),
			gap_y + PIPE_GAP,
			PIPE_WIDTH,
			f32(g_mem.screen_height) - gap_y - PIPE_GAP,
		},
	)
	entity_get(bottom_id).velocity = PIPE_SPEED
}

// Moves pipes, scores the ones the bird has passed, destroys the ones that
// have scrolled off-screen, and reports whether any pipe is touching the
// bird right now.
pipes_update :: proc(dt: f32, bird: ^Entity) -> (hit: bool) {
	g_mem.pipe_spawn_timer -= dt
	if g_mem.pipe_spawn_timer <= 0 {
		pipe_spawn()
		g_mem.pipe_spawn_timer = PIPE_SPAWN_INTERVAL
	}

	// Collected instead of removed in-place, since unordered_remove would
	// shuffle entities we haven't visited yet into the slot we're on.
	to_destroy: [dynamic; 64]Entity_Id

	for &e in g_mem.entities {
		if e.kind != .Pipe_Top && e.kind != .Pipe_Bottom {
			continue
		}

		e.rec.x += e.velocity * dt

		if rl.CheckCollisionRecs(bird.rec, e.rec) {
			hit = true
		}

		if e.kind == .Pipe_Top && !e.scored && e.rec.x + e.rec.width < bird.rec.x {
			e.scored = true
			g_mem.score += 1
		}

		if e.rec.x + e.rec.width < 0 {
			append(&to_destroy, e.id)
		}
	}

	for id in to_destroy {
		entity_destroy(id)
	}

	return
}

//endregion
