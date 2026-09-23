# SICOMPA — Contexto consolidado

## Visão geral do projeto

**SICOMPA** é um simulador didático de rede de comutação de pacotes, em **Odin + Raylib**. Objetivo: visualizar o processo de comutação de forma didática, com pacotes viajando visualmente pelas conexões. Arquitetura: dois handle maps globais (entidades e conexões), renderização em camadas (conexões → entidades → GUI) e um sistema simples de mensagem/popup.

Método de comutação definido: **flooding** (sem otimização de rota). Cada comutador verifica se está conectado ao destino; se não, repassa o pacote aos demais comutadores. Para evitar loops, o `Pacote` precisa carregar a lista de comutadores por onde já passou.

## Por arquivo

**`main.odin`** — entrada. Configura alocador rastreador em debug; inicializa/destrói os handle maps dinâmicos em release; carrega `icon_map.png`/`icon_tower.png`; loop:
`entidades_atualizar()` → `simulacao_atualizar()` → `notificacoes_atualizar()` → `conexoes_renderizar()` → `entidades_renderizar()` → `pacotes_renderizar()` → `gui_renderizar()`, com `free_all(context.temp_allocator)` no fim; `defer { simulacao_limpar(); delete(pacotes); notificacoes_limpar(); delete(notificacoes) }`.

**`entidade.odin`** — `Entidade{handle, dados, sprite, posicao, offset_mouse, colisor_mouse, segurado}`, `Dados :: union{Comutador, Usuario}`, `EntidadeID :: Handle32`. Convenção **`posicao` = centro** (`colisor_mouse` deslocado por `-TAMANHO_COLISOR/2`; sprite desenhado com offset de metade, `ESCALA_ENTIDADE :: 2.0`). Seleção em `entidades_selecionadas` (2 IDs); arraste com botão esquerdo; clique direito via `entidades_processar_click_direito` (entidade → selecionar; linha + seleção pendente → mensagem; linha → deletar; vazio → cancelar); destaque amarelo na 1ª selecionada; `entidade_rotulo_renderizar` desenha o `nome` do Usuário abaixo do sprite.

**`conexoes.odin`** — `conexoes` handle map (Static em debug/Dynamic em release), `ConexaoID :: Handle32`, `Conexao{handle, a, b}`. `criar_conexao` com 3 recusas (auto-conexão, Usuário↔Usuário, par duplicado) via `mostrar_mensagem`; `deletar_conexao`; `remover_conexoes`; `conexao_extremidades`/`get_extremidades` (retornam `posicao` = centro); `conexoes_entidade` (`[]EntidadeID` com temp allocator); `conexao_sob_mouse` e `conexoes_renderizar` (linhas centro-a-centro com highlight de hover).

**`gui.odin`** — botões "Criar Usuário"/"Criar Comutador"/"Nova Mensagem" (abre modal com dropdowns Origem/Destino de usuários + `GuiTextBox` + "Adicionar"/"Cancelar"); dropdowns desenhados por último (aberto por cima de tudo); barra inferior vira painel raygui com "Iniciar/Pausar" e "Limpar"; helper de mensagem com buffer fixo `[256]u8` + timer (`MENSAGEM_DURACAO :: 0.5`).

**`usuario.odin`** — `UsuarioID :: EntidadeID`; `proximo_usuario_id: u32` (nome automático "Usuário N"); `Mensagem{id: u32, origem, destino: EntidadeID, conteudo: string}`; `Usuario{alocador, nome, saida: [dynamic]Mensagem, entrada: [dynamic]Pacote, recebidas: [dynamic]Mensagem}`; `usuario_enviar` (string→runes, corta em blocos de `RUNES_POR_PACOTE`, lança aos vizinhos) e `usuario_receber` (dedupe por `(mensagem_id, indice)`, remonta ao completar `total`, move para `recebidas` e chama `notificar_mensagem_recebida`).

**`comutador.odin`** — `ComutadorID :: EntidadeID`; `Comutador{}` vazio; `comutador_new`/`comutador_free`.

**`pacote.odin`** — `Pacote{origem, destino: EntidadeID, mensagem_id: u32, indice, total: int, bytes: []rune, historico: [dynamic]EntidadeID, de, para: EntidadeID, progresso: f32, cor: rl.Color}`; `RUNES_POR_PACOTE :: 8`; `pacote_clone` (cópia profunda) e `pacote_free`.

**`simulacao.odin`** — globais `pacotes: [dynamic]Pacote`, `simulacao_ativa: bool`, `proximo_mensagem_id: u32`; `pacote_enviar`/`pacote_chegar` (helpers de estado/flooding, não tocam `Usuario`; `pacote_chegar` chama `usuario_receber` no destino); `simulacao_iniciar` (verifica pendências e ativa), `simulacao_atualizar` (avança `progresso`, escoa `saida`, para sozinho quando termina), `simulacao_limpar`, `pacotes_renderizar` (círculo interpolado + rastro).

**`notificacoes.odin`** — `Notificacao{texto: string, timer: f32}`; global `notificacoes: [dynamic]Notificacao`; `notificar`, `notificar_mensagem_recebida(nome, conteudo)`, `notificacoes_atualizar` (decai timer e remove), `notificacoes_renderizar` (cartões empilhados no topo-direito, fade) e `notificacoes_limpar`.

## Modificado na última sessão
- **Fase 1 (simulação/flooding)** implementada: `pacote.odin` expandido (fragmentos + `pacote_clone`/`pacote_free`); `usuario.odin` com `Mensagem`, `usuario_enviar` (fragmenta em `RUNES_POR_PACOTE` e lança aos vizinhos) e `usuario_receber` (dedupe + remontagem em `recebidas`); `simulacao.odin` novo (`pacote_enviar`/`pacote_chegar`, `simulacao_iniciar`/`atualizar`/`limpar`, `pacotes_renderizar`).
- **`gui.odin`**: botão "Nova Mensagem" com modal (dropdowns Origem/Destino + `GuiTextBox` + "Adicionar"/"Cancelar"); barra inferior como painel raygui com "Iniciar/Pausar" e "Limpar".
- **`main.odin`**: `simulacao_atualizar()` e `pacotes_renderizar()` no loop; `defer { simulacao_limpar(); delete(pacotes) }`.
- **Back-end de conexões criado** (`conexoes.odin`): storage em handle map, `criar_conexao` com as 3 recusas e `mostrar_mensagem`, deleção/limpeza, geometria e `conexoes_entidade`.
- **`entidade.odin`**: `entidade_new` corrigido (retorno `(id, ok)`, handle setado após `hm.add`); `entidade_free` chama `remover_conexoes`; seleção passa a usar `EntidadeID`; clique direito extraído para `entidades_processar_click_direito`.
- **Convenção de erro**: padronizada para `ok` (true = sucesso) nos procs do projeto; `hm.add` tratado via `err != false`.
- **Centro como referência**: `entidade_update` e `entidades_renderizar` alinhados à convenção.

## Pendências observadas (fora do escopo desta sessão)
- Itens ainda não iniciados: **4 (persistência `output.json`)** e melhorias visuais (a definir).
- `MENSAGEM_DURACAO :: 0.5` (era 2.5).

# Regras gerias
1. Não tente ler arquivos fora do projeto, sob nenhuma hipótese, principalmente os arquivos da biblioteca padrão do Odin ou do Raylib (eles tem uma documentação na internet para isto).
2. Você está em um ambiente separado do compilador, então não tente chamá-lo ou executá-lo, quem tem essa responsabilidade sou eu.
3. Evite ler arquivos de forma desnecessária, principalmente os arquivos binários em `sprites/` e `styles/`.