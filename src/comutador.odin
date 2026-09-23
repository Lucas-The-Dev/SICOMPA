package main

ComutadorID :: EntidadeID

Comutador :: struct {}

// comutador_new cria um comutador. Atualmente não possui estado próprio.
//
// Retorna: o `Comutador` (vazio).
comutador_new :: proc() -> (comutador: Comutador) {
	return comutador
}

// comutador_free libera recursos do comutador (no-op por enquanto).
//
// Parâmetros:
// - `comutador`: ponteiro para o comutador. Sem retorno.
comutador_free :: proc(comutador: ^Comutador) {
	// return comutador
}
