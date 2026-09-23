package main

import hm "core:container/handle_map"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

GuiWindow :: enum {
	Tutorial,
}

GuiWindows :: bit_set[GuiWindow]

// flexbox_axis calcula a posição de um item empilhado verticalmente.
//
// Parâmetros:
// - `offset`: deslocamento inicial.
// - `size`: altura de cada item.
// - `spacing`: espaçamento entre itens.
// - `num`: índice (0-based) do item.
//
// Retorna: a coordenada do item na pilha.
flexbox_axis :: proc(offset, size, spacing: f32, num: int) -> f32 {
	return offset + (size + spacing) * f32(num)
}

MENSAGEM_DURACAO :: 2.5
mensagem_texto: [256]u8
mensagem_len:   int
mensagem_timer: f32

// mostrar_mensagem copia `texto` para o buffer do popup (cortando se exceder) e
// reinicia o timer de exibição.
//
// Parâmetros:
// - `texto`: mensagem curta a exibir. Sem retorno.
mostrar_mensagem :: proc(texto: string) {
	n := len(texto)
	if n > len(mensagem_texto) {
		n = len(mensagem_texto)
	}
	for i in 0 ..< n {
		mensagem_texto[i] = texto[i]
	}
	mensagem_len = n
	mensagem_timer = MENSAGEM_DURACAO
}

// gui_mensagem_render desenha o popup de mensagem enquanto o timer não expira,
// decrementando-o pelo tempo de frame. Sem retorno.
gui_mensagem_render :: proc() {
	if mensagem_timer <= 0 {
		return
	}
	mensagem_timer -= rl.GetFrameTime()

	texto := string(mensagem_texto[:mensagem_len])
	cstr := strings.clone_to_cstring(texto, context.temp_allocator)
	tamanho: i32 = 20
	largura := rl.MeasureText(cstr, tamanho)
	padding: i32 = 12
	rect := rl.Rectangle {
		x      = (f32(rl.GetScreenWidth()) - f32(largura)) / 2 - f32(padding),
		y      = f32(rl.GetScreenHeight()) - 160,
		width  = f32(largura + padding * 2),
		height = f32(tamanho + padding),
	}
	rl.DrawRectangleRec(rect, rl.Color{0, 0, 0, 200})
	rl.DrawText(cstr, i32(rect.x) + padding, i32(rect.y) + padding / 2, tamanho, rl.RED)
}

modal_mensagem_aberto: bool
mensagem_conteudo: [256]u8
mensagem_origem:   i32
mensagem_destino:  i32
mensagem_origem_edit:  bool
mensagem_destino_edit: bool
mensagem_protocolo:      Protocolo = .UDP
mensagem_protocolo_idx:  i32

modal_arquivo_aberto: bool

ArquivoModo :: enum {
	Exportar,
	Importar,
}

arquivo_modo: ArquivoModo
arquivo_nome: [256]u8

modal_nome_usuario_aberto: bool
nome_usuario_buffer:      [256]u8
ip_usuario_buffer:        [256]u8

// definir_buffer copia `texto` para o buffer fixo (null-terminado), cortando se exceder.
//
// Parâmetros:
// - `dest`: buffer de destino.
// - `texto`: texto a copiar. Sem retorno.
definir_buffer :: proc(dest: []u8, texto: string) {
	n := len(texto)
	if n > len(dest) - 1 {
		n = len(dest) - 1
	}
	for i in 0 ..< n {
		dest[i] = texto[i]
	}
	dest[n] = 0
}

// algum_modal_aberto informa se há algum modal aberto na GUI.
//
// Retorna: `true` se qualquer modal (mensagem, arquivo, nome de usuário ou
// resumo) estiver aberto.
algum_modal_aberto :: proc() -> bool {
	return modal_mensagem_aberto || modal_arquivo_aberto ||
		modal_nome_usuario_aberto || modal_resumo_aberto
}

// construir_lista_usuarios coleta os usuários existentes para os dropdowns.
//
// Retorna:
// - `ids`: handles dos usuários, na ordem de iteração (alocador temporário).
// - `texto`: nomes separados por ";" como `cstring` (lista do raygui).
// - `quantidade`: número de usuários.
construir_lista_usuarios :: proc() -> (ids: []EntidadeID, texto: cstring, quantidade: int) {
	lista := make([dynamic]EntidadeID, 0, 8, context.temp_allocator)
	b := strings.builder_make_len_cap(0, 128, context.temp_allocator)

	indice := 0
	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			append(&lista, handle)
			if indice > 0 {
				fmt.sbprintf(&b, ";")
			}
			fmt.sbprintf(&b, "%s (%s)", dados.nome, ip_para_string(dados.ip))
			indice += 1
		case Comutador:
		}
	}

	ids = lista[:]
	texto = strings.to_cstring(&b)
	quantidade = len(lista)
	return
}

// gui_modal_adicionar valida origem/destino/conteúdo e enfileira a mensagem na
// `saida` do usuário de origem (com aviso em cada erro de validação).
//
// Parâmetros:
// - `ids`: handles dos usuários, alinhados aos índices dos dropdowns. Sem retorno.
gui_modal_adicionar :: proc(ids: []EntidadeID) {
	if len(ids) == 0 {
		mostrar_mensagem("Crie ao menos um usuário.")
		return
	}
	if int(mensagem_origem) >= len(ids) || int(mensagem_destino) >= len(ids) {
		mostrar_mensagem("Selecione origem e destino.")
		return
	}
	origem := ids[int(mensagem_origem)]
	destino := ids[int(mensagem_destino)]
	if origem == destino {
		mostrar_mensagem("Origem e destino devem ser diferentes.")
		return
	}

	texto := string(cstring(&mensagem_conteudo[0]))
	if len(texto) == 0 {
		mostrar_mensagem("Digite o conteúdo da mensagem.")
		return
	}

	entidade, ok := hm.get(&entidades, origem)
	if !ok {
		return
	}
	switch &dados in entidade.dados {
	case Usuario:
		mensagem := Mensagem {
			id        = proximo_mensagem_id,
			origem    = origem,
			destino   = destino,
			conteudo  = strings.clone(texto, dados.alocador),
			protocolo = mensagem_protocolo,
		}
		proximo_mensagem_id += 1
		append(&dados.saida, mensagem)

		historico := Mensagem {
			id        = mensagem.id,
			origem    = origem,
			destino   = destino,
			conteudo  = strings.clone(texto, dados.alocador),
			protocolo = mensagem_protocolo,
		}
		append(&dados.enviadas, historico)

		mostrar_mensagem("Mensagem adicionada à simulação.")
	case Comutador:
	}
}

// gui_modal_mensagem_render desenha o modal "Nova Mensagem": labels, textbox,
// botões e, por último, os dropdowns de Origem/Destino. Sem retorno.
gui_modal_mensagem_render :: proc() {
	if !modal_mensagem_aberto {
		return
	}

	bounds := rl.Rectangle {
		x      = f32(rl.GetRenderWidth()) / 2 - 220,
		y      = f32(rl.GetRenderHeight()) / 2 - 190,
		width  = 440,
		height = 380,
	}
	rl.GuiWindowBox(bounds, "Nova Mensagem")

	ids, lista_texto, quantidade := construir_lista_usuarios()

	if int(mensagem_origem) >= quantidade {
		mensagem_origem = 0
	}
	if int(mensagem_destino) >= quantidade {
		mensagem_destino = 0
	}

	dropdown_aberto := mensagem_origem_edit || mensagem_destino_edit

	origem_bounds := rl.Rectangle{bounds.x + 100, bounds.y + 40, 300, 24}
	destino_bounds := rl.Rectangle{bounds.x + 100, bounds.y + 80, 300, 24}

	rl.GuiLabel({bounds.x + 20, bounds.y + 40, 60, 24}, "Origem")
	rl.GuiLabel({bounds.x + 20, bounds.y + 80, 60, 24}, "Destino")
	rl.GuiLabel({bounds.x + 20, bounds.y + 120, 80, 24}, "Protocolo")
	rl.GuiLabel({bounds.x + 20, bounds.y + 160, 80, 24}, "Conteúdo")

	rl.GuiToggleGroup(
		{bounds.x + 100, bounds.y + 120, 149, 24},
		"UDP;TCP",
		&mensagem_protocolo_idx,
	)
	if mensagem_protocolo_idx != 0 {
		mostrar_mensagem("TCP ainda não implementado.")
		mensagem_protocolo_idx = 0
	}
	if mensagem_protocolo_idx == 0 {
		mensagem_protocolo = .UDP
	} else {
		mensagem_protocolo = .TCP
	}

	rl.GuiTextBox({bounds.x + 100, bounds.y + 160, 300, 24}, cstring(&mensagem_conteudo[0]), len(mensagem_conteudo), !dropdown_aberto)

	adicionar := rl.GuiButton({bounds.x + bounds.width - 250, bounds.y + bounds.height - 40, 110, 30}, "Adicionar")
	cancelar := rl.GuiButton({bounds.x + bounds.width - 130, bounds.y + bounds.height - 40, 110, 30}, "Cancelar")

	if adicionar && !dropdown_aberto {
		gui_modal_adicionar(ids)
		modal_mensagem_aberto = false
	}
	if cancelar && !dropdown_aberto {
		modal_mensagem_aberto = false
	}

	if mensagem_origem_edit {
		rl.GuiDropdownBox(destino_bounds, lista_texto, &mensagem_destino, false)
		if rl.GuiDropdownBox(origem_bounds, lista_texto, &mensagem_origem, true) {
			mensagem_origem_edit = false
		}
	} else if mensagem_destino_edit {
		rl.GuiDropdownBox(origem_bounds, lista_texto, &mensagem_origem, false)
		if rl.GuiDropdownBox(destino_bounds, lista_texto, &mensagem_destino, true) {
			mensagem_destino_edit = false
		}
	} else {
		if rl.GuiDropdownBox(origem_bounds, lista_texto, &mensagem_origem, false) {
			mensagem_origem_edit = true
			mensagem_destino_edit = false
		}
		if rl.GuiDropdownBox(destino_bounds, lista_texto, &mensagem_destino, false) {
			mensagem_destino_edit = true
			mensagem_origem_edit = false
		}
	}
}

// abrir_modal_arquivo abre o modal de arquivo no modo indicado e limpa o campo.
//
// Parâmetros:
// - `modo`: `.Exportar` ou `.Importar`. Sem retorno.
abrir_modal_arquivo :: proc(modo: ArquivoModo) {
	arquivo_modo = modo
	arquivo_nome[0] = 0
	modal_arquivo_aberto = true
}

// gui_modal_arquivo_confirmar lê o nome digitado, anexa ".json" e executa a
// ação do modo atual. Fecha o modal apenas se a operação tiver sucesso.
// Sem parâmetros e sem retorno.
gui_modal_arquivo_confirmar :: proc() {
	nome := string(cstring(&arquivo_nome[0]))
	if len(nome) == 0 {
		mostrar_mensagem("Digite um nome de arquivo.")
		return
	}

	arquivo := com_extensao_json(nome)

	switch arquivo_modo {
	case .Exportar:
		if exportar_esquema(arquivo) {
			modal_arquivo_aberto = false
		}
	case .Importar:
		if importar_esquema(arquivo) {
			modal_arquivo_aberto = false
		}
	}
}

// gui_modal_arquivo_render desenha o modal de nome de arquivo, adaptando título
// e rótulo do botão de ação conforme `arquivo_modo`. Sem retorno.
gui_modal_arquivo_render :: proc() {
	if !modal_arquivo_aberto {
		return
	}

	titulo := "Exportar Esquema"
	rotulo_acao := "Salvar"
	if arquivo_modo == .Importar {
		titulo = "Importar Esquema"
		rotulo_acao = "Abrir"
	}

	bounds := rl.Rectangle {
		x      = f32(rl.GetRenderWidth()) / 2 - 200,
		y      = f32(rl.GetRenderHeight()) / 2 - 80,
		width  = 400,
		height = 160,
	}
	rl.GuiWindowBox(bounds, strings.clone_to_cstring(titulo))

	rl.GuiLabel({bounds.x + 20, bounds.y + 50, 120, 24}, "Nome do Arquivo")
	rl.GuiTextBox(
		{bounds.x + 150, bounds.y + 50, 230, 24},
		cstring(&arquivo_nome[0]),
		len(arquivo_nome),
		true,
	)

	if rl.GuiButton(
		{bounds.x + bounds.width - 230, bounds.y + bounds.height - 40, 100, 30},
		strings.clone_to_cstring(rotulo_acao),
	) {
		gui_modal_arquivo_confirmar()
	}
	if rl.GuiButton(
		{bounds.x + bounds.width - 120, bounds.y + bounds.height - 40, 100, 30},
		"Cancelar",
	) {
		modal_arquivo_aberto = false
	}
}

// abrir_modal_nome_usuario abre o modal de criação de usuário com a sugestão
// "Usuário N" (N = próximo id) pré-preenchida. Sem retorno.
abrir_modal_nome_usuario :: proc() {
	sugestao := fmt.aprintf("Usuário %v", proximo_usuario_id + 1)
	defer delete(sugestao)
	definir_buffer(nome_usuario_buffer[:], sugestao)
	definir_buffer(ip_usuario_buffer[:], ip_para_string(ip_sugerido()))
	modal_nome_usuario_aberto = true
}

// gui_modal_nome_usuario_render desenha o modal de nome do usuário e cria a
// entidade ao confirmar (nome vazio usa a sugestão). Sem retorno.
gui_modal_nome_usuario_render :: proc() {
	if !modal_nome_usuario_aberto {
		return
	}

	bounds := rl.Rectangle {
		x      = f32(rl.GetRenderWidth()) / 2 - 200,
		y      = f32(rl.GetRenderHeight()) / 2 - 100,
		width  = 400,
		height = 200,
	}
	rl.GuiWindowBox(bounds, "Criar Usuário")

	rl.GuiLabel({bounds.x + 20, bounds.y + 45, 90, 24}, "Nome")
	rl.GuiTextBox(
		{bounds.x + 110, bounds.y + 45, 260, 24},
		cstring(&nome_usuario_buffer[0]),
		len(nome_usuario_buffer),
		true,
	)

	rl.GuiLabel({bounds.x + 20, bounds.y + 85, 90, 24}, "IP")
	rl.GuiTextBox(
		{bounds.x + 110, bounds.y + 85, 260, 24},
		cstring(&ip_usuario_buffer[0]),
		len(ip_usuario_buffer),
		true,
	)

	if rl.GuiButton(
		{bounds.x + bounds.width - 230, bounds.y + bounds.height - 40, 100, 30},
		"Criar",
	) {
		nome := string(cstring(&nome_usuario_buffer[0]))
		ip_texto := string(cstring(&ip_usuario_buffer[0]))

		ip, ip_ok := ip_de_string(ip_texto)
		if !ip_ok {
			mostrar_mensagem("IP inválido.")
			return
		}
		if ip_em_uso(ip) {
			mostrar_mensagem("IP já está em uso.")
			return
		}

		center := rl.Vector2{f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2}
		if _, ok := entidade_new(usuario_new(nome, ip), center, sprites[.Usuario]); !ok {
			mostrar_mensagem("Falha ao criar usuário.")
			return
		}
		modal_nome_usuario_aberto = false
	}
	if rl.GuiButton(
		{bounds.x + bounds.width - 120, bounds.y + bounds.height - 40, 100, 30},
		"Cancelar",
	) {
		modal_nome_usuario_aberto = false
	}
}

// gui_renderizar orquestra toda a GUI na ordem de desenho:
// botões, barra inferior, popup, modais e notificações. Sem retorno.
gui_renderizar :: proc() {
	gui_topleft_buttons_render()

	gui_bottom_bar_render()

	gui_mensagem_render()

	gui_modal_mensagem_render()

	gui_modal_arquivo_render()

	gui_modal_nome_usuario_render()

	gui_modal_resumo_render()

	notificacoes_renderizar()
}

// gui_topleft_buttons_render desenha a coluna superior-esquerda com os botões
// Criar Usuário/Comutador, Nova Mensagem, Exportar e Importar. As ações são
// ignoradas enquanto houver modal aberto (`algum_modal_aberto`). Sem retorno.
gui_topleft_buttons_render :: proc() {
	center := rl.Vector2{f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 0), 150, 30}, "Criar Usuário") && !algum_modal_aberto() {
		abrir_modal_nome_usuario()
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 1), 150, 30}, "Criar Comutador") && !algum_modal_aberto() {
		if _, ok := entidade_new(comutador_new(), center, sprites[.Comutador]); !ok {
			mostrar_mensagem("Falha ao criar comutador.")
		}
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 2), 150, 30}, "Nova Mensagem") && !algum_modal_aberto() {
		modal_mensagem_aberto = true
		mensagem_conteudo[0] = 0
		mensagem_protocolo = .UDP
		mensagem_protocolo_idx = 0
		mensagem_origem_edit = false
		mensagem_destino_edit = false
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 3), 150, 30}, "Exportar") && !algum_modal_aberto() {
		abrir_modal_arquivo(.Exportar)
	}
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 4), 150, 30}, "Importar") && !algum_modal_aberto() {
		abrir_modal_arquivo(.Importar)
	}
	rotulo_logs := logs_ativos ? "Logs: ON" : "Logs: OFF"
	if rl.GuiButton({20, flexbox_axis(20, 30, 10, 5), 150, 30}, strings.clone_to_cstring(rotulo_logs)) && !algum_modal_aberto() {
		logs_ativos = !logs_ativos
	}
}

// gui_bottom_bar_render desenha a barra inferior com o estado da simulação e os
// botões Iniciar/Pausar e Limpar. Sem retorno.
gui_bottom_bar_render :: proc() {
	rect := rl.Rectangle {
		x      = f32(rl.GetScreenWidth()) / 2 - 350,
		y      = f32(rl.GetScreenHeight()) - 70,
		width  = 700,
		height = 50,
	}
	rl.GuiPanel(rect, "")

	rotulo := "Pausado"
	if simulacao_ativa {
		rotulo = "Rodando"
	}
	rl.GuiLabel({rect.x + 20, rect.y + 15, 90, 24}, strings.clone_to_cstring(rotulo))

	texto_botao := "Iniciar"
	if simulacao_ativa {
		texto_botao = "Pausar"
	}
	if rl.GuiButton({rect.x + 120, rect.y + 10, 120, 30}, strings.clone_to_cstring(texto_botao)) {
		if simulacao_ativa {
			simulacao_ativa = false
		} else {
			simulacao_iniciar()
		}
	}
	if rl.GuiButton({rect.x + 250, rect.y + 10, 120, 30}, "Limpar") {
		simulacao_limpar()
	}

	perda_pct := probabilidade_perda * 100
	rl.GuiSlider(
		{rect.x + 490, rect.y + 15, 190, 16},
		"Perda%",
		"",
		&perda_pct,
		0,
		100,
	)
	probabilidade_perda = perda_pct / 100
}
