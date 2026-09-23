package main

import rl "vendor:raylib"

RUNES_POR_PACOTE :: 8

FlagTCP :: enum {
	SYN,
	ACK,
	FIN,
}

FlagsTCP :: bit_set[FlagTCP; u8]

Pacote :: struct {
	origem:      EntidadeID,
	destino:     EntidadeID,
	ip_origem:   Ip,
	ip_destino:  Ip,
	protocolo:   Protocolo,
	ttl:         u8,
	seq:         u32,
	ack:         u32,
	flags:       FlagsTCP,
	janela:      u16,
	mensagem_id: u32,
	indice:      int,
	total:       int,
	bytes:       []rune,
	historico:   [dynamic]EntidadeID,
	rota:        [dynamic]EntidadeID,
	rota_indice: int,
	usar_rota:   bool,
	de:          EntidadeID,
	para:        EntidadeID,
	progresso:   f32,
	cor:         rl.Color,
}

// pacote_free libera os buffers de `bytes`, `historico` e `rota` e zera o pacote.
//
// Parâmetros:
// - `pacote`: ponteiro para o pacote a liberar. Sem retorno.
pacote_free :: proc(pacote: ^Pacote) {
	delete(pacote.bytes)
	delete(pacote.historico)
	delete(pacote.rota)
	pacote^ = {}
}

// pacote_clone faz uma cópia profunda do pacote (novos buffers de `bytes`,
// `historico` e `rota`), necessária ao flooding para ramificar o envio.
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
	clone.rota = make([dynamic]EntidadeID, 0, len(pacote.rota) + 1, alocador)
	for v in pacote.rota {
		append(&clone.rota, v)
	}
	return clone
}
