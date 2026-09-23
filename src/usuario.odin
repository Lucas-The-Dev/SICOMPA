package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

UsuarioID :: EntidadeID

proximo_usuario_id: u32

DELAY_ENTRE_PACOTES :: 0.8

Mensagem :: struct {
	id:        u32,
	origem:    EntidadeID,
	destino:   EntidadeID,
	conteudo:  string,
	protocolo: Protocolo,
}

EnvioPendente :: struct {
	mensagem: Mensagem,
	runes:    []rune,
	total:    int,
	indice:   int,
	timer:    f32,
}

Usuario :: struct {
	alocador:      runtime.Allocator,
	nome:          string,
	ip:            Ip,
	saida:         [dynamic]Mensagem,
	enviadas:      [dynamic]Mensagem,
	entrada:       [dynamic]Pacote,
	recebidas:     [dynamic]Mensagem,
	envio:         EnvioPendente,
	envio_ativo:   bool,
	tcp_envio:     TcpEnvio,
	tcp_recebidas: [dynamic]RecebimentoTCP,
}

// usuario_new cria um usuário com nome automático ("Usuário N") e listas vazias.
//
// Parâmetros:
// - `nome`: nome personalizado; vazio usa o automático "Usuário N".
// - `ip`: endereço IPv4; `Ip{}` escolhe o próximo livre da faixa automática.
// - `alocador`: alocador usado para nome e listas dinâmicas.
//
// Retorna: o `Usuario` inicializado (incrementa `proximo_usuario_id`).
usuario_new :: proc(nome := "", ip := IP_VAZIO, alocador := context.allocator) -> (usuario: Usuario) {
	usuario.alocador = alocador
	proximo_usuario_id += 1
	if len(nome) > 0 {
		usuario.nome = strings.clone(nome, alocador)
	} else {
		usuario.nome = fmt.aprintf("Usuário %v", proximo_usuario_id)
	}

	usuario.ip = ip
	if ip == IP_VAZIO {
		usuario.ip = ip_sugerido()
	}
	usuario.saida = make([dynamic]Mensagem, usuario.alocador)
	usuario.enviadas = make([dynamic]Mensagem, usuario.alocador)
	usuario.entrada = make([dynamic]Pacote, usuario.alocador)
	usuario.recebidas = make([dynamic]Mensagem, usuario.alocador)
	usuario.tcp_recebidas = make([dynamic]RecebimentoTCP, usuario.alocador)
	return usuario
}

// usuario_free libera nome, conteúdos das mensagens, pacotes de entrada e as
// listas dinâmicas do usuário.
//
// Parâmetros:
// - `usuario`: ponteiro para o usuário a destruir. Sem retorno.
usuario_free :: proc(usuario: ^Usuario) {
	delete(usuario.nome)

	for mensagem in usuario.saida {
		delete(mensagem.conteudo)
	}
	delete(usuario.saida)

	for mensagem in usuario.enviadas {
		delete(mensagem.conteudo)
	}
	delete(usuario.enviadas)

	for i in 0 ..< len(usuario.entrada) {
		pacote_free(&usuario.entrada[i])
	}
	delete(usuario.entrada)

	for mensagem in usuario.recebidas {
		delete(mensagem.conteudo)
	}
	delete(usuario.recebidas)

	if usuario.envio_ativo {
		delete(usuario.envio.runes)
		delete(usuario.envio.mensagem.conteudo)
	}

	tcp_limpar(usuario)
	delete(usuario.tcp_recebidas)
}

// usuario_enviar_fragmento envia UM fragmento (de índice `indice`) da mensagem
// ativa a todos os vizinhos da origem.
//
// Parâmetros:
// - `usuario`: usuário de origem (define o alocador dos clones).
// - `indice`: índice do fragmento a enviar.
//
// Retorna: `false` se a origem não tem vizinhos; `true` caso os pacotes sejam lançados.
usuario_enviar_fragmento :: proc(usuario: ^Usuario, indice: int) -> (ok: bool) {
	mensagem := usuario.envio.mensagem
	vizinhos := conexoes_entidade(mensagem.origem, context.temp_allocator)
	if len(vizinhos) == 0 {
		return false
	}

	inicio := indice * RUNES_POR_PACOTE
	fim := min(inicio + RUNES_POR_PACOTE, len(usuario.envio.runes))

	base := Pacote {
		origem      = mensagem.origem,
		destino     = mensagem.destino,
		ip_origem   = ip_entidade(mensagem.origem),
		ip_destino  = ip_entidade(mensagem.destino),
		protocolo   = mensagem.protocolo,
		ttl         = TTL_PADRAO,
		mensagem_id = mensagem.id,
		indice      = indice,
		total       = usuario.envio.total,
		bytes       = usuario.envio.runes[inicio:fim],
		cor         = cor_para_mensagem(mensagem.id),
	}

	for vizinho in vizinhos {
		pacote := pacote_clone(base, usuario.alocador)
		pacote_enviar(&pacote, mensagem.origem, vizinho)
	}
	return true
}

// usuario_atualizar_envio avança o envio ativo (UDP fragmentado ou conexão TCP)
// e inicia a próxima mensagem de `saida`.
//
// Parâmetros:
// - `usuario`: usuário dono da fila de envio.
// - `id`: handle do usuário.
// - `dt`: tempo decorrido desde o último frame. Sem retorno.
usuario_atualizar_envio :: proc(usuario: ^Usuario, id: EntidadeID, dt: f32) {
	if usuario.tcp_envio.ativo {
		tcp_atualizar(usuario, id, dt)
		return
	}

	if !usuario.envio_ativo {
		if len(usuario.saida) == 0 {
			return
		}
		mensagem := usuario.saida[0]
		ordered_remove(&usuario.saida, 0)

		if mensagem.protocolo == .TCP {
			tcp_iniciar(usuario, id, mensagem)
			return
		}

		runes := utf8.string_to_runes(mensagem.conteudo, usuario.alocador)
		total := (len(runes) + RUNES_POR_PACOTE - 1) / RUNES_POR_PACOTE
		if total == 0 {
			total = 1
		}

		usuario.envio = EnvioPendente {
			mensagem = mensagem,
			runes    = runes,
			total    = total,
		}
		usuario.envio_ativo = true
	}

	if len(conexoes_entidade(usuario.envio.mensagem.origem, context.temp_allocator)) == 0 {
		mostrar_mensagem("Usuário de origem sem conexões; mensagem descartada.")
		delete(usuario.envio.runes)
		delete(usuario.envio.mensagem.conteudo)
		usuario.envio = {}
		usuario.envio_ativo = false
		return
	}

	usuario.envio.timer -= dt
	if usuario.envio.timer > 0 {
		return
	}

	usuario_enviar_fragmento(usuario, usuario.envio.indice)
	usuario.envio.indice += 1

	if usuario.envio.indice >= usuario.envio.total {
		delete(usuario.envio.runes)
		delete(usuario.envio.mensagem.conteudo)
		usuario.envio = {}
		usuario.envio_ativo = false
		return
	}
	usuario.envio.timer = DELAY_ENTRE_PACOTES
}

// usuario_receber acumula fragmentos de uma mensagem com dedupe por
// `(mensagem_id, indice)`. Ao completar `total` fragmentos, remonta a string,
// move a mensagem para `recebidas`, notifica e descarta os fragmentos.
//
// Parâmetros:
// - `usuario`: usuário destinatário.
// - `pacote`: fragmento recebido. Sem retorno.
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
		id        = pacote.mensagem_id,
		origem    = pacote.origem,
		destino   = pacote.destino,
		conteudo  = utf8.runes_to_string(todos[:], usuario.alocador),
		protocolo = pacote.protocolo,
	}
	append(&usuario.recebidas, mensagem)

	notificar_mensagem_recebida(usuario.nome, mensagem.conteudo, mensagem.protocolo)

	usuario_remover_fragmentos(usuario, pacote.mensagem_id)
}

// usuario_remover_fragmentos remove de `entrada` todos os fragmentos da
// mensagem `mensagem_id`, liberando-os.
//
// Parâmetros:
// - `usuario`: usuário dono da lista de entrada.
// - `mensagem_id`: id da mensagem cujos fragmentos serão descartados. Sem retorno.
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
