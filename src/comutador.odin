package main

ComutadorID :: EntidadeID

proximo_comutador_id: u32

Comutador :: struct {
	id: u32,
}

// comutador_new cria um comutador com um id sequencial (para logs/tabela).
//
// Retorna: o `Comutador` (incrementa `proximo_comutador_id`).
comutador_new :: proc() -> (comutador: Comutador) {
	proximo_comutador_id += 1
	comutador.id = proximo_comutador_id
	return comutador
}

// comutador_free libera recursos do comutador (no-op por enquanto).
//
// Parâmetros:
// - `comutador`: ponteiro para o comutador. Sem retorno.
comutador_free :: proc(comutador: ^Comutador) {
	// return comutador
}
