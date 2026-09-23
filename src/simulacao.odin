package main

import hm "core:container/handle_map"
import rl "vendor:raylib"

pacotes: [dynamic]Pacote
simulacao_ativa: bool
proximo_mensagem_id: u32

VELOCIDADE_PACOTE :: 260.0
RAIO_PACOTE :: 7.0

@(rodata)
CORES_MENSAGEM := [6]rl.Color {
	rl.SKYBLUE,
	rl.ORANGE,
	rl.LIME,
	rl.VIOLET,
	rl.PINK,
	rl.GOLD,
}

cor_para_mensagem :: proc(id: u32) -> rl.Color {
	return CORES_MENSAGEM[id % u32(len(CORES_MENSAGEM))]
}

posicao_entidade :: proc(id: EntidadeID) -> (rl.Vector2, bool) {
	entidade, ok := hm.get(&entidades, id)
	if !ok {
		return {}, false
	}
	return entidade.posicao, true
}

pacote_enviar :: proc(pacote: ^Pacote, de, para: EntidadeID) {
	pacote.de = de
	pacote.para = para
	pacote.progresso = 0
	append(&pacotes, pacote^)
}

entidade_no_historico :: proc(historico: [dynamic]EntidadeID, id: EntidadeID) -> bool {
	for h in historico {
		if h == id {
			return true
		}
	}
	return false
}

pacote_chegar :: proc(pacote: Pacote) {
	if pacote.destino == pacote.para {
		if entidade, ok := hm.get(&entidades, pacote.para); ok {
			switch &dados in entidade.dados {
			case Usuario:
				usuario_receber(&dados, pacote)
			case Comutador:
			}
		}
		return
	}

	entidade, ok := hm.get(&entidades, pacote.para)
	if !ok {
		return
	}
	if _, is_comutador := entidade.dados.(Comutador); !is_comutador {
		return
	}

	no := pacote.para
	vizinhos := conexoes_entidade(no, context.temp_allocator)

	destino_vizinho := false
	for v in vizinhos {
		if v == pacote.destino {
			destino_vizinho = true
			break
		}
	}

	if destino_vizinho {
		copia := pacote_clone(pacote)
		append(&copia.historico, no)
		pacote_enviar(&copia, no, pacote.destino)
		return
	}

	for v in vizinhos {
		if v == pacote.de {
			continue
		}
		if entidade_no_historico(pacote.historico, v) {
			continue
		}
		copia := pacote_clone(pacote)
		append(&copia.historico, no)
		pacote_enviar(&copia, no, v)
	}
}

simulacao_escoar_saidas :: proc() {
	it := hm.iterator_make(&entidades)
	for entidade, _ in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			for i := len(dados.saida) - 1; i >= 0; i -= 1 {
				mensagem := dados.saida[i]
				if !usuario_enviar(&dados, mensagem) {
					mostrar_mensagem("Usuário de origem sem conexões; mensagem descartada.")
				}
				delete(mensagem.conteudo)
				unordered_remove(&dados.saida, i)
			}
		case Comutador:
		}
	}
}

simulacao_tem_pendencia :: proc() -> bool {
	it := hm.iterator_make(&entidades)
	for entidade, _ in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			if len(dados.saida) > 0 || len(dados.entrada) > 0 {
				return true
			}
		case Comutador:
		}
	}
	return false
}

simulacao_iniciar :: proc() {
	if len(pacotes) == 0 && !simulacao_tem_pendencia() {
		mostrar_mensagem("Sem mensagens para simular.")
		simulacao_ativa = false
		return
	}
	simulacao_ativa = true
	simulacao_escoar_saidas()
}

simulacao_atualizar :: proc() {
	if !simulacao_ativa {
		return
	}
	simulacao_escoar_saidas()

	dt := rl.GetFrameTime()
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

simulacao_limpar :: proc() {
	for i in 0 ..< len(pacotes) {
		pacote_free(&pacotes[i])
	}
	clear(&pacotes)
	simulacao_ativa = false
}

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
		rl.DrawCircleV(pos, RAIO_PACOTE, pacote.cor)
	}
}
