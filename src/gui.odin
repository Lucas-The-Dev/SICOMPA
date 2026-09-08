package main

import "core:fmt"
import rl "vendor:raylib"

GuiWindow :: enum {
	Tutorial,
}

GuiWindows :: bit_set[GuiWindow]

flexbox_axis :: proc(offset, size, spacing: f32, num: int) -> f32 {
	return offset + (size + spacing) * f32(num)
}

gui_renderizar :: proc() {
	gui_topleft_buttons_render()

	gui_bottom_bar_render()
}

gui_topleft_buttons_render :: proc() {
	center := rl.Vector2{f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 0), 150, 30}, "Criar Usuário") {
		entidade_new(usuario_new(), center, sprites[.Usuario])
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 1), 150, 30}, "Criar Comutador") {
		entidade_new(comutador_new(), center, sprites[.Comutador])
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
