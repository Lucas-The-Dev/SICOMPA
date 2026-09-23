package main

import hm "core:container/handle_map"
import "core:fmt"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Parâmetros ajustáveis pela GUI.
TCP_JANELA :: 1
tcp_rto: f32 = 1.0
tcp_max_tentativas: int = 5

EstadoTCP :: enum {
	FECHADO,
	SYN_ENVIADO,
	ESTABELECIDO,
	FIN_ENVIADO,
}

TcpEnvio :: struct {
	ativo:      bool,
	estado:     EstadoTCP,
	destino:    EntidadeID,
	mensagem:   Mensagem,
	runes:      []rune,
	total:      int,
	base:       int,                 // seq aguardando ACK (janela = 1)
	rota_ida:   [dynamic]EntidadeID, // origem -> destino
	rto:        f32,
	tentativas: int,
	cor:        rl.Color,
}

RecebimentoTCP :: struct {
	ativo:       bool,
	origem:      EntidadeID,
	destino:     EntidadeID,
	mensagem_id: u32,
	proximo_seq: int,
	runes:       [dynamic]rune,       // acumulado em ordem
	rota_volta:  [dynamic]EntidadeID, // destino -> origem
	rota_pronta: bool,
	cor:         rl.Color,
}

// tcp_definir_rota preenche `dest` com a rota de volta até `p.origem`,
// invertendo o histórico do flooding. Serve tanto ao emissor (rota_ida, a
// partir do SYN-ACK) quanto ao receptor (rota_volta, a partir do ACK).
//
// Parâmetros:
// - `dest`: rota a preencher (lista de saltos, sem o nó atual).
// - `p`: pacote inundado cujo caminho será invertido. Sem retorno.
tcp_definir_rota :: proc(dest: ^[dynamic]EntidadeID, p: Pacote) {
	clear(dest)
	for i := len(p.historico) - 1; i >= 0; i -= 1 {
		append(dest, p.historico[i])
	}
	append(dest, p.origem)
}

// tcp_enviar_flood envia `base` a todos os vizinhos de `id` (handshake).
//
// Parâmetros:
// - `usuario`: usuário de origem (alocador dos clones).
// - `id`: handle da entidade de origem.
// - `base`: pacote base a inundar. Sem retorno.
tcp_enviar_flood :: proc(usuario: ^Usuario, id: EntidadeID, base: Pacote) {
	vizinhos := conexoes_entidade(id, context.temp_allocator)
	for v in vizinhos {
		copia := pacote_clone(base, usuario.alocador)
		pacote_enviar(&copia, id, v)
	}
}

// tcp_enviar_rota envia `base` pelo primeiro salto de `rota` (source routing).
//
// Parâmetros:
// - `usuario`: usuário de origem (alocador dos clones).
// - `id`: handle da entidade de origem.
// - `base`: pacote base.
// - `rota`: lista de saltos até o destino. Sem retorno.
tcp_enviar_rota :: proc(usuario: ^Usuario, id: EntidadeID, base: Pacote, rota: []EntidadeID) {
	if len(rota) == 0 {
		return
	}
	copia := pacote_clone(base, usuario.alocador)
	copia.usar_rota = true
	copia.rota = make([dynamic]EntidadeID, len(rota), usuario.alocador)
	copy(copia.rota[:], rota)
	copia.rota_indice = 0
	pacote_enviar(&copia, id, rota[0])
}

// tcp_iniciar abre a conexão para `mensagem` (estado SYN_ENVIADO) e inunda o SYN.
//
// Parâmetros:
// - `usuario`: usuário de origem.
// - `id`: handle do usuário de origem.
// - `mensagem`: mensagem a enviar. Sem retorno.
tcp_iniciar :: proc(usuario: ^Usuario, id: EntidadeID, mensagem: Mensagem) {
	runes := utf8.string_to_runes(mensagem.conteudo, usuario.alocador)
	total := (len(runes) + RUNES_POR_PACOTE - 1) / RUNES_POR_PACOTE
	if total == 0 {
		total = 1
	}

	usuario.tcp_envio = TcpEnvio {
		ativo = true,
		estado = .SYN_ENVIADO,
		destino = mensagem.destino,
		mensagem = mensagem,
		runes = runes,
		total = total,
		rota_ida = make([dynamic]EntidadeID, 0, 8, usuario.alocador),
		rto = tcp_rto,
		cor = cor_para_mensagem(mensagem.id),
	}

	base := Pacote {
		origem = id,
		destino = mensagem.destino,
		ip_origem = usuario.ip,
		ip_destino = ip_entidade(mensagem.destino),
		protocolo = .TCP,
		flags = {.SYN},
		ttl = TTL_PADRAO,
		mensagem_id = mensagem.id,
		total = total,
		cor = usuario.tcp_envio.cor,
	}
	tcp_enviar_flood(usuario, id, base)
}

// tcp_enviar_syn reconstrói e inunda o SYN (retransmissão do handshake).
//
// Parâmetros:
// - `usuario`: usuário de origem.
// - `id`: handle do usuário. Sem retorno.
tcp_enviar_syn :: proc(usuario: ^Usuario, id: EntidadeID) {
	e := &usuario.tcp_envio
	base := Pacote {
		origem = id,
		destino = e.destino,
		ip_origem = usuario.ip,
		ip_destino = ip_entidade(e.destino),
		protocolo = .TCP,
		flags = {.SYN},
		ttl = TTL_PADRAO,
		mensagem_id = e.mensagem.id,
		total = e.total,
		cor = e.cor,
	}
	tcp_enviar_flood(usuario, id, base)
}

// tcp_enviar_dados envia o segmento `seq` pela rota fixa.
//
// Parâmetros:
// - `usuario`: usuário de origem.
// - `id`: handle do usuário.
// - `seq`: índice do fragmento a enviar. Sem retorno.
tcp_enviar_dados :: proc(usuario: ^Usuario, id: EntidadeID, seq: int) {
	e := &usuario.tcp_envio
	inicio := seq * RUNES_POR_PACOTE
	fim := min(inicio + RUNES_POR_PACOTE, len(e.runes))
	base := Pacote {
		origem = id,
		destino = e.destino,
		ip_origem = usuario.ip,
		ip_destino = ip_entidade(e.destino),
		protocolo = .TCP,
		seq = u32(seq),
		total = e.total,
		bytes = e.runes[inicio:fim],
		ttl = TTL_PADRAO,
		mensagem_id = e.mensagem.id,
		cor = e.cor,
	}
	tcp_enviar_rota(usuario, id, base, e.rota_ida[:])
}

// tcp_enviar_fin envia o FIN pela rota fixa.
//
// Parâmetros:
// - `usuario`: usuário de origem.
// - `id`: handle do usuário. Sem retorno.
tcp_enviar_fin :: proc(usuario: ^Usuario, id: EntidadeID) {
	e := &usuario.tcp_envio
	base := Pacote {
		origem = id,
		destino = e.destino,
		ip_origem = usuario.ip,
		ip_destino = ip_entidade(e.destino),
		protocolo = .TCP,
		flags = {.FIN},
		seq = u32(e.total),
		ttl = TTL_PADRAO,
		mensagem_id = e.mensagem.id,
		total = e.total,
		cor = e.cor,
	}
	tcp_enviar_rota(usuario, id, base, e.rota_ida[:])
}

// tcp_enviar_ack envia um ACK cumulativo (ack = próximo seq esperado) ao emissor.
//
// Parâmetros:
// - `usuario`: usuário receptor.
// - `id`: handle do receptor.
// - `r`: estado de recebimento.
// - `p`: pacote que motivou o ACK. Sem retorno.
tcp_enviar_ack :: proc(usuario: ^Usuario, id: EntidadeID, r: ^RecebimentoTCP, p: Pacote) {
	base := Pacote {
		origem = id,
		destino = r.origem,
		ip_origem = usuario.ip,
		ip_destino = p.ip_origem,
		protocolo = .TCP,
		flags = {.ACK},
		ack = u32(r.proximo_seq),
		ttl = TTL_PADRAO,
		mensagem_id = r.mensagem_id,
		cor = r.cor,
	}
	tcp_enviar_rota(usuario, id, base, r.rota_volta[:])
}

// tcp_atualizar avança a temporização da conexão ativa: retransmite o segmento
// em voo ao esgotar o RTO e aborta após `tcp_max_tentativas`.
//
// Parâmetros:
// - `usuario`: usuário dono da conexão.
// - `id`: handle do usuário.
// - `dt`: tempo decorrido. Sem retorno.
tcp_atualizar :: proc(usuario: ^Usuario, id: EntidadeID, dt: f32) {
	e := &usuario.tcp_envio
	if !e.ativo {
		return
	}

	e.rto -= dt
	if e.rto > 0 {
		return
	}

	e.tentativas += 1
	if e.tentativas > tcp_max_tentativas {
		mostrar_mensagem("TCP: sem resposta; conexão abortada.")
		tcp_concluir(usuario)
		return
	}

	switch e.estado {
	case .SYN_ENVIADO:
		tcp_enviar_syn(usuario, id)
	case .ESTABELECIDO:
		tcp_enviar_dados(usuario, id, e.base)
	case .FIN_ENVIADO:
		tcp_enviar_fin(usuario, id)
	case .FECHADO:
	}
	e.rto = tcp_rto
}

// tcp_receber despacha um pacote TCP pelo seu tipo (flags/conteúdo).
//
// Parâmetros:
// - `usuario`: usuário destinatário.
// - `id`: handle do usuário.
// - `p`: pacote recebido. Sem retorno.
tcp_receber :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	has_syn := .SYN in p.flags
	has_fin := .FIN in p.flags
	has_ack := .ACK in p.flags

	switch {
	case has_syn && !has_ack:
		tcp_receber_syn(usuario, id, p)
	case has_syn && has_ack:
		tcp_receber_synack(usuario, id, p)
	case has_fin && !has_ack:
		tcp_receber_fin(usuario, id, p)
	case has_fin && has_ack:
		tcp_receber_finack(usuario, id, p)
	case len(p.bytes) > 0:
		tcp_receber_dados(usuario, id, p)
	case has_ack:
		tcp_receber_ack(usuario, id, p)
	}
}

// tcp_receber_syn cria (ou reusa) o estado de recebimento e responde SYN-ACK.
//
// Parâmetros:
// - `usuario`: usuário receptor.
// - `id`: handle do receptor.
// - `p`: pacote SYN recebido. Sem retorno.
tcp_receber_syn :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	r := tcp_achar_recebimento(usuario, p.mensagem_id, p.origem)
	if r == nil {
		append(&usuario.tcp_recebidas, RecebimentoTCP {
			ativo = true,
			origem = p.origem,
			destino = id,
			mensagem_id = p.mensagem_id,
			runes = make([dynamic]rune, 0, 64, usuario.alocador),
			rota_volta = make([dynamic]EntidadeID, 0, 8, usuario.alocador),
			cor = cor_para_mensagem(p.mensagem_id),
		})
		r = &usuario.tcp_recebidas[len(usuario.tcp_recebidas) - 1]
	}

	tcp_definir_rota(&r.rota_volta, p)

	base := Pacote {
		origem = id,
		destino = p.origem,
		ip_origem = usuario.ip,
		ip_destino = p.ip_origem,
		protocolo = .TCP,
		flags = {.SYN, .ACK},
		ttl = TTL_PADRAO,
		mensagem_id = p.mensagem_id,
		cor = r.cor,
	}
	tcp_enviar_flood(usuario, id, base)
}

// tcp_receber_synack fixa a rota_ida e completa o handshake no emissor.
//
// Parâmetros:
// - `usuario`: usuário emissor.
// - `id`: handle do emissor.
// - `p`: pacote SYN-ACK recebido. Sem retorno.
tcp_receber_synack :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	e := &usuario.tcp_envio
	if !e.ativo || e.estado != .SYN_ENVIADO {
		return
	}

	tcp_definir_rota(&e.rota_ida, p)

	base := Pacote {
		origem = id,
		destino = p.origem,
		ip_origem = usuario.ip,
		ip_destino = p.ip_origem,
		protocolo = .TCP,
		flags = {.ACK},
		ttl = TTL_PADRAO,
		mensagem_id = p.mensagem_id,
		cor = e.cor,
	}
	tcp_enviar_flood(usuario, id, base)

	e.estado = .ESTABELECIDO
	e.base = 0
	e.tentativas = 0
	e.rto = tcp_rto
	tcp_enviar_dados(usuario, id, 0)
}

// tcp_receber_dados acumula um segmento em ordem e confirma com ACK.
//
// Parâmetros:
// - `usuario`: usuário receptor.
// - `id`: handle do receptor.
// - `p`: segmento de dados recebido. Sem retorno.
tcp_receber_dados :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	r := tcp_achar_recebimento(usuario, p.mensagem_id, p.origem)
	if r == nil {
		return
	}

	if u32(r.proximo_seq) == p.seq {
		append(&r.runes, ..p.bytes)
		r.proximo_seq += 1
	}

	tcp_enviar_ack(usuario, id, r, p)
}

// tcp_receber_ack trata ACKs: fixa a rota_volta (ACK de estabelecimento) ou
// avança a base do emissor (ACK de dados).
//
// Parâmetros:
// - `usuario`: usuário.
// - `id`: handle do usuário.
// - `p`: pacote ACK recebido. Sem retorno.
tcp_receber_ack :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	r := tcp_achar_recebimento(usuario, p.mensagem_id, p.origem)
	if r != nil && p.ack == 0 {
		tcp_definir_rota(&r.rota_volta, p)
		r.rota_pronta = true
		return
	}

	e := &usuario.tcp_envio
	if !e.ativo || e.estado != .ESTABELECIDO {
		return
	}
	if p.ack <= u32(e.base) {
		return
	}
	if p.ack == u32(e.base + 1) {
		e.base += 1
		e.tentativas = 0
		if e.base < e.total {
			tcp_enviar_dados(usuario, id, e.base)
			e.rto = tcp_rto
		} else {
			tcp_enviar_fin(usuario, id)
			e.estado = .FIN_ENVIADO
			e.tentativas = 0
			e.rto = tcp_rto
		}
	}
}

// tcp_receber_fin finaliza a recepção: remonta a mensagem, notifica e responde
// FIN-ACK pela rota_volta.
//
// Parâmetros:
// - `usuario`: usuário receptor.
// - `id`: handle do receptor.
// - `p`: pacote FIN recebido. Sem retorno.
tcp_receber_fin :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	r := tcp_achar_recebimento(usuario, p.mensagem_id, p.origem)
	if r == nil {
		return
	}

	conteudo := utf8.runes_to_string(r.runes[:], usuario.alocador)
	append(&usuario.recebidas, Mensagem {
		id = r.mensagem_id,
		origem = r.origem,
		destino = id,
		conteudo = conteudo,
		protocolo = .TCP,
	})
	notificar_mensagem_recebida(usuario.nome, conteudo, .TCP)

	base := Pacote {
		origem = id,
		destino = p.origem,
		ip_origem = usuario.ip,
		ip_destino = p.ip_origem,
		protocolo = .TCP,
		flags = {.FIN, .ACK},
		ack = u32(r.proximo_seq),
		ttl = TTL_PADRAO,
		mensagem_id = p.mensagem_id,
		cor = r.cor,
	}
	tcp_enviar_rota(usuario, id, base, r.rota_volta[:])

	tcp_remover_recebimento(usuario, r)
}

// tcp_receber_finack encerra a conexão no emissor ao receber o FIN-ACK.
//
// Parâmetros:
// - `usuario`: usuário emissor.
// - `id`: handle do emissor.
// - `p`: pacote FIN-ACK recebido. Sem retorno.
tcp_receber_finack :: proc(usuario: ^Usuario, id: EntidadeID, p: Pacote) {
	e := &usuario.tcp_envio
	if !e.ativo || e.estado != .FIN_ENVIADO {
		return
	}
	tcp_concluir(usuario)
}

// tcp_achar_recebimento localiza o estado de recebimento por mensagem e origem.
//
// Parâmetros:
// - `usuario`: usuário receptor.
// - `mensagem_id`: id da mensagem.
// - `origem`: handle do emissor.
//
// Retorna: ponteiro para o estado, ou `nil`.
tcp_achar_recebimento :: proc(usuario: ^Usuario, mensagem_id: u32, origem: EntidadeID) -> ^RecebimentoTCP {
	for i in 0 ..< len(usuario.tcp_recebidas) {
		r := &usuario.tcp_recebidas[i]
		if r.ativo && r.mensagem_id == mensagem_id && r.origem == origem {
			return r
		}
	}
	return nil
}

// tcp_remover_recebimento remove e libera um estado de recebimento.
//
// Parâmetros:
// - `usuario`: usuário receptor.
// - `r`: ponteiro para o estado a remover. Sem retorno.
tcp_remover_recebimento :: proc(usuario: ^Usuario, r: ^RecebimentoTCP) {
	for i in 0 ..< len(usuario.tcp_recebidas) {
		if &usuario.tcp_recebidas[i] == r {
			delete(usuario.tcp_recebidas[i].runes)
			delete(usuario.tcp_recebidas[i].rota_volta)
			unordered_remove(&usuario.tcp_recebidas, i)
			return
		}
	}
}

// tcp_concluir libera os buffers da conexão ativa do emissor.
//
// Parâmetros:
// - `usuario`: usuário emissor. Sem retorno.
tcp_concluir :: proc(usuario: ^Usuario) {
	if usuario.tcp_envio.ativo {
		delete(usuario.tcp_envio.runes)
		delete(usuario.tcp_envio.rota_ida)
		delete(usuario.tcp_envio.mensagem.conteudo)
	}
	usuario.tcp_envio = {}
}

// tcp_limpar limpa envio e recebimentos de um usuário (mantém os arrays vivos).
//
// Parâmetros:
// - `usuario`: usuário a limpar. Sem retorno.
tcp_limpar :: proc(usuario: ^Usuario) {
	tcp_concluir(usuario)
	for &r in usuario.tcp_recebidas {
		delete(r.runes)
		delete(r.rota_volta)
	}
	clear(&usuario.tcp_recebidas)
}

// tcp_limpar_todos limpa o estado TCP de todos os usuários.
//
// Sem parâmetros e sem retorno.
tcp_limpar_todos :: proc() {
	it := hm.iterator_make(&entidades)
	for entidade, _ in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			tcp_limpar(&dados)
		case Comutador:
		}
	}
}

// tcp_rotulo devolve um rótulo curto do pacote TCP para logs/render.
//
// Parâmetros:
// - `p`: pacote consultado.
//
// Retorna: "SYN", "SYN-ACK", "ACK", "FIN", "FIN-ACK" ou "seq N".
tcp_rotulo :: proc(p: Pacote) -> string {
	has_syn := .SYN in p.flags
	has_fin := .FIN in p.flags
	has_ack := .ACK in p.flags

	switch {
	case has_syn && has_ack:
		return "SYN-ACK"
	case has_syn:
		return "SYN"
	case has_fin && has_ack:
		return "FIN-ACK"
	case has_fin:
		return "FIN"
	case has_ack:
		return "ACK"
	}
	return fmt.aprintf("seq %v", p.seq)
}
