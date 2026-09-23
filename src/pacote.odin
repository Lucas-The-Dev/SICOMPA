package main

import rl "vendor:raylib"

RUNES_POR_PACOTE :: 8

Pacote :: struct {
	origem:      EntidadeID,
	destino:     EntidadeID,
	ip_origem:   Ip,
	ip_destino:  Ip,
	protocolo:   Protocolo,
	ttl:         u8,
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

// pacote_free libera os buffers de `bytes` e `historico` e zera o pacote.
//
// Parâmetros:
// - `pacote`: ponteiro para o pacote a liberar. Sem retorno.
pacote_free :: proc(pacote: ^Pacote) {
	delete(pacote.bytes)
	delete(pacote.historico)
	pacote^ = {}
}

// pacote_clone faz uma cópia profunda do pacote (novos buffers de `bytes` e
// `historico`), necessária ao flooding para ramificar o envio.
//
// Parâmetros:
// - `pacote`: pacote original.
// - `alocador`: alocador dos novos buffers.
//
// Retorna: um `Pacote` independente do original.
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
