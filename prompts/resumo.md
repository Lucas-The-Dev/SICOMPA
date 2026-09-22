# SICOMPA — Contexto consolidado e preparação do Item 1

## Visão geral do projeto

**SICOMPA** é um simulador didático de rede de comutação de pacotes, em **Odin** + **Raylib**. Objetivo: visualizar o processo de comutação de forma didática, com pacotes viajando visualmente pelas conexões.

Método de comutação definido: **flooding** (sem otimização de rota). Cada comutador verifica se está conectado ao destino; se não, repassa o pacote aos demais comutadores. Para evitar loops, o `Pacote` precisa carregar a lista de comutadores por onde já passou.

### Estado do código
- `src/main.odin` — entrada; alocador rastreador (debug), handle map de entidades, janela, sprites, loop: `entidades_atualizar` → `entidades_renderizar` → `gui_renderizar`.
- `src/entidade.odin` — `Entidade` (handle, `dados: union{Comutador,Usuario}`, sprite, `posicao`, colisor de mouse, `segurado`), seleção, arraste e render.
- `src/comutador.odin` — `Comutador` vazio.
- `src/usuario.odin` — `Usuario` com `entrada [dynamic]Pacote` e `vizinhos [dynamic]ComutadorID`.
- `src/pacote.odin` — `Pacote{ bytes: []rune }` (a expandir).
- `src/gui.odin` — botões "Criar Usuário"/"Criar Comutador"/"Enviar Mensagem" (vazio) e barra inferior.
- Build: `odin build src -o:speed`; Run: `odin run src -debug`.

## Regras de negócio definidas
- Conexões permitidas: **Usuário↔Comutador** e **Comutador↔Comutador**. Proibido **Usuário↔Usuário**.
- Comutação por **flooding**.
- Simulação **contínua**, com pacotes animados visualmente.
- Persistência: salvar/importar como `output.json` (sem file dialog).
- Conexões: **lista central** como fonte única (ver ponto em aberto sobre formato).

## Correções de base

Já aplicadas pelo usuário:
1. `Entidade.handle` agora é preenchido após o `hm.add`, com tratamento de erro (`nil` em falha).
2. `EntidadesSelecionadas` passou a guardar `EntidadeID` (não ponteiros), com adaptação dos dependentes.
3. Loop de seleção sem `break` — corrigido.
4. (Pendente para o implementador) Padronizar **`posicao` = centro** da entidade; ajustar colisor (`entidade.odin`) e `DrawTextureEx` para desenhar deslocando pela metade do sprite.

Ainda pendente:
- Âncora central (item 4 acima) será implementada por mim.
- Definir destino de `Usuario.vizinhos` (proposto remover).

## Nomes/estruturas acordados

- Novo arquivo `src/conexao.odin`.
- `ConexaoID :: Handle32` (usuário escreveu "ConexoesID"; padronizar `ConexaoID`).
- `Conexao { handle: ConexaoID, a, b: EntidadeID }` (aresta não-direcionada; dedupe checa `(a,b)` e `(b,a)`).
- Lista central `conexoes: [dynamic]Conexao`; deleção por `swap_remove`.
- `criar_conexao(entidade1, entidade2: ^Entidade)` (substitui `entidades_conectar`).
- `remover_conexoes(id: EntidadeID)` — chamado por `entidade_free` antes de remover a entidade.
- `get_extremidades(conexao) -> (Vector2, Vector2)` (substitui o nome `conexao_pontos`) — centraliza a geometria para render e animação.
- `conexoes_entidade(entidade, alocador := context.temp_allocator) -> []EntidadeID` — retorna IDs (não ponteiros), limpo pelo `free_all` do frame.
- `conexoes_renderizar` — desenha linhas **centro-a-centro** (atrás das entidades; chamar antes de `entidades_renderizar`).
- `pacote_renderizar` — procedimento separado para animar a viagem dos pacotes (itens 2/3).

### Regras de `criar_conexao` (3 recusas)
1. Proibida conexão direta entre dois usuários.
2. Proibidas conexões paralelas entre o mesmo par.
3. Proibida auto-conexão.
Ao recusar, exibir **mensagem rápida em popup na parte inferior da tela**.

### Prioridade do botão direito (regra do usuário)
1. Clicar em entidade → selecionar.
2. Clicar em linha → deletar linha.
3. Clicar em local vazio → cancelar seleção.
4. Clicar em linha enquanto há seleção pendente → mensagem informando que está em modo de seleção e não pode apagar.

Outros acordos:
- Feedback visual de **seleção pendente** (highlight na 1ª entidade selecionada).
- Feedback visual no **hover da conexão**.
- Deletar linha via `rl.CheckCollisionPointLine(point, p1, p2, threshold)` (~8px).
- **Esc não será usado** (fecha a app por padrão no Raylib); cancelamento de seleção só pelo clique vazio.
- Manter o nome `entidades_selecionadas` (o usuário considera `selecao_conexao` ambíguo).

## Itens futuros (decididos)
- **Item 2 (mensagens):** modal de texto (origem/destino/conteúdo) reaproveitando a seleção; `Pacote` ganha `origem`, `destino: EntidadeID` e `visitados: [dynamic]EntidadeID`; flooding por comutador.
- **Item 3 (simulação):** flag global `simulacao_ativa`; botões "Iniciar"/"Pausar" na barra inferior; `pacote_renderizar` só avança quando ativa.
- **Item 4 (persistência):** schema JSON (tipo/posição das entidades + conexões) com `core:encoding/json`; salvar/importar em `output.json`.

## Pontos em aberto (confirmar antes de implementar)

1. **Formato da fonte única de conexões:** você pediu `conexoes: [dynamic]Conexao` (item 1), mas a última frase diz "manter apenas o **Handle Map** de conexões" (mensagem truncada em *"Handle Map de conex~"*). Qual vale — lista dinâmica com `ConexaoID`, ou um handle map de conexões?
2. **`Usuario.vizinhos`**: remover (redundante com a lista central) ou manter?
3. Sua mensagem foi **truncada** no final; confirmar o restante do ponto sobre `Entidade.conectados`/handle map.
4. Linhas **centro-a-centro** confirmadas (atrás dos ícones)?
