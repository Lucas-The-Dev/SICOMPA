# SICOMPA — Resumo da sessão (Fase 1 + correções pós-teste)

## Objetivo
Concluir a **Fase 1 — simulação de envio de pacotes entre usuários** (flooding com animação) e aplicar as correções levantadas no primeiro teste.

## O que foi implementado

### Núcleo da simulação
- **`pacote.odin`**: `Pacote` passou a representar um fragmento em trânsito:
  `origem`, `destino`, `mensagem_id: u32`, `indice`, `total`, `bytes: []rune`, `historico: [dynamic]EntidadeID`, `de`, `para`, `progresso: f32`, `cor`.
  `RUNES_POR_PACOTE :: 8`; `pacote_clone` (cópia profunda de `bytes` e `historico`) e `pacote_free`.
- **`usuario.odin`**:
  - `Mensagem{id, origem, destino, conteudo: string}`.
  - `Usuario{alocador, nome, saida: [dynamic]Mensagem, entrada: [dynamic]Pacote, recebidas: [dynamic]Mensagem}`.
  - `usuario_enviar`: converte `conteudo` para runes, fatia em blocos de `RUNES_POR_PACOTE` e lança um `Pacote` por vizinho via `pacote_enviar`.
  - `usuario_receber`: dedupe por `(mensagem_id, indice)`, acumula fragmentos em `entrada`; ao completar `total`, remonta a string original e move para `recebidas`, chamando a notificação.
- **`simulacao.odin`** (novo):
  - Globais `pacotes: [dynamic]Pacote`, `simulacao_ativa: bool`, `proximo_mensagem_id: u32`; `VELOCIDADE_PACOTE`, `RAIO_PACOTE`, paleta `CORES_MENSAGEM`.
  - `pacote_enviar` / `pacote_chegar`: helpers de estado/render; **não** tocam a classe `Usuario` (exceto `pacote_chegar`, que chama `usuario_receber` quando o nó atingido é o destino).
  - Flooding: no comutador, se o destino é vizinho direto encaminha só a ele; senão clona para os vizinhos fora de `historico`/`de`.
  - `simulacao_iniciar`: verifica pendências e ativa; `simulacao_atualizar`: escoa `saida`, avança `progresso` e para sozinho ao terminar; `simulacao_limpar`; `pacotes_renderizar` (círculo interpolado + rastro).

### GUI e integração
- **`gui.odin`**: botão **"Nova Mensagem"** com modal (dropdowns Origem/Destino de usuários + `GuiTextBox` + **"Adicionar"**/"Cancelar"); barra inferior como painel raygui com **Iniciar/Pausar** e **Limpar**.
- **`main.odin`**: `simulacao_atualizar()` e `pacotes_renderizar()` no loop; `defer { simulacao_limpar(); delete(pacotes) }`.

## Correções pós-teste

1. **Animação só andava com o mouse em movimento** — causa: `rl.EnableEventWaiting()` (loop dirigido por eventos bloqueava `EndDrawing()`). **Correção:** removido; o loop roda por frame com `SetTargetFPS(180)`.
2. **Nomear usuários** — `Usuario.nome` + `proximo_usuario_id` (auto "Usuário N"); nome desenhado sob o sprite (`entidade_rotulo_renderizar`); dropdowns usam `dados.nome`.
3. **Dropdown aparecia atrás de outros componentes** — `GuiDropdownBox` desenha a lista na hora da chamada. **Correção:** no modal, labels/textbox/botões são desenhados primeiro e os dropdowns por último (o aberto por último de tudo), com guarda para botões/textbox não agirem enquanto um dropdown está aberto.
4. **Feedback de mensagem recebida** — novo **`notificacoes.odin`**: cartões empilhados no canto superior direito, ~4 s, com fade; `usuario_receber` chama `notificar_mensagem_recebida(nome, conteudo)`.

## Ajustes de compilação (feitos pelo usuário, não repetir)
- `CORES_MENSAGEM` virou `@(rodata) [6]rl.Color` (constante não pode ser indexada por variável).
- `make([dynamic]rune, ...)` em `usuario_receber` (ambiguidade do `make`).
- Conversões para `cstring` nos rótulos/botões (`strings.clone_to_cstring`).
- `strings.to_cstring(&b)` sem passar allocator.

## Estado atual
A Fase 1 está **funcional**: criar usuários/comutadores, conectar, adicionar mensagem, iniciar/pausar a simulação, ver os pacotes trafegando em flooding e a notificação de recebimento. Compila com `odin build src -o:speed` / `run.sh`.

## Próximos passos (sessão seguinte)
- **Item 2/4 do roadmap — persistência `output.json`**: exportar **e** importar (tipo/posição das entidades + conexões) com `core:encoding/json`.
- **Melhorias visuais**: escopo ainda a definir pelo usuário.
- Revisar `MENSAGEM_DURACAO :: 0.5` (popup curto).

---

# SICOMPA — Resumo da sessão (importação/exportação + correções pendentes)

## Objetivo
Implementar a persistência do esquema (exportar/importar em JSON) e, antes disso, resolver as pendências deixadas na sessão anterior (`conexoes_limpar`; `entidades_limpar` e textura compartilhada).

## Correções pendentes (feitas primeiro)
- **`conexoes.odin`**: novo `conexoes_limpar()`, que remove todas as conexões (coleta handles e `hm.remove`).
- **`entidade.odin`**:
  - `entidade_free` **não** descarrega mais `rl.UnloadTexture` — a textura é global/compartilhada (`sprites[.Usuario]`/`sprites[.Comutador]`), e descarregá-la quebraria as demais entidades.
  - novo `entidades_limpar()`: chama `simulacao_limpar()`, percorre as entidades liberando `dados` (`usuario_free`/`comutador_free`), remove do handle map, chama `conexoes_limpar()` e zera `entidades_selecionadas`.

## Persistência (`persistencia.odin`, novo)
- **Esquema JSON** (`VERSION_ESQUEMA :: 1`):
  - `TipoEntidade :: enum { Usuario, Comutador }`.
  - `EntidadeEsquema{tipo, x, y, nome}` (nome com `json:"nome,omitempty"`).
  - `ConexaoEsquema{a, b}` referenciando entidades por **índice**.
  - `Esquema{versao, entidades, conexoes}`.
- **`montar_esquema`**: itera o handle map, monta `map[EntidadeID]int` (handle → índice) e serializa as conexões por índice.
- **`exportar_esquema(nome)`**: `json.marshal` (pretty, 4 espaços) + `os.write_entire_file`; notifica no sucesso.
- **`importar_esquema(nome)`**: `os.read_entire_file` + `json.unmarshal`; valida; `entidades_limpar()`; zera `proximo_usuario_id`/`proximo_mensagem_id`; recria entidades preservando tipo, posição e nome (nome clonado no alocador do usuário) e refaz as conexões por índice.
- **Wrappers** `arquivo_ler`/`arquivo_escrever` isolam a API de `core:os`; `com_extensao_json` anexa `.json` se faltar.
- Mensagens e pendências **não** entram no arquivo.

## GUI (`gui.odin`)
- Botões **"Exportar"** e **"Importar"** na coluna superior-esquerda (índices 3 e 4, abaixo de "Nova Mensagem").
- `modal_arquivo_aberto` + `ArquivoModo{Exportar, Importar}` + buffer `arquivo_nome: [256]u8`.
- `gui_modal_arquivo_render`: janela com `GuiTextBox` e botões "Salvar"/"Abrir" e "Cancelar"; título e rótulo mudam conforme o modo.
- `algum_modal_aberto()` (`modal_mensagem_aberto || modal_arquivo_aberto`) impede que os botões globais ajam com um modal aberto.
- `gui_renderizar` passa a chamar `gui_modal_arquivo_render()`.

## Observação de compatibilidade
- Foi usada a API atual de `core:os`: `read_entire_file(name, allocator)` e `write_entire_file(name, data)`, retornando `os.Error`. Em versões antigas (retornos `bool`), o ajuste fica restrito a `arquivo_ler`/`arquivo_escrever`.

## Estado atual
Importação/exportação funcionais: exporta entidades/conexões/nomes para `<nome>.json` na pasta de execução e remonta a tela a partir do arquivo (substituindo o esquema atual). Sem alterações em `main.odin`.

## Próximos passos sugeridos
- Validar `VERSION_ESQUEMA` na importação e detalhar mensagens de erro.
- Melhorias visuais (escopo a definir).
- Rever `MENSAGEM_DURACAO :: 2.5`.
