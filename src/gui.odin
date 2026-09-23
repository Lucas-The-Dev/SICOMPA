package main

import hm "core:container/handle_map"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

GuiWindow :: enum {
	Tutorial,
}

GuiWindows :: bit_set[GuiWindow]

flexbox_axis :: proc(offset, size, spacing: f32, num: int) -> f32 {
	return offset + (size + spacing) * f32(num)
}

MENSAGEM_DURACAO :: 2.5
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

modal_mensagem_aberto: bool
mensagem_conteudo: [256]u8
mensagem_origem:   i32
mensagem_destino:  i32
mensagem_origem_edit:  bool
mensagem_destino_edit: bool

construir_lista_usuarios :: proc() -> (ids: []EntidadeID, texto: cstring, quantidade: int) {
	lista := make([dynamic]EntidadeID, 0, 8, context.temp_allocator)
	b := strings.builder_make_len_cap(0, 128, context.temp_allocator)

	indice := 0
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			append(&lista, handle)
			if indice > 0 {
				fmt.sbprintf(&b, ";")
			}
			fmt.sbprintf(&b, "%s", dados.nome)
			indice += 1
		case Comutador:
		}
	}

	ids = lista[:]
	texto = strings.to_cstring(&b)
	quantidade = len(lista)
	return
}

gui_modal_adicionar :: proc(ids: []EntidadeID) {
	if len(ids) == 0 {
		mostrar_mensagem("Crie ao menos um usuário.")
		return
	}
	if int(mensagem_origem) >= len(ids) || int(mensagem_destino) >= len(ids) {
		mostrar_mensagem("Selecione origem e destino.")
		return
	}
	origem := ids[int(mensagem_origem)]
	destino := ids[int(mensagem_destino)]
	if origem == destino {
		mostrar_mensagem("Origem e destino devem ser diferentes.")
		return
	}

	texto := string(cstring(&mensagem_conteudo[0]))
	if len(texto) == 0 {
		mostrar_mensagem("Digite o conteúdo da mensagem.")
		return
	}

	entidade, ok := hm.get(&entidades, origem)
	if !ok {
		return
	}
	switch &dados in entidade.dados {
	case Usuario:
		mensagem := Mensagem {
			id       = proximo_mensagem_id,
			origem   = origem,
			destino  = destino,
			conteudo = strings.clone(texto, dados.alocador),
		}
		proximo_mensagem_id += 1
		append(&dados.saida, mensagem)
		mostrar_mensagem("Mensagem adicionada à simulação.")
	case Comutador:
	}
}

gui_modal_mensagem_render :: proc() {
	if !modal_mensagem_aberto {
		return
	}

	bounds := rl.Rectangle {
		x      = f32(rl.GetRenderWidth()) / 2 - 220,
		y      = f32(rl.GetRenderHeight()) / 2 - 170,
		width  = 440,
		height = 340,
	}
	rl.GuiWindowBox(bounds, "Nova Mensagem")

	ids, lista_texto, quantidade := construir_lista_usuarios()

	if int(mensagem_origem) >= quantidade {
		mensagem_origem = 0
	}
	if int(mensagem_destino) >= quantidade {
		mensagem_destino = 0
	}

	dropdown_aberto := mensagem_origem_edit || mensagem_destino_edit

	origem_bounds := rl.Rectangle{bounds.x + 100, bounds.y + 40, 300, 24}
	destino_bounds := rl.Rectangle{bounds.x + 100, bounds.y + 80, 300, 24}

	rl.GuiLabel({bounds.x + 20, bounds.y + 40, 60, 24}, "Origem")
	rl.GuiLabel({bounds.x + 20, bounds.y + 80, 60, 24}, "Destino")
	rl.GuiLabel({bounds.x + 20, bounds.y + 120, 80, 24}, "Conteúdo")

	rl.GuiTextBox({bounds.x + 100, bounds.y + 120, 300, 24}, cstring(&mensagem_conteudo[0]), len(mensagem_conteudo), !dropdown_aberto)

	adicionar := rl.GuiButton({bounds.x + bounds.width - 250, bounds.y + bounds.height - 40, 110, 30}, "Adicionar")
	cancelar := rl.GuiButton({bounds.x + bounds.width - 130, bounds.y + bounds.height - 40, 110, 30}, "Cancelar")

	if adicionar && !dropdown_aberto {
		gui_modal_adicionar(ids)
		modal_mensagem_aberto = false
	}
	if cancelar && !dropdown_aberto {
		modal_mensagem_aberto = false
	}

	if mensagem_origem_edit {
		rl.GuiDropdownBox(destino_bounds, lista_texto, &mensagem_destino, false)
		if rl.GuiDropdownBox(origem_bounds, lista_texto, &mensagem_origem, true) {
			mensagem_origem_edit = false
		}
	} else if mensagem_destino_edit {
		rl.GuiDropdownBox(origem_bounds, lista_texto, &mensagem_origem, false)
		if rl.GuiDropdownBox(destino_bounds, lista_texto, &mensagem_destino, true) {
			mensagem_destino_edit = false
		}
	} else {
		if rl.GuiDropdownBox(origem_bounds, lista_texto, &mensagem_origem, false) {
			mensagem_origem_edit = true
			mensagem_destino_edit = false
		}
		if rl.GuiDropdownBox(destino_bounds, lista_texto, &mensagem_destino, false) {
			mensagem_destino_edit = true
			mensagem_origem_edit = false
		}
	}
}

gui_renderizar :: proc() {
	gui_topleft_buttons_render()

	gui_bottom_bar_render()

	gui_mensagem_render()

	gui_modal_mensagem_render()

	notificacoes_renderizar()
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
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 2), 150, 30}, "Nova Mensagem") {
		modal_mensagem_aberto = true
		mensagem_conteudo[0] = 0
		mensagem_origem_edit = false
		mensagem_destino_edit = false
	}
}

gui_bottom_bar_render :: proc() {
	rect := rl.Rectangle {
		x      = f32(rl.GetScreenWidth()) / 2 - 250,
		y      = f32(rl.GetScreenHeight()) - 70,
		width  = 500,
		height = 50,
	}
	rl.GuiPanel(rect, "")

	rotulo := "Pausado"
	if simulacao_ativa {
		rotulo = "Rodando"
	}
	rl.GuiLabel({rect.x + 20, rect.y + 15, 90, 24}, strings.clone_to_cstring(rotulo))

	texto_botao := "Iniciar"
	if simulacao_ativa {
		texto_botao = "Pausar"
	}
	if rl.GuiButton({rect.x + 120, rect.y + 10, 120, 30}, strings.clone_to_cstring(texto_botao)) {
		if simulacao_ativa {
			simulacao_ativa = false
		} else {
			simulacao_iniciar()
		}
	}
	if rl.GuiButton({rect.x + 250, rect.y + 10, 120, 30}, "Limpar") {
		simulacao_limpar()
	}
}
