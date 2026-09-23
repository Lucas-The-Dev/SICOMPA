package main

// Protocolo é a camada de transporte escolhida para uma mensagem.
// Apenas UDP está implementado; TCP é reservado para uma fase futura.
Protocolo :: enum {
	UDP,
	TCP,
}

// nome_protocolo devolve o rótulo curto do protocolo para logs/GUI.
//
// Parâmetros:
// - `protocolo`: protocolo consultado.
//
// Retorna: "UDP", "TCP" ou "?".
nome_protocolo :: proc(protocolo: Protocolo) -> string {
	switch protocolo {
	case .UDP:
		return "UDP"
	case .TCP:
		return "TCP"
	}
	return "?"
}
