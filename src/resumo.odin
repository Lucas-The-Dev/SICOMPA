package main

import hm "core:container/handle_map"
import "core:strings"
import rl "vendor:raylib"

ICONE_RESUMO_TAMANHO :: 14.0
LINHA_ALTURA :: 22.0

ResumoTipo :: enum {
	Enviada,
	Recebida,
}

ResumoLinha :: struct {
	tipo:        ResumoTipo,
	protocolo:   Protocolo,
	contraparte: EntidadeID,
	conteudo:    string,
}

modal_resumo_aberto: bool
resumo_usuario:      EntidadeID
resumo_scroll:       f32

// abrir_modal_resumo abre a tabela de mensagens do usuário `id`, zerando a rolagem.
//
// Parâmetros:
// - `id`: handle do usuário. Sem retorno.
abrir_modal_resumo :: proc(id: EntidadeID) {
	resumo_usuario = id
	resumo_scroll = 0
	modal_resumo_aberto = true
}

// icone_resumo_rect calcula o retângulo do ícone no canto superior-direito do
// sprite (16x16 * ESCALA_ENTIDADE, centro em `posicao`).
//
// Parâmetros:
// - `entidade`: entidade dona do ícone.
//
// Retorna: o retângulo clicável do ícone.
icone_resumo_rect :: proc(entidade: ^Entidade) -> rl.Rectangle {
	metade := f32(entidade.sprite.width) * ESCALA_ENTIDADE / 2
	return {
		entidade.posicao.x + metade - ICONE_RESUMO_TAMANHO,
		entidade.posicao.y - metade,
		ICONE_RESUMO_TAMANHO,
		ICONE_RESUMO_TAMANHO,
	}
}

// resumo_icone_renderizar desenha o ícone (apenas para Usuário), com destaque no hover.
//
// Parâmetros:
// - `entidade`: entidade dona do ícone. Sem retorno.
resumo_icone_renderizar :: proc(entidade: ^Entidade) {
	rect := icone_resumo_rect(entidade)
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	cor := hover ? rl.WHITE : rl.Color{200, 200, 200, 255}
	origem := rl.Rectangle{0, 0, f32(sprites[.Resumo].width), f32(sprites[.Resumo].height)}
	rl.DrawTexturePro(sprites[.Resumo], origem, rect, rl.Vector2{}, 0, cor)
}

// resumo_processar_clique abre o modal se o clique esquerdo atingiu o ícone de
// algum usuário. Retorna `true` nesse caso (para suprimir o arraste).
resumo_processar_clique :: proc() -> bool {
	mouse := rl.GetMousePosition()
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		if _, is_usuario := entidade.dados.(Usuario); !is_usuario {
			continue
		}
		if rl.CheckCollisionPointRec(mouse, icone_resumo_rect(entidade)) {
			abrir_modal_resumo(handle)
			return true
		}
	}
	return false
}

// gui_modal_resumo_render desenha a tabela de mensagens (enviadas + recebidas)
// do usuário selecionado, com rolagem pela roda do mouse. Sem retorno.
gui_modal_resumo_render :: proc() {
	if !modal_resumo_aberto {
		return
	}

	entidade, ok := hm.get(&entidades, resumo_usuario)
	if !ok {
		modal_resumo_aberto = false
		return
	}
	dados, is_usuario := entidade.dados.(Usuario)
	if !is_usuario {
		modal_resumo_aberto = false
		return
	}

	bounds := rl.Rectangle {
		x      = f32(rl.GetRenderWidth()) / 2 - 260,
		y      = f32(rl.GetRenderHeight()) / 2 - 180,
		width  = 520,
		height = 360,
	}
	rl.GuiWindowBox(bounds, "Mensagens do Usuário")
	rl.GuiLabel(
		{bounds.x + 20, bounds.y + 30, bounds.width - 40, 24},
		strings.clone_to_cstring(dados.nome),
	)

	linhas := make([dynamic]ResumoLinha, 0, 32, context.temp_allocator)
	for m in dados.enviadas {
		append(&linhas, ResumoLinha{.Enviada, m.protocolo, m.destino, m.conteudo})
	}
	for m in dados.recebidas {
		append(&linhas, ResumoLinha{.Recebida, m.protocolo, m.origem, m.conteudo})
	}

	area := rl.Rectangle {
		x      = bounds.x + 16,
		y      = bounds.y + 78,
		width  = bounds.width - 32,
		height = bounds.height - 140,
	}
	max_scroll := max(0, f32(len(linhas)) * LINHA_ALTURA - area.height + LINHA_ALTURA)
	resumo_scroll -= rl.GetMouseWheelMove() * LINHA_ALTURA * 2
	resumo_scroll = clamp(resumo_scroll, 0, max_scroll)

	rl.DrawRectangleRec(area, rl.Color{30, 30, 40, 255})
	rl.DrawRectangleLinesEx(area, 1, rl.GRAY)
	rl.DrawText("Tipo", i32(area.x) + 8, i32(area.y) - 22, 16, rl.RAYWHITE)
	rl.DrawText("Protocolo", i32(area.x) + 90, i32(area.y) - 22, 16, rl.RAYWHITE)
	rl.DrawText("Contraparte", i32(area.x) + 180, i32(area.y) - 22, 16, rl.RAYWHITE)
	rl.DrawText("Conteúdo", i32(area.x) + 320, i32(area.y) - 22, 16, rl.RAYWHITE)

	rl.BeginScissorMode(i32(area.x), i32(area.y), i32(area.width), i32(area.height))
	y := area.y - resumo_scroll
	for linha in linhas {
		if y + LINHA_ALTURA >= area.y && y <= area.y + area.height {
			if linha.tipo == .Enviada {
				rl.DrawText("Enviada", i32(area.x) + 8, i32(y) + 2, 16, rl.LIGHTGRAY)
			} else {
				rl.DrawText("Recebida", i32(area.x) + 8, i32(y) + 2, 16, rl.LIGHTGRAY)
			}
			rl.DrawText(
				strings.clone_to_cstring(nome_protocolo(linha.protocolo)),
				i32(area.x) + 90,
				i32(y) + 2,
				16,
				rl.LIGHTGRAY,
			)
			nome := nome_entidade(linha.contraparte)
			rl.DrawText(
				strings.clone_to_cstring(nome),
				i32(area.x) + 180,
				i32(y) + 2,
				16,
				rl.LIGHTGRAY,
			)
			rl.DrawText(
				strings.clone_to_cstring(linha.conteudo),
				i32(area.x) + 320,
				i32(y) + 2,
				16,
				rl.WHITE,
			)
		}
		y += LINHA_ALTURA
	}
	rl.EndScissorMode()

	if rl.GuiButton(
		{bounds.x + bounds.width - 110, bounds.y + bounds.height - 42, 90, 28},
		"Fechar",
	) {
		modal_resumo_aberto = false
	}
}
