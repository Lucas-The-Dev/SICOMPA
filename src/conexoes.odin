package main

import hm "core:container/handle_map"

ConexaoID :: hm.Handle32

Conexao :: struct {
	handle: ConexaoID,
	a, b: EntidadeID
}

criar_conexao :: proc(a, b: EntidadeID) -> ConexaoID {}

deletar_conexao :: proc(conexao: ConexaoID) {}

conexoes_renderizar :: proc() {}

get_extremidades :: proc(conexao: ConexaoID) -> (Vector2, Vector2) {}

conexoes_entidade :: proc(entidade: EntidadeID, alocator := context.temp_allocator) -> [] EntidadeID


