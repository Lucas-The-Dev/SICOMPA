package main

import "core:strings"
import rl "vendor:raylib"

GuiWindow :: enum {
	Tutorial,
}

GuiWindows :: bit_set[GuiWindow]

flexbox_axis :: proc(offset, size, spacing: f32, num: int) -> f32 {
	return offset + (size + spacing) * f32(num)
}

MENSAGEM_DURACAO :: 0.5
mensagem_texto: [256]u8
mensagem_len:   int
mensagem_timer: f32

mostrar_mensagem :: proc(texto: string) {
	n := len(texto)
	if n > len(mensagem_texto) {
		n = len(mensagem_texto)
	}
	for i in 0 ..< n {
		mensagem_texto[i] = texto[i]
	}
	mensagem_len = n
	mensagem_timer = MENSAGEM_DURACAO
}

gui_mensagem_render :: proc() {
	if mensagem_timer <= 0 {
		return
	}
	mensagem_timer -= rl.GetFrameTime()

	texto := string(mensagem_texto[:mensagem_len])
	cstr := strings.clone_to_cstring(texto, context.temp_allocator)
	tamanho: i32 = 20
	largura := rl.MeasureText(cstr, tamanho)
	padding: i32 = 12
	rect := rl.Rectangle {
		x      = (f32(rl.GetScreenWidth()) - f32(largura)) / 2 - f32(padding),
		y      = f32(rl.GetScreenHeight()) - 160,
		width  = f32(largura + padding * 2),
		height = f32(tamanho + padding),
	}
	rl.DrawRectangleRec(rect, rl.Color{0, 0, 0, 200})
	rl.DrawText(cstr, i32(rect.x) + padding, i32(rect.y) + padding / 2, tamanho, rl.RED)
}

gui_renderizar :: proc() {
	gui_topleft_buttons_render()

	gui_bottom_bar_render()

	gui_mensagem_render()
}

gui_topleft_buttons_render :: proc() {
	center := rl.Vector2{f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 0), 150, 30}, "Criar Usuário") {
		if _, ok := entidade_new(usuario_new(), center, sprites[.Usuario]); !ok {
			mostrar_mensagem("Falha ao criar usuário.")
		}
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 1), 150, 30}, "Criar Comutador") {
		if _, ok := entidade_new(comutador_new(), center, sprites[.Comutador]); !ok {
			mostrar_mensagem("Falha ao criar comutador.")
		}
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 2), 150, 30}, "Enviar Mensagem") {

	}
}

gui_bottom_bar_render :: proc() {
	rect: rl.Rectangle
	rect.width = 450
	rect.height = 100
	rect.x = (f32(rl.GetScreenWidth()) - rect.width) / 2
	rect.y = f32(rl.GetScreenHeight()) - rect.height - 20
	rl.DrawRectangleRec(rect, rl.GREEN)
	// if rl.GuiPanel()
}
