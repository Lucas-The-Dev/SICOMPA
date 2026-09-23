# SICOMPA — Contexto consolidado

## Visão geral do projeto

**SICOMPA** é um simulador didático de rede de comutação de pacotes, em **Odin + Raylib**. Objetivo: visualizar o processo de comutação de forma didática, com pacotes viajando visualmente pelas conexões. Arquitetura: dois handle maps globais (entidades e conexões), renderização em camadas (conexões → entidades → pacotes → GUI) e um sistema simples de mensagem/popup (curto) + notificações no topo-direito.

Método de comutação definido: **flooding** (sem otimização de rota). Cada comutador verifica se está conectado ao destino; se não, repassa o pacote aos demais comutadores. Para evitar loops, o `Pacote` precisa carregar a lista de comutadores por onde já passou.

## Por arquivo

**`main.odin`** — entrada. Configura alocador rastreador em debug; inicializa/destrói os handle maps dinâmicos em release; carrega `icon_map.png`/`icon_tower.png`; loop:
`entidades_atualizar()` → `simulacao_atualizar()` → `notificacoes_atualizar()` → `conexoes_renderizar()` → `entidades_renderizar()` → `pacotes_renderizar()` → `gui_renderizar()`, com `free_all(context.temp_allocator)` no fim; `defer { simulacao_limpar(); delete(pacotes); notificacoes_limpar(); delete(notificacoes) }`.

**`entidade.odin`** — `Entidade{handle, dados, sprite, posicao, offset_mouse, colisor_mouse, segurado}`, `Dados :: union{Comutador, Usuario}`, `EntidadeID :: Handle32`. Convenção **`posicao` = centro** (`colisor_mouse` deslocado por `-TAMANHO_COLISOR/2`; sprite desenhado com offset de metade, `ESCALA_ENTIDADE :: 2.0`). Seleção em `entidades_selecionadas` (2 IDs); arraste com botão esquerdo; clique direito via `entidades_processar_click_direito` (entidade → selecionar; linha + seleção pendente → mensagem; linha → deletar; vazio → cancelar); destaque amarelo na 1ª selecionada; `entidade_rotulo_renderizar` desenha o `nome` do Usuário abaixo do sprite. `entidade_free` **não** descarrega textura (sprites são globais/compartilhadas); `entidades_limpar` limpa pacotes (`simulacao_limpar`), libera `dados` de cada entidade, remove do handle map, limpa conexões e zera a seleção (usado na importação).

**`conexoes.odin`** — `conexoes` handle map (Static em debug/Dynamic em release), `ConexaoID :: Handle32`, `Conexao{handle, a, b}`. `criar_conexao` com 3 recusas (auto-conexão, Usuário↔Usuário, par duplicado) via `mostrar_mensagem`; `deletar_conexao`; `remover_conexoes`; `conexao_extremidades`/`get_extremidades` (retornam `posicao` = centro); `conexoes_entidade` (`[]EntidadeID` com temp allocator); `conexoes_limpar` (remove todas); `conexao_sob_mouse` e `conexoes_renderizar` (linhas centro-a-centro com highlight de hover).

**`gui.odin`** — botões "Criar Usuário"/"Criar Comutador"/"Nova Mensagem" (abre modal com dropdowns Origem/Destino de usuários + `GuiTextBox` + "Adicionar"/"Cancelar") e "Exportar"/"Importar" (abre modal de nome de arquivo: `GuiTextBox` + Salvar/Abrir/Cancelar, anexa `.json`); dropdowns desenhados por último (aberto por cima de tudo); `algum_modal_aberto()` evita que os botões globais ajam com um modal aberto; barra inferior vira painel raygui com "Iniciar/Pausar" e "Limpar"; helper de mensagem com buffer fixo `[256]u8` + timer (`MENSAGEM_DURACAO :: 2.5`).

**`usuario.odin`** — `UsuarioID :: EntidadeID`; `proximo_usuario_id: u32` (nome automático "Usuário N"); `Mensagem{id: u32, origem, destino: EntidadeID, conteudo: string}`; `Usuario{alocador, nome, saida: [dynamic]Mensagem, entrada: [dynamic]Pacote, recebidas: [dynamic]Mensagem}`; `usuario_enviar` (string→runes, corta em blocos de `RUNES_POR_PACOTE`, lança aos vizinhos) e `usuario_receber` (dedupe por `(mensagem_id, indice)`, remonta ao completar `total`, move para `recebidas` e chama `notificar_mensagem_recebida`).

**`comutador.odin`** — `ComutadorID :: EntidadeID`; `Comutador{}` vazio; `comutador_new`/`comutador_free`.

**`pacote.odin`** — `Pacote{origem, destino: EntidadeID, mensagem_id: u32, indice, total: int, bytes: []rune, historico: [dynamic]EntidadeID, de, para: EntidadeID, progresso: f32, cor: rl.Color}`; `RUNES_POR_PACOTE :: 8`; `pacote_clone` (cópia profunda) e `pacote_free`.

**`simulacao.odin`** — globais `pacotes: [dynamic]Pacote`, `simulacao_ativa: bool`, `proximo_mensagem_id: u32`; `pacote_enviar`/`pacote_chegar` (helpers de estado/flooding, não tocam `Usuario`; `pacote_chegar` chama `usuario_receber` no destino); `simulacao_iniciar` (verifica pendências e ativa), `simulacao_atualizar` (avança `progresso`, escoa `saida`, para sozinho quando termina), `simulacao_limpar`, `pacotes_renderizar` (círculo interpolado + rastro).

**`notificacoes.odin`** — `Notificacao{texto: string, timer: f32}`; global `notificacoes: [dynamic]Notificacao`; `notificar`, `notificar_mensagem_recebida(nome, conteudo)`, `notificacoes_atualizar` (decai timer e remove), `notificacoes_renderizar` (cartões empilhados no topo-direito, fade) e `notificacoes_limpar`.

**`persistencia.odin`** — importação/exportação do esquema em JSON (`VERSION_ESQUEMA :: 1`). Tipos `TipoEntidade` (`Usuario`/`Comutador`), `EntidadeEsquema{tipo, x, y, nome}`, `ConexaoEsquema{a, b}` (índices) e `Esquema{versao, entidades, conexoes}`. `montar_esquema` mapeia `EntidadeID → índice`; `exportar_esquema` (marshal pretty + `os.write_entire_file`) e `importar_esquema` (`os.read_entire_file` + `json.unmarshal`, `entidades_limpar`, recria entidades preservando tipo/posição/nome e refaz as conexões). Wrappers `arquivo_ler`/`arquivo_escrever` isolam a API de `core:os`; `com_extensao_json` anexa `.json`. Mensagens/pendências **não** são persistidas.

## Histórico de sessões

### Sessão atual — Importação/exportação + correções pendentes
- **`persistencia.odin`** (novo): esquema JSON (`VERSION_ESQUEMA :: 1`) com tipo/posição/nome por entidade e conexões por índice; `exportar_esquema` (marshal pretty + `os.write_entire_file`) e `importar_esquema` (`os.read_entire_file` + `json.unmarshal`, `entidades_limpar` e remontagem). Nomes de usuário preservados; mensagens/pendências fora do arquivo.
- **`gui.odin`**: botões "Exportar"/"Importar" na coluna superior-esquerda (índices 3 e 4); modal de nome de arquivo (`GuiTextBox` + Salvar/Abrir/Cancelar) anexando `.json`; `algum_modal_aberto()` impede ações dos botões globais com modal aberto. `MENSAGEM_DURACAO` corrigido para `2.5` na doc.
- **Correções pendentes**: `conexoes_limpar` (conexoes.odin); `entidades_limpar` e remoção do `rl.UnloadTexture` de textura compartilhada em `entidade_free` (entidade.odin).
- Sem mudanças em `main.odin`; `AGENTS.md` atualizado após confirmação.

### Sessão anterior — Fase 1 (simulação/flooding) + correções pós-teste
- **Fase 1 (simulação/flooding)** concluída: `pacote.odin` expandido (fragmentos + `pacote_clone`/`pacote_free`); `usuario.odin` com `Mensagem`, `usuario_enviar` (fragmenta em `RUNES_POR_PACOTE` e lança aos vizinhos) e `usuario_receber` (dedupe + remontagem em `recebidas`); `simulacao.odin` novo (`pacote_enviar`/`pacote_chegar`, `simulacao_iniciar`/`atualizar`/`limpar`, `pacotes_renderizar`).
- **`gui.odin`**: botão "Nova Mensagem" com modal (dropdowns Origem/Destino + `GuiTextBox` + "Adicionar"/"Cancelar"); barra inferior como painel raygui com "Iniciar/Pausar" e "Limpar".
- **`main.odin`**: `simulacao_atualizar()` e `pacotes_renderizar()` no loop; `defer { simulacao_limpar(); delete(pacotes) }`.
- **Pós-teste, 4 correções:**
  1. **Animação travada**: removido `rl.EnableEventWaiting()` em `main.odin`. O modo dirigido por eventos bloqueava `EndDrawing()` até chegar um evento, então a simulação só avançava com o mouse em movimento. Agora o loop roda por frame (limitado por `SetTargetFPS(180)`).
  2. **Nome do usuário**: `Usuario.nome` + global `proximo_usuario_id` em `usuario.odin` (automático "Usuário N", liberado em `usuario_free`); `entidade_rotulo_renderizar` desenha o nome sob o sprite; dropdowns usam `dados.nome`.
  3. **Dropdown sobreposto**: `gui_modal_mensagem_render` desenha labels/textbox/botões primeiro e os dropdowns por último (o aberto por último de tudo), com guarda para botões/textbox não agirem enquanto há dropdown aberto; modal mais alto.
  4. **Feedback de recebimento**: novo `notificacoes.odin` (cartões empilhados no topo-direito, ~4s, fade). `usuario_receber` chama `notificar_mensagem_recebida(nome, conteudo)` ao completar a remontagem. `main.odin` chama `notificacoes_atualizar()` e `gui_renderizar()` chama `notificacoes_renderizar()`; limpeza no `defer`.
- **Ajustes de compilação aplicados pelo usuário** (não repetir): `CORES_MENSAGEM` virou `@(rodata) [6]rl.Color` (constante não pode ser indexada por variável); `make([dynamic]rune, ...)` em `usuario_receber` (evitar ambiguidade de `make`); conversões para `cstring` nos rótulos/botões; `strings.to_cstring(&b)` sem passar allocator.
- **Back-end de conexões** (`conexoes.odin`): storage em handle map, `criar_conexao` com as 3 recusas e `mostrar_mensagem`, deleção/limpeza, geometria e `conexoes_entidade`.
- **`entidade.odin`**: `entidade_new` corrigido (retorno `(id, ok)`, handle setado após `hm.add`); `entidade_free` chama `remover_conexoes`; seleção passa a usar `EntidadeID`; clique direito extraído para `entidades_processar_click_direito`.
- **Convenção de erro**: padronizada para `ok` (true = sucesso) nos procs do projeto; `hm.add` tratado via `err != false`.

## Pendências observadas (fora do escopo desta sessão)
- Melhorias visuais ainda a definir pelo usuário.
- Validar `VERSION_ESQUEMA` na importação e detalhar mensagens de erro de arquivo.
- Revisar `MENSAGEM_DURACAO :: 2.5` (popup) — pode ser revisto.

# Regras gerias
1. Não tente ler arquivos fora do projeto, sob nenhuma hipótese, principalmente os arquivos da biblioteca padrão do Odin ou do Raylib (eles tem uma documentação na internet para isto).
2. Você está em um ambiente separado do compilador, então não tente chamá-lo ou executá-lo, quem tem essa responsabilidade sou eu.
3. Evite ler arquivos de forma desnecessária, principalmente os arquivos binários em `sprites/` e `styles/`.