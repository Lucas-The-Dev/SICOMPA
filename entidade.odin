package main

import hm "core:container/handle_map"
import rl "vendor:raylib"

when ODIN_DEBUG {
	entidades: hm.Static_Handle_Map(1024, Entidade, EntidadeID)
} else {
	entidades: hm.Dynamic_Handle_Map(Entidade, EntidadeID)
}

EntidadeID :: hm.Handle32

Entidade :: struct {
	handle:  EntidadeID,
	// sprite:   rl.Texture,
	posicao: rl.Vector2,
	tipo:    TipoEntidade,
}

TipoEntidade :: enum {
	Comutador,
	Usuario,
}
