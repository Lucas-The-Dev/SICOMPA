package main

import hm "core:container/handle_map"
import "core:fmt"
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

entidades_selecionadas := EntidadesSelecionadas {
	quantidade   = 0,
	selecionadas = [2]EntidadeID{}
}

entidade_new :: proc(dados: Dados, posicao: rl.Vector2, sprite: rl.Texture2D) -> (EntidadeID, bool) {
	assert(dados != nil)
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
	if !err {
		entidade, _ := hm.get(&entidades, handle)
		entidade.handle = handle
	}
	
	return handle, err
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

	hm.remove(&entidades, id)
	return true
}

entidade_update :: proc(entidade: ^Entidade) {
	if entidade.segurado {
		entidade.posicao = rl.GetMousePosition() + entidade.offset_mouse
	}

	entidade.colisor_mouse.x = entidade.posicao.x
	entidade.colisor_mouse.y = entidade.posicao.y
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

entidades_selecionar :: proc(entidade: ^Entidade) {
	entidades_selecionadas.selecionadas[entidades_selecionadas.quantidade] = entidade.handle
	entidades_selecionadas.quantidade += 1

	if entidades_selecionadas.quantidade == 2 {
		fmt.println("Conectando %s a %s",entidades_selecionadas.selecionadas[0], entidades_selecionadas.selecionadas[1])
		criar_conexao(entidades_selecionadas.selecionadas[0], entidades_selecionadas.selecionadas[1])

		entidades_selecionadas.quantidade = 0
	}
}

entidades_atualizar :: proc() {
	it := hm.iterator_make(&entidades)
	holding_another := false

	for entidade, handle in hm.iterate(&it) {
		if !holding_another {
			entidade_arrastar(entidade, &holding_another)
		}

		entidade_update(entidade)
	}

	if rl.IsMouseButtonPressed(.RIGHT) {
		it := hm.iterator_make(&entidades)
		fmt.println("clicado")

		for entidade, _ in hm.iterate(&it) {
			if rl.CheckCollisionPointRec(rl.GetMousePosition(), entidade.colisor_mouse) {
				entidades_selecionar(entidade)
				break
			}
		}
	}
}

entidades_renderizar :: proc() {
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		// when ODIN_DEBUG {
		// 	rl.DrawRectangleRec(entidade.colisor_mouse, rl.RED)
		// }
		rl.DrawTextureEx(entidade.sprite, entidade.posicao, 0.0, 2.0, rl.WHITE)
	}
}
