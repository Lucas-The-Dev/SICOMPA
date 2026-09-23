# SICOMPA — Contexto consolidado

## Visão geral do projeto

**SICOMPA** é um simulador didático de rede de comutação de pacotes, em **Odin + Raylib**. Objetivo: visualizar o processo de comutação de forma didática, com pacotes viajando visualmente pelas conexões. Arquitetura: dois handle maps globais (entidades e conexões), renderização em camadas (conexões → entidades → pacotes → GUI) e um sistema simples de mensagem/popup (curto) + notificações no topo-direito.

Método de comutação definido: **flooding** (sem otimização de rota). Cada comutador verifica se está conectado ao destino; se não, repassa o pacote aos demais comutadores. Para evitar loops, o `Pacote` carrega o histórico de comutadores por onde já passou.

## Por arquivo

**`main.odin`** — entrada. Configura alocador rastreador em debug; inicializa/destrói os handle maps dinâmicos em release; carrega `icon_map.png`/`icon_tower.png`/`resumo.png` no array global `sprites[EntitySprite]` (`Usuario`/`Comutador`/`Resumo`); loop:
`entidades_atualizar()` → `simulacao_atualizar()` → `notificacoes_atualizar()` → `conexoes_renderizar()` → `entidades_renderizar()` → `pacotes_renderizar()` → `gui_renderizar()`, com `free_all(context.temp_allocator)` no fim; `defer { simulacao_limpar(); delete(pacotes); notificacoes_limpar(); delete(notificacoes) }`.

**`entidade.odin`** — `Entidade{handle, dados, sprite, posicao, offset_mouse, colisor_mouse, segurado}`, `Dados :: union{Comutador, Usuario}`, `EntidadeID :: Handle32`. Convenção **`posicao` = centro** (`colisor_mouse` deslocado por `-TAMANHO_COLISOR/2`; sprite 16×16 desenhado com offset de metade, `ESCALA_ENTIDADE :: 2.0`). Seleção em `entidades_selecionadas` (2 IDs); arraste com botão esquerdo; clique direito via `entidades_processar_click_direito` (entidade → selecionar; linha + seleção pendente → mensagem; linha → deletar; vazio → cancelar); destaque amarelo na 1ª selecionada; `entidade_rotulo_renderizar` desenha o `nome` do Usuário abaixo do sprite. Clique esquerdo no ícone de resumo é tratado em `entidades_atualizar` **antes** do arraste (via `resumo_processar_clique`, suprime a captura). `nome_entidade(id)` devolve rótulo legível (nome do Usuário / `"Comutador N"`). `entidade_free` **não** descarrega textura (sprites são globais/compartilhadas); `entidades_limpar` limpa pacotes (`simulacao_limpar`), libera `dados` de cada entidade, remove do handle map, limpa conexões e zera a seleção (usado na importação).

**`conexoes.odin`** — `conexoes` handle map (Static em debug/Dynamic em release), `ConexaoID :: Handle32`, `Conexao{handle, a, b}`. `criar_conexao` com 3 recusas (auto-conexão, Usuário↔Usuário, par duplicado) via `mostrar_mensagem`; `deletar_conexao`; `remover_conexoes`; `conexao_extremidades`/`get_extremidades` (retornam `posicao` = centro); `conexoes_entidade` (`[]EntidadeID` com temp allocator); `conexoes_limpar`; `conexao_sob_mouse` e `conexoes_renderizar` (linhas centro-a-centro com highlight de hover).

**`gui.odin`** — botões na coluna superior-esquerda: "Criar Usuário" (abre modal de nome), "Criar Comutador", "Nova Mensagem" (modal com dropdowns Origem/Destino + `GuiTextBox` + Adicionar/Cancelar), "Exportar"/"Importar" (modal de nome de arquivo anexando `.json`) e "Logs: ON/OFF" (alterna `logs_ativos`). Modal de criação de usuário pré-preenche o nome com `"Usuário N"` (N = `proximo_usuario_id + 1`) via `definir_buffer`; nome vazio usa o automático. Dropdowns desenhados por último (aberto por cima de tudo). `algum_modal_aberto()` cobre todos os modais e bloqueia ações dos botões globais; barra inferior (raygui) com "Iniciar/Pausar" e "Limpar"; helper de mensagem com buffer fixo `[256]u8` + timer (`MENSAGEM_DURACAO :: 2.5`). Ao adicionar mensagem, alimenta `saida` (fila) e `enviadas` (histórico).

**`usuario.odin`** — `UsuarioID :: EntidadeID`; `proximo_usuario_id: u32`; `DELAY_ENTRE_PACOTES :: 0.8`; `Mensagem{id, origem, destino, conteudo}`; `Usuario{alocador, nome, saida, enviadas, entrada, recebidas, envio: EnvioPendente, envio_ativo}`. `usuario_new(nome := "", ...)` (nome personalizado ou `"Usuário N"`). Envio **fragmentado com delay**: `usuario_atualizar_envio(usuario, dt)` move a 1ª mensagem de `saida` para `envio`, envia o 1º fragmento imediatamente e os demais a cada `DELAY_ENTRE_PACOTES`; `usuario_enviar_fragmento` lança um fragmento a todos os vizinhos. `usuario_receber` (dedupe por `(mensagem_id, indice)`, remonta ao completar `total`, move para `recebidas` e chama `notificar_mensagem_recebida`).

**`comutador.odin`** — `ComutadorID :: EntidadeID`; `proximo_comutador_id: u32`; `Comutador{id: u32}` (id sequencial para logs/tabela); `comutador_new`/`comutador_free`.

**`pacote.odin`** — `Pacote{origem, destino: EntidadeID, mensagem_id: u32, indice, total: int, bytes: []rune, historico: [dynamic]EntidadeID, de, para: EntidadeID, progresso: f32, cor: rl.Color}`; `RUNES_POR_PACOTE :: 8`; `pacote_clone` (cópia profunda) e `pacote_free`.

**`simulacao.odin`** — globais `pacotes: [dynamic]Pacote`, `simulacao_ativa`, `proximo_mensagem_id`, `logs_ativos: bool = true`; `VELOCIDADE_PACOTE :: 260.0`, `RAIO_PACOTE :: 7.0`, paleta `CORES_MENSAGEM`; `cor_para_mensagem(id)`. `pacote_enviar` (define salto e enfileira) e `pacote_chegar` (destino → `usuario_receber`; comutador → rota direta se destino é vizinho, senão clona aos vizinhos fora do histórico/`de`); ambos chamam `log_pacote`. `simulacao_atualizar_envios(dt)` avança os envios dos usuários; `simulacao_iniciar` chama com `dt = 0`; `simulacao_atualizar` (avança `progresso`, para sozinho quando termina); `simulacao_tem_pendencia` (considera `saida`, `entrada` e `envio_ativo`); `simulacao_limpar`; `pacotes_renderizar` (círculo interpolado + rastro). `log_pacote(pacote, evento)` imprime no terminal saltos/entregas/flood com `nome_entidade` e histórico.

**`resumo.odin`** — ícone de resumo por Usuário no canto superior-direito do sprite (`sprites[.Resumo]`, `ICONE_RESUMO_TAMANHO :: 14`), com hover. `resumo_processar_clique` abre o modal do usuário sob o clique. `gui_modal_resumo_render` desenha tabela única **Tipo | Contraparte | Conteúdo** combinando `enviadas` (Enviada) e `recebidas` (Recebida), com rolagem pela roda do mouse, recorte por `BeginScissorMode` e botão "Fechar".

**`notificacoes.odin`** — `Notificacao{texto, timer}`; global `notificacoes`; `notificar`, `notificar_mensagem_recebida(nome, conteudo)` (formato `"%s recebeu a mensagem: %s"`), `notificacoes_atualizar` (decai timer e remove), `notificacoes_renderizar` (cartões empilhados no topo-direito, fade) e `notificacoes_limpar`.

**`persistencia.odin`** — importação/exportação do esquema em JSON (`VERSION_ESQUEMA :: 1`). Tipos `TipoEntidade` (`Usuario`/`Comutador`), `EntidadeEsquema{tipo, x, y, nome}`, `ConexaoEsquema{a, b}` (índices) e `Esquema{versao, entidades, conexoes}`. `montar_esquema` mapeia `EntidadeID → índice`; `exportar_esquema` (marshal pretty + `os.write_entire_file`) e `importar_esquema` (`os.read_entire_file` + `json.unmarshal`, `entidades_limpar`, zera contadores de id, recria entidades preservando tipo/posição/nome e refaz as conexões). Wrappers `arquivo_ler`/`arquivo_escrever` isolam a API de `core:os`; `com_extensao_json` anexa `.json`. Mensagens/pendências **não** são persistidas.

## Convenções e pendências

- **Convenção de erro**: procs retornam `ok` (`true` = sucesso); `hm.add` tratado via `err != false`.
- **Contadores globais**: `proximo_usuario_id`, `proximo_comutador_id`, `proximo_mensagem_id` — zerados na importação.
- **Pendências**: melhorias visuais a definir; validar `VERSION_ESQUEMA` na importação e detalhar mensagens de erro de arquivo; revisar `MENSAGEM_DURACAO :: 2.5`.

# Regras gerais
1. Não tente ler arquivos fora do projeto, sob nenhuma hipótese, principalmente os arquivos da biblioteca padrão do Odin ou do Raylib (eles têm documentação na internet para isto).
2. Você está em um ambiente separado do compilador, então não tente chamá-lo ou executá-lo; quem tem essa responsabilidade é o usuário.
3. Evite ler arquivos de forma desnecessária, principalmente os arquivos binários em `sprites/` e `styles/`.
