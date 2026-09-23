package main

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

UsuarioID :: EntidadeID

proximo_usuario_id: u32

Mensagem :: struct {
	id:       u32,
	origem:   EntidadeID,
	destino:  EntidadeID,
	conteudo: string,
}

Usuario :: struct {
	alocador:  runtime.Allocator,
	nome:      string,
	saida:     [dynamic]Mensagem,
	entrada:   [dynamic]Pacote,
	recebidas: [dynamic]Mensagem,
}

usuario_new :: proc(alocador := context.allocator) -> (usuario: Usuario) {
	usuario.alocador = alocador
	proximo_usuario_id += 1
	usuario.nome = fmt.aprintf("Usuário %v", proximo_usuario_id)
	usuario.saida = make([dynamic]Mensagem, usuario.alocador)
	usuario.entrada = make([dynamic]Pacote, usuario.alocador)
	usuario.recebidas = make([dynamic]Mensagem, usuario.alocador)
	return usuario
}

usuario_free :: proc(usuario: ^Usuario) {
	delete(usuario.nome)

	for mensagem in usuario.saida {
		delete(mensagem.conteudo)
	}
	delete(usuario.saida)

	for i in 0 ..< len(usuario.entrada) {
		pacote_free(&usuario.entrada[i])
	}
	delete(usuario.entrada)

	for mensagem in usuario.recebidas {
		delete(mensagem.conteudo)
	}
	delete(usuario.recebidas)
}

usuario_enviar :: proc(usuario: ^Usuario, mensagem: Mensagem) -> (ok: bool) {
	vizinhos := conexoes_entidade(mensagem.origem, context.temp_allocator)
	if len(vizinhos) == 0 {
		return false
	}

	runes := utf8.string_to_runes(mensagem.conteudo, context.temp_allocator)
	total := (len(runes) + RUNES_POR_PACOTE - 1) / RUNES_POR_PACOTE
	if total == 0 {
		total = 1
	}

	cor := cor_para_mensagem(mensagem.id)

	for indice in 0 ..< total {
		inicio := indice * RUNES_POR_PACOTE
		fim := inicio + RUNES_POR_PACOTE
		if fim > len(runes) {
			fim = len(runes)
		}

		base := Pacote {
			origem      = mensagem.origem,
			destino     = mensagem.destino,
			mensagem_id = mensagem.id,
			indice      = indice,
			total       = total,
			bytes       = runes[inicio:fim],
			cor         = cor,
		}

		for vizinho in vizinhos {
			pacote := pacote_clone(base, usuario.alocador)
			pacote_enviar(&pacote, mensagem.origem, vizinho)
		}
	}
	return true
}

usuario_receber :: proc(usuario: ^Usuario, pacote: Pacote) {
	for mensagem in usuario.recebidas {
		if mensagem.id == pacote.mensagem_id {
			return
		}
	}

	for fragmento in usuario.entrada {
		if fragmento.mensagem_id == pacote.mensagem_id && fragmento.indice == pacote.indice {
			return
		}
	}

	novo := pacote_clone(pacote, usuario.alocador)
	append(&usuario.entrada, novo)

	quantidade := 0
	for fragmento in usuario.entrada {
		if fragmento.mensagem_id == pacote.mensagem_id {
			quantidade += 1
		}
	}
	if quantidade < pacote.total {
		return
	}

	todos := make([dynamic]rune, 0, pacote.total * RUNES_POR_PACOTE, context.temp_allocator)
	for i in 0 ..< pacote.total {
		for fragmento in usuario.entrada {
			if fragmento.mensagem_id == pacote.mensagem_id && fragmento.indice == i {
				append(&todos, ..fragmento.bytes)
				break
			}
		}
	}

	mensagem := Mensagem {
		id       = pacote.mensagem_id,
		origem   = pacote.origem,
		destino  = pacote.destino,
		conteudo = utf8.runes_to_string(todos[:], usuario.alocador),
	}
	append(&usuario.recebidas, mensagem)

	notificar_mensagem_recebida(usuario.nome, mensagem.conteudo)

	usuario_remover_fragmentos(usuario, pacote.mensagem_id)
}

usuario_remover_fragmentos :: proc(usuario: ^Usuario, mensagem_id: u32) {
	i := 0
	for i < len(usuario.entrada) {
		if usuario.entrada[i].mensagem_id == mensagem_id {
			pacote_free(&usuario.entrada[i])
			unordered_remove(&usuario.entrada, i)
		} else {
			i += 1
		}
	}
}
