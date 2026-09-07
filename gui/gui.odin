package gui

import "core:fmt"
import rl "vendor:raylib"

render :: proc() {
	if rl.GuiButton({20, 20, 120, 30}, "Criar Usuário") {

	}
	if rl.GuiButton({20, 20 + (30 + 10), 120, 30}, "Criar Comutador") {

	}
	if rl.GuiButton({20, 20 + (30 + 10) * 2, 120, 30}, "Enviar Mensagem") {

	}
}
