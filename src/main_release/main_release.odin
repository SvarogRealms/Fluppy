package main

// Shipping build: the game package is linked in directly, no dll loading,
// no reload watching. This is what you'd actually ship to players.

import "../game"

main :: proc() {
	game.game_init_window()
	game.game_init()

	for game.game_update() {}

	game.game_shutdown()
	game.game_shutdown_window()
}
