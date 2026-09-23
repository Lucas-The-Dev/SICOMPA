package main

import hm "core:container/handle_map"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

pacotes: [dynamic]Pacote
simulacao_ativa: bool
proximo_mensagem_id: u32
logs_ativos: bool = true

VELOCIDADE_PACOTE :: 260.0
RAIO_PACOTE :: 7.0

TTL_PADRAO :: 32

// probabilidade_perda é a chance (0.0..1.0) de descartar um pacote a cada salto.
probabilidade_perda: f32 = 0

// perder_pacote sorteia se o pacote é descartado neste salto.
//
// Retorna: `true` se o pacote deve ser perdido.
perder_pacote :: proc() -> bool {
	if probabilidade_perda <= 0 {
		return false
	}
	return rl.GetRandomValue(0, 9999) < i32(probabilidade_perda * 10000)
}

@(rodata)
CORES_MENSAGEM := [6]rl.Color {
	rl.SKYBLUE,
	rl.ORANGE,
	rl.LIME,
	rl.VIOLET,
	rl.PINK,
	rl.GOLD,
}

// cor_para_mensagem escolhe uma cor estável a partir do id da mensagem.
//
// Parâmetros:
// - `id`: id da mensagem.
//
// Retorna: a cor correspondente na paleta `CORES_MENSAGEM`.
cor_para_mensagem :: proc(id: u32) -> rl.Color {
	return CORES_MENSAGEM[id % u32(len(CORES_MENSAGEM))]
}

// log_pacote imprime no terminal um evento do pacote (salto, entrega, descarte),
// com protocolo, IPs de origem/destino, TTL e o histórico de comutadores.
//
// Parâmetros:
// - `pacote`: pacote envolvido no evento.
// - `evento`: rótulo curto do que aconteceu. Sem retorno.
log_pacote :: proc(pacote: Pacote, evento: string) {
	if !logs_ativos {
		return
	}

	hist := strings.builder_make_len_cap(0, 64, context.temp_allocator)
	fmt.sbprintf(&hist, "[")
	for h, i in pacote.historico {
		if i > 0 {
			fmt.sbprintf(&hist, ", ")
		}
		fmt.sbprintf(&hist, "%s", nome_entidade(h))
	}
	fmt.sbprintf(&hist, "]")

	if pacote.protocolo == .TCP {
		fmt.printf(
			"[msg %v][TCP] %s: %s(%s) -> %s(%s) | %s seq=%v ack=%v | ttl=%v | hist=%s\n",
			pacote.mensagem_id,
			evento,
			nome_entidade(pacote.de),
			ip_para_string(pacote.ip_origem),
			nome_entidade(pacote.para),
			ip_para_string(pacote.ip_destino),
			tcp_rotulo(pacote),
			pacote.seq,
			pacote.ack,
			pacote.ttl,
			strings.to_string(hist),
		)
		return
	}

	fmt.printf(
		"[msg %v][pkt %v/%v][%s] %s: %s(%s) -> %s(%s) | ttl=%v | hist=%s\n",
		pacote.mensagem_id,
		pacote.indice,
		pacote.total,
		nome_protocolo(pacote.protocolo),
		evento,
		nome_entidade(pacote.de),
		ip_para_string(pacote.ip_origem),
		nome_entidade(pacote.para),
		ip_para_string(pacote.ip_destino),
		pacote.ttl,
		strings.to_string(hist),
	)
}

// posicao_entidade consulta o centro de uma entidade.
//
// Parâmetros:
// - `id`: handle da entidade.
//
// Retorna: centro da entidade e `true` se ela existe; caso contrário `{}`/`false`.
posicao_entidade :: proc(id: EntidadeID) -> (rl.Vector2, bool) {
	entidade, ok := hm.get(&entidades, id)
	if !ok {
		return {}, false
	}
	return entidade.posicao, true
}

// pacote_enviar define o trecho atual (`de`→`para`), zera o progresso e enfileira
// o pacote no array global `pacotes` (o dono passa a ser a simulação).
//
// Parâmetros:
// - `pacote`: pacote a enfileirar.
// - `de`, `para`: entidades de origem e destino deste salto. Sem retorno.
pacote_enviar :: proc(pacote: ^Pacote, de, para: EntidadeID) {
	pacote.de = de
	pacote.para = para
	pacote.progresso = 0
	log_pacote(pacote^, "SALTO")
	append(&pacotes, pacote^)
}

// entidade_no_historico verifica se `id` já consta no histórico do pacote,
// evitando que o flooding volte a um nó por onde já passou.
//
// Parâmetros:
// - `historico`: lista de comutadores já visitados.
// - `id`: entidade consultada.
//
// Retorna: `true` se encontrada, `false` caso contrário.
entidade_no_historico :: proc(historico: [dynamic]EntidadeID, id: EntidadeID) -> bool {
	for h in historico {
		if h == id {
			return true
		}
	}
	return false
}

// pacote_chegar trata um pacote que atingiu `pacote.para`.
// Se `para` é o destino, entrega ao usuário (`usuario_receber`); se é um
// comutador, aplica o flooding (encaminha ao destino se for vizinho, senão
// clona para vizinhos fora do histórico/`de`).
//
// Parâmetros:
// - `pacote`: pacote que chegou ao nó. Sem retorno.
pacote_chegar :: proc(pacote_entrada: Pacote) {
	// Cópia local mutável (parâmetros Odin são imutáveis).
	p := pacote_entrada

	if perder_pacote() {
		log_pacote(p, "PERDIDO")
		return
	}

	if p.destino == p.para {
		log_pacote(p, "ENTREGA")
		if entidade, ok := hm.get(&entidades, p.para); ok {
			switch &dados in entidade.dados {
			case Usuario:
				switch p.protocolo {
				case .UDP:
					usuario_receber(&dados, p)
				case .TCP:
					tcp_receber(&dados, p.para, p)
				}
			case Comutador:
			}
		}
		return
	}

	entidade, ok := hm.get(&entidades, p.para)
	if !ok {
		return
	}
	if _, is_comutador := entidade.dados.(Comutador); !is_comutador {
		return
	}

	if p.ttl <= 1 {
		log_pacote(p, "TTL ESGOTADO")
		return
	}
	p.ttl -= 1

	no := p.para

	if p.usar_rota {
		proximo_idx := p.rota_indice + 1
		if proximo_idx >= len(p.rota) {
			log_pacote(p, "ROTA FIM")
			return
		}
		proximo := p.rota[proximo_idx]
		if _, ok := hm.get(&entidades, proximo); !ok {
			log_pacote(p, "ROTA INVÁLIDA")
			return
		}
		log_pacote(p, "ROTA")
		copia := pacote_clone(p)
		copia.rota_indice = proximo_idx
		pacote_enviar(&copia, no, proximo)
		return
	}

	vizinhos := conexoes_entidade(no, context.temp_allocator)

	destino_vizinho := false
	for v in vizinhos {
		if v == p.destino {
			destino_vizinho = true
			break
		}
	}

	if destino_vizinho {
		log_pacote(p, "ROTA DIRETA")
		copia := pacote_clone(p)
		append(&copia.historico, no)
		pacote_enviar(&copia, no, p.destino)
		return
	}

	log_pacote(p, "FLOOD")
	for v in vizinhos {
		if v == p.de {
			continue
		}
		if entidade_no_historico(p.historico, v) {
			continue
		}
		copia := pacote_clone(p)
		append(&copia.historico, no)
		pacote_enviar(&copia, no, v)
	}
}

// simulacao_atualizar_envios percorre os usuários avançando os envios, que
// liberam um fragmento a cada `DELAY_ENTRE_PACOTES`.
//
// Parâmetros:
// - `dt`: tempo decorrido desde o último frame. Sem retorno.
simulacao_atualizar_envios :: proc(dt: f32) {
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			usuario_atualizar_envio(&dados, handle, dt)
		case Comutador:
		}
	}
}

// simulacao_tem_pendencia informa se ainda há trabalho a escoar.
//
// Retorna: `true` se algum usuário tem mensagens em `saida` ou um envio em
// andamento, `false` caso contrário. Fragmentos parciais de `entrada` são
// ignorados para permitir que a simulação encerre mesmo com perdas.
simulacao_tem_pendencia :: proc() -> bool {
	it := hm.iterator_make(&entidades)
	for entidade, _ in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			// Fragmentos parciais em `entrada` não contam como pendência: com
			// perda de pacotes eles nunca completariam, e a simulação precisa
			// poder parar. A conexão TCP ativa, porém, mantém a simulação viva.
			if len(dados.saida) > 0 || dados.envio_ativo || dados.tcp_envio.ativo {
				return true
			}
		case Comutador:
		}
	}
	return false
}

// simulacao_iniciar ativa a simulação. Sem pacotes em trânsito nem pendências,
// apenas avisa e mantém a simulação parada. Sem retorno.
simulacao_iniciar :: proc() {
	if len(pacotes) == 0 && !simulacao_tem_pendencia() {
		mostrar_mensagem("Sem mensagens para simular.")
		simulacao_ativa = false
		return
	}
	simulacao_ativa = true
	simulacao_atualizar_envios(0)
}

// simulacao_atualizar avança a simulação por frame: escoa envios, move cada
// pacote por `VELOCIDADE_PACOTE` (entregando ao chegar) e para sozinha quando
// não há mais pacotes nem pendências. Sem retorno.
simulacao_atualizar :: proc() {
	if !simulacao_ativa {
		return
	}

	dt := rl.GetFrameTime()
	simulacao_atualizar_envios(dt)

	for i := len(pacotes) - 1; i >= 0; i -= 1 {
		pacote := pacotes[i]

		p_de, ok_de := posicao_entidade(pacote.de)
		p_para, ok_para := posicao_entidade(pacote.para)
		if !ok_de || !ok_para {
			pacote_free(&pacotes[i])
			unordered_remove(&pacotes, i)
			continue
		}

		distancia := rl.Vector2Distance(p_de, p_para)
		if distancia <= 0.0001 {
			pacote_chegar(pacote)
			pacote_free(&pacotes[i])
			unordered_remove(&pacotes, i)
			continue
		}

		pacote.progresso += (VELOCIDADE_PACOTE * dt) / distancia

		if pacote.progresso >= 1.0 {
			pacote_chegar(pacote)
			pacote_free(&pacotes[i])
			unordered_remove(&pacotes, i)
			continue
		}

		pacotes[i].progresso = pacote.progresso
	}

	if len(pacotes) == 0 && !simulacao_tem_pendencia() {
		simulacao_ativa = false
	}
}

// simulacao_limpar libera todos os pacotes em trânsito, esvazia o array global
// e desativa a simulação. Sem retorno.
simulacao_limpar :: proc() {
	for i in 0 ..< len(pacotes) {
		pacote_free(&pacotes[i])
	}
	clear(&pacotes)
	tcp_limpar_todos()
	simulacao_ativa = false
}

// pacotes_renderizar desenha cada pacote interpolado entre `de` e `para`, com um
// rastro na direção do movimento (círculo para UDP; quadrado reservado ao TCP).
// Sem retorno.
pacotes_renderizar :: proc() {
	for pacote in pacotes {
		p_de, ok_de := posicao_entidade(pacote.de)
		p_para, ok_para := posicao_entidade(pacote.para)
		if !ok_de || !ok_para {
			continue
		}

		t := clamp(pacote.progresso, 0, 1)
		pos := rl.Vector2{rl.Lerp(p_de.x, p_para.x, t), rl.Lerp(p_de.y, p_para.y, t)}

		direcao := rl.Vector2Normalize(p_para - p_de)
		rastro := pos - direcao * (RAIO_PACOTE * 2.0)
		cor_rastro := rl.Color{pacote.cor.r, pacote.cor.g, pacote.cor.b, 120}
		rl.DrawLineEx(rastro, pos, RAIO_PACOTE, cor_rastro)

		switch pacote.protocolo {
		case .UDP:
			rl.DrawCircleV(pos, RAIO_PACOTE, pacote.cor)
		case .TCP:
			rl.DrawRectanglePro(
				rl.Rectangle{pos.x, pos.y, RAIO_PACOTE * 2, RAIO_PACOTE * 2},
				rl.Vector2{RAIO_PACOTE, RAIO_PACOTE},
				45,
				pacote.cor,
			)
			rotulo := tcp_rotulo(pacote)
			cstr := strings.clone_to_cstring(rotulo, context.temp_allocator)
			rl.DrawText(cstr, i32(pos.x) + 8, i32(pos.y) - 20, 14, rl.WHITE)
		}
	}
}
