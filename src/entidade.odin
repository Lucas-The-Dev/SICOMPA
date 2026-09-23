package main

import hm "core:container/handle_map"
import "core:strings"
import rl "vendor:raylib"

when ODIN_DEBUG {
	entidades: hm.Static_Handle_Map(1024, Entidade, EntidadeID)
} else {
	entidades: hm.Dynamic_Handle_Map(Entidade, EntidadeID)
}

EntidadeID :: hm.Handle32

Entidade :: struct {
	handle:        EntidadeID,
	dados:         Dados,
	sprite:        rl.Texture,
	posicao:       rl.Vector2,

	// Raio de Colisão com Mouse
	offset_mouse:  rl.Vector2,
	colisor_mouse: rl.Rectangle,
	segurado:      bool,
}

EntidadesSelecionadas :: struct {
	quantidade:   int,
	selecionadas: [2]EntidadeID
}

Dados :: union {
	Comutador,
	Usuario,
}

TAMANHO_COLISOR :: 32
ESCALA_ENTIDADE :: 2.0

entidades_selecionadas := EntidadesSelecionadas {
	quantidade   = 0,
	selecionadas = [2]EntidadeID{}
}

// entidade_new insere uma nova entidade no handle map global.
//
// Parâmetros:
// - `dados`: união `Comutador`/`Usuario` que define o tipo da entidade.
// - `posicao`: centro da entidade na tela.
// - `sprite`: textura compartilhada usada na renderização.
//
// Retorna:
// - `id`: handle da entidade criada.
// - `ok`: `true` se a inserção e a leitura do handle funcionaram.
entidade_new :: proc(dados: Dados, posicao: rl.Vector2, sprite: rl.Texture2D) -> (id: EntidadeID, ok: bool) {
	entidade := Entidade {
		sprite        = sprite,
		posicao       = posicao,
		dados         = dados,
		colisor_mouse = {
			posicao.x - TAMANHO_COLISOR / 2,
			posicao.y - TAMANHO_COLISOR / 2,
			TAMANHO_COLISOR,
			TAMANHO_COLISOR,
		},
	}

	handle, _ := hm.add(&entidades, entidade)

	if e, found := hm.get(&entidades, handle); found {
		e.handle = handle
		return handle, true
	}

	return EntidadeID{}, false
}

// entidade_free libera uma entidade e tudo que depende dela.
// Chama `usuario_free`/`comutador_free`, remove as conexões ligadas a ela e a
// retira do handle map. Não descarrega a textura, pois os sprites são globais.
//
// Parâmetros:
// - `id`: handle da entidade a remover.
//
// Retorna: `true` se a entidade existia e foi removida, `false` caso contrário.
entidade_free :: proc(id: EntidadeID) -> (ok: bool) {
	entidade := hm.get(&entidades, id) or_return

	// A textura é compartilhada (sprites globais), não deve ser descarregada aqui.

	switch &tipo in entidade.dados {
	case Comutador:
		comutador_free(&tipo)
	case Usuario:
		usuario_free(&tipo)
	}

	remover_conexoes(id)

	hm.remove(&entidades, id)
	return true
}

// entidades_limpar remove todas as entidades e conexões do estado atual.
// Ordem: limpa pacotes (`simulacao_limpar`), libera `dados` de cada entidade,
// remove-as do handle map, limpa as conexões e zera a seleção. Sem retorno.
entidades_limpar :: proc() {
	simulacao_limpar()

	para_remover := make([dynamic]EntidadeID, 0, 16, context.temp_allocator)
	it := hm.iterator_make(&entidades)
	for _, handle in hm.iterate(&it) {
		append(&para_remover, handle)
	}

	for id in para_remover {
		if entidade, ok := hm.get(&entidades, id); ok {
			switch &dados in entidade.dados {
			case Usuario:
				usuario_free(&dados)
			case Comutador:
				comutador_free(&dados)
			}
		}
		hm.remove(&entidades, id)
	}

	conexoes_limpar()

	entidades_selecionadas.quantidade = 0
}

// entidade_update recalcula posição (se arrastada) e o colisor de mouse.
//
// Parâmetros:
// - `entidade`: ponteiro para a entidade a atualizar. Sem retorno.
entidade_update :: proc(entidade: ^Entidade) {
	if entidade.segurado {
		entidade.posicao = rl.GetMousePosition() + entidade.offset_mouse
	}

	entidade.colisor_mouse.x = entidade.posicao.x - TAMANHO_COLISOR / 2
	entidade.colisor_mouse.y = entidade.posicao.y - TAMANHO_COLISOR / 2
}

// entidade_arrastar inicia o arraste sob o clique esquerdo e solta ao liberar.
//
// Parâmetros:
// - `entidade`: entidade candidata ao arraste.
// - `holding_another`: flag compartilhada que impede pegar mais de uma entidade
//   no mesmo frame; é marcada como `true` quando o arraste começa. Sem retorno.
entidade_arrastar :: proc(entidade: ^Entidade, holding_another: ^bool) {
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(rl.GetMousePosition(), entidade.colisor_mouse) {
			entidade.segurado = true
			entidade.offset_mouse = entidade.posicao - rl.GetMousePosition()
			holding_another^ = true
		}
	} else if rl.IsMouseButtonReleased(.LEFT) {
		entidade.segurado = false
	}
}

// entidades_selecionar acumula IDs na seleção (até 2) e, ao completar dois,
// tenta criar uma conexão entre eles e reinicia a seleção.
//
// Parâmetros:
// - `id`: handle da entidade selecionada. Sem retorno.
entidades_selecionar :: proc(id: EntidadeID) {
	entidades_selecionadas.selecionadas[entidades_selecionadas.quantidade] = id
	entidades_selecionadas.quantidade += 1

	if entidades_selecionadas.quantidade == 2 {
		criar_conexao(
			entidades_selecionadas.selecionadas[0],
			entidades_selecionadas.selecionadas[1],
		)
		entidades_selecionadas.quantidade = 0
	}
}

// entidades_atualizar percorre as entidades aplicando arraste/update e, ao fim,
// trata o clique direito (`entidades_processar_click_direito`). Sem retorno.
entidades_atualizar :: proc() {
	it := hm.iterator_make(&entidades)
	holding_another := false

	for entidade, _ in hm.iterate(&it) {
		if !holding_another {
			entidade_arrastar(entidade, &holding_another)
		}

		entidade_update(entidade)
	}

	if rl.IsMouseButtonPressed(.RIGHT) {
		entidades_processar_click_direito()
	}
}

// entidades_processar_click_direito trata o clique direito do mouse:
// entidade → selecionar; conexão com seleção pendente → avisar; conexão → apagar;
// área vazia → cancelar a seleção. Sem retorno.
entidades_processar_click_direito :: proc() {
	mouse := rl.GetMousePosition()

	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		if rl.CheckCollisionPointRec(mouse, entidade.colisor_mouse) {
			entidades_selecionar(handle)
			return
		}
	}

	if conexao, ok := conexao_sob_mouse(); ok {
		if entidades_selecionadas.quantidade > 0 {
			mostrar_mensagem("Modo de seleção ativo: clique no vazio para cancelar antes de apagar.")
		} else {
			deletar_conexao(conexao)
		}
		return
	}

	entidades_selecionadas.quantidade = 0
}

// entidades_renderizar desenha cada sprite (com `ESCALA_ENTIDADE`), seu rótulo
// e um destaque amarelo na primeira entidade selecionada. Sem retorno.
entidades_renderizar :: proc() {
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		tamanho := rl.Vector2 {
			f32(entidade.sprite.width) * ESCALA_ENTIDADE,
			f32(entidade.sprite.height) * ESCALA_ENTIDADE,
		}
		rl.DrawTextureEx(entidade.sprite, entidade.posicao - tamanho / 2, 0.0, ESCALA_ENTIDADE, rl.WHITE)

		entidade_rotulo_renderizar(entidade)

		if entidades_selecionadas.quantidade == 1 &&
		   entidades_selecionadas.selecionadas[0] == handle {
			rl.DrawCircleLines(
				i32(entidade.posicao.x),
				i32(entidade.posicao.y),
				f32(TAMANHO_COLISOR),
				rl.YELLOW,
			)
		}
	}
}

// entidade_rotulo_renderizar desenha o nome abaixo do sprite (apenas Usuário).
//
// Parâmetros:
// - `entidade`: entidade cujo rótulo será desenhado. Sem retorno.
entidade_rotulo_renderizar :: proc(entidade: ^Entidade) {
	switch &dados in entidade.dados {
	case Usuario:
		cstr := strings.clone_to_cstring(dados.nome, context.temp_allocator)
		tamanho: i32 = 16
		largura := rl.MeasureText(cstr, tamanho)
		rl.DrawText(
			cstr,
			i32(entidade.posicao.x) - largura / 2,
			i32(entidade.posicao.y) + TAMANHO_COLISOR / 2 + 4,
			tamanho,
			rl.RAYWHITE,
		)
	case Comutador:
	}
}
