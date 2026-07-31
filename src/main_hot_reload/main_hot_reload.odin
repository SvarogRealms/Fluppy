package main

// Dev host: loads game.dll, runs the game loop through function pointers,
// and reloads the dll whenever it notices a newer one on disk - without
// closing the raylib window or losing game state. Rebuild game.dll (task
// "build game (hot reload)") while this exe is running to see the change.

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

Game_API :: struct {
	lib:               dynlib.Library,
	init_window:       proc(),
	init:              proc(),
	update:            proc() -> bool,
	shutdown:          proc(),
	shutdown_window:   proc(),
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	hot_reloaded:      proc(mem: rawptr),
	force_reload:      proc() -> bool,
	modification_time: time.Time,
	api_version:       int,
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_err := os.last_write_time_by_name("game.dll")
	if mod_time_err != nil {
		fmt.println("Could not get last write time of game.dll:", mod_time_err)
		return
	}

	// Windows keeps a loaded dll file locked, so the compiler couldn't
	// overwrite game.dll while we still had it open. Load a numbered copy
	// instead and leave the real game.dll free to be rebuilt at any time.
	dll_name := fmt.tprintf("game_{0}.dll", api_version)
	if !copy_dll(dll_name) {
		return
	}

	_, ok = dynlib.initialize_symbols(&api, dll_name, "game_", "lib")
	if !ok {
		fmt.println("Failed initializing symbols:", dynlib.last_error())
		return
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true
	return
}

copy_dll :: proc(to: string) -> bool {
	data, read_err := os.read_entire_file_from_path("game.dll", context.temp_allocator)
	if read_err != nil {
		fmt.println("Could not read game.dll:", read_err)
		return false
	}
	defer delete(data, context.temp_allocator)

	write_err := os.write_entire_file_from_bytes(to, data)
	if write_err != nil {
		fmt.println("Could not write", to, ":", write_err)
		return false
	}

	return true
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}

	remove_err := os.remove(fmt.tprintf("game_{0}.dll", api.api_version))
	if remove_err != nil {
		fmt.println("Failed to remove copied dll:", remove_err)
	}
}

main :: proc() {
	api_version := 0
	game_api, api_ok := load_game_api(api_version)
	if !api_ok {
		fmt.println("Failed to load game API from game.dll")
		return
	}
	api_version += 1

	game_api.init_window()
	game_api.init()

	for game_api.update() {
		mod_time, mod_time_err := os.last_write_time_by_name("game.dll")
		needs_reload :=
			game_api.force_reload() ||
			(mod_time_err == nil && mod_time != game_api.modification_time)
		if !needs_reload {
			continue
		}

		new_api, new_ok := load_game_api(api_version)
		if !new_ok {
			// Likely mid-write from the compiler; try again next frame.
			continue
		}

		game_memory := game_api.memory()
		same_shape := new_api.memory_size() == game_api.memory_size()

		if same_shape {
			new_api.hot_reloaded(game_memory)
		} else {
			fmt.println("Game_Memory layout changed size, restarting game state")
			game_api.shutdown() // free the old memory before it's replaced
			new_api.init()
		}

		unload_game_api(&game_api)
		game_api = new_api
		api_version += 1
	}

	game_api.shutdown()
	game_api.shutdown_window()
	unload_game_api(&game_api)
}
