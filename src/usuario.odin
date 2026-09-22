package main

import "base:runtime"
UsuarioID :: EntidadeID

Usuario :: struct {
	alocador: runtime.Allocator,
	entrada:  [dynamic]Pacote,
}

usuario_new :: proc(alocador := context.allocator) -> (usuario: Usuario) {
	usuario.alocador = alocador
	usuario.entrada = make(type_of(usuario.entrada), usuario.alocador)
	return usuario
}

usuario_free :: proc(usuario: ^Usuario) {
	delete(usuario.entrada)
}
