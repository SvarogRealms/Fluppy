package main

import "core:fmt"
import rl "vendor:raylib"

main :: proc() {
    // Initialize the window
    screen_width  : i32 = 800
    screen_height : i32 = 450
    rl.InitWindow(screen_width, screen_height, "Odin + Raylib Hello World")
    defer rl.CloseWindow() // Ensures the window closes when main exits

    rl.SetTargetFPS(60)
    rl.SetExitKey(.Q)

    // Game loop
    for !rl.WindowShouldClose() {
        // Update logic goes here

        // Draw logic
        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.RAYWHITE)
        rl.DrawText("Hello, World!", 190, 200, 20, rl.BLACK)
    }
}