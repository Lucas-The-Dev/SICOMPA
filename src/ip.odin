package main

import hm "core:container/handle_map"
import "core:fmt"
import "core:strconv"
import "core:strings"

// Ip é um endereço IPv4 armazenado em 4 octetos.
Ip :: distinct [4]u8

IP_AUTO_BASE :: [4]u8{192, 168, 0, 0}
IP_VAZIO :: Ip{}

// ip_para_string formata o IP como "a.b.c.d" (alocador temporário).
//
// Parâmetros:
// - `ip`: endereço a formatar.
//
// Retorna: a representação textual do IP.
ip_para_string :: proc(ip: Ip) -> string {
	return fmt.aprintf(
		"%v.%v.%v.%v",
		ip[0],
		ip[1],
		ip[2],
		ip[3],
		allocator = context.temp_allocator,
	)
}

// ip_de_string valida e converte um texto "a.b.c.d" em `Ip`.
//
// Parâmetros:
// - `texto`: endereço no formato decimal pontuado.
//
// Retorna: o `Ip` convertido e `true` se o texto for um IPv4 válido.
ip_de_string :: proc(texto: string) -> (ip: Ip, ok: bool) {
	partes := strings.split(texto, ".", context.temp_allocator)
	if len(partes) != 4 {
		return {}, false
	}

	for parte, i in partes {
		if len(parte) == 0 || len(parte) > 3 {
			return {}, false
		}
		valor, parse_ok := strconv.parse_int(parte, 10)
		if !parse_ok || valor < 0 || valor > 255 {
			return {}, false
		}
		ip[i] = u8(valor)
	}
	return ip, true
}

// ip_em_uso informa se algum usuário já possui o IP informado.
//
// Parâmetros:
// - `ip`: endereço consultado.
//
// Retorna: `true` se já houver um usuário com esse IP.
ip_em_uso :: proc(ip: Ip) -> bool {
	it := hm.iterator_make(&entidades)
	for entidade, _ in hm.iterate(&it) {
		switch &dados in entidade.dados {
		case Usuario:
			if dados.ip == ip {
				return true
			}
		case Comutador:
		}
	}
	return false
}

// ip_sugerido escolhe o próximo IP livre na faixa `IP_AUTO_BASE`.
//
// Retorna: o primeiro IP livre (`192.168.0.1`..`192.168.0.254`).
ip_sugerido :: proc() -> Ip {
	for n := 1; n <= 254; n += 1 {
		candidato := Ip{IP_AUTO_BASE[0], IP_AUTO_BASE[1], IP_AUTO_BASE[2], u8(n)}
		if !ip_em_uso(candidato) {
			return candidato
		}
	}
	return Ip{IP_AUTO_BASE[0], IP_AUTO_BASE[1], IP_AUTO_BASE[2], 254}
}

// ip_entidade consulta o IP de uma entidade (zero para comutadores).
//
// Parâmetros:
// - `id`: handle da entidade.
//
// Retorna: o IP do usuário; `Ip{}` se não existir ou não for usuário.
ip_entidade :: proc(id: EntidadeID) -> Ip {
	entidade, ok := hm.get(&entidades, id)
	if !ok {
		return {}
	}
	switch &dados in entidade.dados {
	case Usuario:
		return dados.ip
	case Comutador:
	}
	return {}
}
