package main

import rl "vendor:raylib"

RUNES_POR_PACOTE :: 8

Pacote :: struct {
	origem:      EntidadeID,
	destino:     EntidadeID,
	mensagem_id: u32,
	indice:      int,
	total:       int,
	bytes:       []rune,
	historico:   [dynamic]EntidadeID,
	de:          EntidadeID,
	para:        EntidadeID,
	progresso:   f32,
	cor:         rl.Color,
}

pacote_free :: proc(pacote: ^Pacote) {
	delete(pacote.bytes)
	delete(pacote.historico)
	pacote^ = {}
}

pacote_clone :: proc(pacote: Pacote, alocador := context.allocator) -> Pacote {
	clone := pacote
	clone.bytes = make([]rune, len(pacote.bytes), alocador)
	copy(clone.bytes, pacote.bytes)
	clone.historico = make([dynamic]EntidadeID, 0, len(pacote.historico) + 1, alocador)
	for v in pacote.historico {
		append(&clone.historico, v)
	}
	return clone
}
