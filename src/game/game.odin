package game

// All actual gameplay code and state lives here. This package gets compiled
// two different ways:
//   - as game.dll, loaded by main_hot_reload for fast iteration while playing
//   - statically linked into main_release for the real shipping build
// Because of that, this file must never call rl.InitWindow / rl.CloseWindow
// itself (that would tear down the window on every reload) - the host does
// that once, via game_init_window / game_shutdown_window.

import rl "vendor:raylib"

GRAVITY :: 900 // pixels / second^2
FLAP_VELOCITY :: -350 // pixels / second (negative is up)

// Everything that needs to survive a hot reload goes in here. g_mem is
// allocated once by game_init and its pointer is handed back to us in
// game_hot_reloaded after every reload, so the struct's contents (the entity
// list, bird id, etc.) carry over untouched. If you change the shape of this
// struct, the host detects the size mismatch and restarts state instead of
// reinterpreting stale bytes as the new layout.
Game_Memory :: struct {
	screen_width:     i32,
	screen_height:    i32,
	entities:         [dynamic; MAX_ENTITIES]Entity,
	next_entity_id:   Entity_Id,
	bird_id:          Entity_Id,
	pipe_spawn_timer: f32,
	score:            int,
	game_over:        bool,
}

g_mem: ^Game_Memory

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(720 / 2, 1280 / 2, "Odin + Raylib Flappy")
	rl.SetWindowMonitor(0)
	rl.SetTargetFPS(60)
	rl.SetExitKey(.Q)
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem.screen_width = 720 / 2
	g_mem.screen_height = 1280 / 2

	game_reset()
}

// Clears all entities and puts a fresh bird back in the middle of the
// screen. Used both for first-time setup and for restarting after death.
game_reset :: proc() {
	clear(&g_mem.entities)
	g_mem.next_entity_id = 0
	g_mem.pipe_spawn_timer = 0
	g_mem.score = 0
	g_mem.game_over = false

	g_mem.bird_id = entity_create(
		.Bird,
		{f32(g_mem.screen_width) / 2 - 80, f32(g_mem.screen_height) / 2 - 16, 32, 32},
	)
}

@(export)
game_update :: proc() -> bool {
	dt := rl.GetFrameTime()

	if g_mem.game_over {
		if rl.IsKeyPressed(.SPACE) {
			game_reset()
		}
	} else {
		bird := entity_get(g_mem.bird_id)

		if rl.IsKeyPressed(.SPACE) {
			bird.velocity = FLAP_VELOCITY
		}
		bird.velocity += GRAVITY * dt
		bird.rec.y += bird.velocity * dt

		// Ceiling just stops the bird; only the ground and pipes end the game.
		if bird.rec.y < 0 {
			bird.rec.y = 0
			bird.velocity = 0
		}
		if bird.rec.y + bird.rec.height > f32(g_mem.screen_height) {
			bird.rec.y = f32(g_mem.screen_height) - bird.rec.height
			g_mem.game_over = true
		}

		if pipes_update(dt, bird) {
			g_mem.game_over = true
		}
	}

	rl.BeginDrawing()
	rl.ClearBackground(rl.SKYBLUE)
	for e in g_mem.entities {
		color := e.kind == .Bird ? rl.GREEN : rl.RED
		rl.DrawRectangleRec(e.rec, color)
	}
	rl.DrawText(rl.TextFormat("score: %d", g_mem.score), 10, 10, 24, rl.BLACK)
	if g_mem.game_over {
		rl.DrawText(
			"GAME OVER - press space",
			20,
			g_mem.screen_height / 2 - 12,
			20,
			rl.BLACK,
		)
	}
	rl.EndDrawing()

	return !rl.WindowShouldClose()
}

@(export)
game_shutdown :: proc() {
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)
}

// Lets the running game manually force a reload (e.g. bound to a key) in
// case the host's file-watch ever misses a rebuild.
@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}
