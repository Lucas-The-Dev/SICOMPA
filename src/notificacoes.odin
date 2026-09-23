package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

NOTIFICACAO_DURACAO :: 4.0

Notificacao :: struct {
	texto: string,
	timer: f32,
}

notificacoes: [dynamic]Notificacao

// notificar enfileira uma notificação no topo-direito com duração padrão,
// clonando o texto no alocador global.
//
// Parâmetros:
// - `texto`: mensagem exibida no cartão. Sem retorno.
notificar :: proc(texto: string) {
	append(&notificacoes, Notificacao{
		texto = strings.clone(texto, context.allocator),
		timer = NOTIFICACAO_DURACAO,
	})
}

// notificar_mensagem_recebida monta e enfileira o aviso de mensagem recebida.
//
// Parâmetros:
// - `nome`: nome do usuário destinatário.
// - `conteudo`: texto remontado da mensagem.
// - `protocolo`: protocolo usado na mensagem. Sem retorno.
notificar_mensagem_recebida :: proc(nome: string, conteudo: string, protocolo: Protocolo) {
	texto := fmt.aprintf("[%s] %s recebeu a mensagem: %s", nome_protocolo(protocolo), nome, conteudo)
	defer delete(texto)
	notificar(texto)
}

// notificacoes_atualizar decrementa o timer de cada notificação e remove as
// expiradas (liberando o texto). Sem retorno.
notificacoes_atualizar :: proc() {
	if len(notificacoes) == 0 {
		return
	}

	dt := rl.GetFrameTime()
	i := 0
	for i < len(notificacoes) {
		notificacoes[i].timer -= dt
		if notificacoes[i].timer <= 0 {
			delete(notificacoes[i].texto)
			unordered_remove(&notificacoes, i)
		} else {
			i += 1
		}
	}
}

// notificacoes_renderizar desenha os cartões empilhados no topo-direito, com
// fade de saída baseado no timer. Sem retorno.
notificacoes_renderizar :: proc() {
	largura: f32 = 420
	altura: f32 = 48
	margem: f32 = 12
	espacamento: f32 = 8

	y := margem
	for i in 0 ..< len(notificacoes) {
		n := &notificacoes[i]

		alpha := clamp(n.timer, 0, 1)

		x := f32(rl.GetScreenWidth()) - largura - margem
		rect := rl.Rectangle{x, y, largura, altura}
		rl.DrawRectangleRounded(rect, 0.2, 8, rl.Color{20, 20, 30, u8(220.0 * alpha)})

		cstr := strings.clone_to_cstring(n.texto, context.temp_allocator)
		rl.DrawText(
			cstr,
			i32(rect.x) + 12,
			i32(rect.y) + 12,
			16,
			rl.Color{240, 240, 240, u8(255.0 * alpha)},
		)

		y += altura + espacamento
	}
}

// notificacoes_limpar libera os textos de todas as notificações e esvazia a
// lista global. Sem retorno.
notificacoes_limpar :: proc() {
	for i in 0 ..< len(notificacoes) {
		delete(notificacoes[i].texto)
	}
	clear(&notificacoes)
}
