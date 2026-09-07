package main

UsuarioID :: EntidadeID

Pacote :: struct {
	bytes: []rune,
}

Usuario :: struct {
	entrada:  [dynamic]Pacote,
	vizinhos: [dynamic]ComutadorID,
}

usuarios: map[UsuarioID]Usuario
