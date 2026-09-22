package main

import hm "core:container/handle_map"
import rl "vendor:raylib"

when ODIN_DEBUG {
	conexoes: hm.Static_Handle_Map(1024, Conexao, ConexaoID)
} else {
	conexoes: hm.Dynamic_Handle_Map(Conexao, ConexaoID)
}

ConexaoID :: hm.Handle32

Conexao :: struct {
	handle: ConexaoID,
	a, b:   EntidadeID,
}

criar_conexao :: proc(a, b: EntidadeID) -> (conexao: ConexaoID, ok: bool) {
	if a == b {
		mostrar_mensagem("Não é possível conectar uma entidade a ela mesma.")
		return {}, false
	}

	ea, ok_a := hm.get(&entidades, a)
	eb, ok_b := hm.get(&entidades, b)
	if !ok_a || !ok_b {
		return {}, false
	}

	if _, ua := ea.dados.(Usuario); ua {
		if _, ub := eb.dados.(Usuario); ub {
			mostrar_mensagem("Conexão direta entre dois usuários não é permitida.")
			return {}, false
		}
	}

	it := hm.iterator_make(&conexoes)
	for c, _ in hm.iterate(&it) {
		if (c.a == a && c.b == b) || (c.a == b && c.b == a) {
			mostrar_mensagem("Essas entidades já estão conectadas.")
			return {}, false
		}
	}

	handle, err := hm.add(&conexoes, Conexao{a = a, b = b})
	if err != false {
		return {}, false
	}
	if c, found := hm.get(&conexoes, handle); found {
		c.handle = handle
	}
	return handle, true
}

deletar_conexao :: proc(conexao: ConexaoID) {
	hm.remove(&conexoes, conexao)
}

remover_conexoes :: proc(id: EntidadeID) {
	para_remover := make([dynamic]ConexaoID, 0, 8, context.temp_allocator)
	it := hm.iterator_make(&conexoes)
	for c, handle in hm.iterate(&it) {
		if c.a == id || c.b == id {
			append(&para_remover, handle)
		}
	}
	for handle in para_remover {
		hm.remove(&conexoes, handle)
	}
}

conexao_extremidades :: proc(c: ^Conexao) -> (rl.Vector2, rl.Vector2) {
	ea, ok_a := hm.get(&entidades, c.a)
	eb, ok_b := hm.get(&entidades, c.b)
	if !ok_a || !ok_b {
		return {}, {}
	}
	return ea.posicao, eb.posicao
}

get_extremidades :: proc(conexao: ConexaoID) -> (rl.Vector2, rl.Vector2) {
	c, ok := hm.get(&conexoes, conexao)
	if !ok {
		return {}, {}
	}
	return conexao_extremidades(c)
}

conexoes_entidade :: proc(entidade: EntidadeID, alocador := context.temp_allocator) -> []EntidadeID {
	vizinhos := make([dynamic]EntidadeID, 0, 8, alocador)
	it := hm.iterator_make(&conexoes)
	for c, _ in hm.iterate(&it) {
		if c.a == entidade {
			append(&vizinhos, c.b)
		} else if c.b == entidade {
			append(&vizinhos, c.a)
		}
	}
	return vizinhos[:]
}
