package main

import "base:runtime"
import hm "core:container/handle_map"
import "core:fmt"
import "core:mem"
import rl "vendor:raylib"

sprites := [EntitySprite]rl.Texture2D {
	.Usuario   = rl.Texture2D{},
	.Comutador = rl.Texture2D{},
}

EntitySprite :: enum {
	Usuario,
	Comutador,
}

main :: proc() {
	// Alocador Rastreador para ver vazamentos de memória.
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// Usar Dynamic_Handle_Map para a versão final.
	when !ODIN_DEBUG {
		hm.dynamic_init(&entidades, context.allocator)
		hm.dynamic_init(&conexoes, context.allocator)
		defer {
			hm.dynamic_destroy(&conexoes)
			hm.dynamic_destroy(&entidades)
		}
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI})
	rl.InitWindow(1280, 720, "SICOMPA - Simulador de Comutação de Pacotes")
	defer rl.CloseWindow()

	// sprites := [EntitySprite]rl.Texture2D {
	// 	.Usuario   = rl.LoadTexture("sprites/icon_map.png"),
	// 	.Comutador = rl.LoadTexture("sprites/icon_tower.png"),
	// }

	sprites[.Usuario] = rl.LoadTexture("sprites/icon_map.png")
	sprites[.Comutador] = rl.LoadTexture("sprites/icon_tower.png")
	defer {
		for sprite in sprites {
			rl.UnloadTexture(sprite)
		}
	}

	rl.EnableEventWaiting()

	rl.SetTargetFPS(180)
	for !rl.WindowShouldClose() {
		entidades_atualizar()

		rl.BeginDrawing()
		rl.ClearBackground(rl.DARKGRAY)

		entidades_renderizar()

		gui_renderizar()

		when ODIN_DEBUG {
			rl.DrawFPS(2, rl.GetRenderHeight() - 18)
		}
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}
}
