package main

import hm "core:container/handle_map"
import "core:encoding/json"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

VERSION_ESQUEMA :: 1

TipoEntidade :: enum {
	Usuario,
	Comutador,
}

EntidadeEsquema :: struct {
	tipo: TipoEntidade `json:"tipo"`,
	x:    f32          `json:"x"`,
	y:    f32          `json:"y"`,
	nome: string       `json:"nome,omitempty"`,
}

ConexaoEsquema :: struct {
	a: int `json:"a"`,
	b: int `json:"b"`,
}

Esquema :: struct {
	versao:    int               `json:"versao"`,
	entidades: []EntidadeEsquema `json:"entidades"`,
	conexoes:  []ConexaoEsquema  `json:"conexoes"`,
}

// Anexa a extensão ".json" caso ainda não esteja presente.
com_extensao_json :: proc(nome: string) -> string {
	if strings.has_suffix(nome, ".json") {
		return strings.clone(nome, context.temp_allocator)
	}
	return strings.concatenate({nome, ".json"}, context.temp_allocator)
}

// Wrappers de arquivo para isolar a API de `core:os`.
arquivo_ler :: proc(nome: string) -> (data: []byte, ok: bool) {
	d, err := os.read_entire_file(nome, context.temp_allocator)
	if err != nil {
		return nil, false
	}
	return d, true
}

arquivo_escrever :: proc(nome: string, data: []byte) -> bool {
	err := os.write_entire_file(nome, data)
	return err == nil
}

// Monta o esquema a partir do estado atual (somente entidades, posições,
// nomes de usuário e conexões). As alocações usam o alocador temporário.
montar_esquema :: proc() -> Esquema {
	entidades_esquema := make([dynamic]EntidadeEsquema, 0, 16, context.temp_allocator)
	indices := make(map[EntidadeID]int)
	defer delete(indices)

	it := hm.iterator_make(&entidades)
	for entidade, handle in hm.iterate(&it) {
		tipo: TipoEntidade
		nome: string

		switch &dados in entidade.dados {
		case Usuario:
			tipo = .Usuario
			nome = dados.nome
		case Comutador:
			tipo = .Comutador
		}

		indices[handle] = len(entidades_esquema)
		append(
			&entidades_esquema,
			EntidadeEsquema {
				tipo = tipo,
				x = entidade.posicao.x,
				y = entidade.posicao.y,
				nome = nome,
			},
		)
	}

	conexoes_esquema := make([dynamic]ConexaoEsquema, 0, 16, context.temp_allocator)
	itc := hm.iterator_make(&conexoes)
	for c, _ in hm.iterate(&itc) {
		ia, ok_a := indices[c.a]
		ib, ok_b := indices[c.b]
		if !ok_a || !ok_b {
			continue
		}
		append(&conexoes_esquema, ConexaoEsquema{a = ia, b = ib})
	}

	return Esquema {
		versao = VERSION_ESQUEMA,
		entidades = entidades_esquema[:],
		conexoes = conexoes_esquema[:],
	}
}

exportar_esquema :: proc(nome: string) -> bool {
	esquema := montar_esquema()

	opcoes := json.Marshal_Options {
		pretty     = true,
		use_spaces = true,
		spaces     = 4,
	}
	data, err := json.marshal(esquema, opcoes, context.temp_allocator)
	if err != nil {
		mostrar_mensagem("Falha ao serializar o esquema.")
		return false
	}

	if !arquivo_escrever(nome, data) {
		mostrar_mensagem("Falha ao escrever o arquivo.")
		return false
	}

	notificar(strings.concatenate({"Esquema exportado: ", nome}, context.temp_allocator))
	return true
}

importar_esquema :: proc(nome: string) -> bool {
	data, ok := arquivo_ler(nome)
	if !ok {
		mostrar_mensagem("Arquivo não encontrado.")
		return false
	}

	esquema: Esquema
	if err := json.unmarshal(data, &esquema, allocator = context.temp_allocator); err != nil {
		mostrar_mensagem("Arquivo inválido.")
		return false
	}

	if len(esquema.entidades) == 0 {
		mostrar_mensagem("O esquema não possui entidades.")
		return false
	}

	entidades_limpar()
	proximo_usuario_id = 0
	proximo_mensagem_id = 0

	criadas := make([]EntidadeID, len(esquema.entidades), context.temp_allocator)

	for e, i in esquema.entidades {
		dados: Dados
		sprite := sprites[.Comutador]

		switch e.tipo {
		case .Usuario:
			u := usuario_new()
			delete(u.nome)
			u.nome = strings.clone(e.nome, u.alocador)
			dados = u
			sprite = sprites[.Usuario]
		case .Comutador:
			dados = comutador_new()
		case:
			mostrar_mensagem("Tipo de entidade desconhecido no arquivo.")
			entidades_limpar()
			return false
		}

		id, criado := entidade_new(dados, rl.Vector2{e.x, e.y}, sprite)
		if !criado {
			mostrar_mensagem("Falha ao criar entidade do esquema.")
			entidades_limpar()
			return false
		}
		criadas[i] = id
	}

	for c in esquema.conexoes {
		if c.a < 0 || c.b < 0 || c.a >= len(criadas) || c.b >= len(criadas) {
			continue
		}
		criar_conexao(criadas[c.a], criadas[c.b])
	}

	notificar(strings.concatenate({"Esquema importado: ", nome}, context.temp_allocator))
	return true
}
