# SICOMPA — Contexto consolidado

## Visão geral do projeto

**SICOMPA** é um simulador didático de rede de comutação de pacotes, em **Odin + Raylib**. Objetivo: visualizar o processo de comutação de forma didática, com pacotes viajando visualmente pelas conexões. Arquitetura: dois handle maps globais (entidades e conexões), renderização em camadas (conexões → entidades → GUI) e um sistema simples de mensagem/popup.

Método de comutação definido: **flooding** (sem otimização de rota). Cada comutador verifica se está conectado ao destino; se não, repassa o pacote aos demais comutadores. Para evitar loops, o `Pacote` precisa carregar a lista de comutadores por onde já passou.

## Por arquivo

**`main.odin`** — entrada. Configura alocador rastreador em debug; inicializa/destrói os handle maps dinâmicos em release; carrega `icon_map.png`/`icon_tower.png`; loop:
`entidades_atualizar()` → `conexoes_renderizar()` → `entidades_renderizar()` → `gui_renderizar()`, com `free_all(context.temp_allocator)` no fim.

**`entidade.odin`** — `Entidade{handle, dados, sprite, posicao, offset_mouse, colisor_mouse, segurado}`, `Dados :: union{Comutador, Usuario}`, `EntidadeID :: Handle32`. Convenção **`posicao` = centro** (`colisor_mouse` deslocado por `-TAMANHO_COLISOR/2`; sprite desenhado com offset de metade, `ESCALA_ENTIDADE :: 2.0`). Seleção em `entidades_selecionadas` (2 IDs); arraste com botão esquerdo; clique direito via `entidades_processar_click_direito` (entidade → selecionar; linha + seleção pendente → mensagem; linha → deletar; vazio → cancelar); destaque amarelo na 1ª selecionada.

**`conexoes.odin`** — `conexoes` handle map (Static em debug/Dynamic em release), `ConexaoID :: Handle32`, `Conexao{handle, a, b}`. `criar_conexao` com 3 recusas (auto-conexão, Usuário↔Usuário, par duplicado) via `mostrar_mensagem`; `deletar_conexao`; `remover_conexoes`; `conexao_extremidades`/`get_extremidades` (retornam `posicao` = centro); `conexoes_entidade` (`[]EntidadeID` com temp allocator); `conexao_sob_mouse` e `conexoes_renderizar` (linhas centro-a-centro com highlight de hover).

**`gui.odin`** — botões "Criar Usuário"/"Criar Comutador"/"Enviar Mensagem" (vazio); barra inferior (retângulo verde); helper de mensagem com buffer fixo `[256]u8` + timer (`MENSAGEM_DURACAO :: 0.5`) desenhado como popup inferior.

**`usuario.odin`** — `UsuarioID :: EntidadeID`; `Usuario{alocador, entrada [dynamic]Pacote}`; `usuario_new`/`usuario_free`.

**`comutador.odin`** — `ComutadorID :: EntidadeID`; `Comutador{}` vazio; `comutador_new`/`comutador_free`.

**`pacote.odin`** — `Pacote{origem, destino: EntidadeID, historico: [dynamic]ComutadorID, bytes: []rune}`.

## Modificado na útima sessão
- **Back-end de conexões criado** (`conexoes.odin`): storage em handle map, `criar_conexao` com as 3 recusas e `mostrar_mensagem`, deleção/limpeza, geometria e `conexoes_entidade`.
- **`entidade.odin`**: `entidade_new` corrigido (retorno `(id, ok)`, handle setado após `hm.add`); `entidade_free` chama `remover_conexoes`; seleção passa a usar `EntidadeID`; clique direito extraído para `entidades_processar_click_direito`.
- **Convenção de erro**: padronizada para `ok` (true = sucesso) nos procs do projeto; `hm.add` tratado via `err != false`.
- **Fase 3**: `conexoes_renderizar` (linhas centro-a-centro + hover), `conexao_sob_mouse`, prioridade do botão direito e **highlight de seleção**; chamada de render inserida no `main`.
- **Centro como referência**: `entidade_update` e `entidades_renderizar` alinhados à convenção.
- **`pacote.odin`**: campos ajustados (`origem/destino: EntidadeID`, `historico: [dynamic]ComutadorID`).
- **`main.odin`**: init/destroy do handle map de conexões.

## Pendências observadas (fora do escopo desta sessão)
- `gui.odin:65,70`: condição invertida — mostra "Falha..." quando `ok == true` (deveria ser `!ok`).
- `MENSAGEM_DURACAO :: 0.5` (era 2.5).
- `Pacote.historico` é `[dynamic]`; falta `pacote_free` para liberar (relevante no Item 2).
- Itens ainda não iniciados: **2 (mensagens/flooding)**, **3 (simulação ativa/iniciar-pausar)** e **4 (persistência `output.json`)**.

# Regras gerias
1. Não tente ler arquivos fora do projeto, sob nenhuma hipótese, principalmente os arquivos da biblioteca padrão do Odin ou do Raylib (eles tem uma documentação na internet para isto).
2. Você está em um ambiente separado do compilador, então não tente chamá-lo ou executá-lo, quem tem essa responsabilidade sou eu.
3. Evite ler arquivos de forma desnecessária, principalmente os arquivos binários em `sprites/` e `styles/`.