package main

import hm "core:container/handle_map"
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

	handle, err := hm.add(&entidades, entidade)
	if err != false {
		return EntidadeID{}, false
	}

	if e, found := hm.get(&entidades, handle); found {
		e.handle = handle
	}

	return handle, true
}

entidade_free :: proc(id: EntidadeID) -> (ok: bool) {
	entidade := hm.get(&entidades, id) or_return

	rl.UnloadTexture(entidade.sprite)

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

entidade_update :: proc(entidade: ^Entidade) {
	if entidade.segurado {
		entidade.posicao = rl.GetMousePosition() + entidade.offset_mouse
	}

	entidade.colisor_mouse.x = entidade.posicao.x - TAMANHO_COLISOR / 2
	entidade.colisor_mouse.y = entidade.posicao.y - TAMANHO_COLISOR / 2
}

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

entidades_renderizar :: proc() {
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		tamanho := rl.Vector2 {
			f32(entidade.sprite.width) * ESCALA_ENTIDADE,
			f32(entidade.sprite.height) * ESCALA_ENTIDADE,
		}
		rl.DrawTextureEx(entidade.sprite, entidade.posicao - tamanho / 2, 0.0, ESCALA_ENTIDADE, rl.WHITE)

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
