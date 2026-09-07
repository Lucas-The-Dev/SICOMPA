package main

import "base:runtime"
import hm "core:container/handle_map"
import "core:fmt"
import "core:mem"
import rl "vendor:raylib"

import "gui"

fonts: [dynamic]rl.Font

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
		defer hm.dynamic_destroy(&entidades)
	}

	usuarios = make(map[UsuarioID]Usuario)
	comutadores = make(map[ComutadorID]Comutador)
	defer {
		delete(comutadores)
		delete(usuarios)
	}

	rl.InitWindow(1280, 720, "SICOMPA - Simulador de Comutação de Pacotes")
	defer rl.CloseWindow()

	fonts = make([dynamic]rl.Font)
	defer {
		for font in fonts {
			rl.UnloadFont(font)
		}
		delete(fonts)
	}

	append(&fonts, rl.LoadFont("fonts/roboto.ttf"))
	rl.GuiSetFont(fonts[0])

	rl.SetTargetFPS(180)
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.DARKGRAY)


		gui.render()

		rl.DrawFPS(2, rl.GetRenderHeight() - 18)
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}
}
