# Journal Customizado — Plano Tecnico de Implementacao

> Este documento substitui a versao anterior de design amplo por um plano tecnico de implementacao incremental. O foco agora e construir o mod em etapas pequenas, cada uma validavel por si so, mantendo o progresso de quest no engine e usando o renderer nativo de livro como interface principal do diario.

---

## 1. Nome, escopo e decisoes de base

### 1.1 Nome do primeiro mod

- Nome visivel do pacote: `Mod 1 - Journal Customizado`
- Namespace tecnico inicial: `journal_custom`
- Pasta Lua inicial: `MWSE/mods/journal_custom/`

**Decisao:** o primeiro mod passa a usar o identificador tecnico `journal_custom`, com pasta e metadata autocontidos. O nome visivel do pacote continua `Mod 1 - Journal Customizado`.

### 1.2 Escopo do sistema

O mod tera duas camadas diferentes:

- **Engine journal**: continua sendo a fonte da verdade para progresso de quest, `tes3.getJournalIndex`, compatibilidade com scripts e estado do savegame.
- **Journal do mod**: passa a ser a fonte da verdade para leitura, edicao, busca, tags, filtros, ordem visual e notas do jogador, com estado persistente embutido no save atual.

### 1.3 Decisoes arquiteturais que nao devem mudar

1. O jogador nao usara o `MenuJournal` vanilla como UI principal.
2. O visual principal sera o renderer nativo de livro via `tes3ui.showBookMenu`.
3. O journal do mod nao depende de duplicar entradas no journal vanilla por padrao.
4. O estado persistente do journal do mod, embutido no save atual, e a unica fonte da verdade para o que sera exibido, editado, apagado ou reorganizado.
5. A UX final de edicao fica em aberto ate a Fase 7 estabilizar; as opcoes atuais sao edicao no proprio journal ou em um editor modal dedicado.
6. O desenvolvimento sera incremental, com feature flags e validacao por fase.

---

## 2. Fluxo final do sistema

```text
[Quest progride no engine]
        ↓
[tes3.event.journal]
        ↓
[journal.capture registra/atualiza entry no estado em memoria do journal do save]
        ↓
[Jogador pressiona a tecla de journal]
        ↓
[journal.compat bloqueia MenuJournal vanilla]
        ↓
[journal.book abre MenuBook com HTML gerado a partir do estado atual do journal]
        ↓
[journal.mapping coleta blocos visiveis da pagina]
        ↓
[journal.input controla selecao navegavel no spread aberto]
        ↓
[fase futura de edicao decide entre journal ou modal]
        ↓
[journal.data atualiza o estado em memoria do save atual]
        ↓
[journal.book reconstroi o livro preservando contexto]
        ↓
[tes3.event.save sincroniza as alteracoes confirmadas no savegame]
```

---

## 3. Metodo de desenvolvimento incremental

### 3.1 Principio geral

Cada fase deve cumprir quatro requisitos:

1. **Entrega pequena**: uma capacidade nova, nao um pacote grande de features.
2. **Observabilidade**: log claro, estado persistido e comportamento visivel.
3. **Rollback simples**: se a fase der errado, uma flag desliga o comportamento novo.
4. **Validacao local**: deve existir um jeito barato de provar se a fase funciona antes de continuar.

### 3.2 Feature flags obrigatorias

O `config.lua` deve nascer com flags de rollout. Elas reduzem risco e tornam cada fase testavel.

```lua
return {
    debugLogging = true,
    enableVanillaJournalBlock = false,
    enableBookMode = false,
    enableMigration = false,
    enableSelection = false,
    enableEditMode = false,
    enableSearch = false,
    enableCustomOrder = false,
    syncPlayerNotesToVanilla = false,
}
```

### 3.3 Estrategia de validacao por fase

Cada fase deve ter:

- **Validacao em editor**: sem erros novos nos arquivos tocados, nomes corretos, referencias atualizadas.
- **Validacao em jogo**: comportamento observavel com passos manuais curtos.
- **Sinal de falha**: criterio objetivo que impede avancar para a proxima fase.

---

## 4. Estrutura de modulos

```text
MWSE/mods/journal_custom/
├── main.lua
├── config.lua
├── mcm.lua
├── journal/
│   ├── capture.lua
│   ├── migrate.lua
│   ├── data.lua
│   ├── render.lua
│   ├── mapping.lua
│   ├── book.lua
│   ├── input.lua
│   ├── search.lua
│   ├── order.lua
│   └── compat.lua
└── util/
    ├── logger.lua
    ├── text.lua
    └── date.lua
```

---

## 5. Plano tecnico por arquivo

## 5.1 `main.lua`

### Responsabilidades

- carregar configuracao
- inicializar logger
- registrar eventos globais
- conectar modulos sem colocar logica de negocio aqui

### API esperada

```lua
local config = require("journal_custom.config")
local logger = require("journal_custom.util.logger")
local capture = require("journal_custom.journal.capture")
local compat = require("journal_custom.journal.compat")
local book = require("journal_custom.journal.book")

local function initialized()
    capture.register()
    compat.register(book.open)
end
```

### Regras

- `main.lua` nao serializa o journal diretamente; ele apenas coordena o commit antes do save
- `main.lua` nao monta HTML
- `main.lua` nao manipula pagina do livro diretamente

### Validacao local

- o log do MWSE deve mostrar um unico `Inicializado.`
- nenhuma dependencia circular deve aparecer ao carregar o mod

---

## 5.2 `config.lua`

### Responsabilidades

- declarar defaults
- carregar e salvar configuracao persistente
- expor feature flags e keybinds

### API publica

```lua
local M = {}

function M.getDefaults() end
function M.load() end
function M.save(state) end

return M
```

### Estrutura recomendada

- `settings` para UI e keybinds
- `featureFlags` para rollout incremental
- `schemaVersion` para futuras migracoes de config

### Validacao local

- alterar uma flag e confirmar que ela persiste em JSON
- abrir e fechar o jogo sem perder a configuracao

---

## 5.3 `mcm.lua`

### Responsabilidades

- expor keybinds
- expor feature flags de debug e rollout
- expor opcoes de busca, ordenacao e sincronizacao opcional com vanilla

### API publica

```lua
local M = {}

function M.register(configModule) end

return M
```

### Escopo inicial

Na primeira versao, o MCM nao precisa expor tudo. O minimo necessario:

- keybind do diario
- `enableVanillaJournalBlock`
- `enableBookMode`
- `enableEditMode`
- `debugLogging`

### Validacao local

- mudar keybind e verificar que o mod respeita o binding novo
- desligar flag e confirmar que o comportamento some sem editar codigo

---

## 5.4 `util/logger.lua`

### Responsabilidades

- centralizar prefixo de log
- oferecer funcoes `debug`, `info`, `warn`, `error`
- respeitar a flag `debugLogging`

### API publica

```lua
local M = {}

function M.get() end
function M.debug(...) end
function M.info(...) end
function M.warn(...) end
function M.error(...) end

return M
```

### Validacao local

- com `debugLogging = true`, logs detalhados aparecem
- com `debugLogging = false`, apenas logs importantes permanecem

---

## 5.5 `util/text.lua`

### Responsabilidades

- sanitizar texto para HTML de livro
- remover markup proprietario do journal quando necessario
- gerar chaves de ancoragem para mapeamento de blocos visiveis

### API publica

```lua
local M = {}

function M.sanitizeBookText(text) end
function M.stripJournalMarkup(text) end
function M.buildAnchorKey(text) end
function M.normalizeWhitespace(text) end

return M
```

### Regras

- `sanitizeBookText` nunca deve retornar `nil`
- todo texto renderizado no livro deve terminar sendo compativel com `showBookMenu`
- `buildAnchorKey` deve ser deterministico

### Validacao local

- passar texto com `<`, `>`, `&`, `@Topic#` e quebras de linha
- confirmar que a saida renderiza e nao quebra o livro

---

## 5.6 `util/date.lua`

### Responsabilidades

- construir data de exibicao para entradas novas
- gerar strings de fallback para entradas migradas

### API publica

```lua
local M = {}

function M.buildCurrentDisplayDate() end
function M.buildUnknownDisplayDate() end

return M
```

### Validacao local

- chamar em dias/meses diferentes
- confirmar que formato e estavel e legivel

---

## 5.7 `journal/data.lua`

### Responsabilidades

- carregar o journal persistido dentro do save atual
- manter um estado de sessao em memoria para selecao, cache e contexto efemero
- preparar o snapshot persistente do journal quando o jogo salvar
- criar, atualizar, apagar logicamente e ordenar entries
- expor consultas de alto nivel para render, busca e input

### Fonte da verdade

Este modulo e o nucleo do sistema. Nenhum outro modulo deve modificar `state.entries` diretamente. O journal persistido vive no save atual; o modulo pode manter campos efemeros em memoria durante a sessao, mas apenas o subconjunto persistente entra no savegame.

### API publica

```lua
local M = {}

function M.load() end
function M.save() end
function M.getState() end
function M.getEntry(id) end
function M.getEntries() end
function M.upsertEngineEntry(entry) end
function M.createPlayerEntry(params) end
function M.updateEditedText(id, text) end
function M.markDeleted(id, deleted) end
function M.setCustomOrder(id, order) end
function M.setLastKnownPage(id, page) end
function M.setSelectedEntry(id) end

return M
```

### Invariantes

- todo `entry.id` e unico
- `editedText` existe para toda entry visivel
- `source` so pode ser `engine` ou `player`
- `deleted = true` nunca remove fisicamente a entry do estado persistido do save

### Validacao local

- criar entry do jogador, salvar o jogo e recarregar
- editar entry, salvar o jogo e confirmar persistencia
- marcar deletada e confirmar que a entry permanece no estado persistido

---

## 5.8 `journal/capture.lua`

### Responsabilidades

- escutar `tes3.event.journal`
- transformar evento do engine em entrada no estado em memoria do journal do save
- evitar duplicatas quando uma mesma quest atualizar varias vezes

### API publica

```lua
local M = {}

function M.register() end
function M.buildEntryFromJournalEvent(e) end

return M
```

### Regras

- esta fase nao escreve no journal vanilla
- esta fase nao abre livro
- esta fase nao depende de UI

### Validacao local

- completar uma etapa de quest no jogo
- verificar log de captura
- verificar se o estado persistente do save recebeu `questId`, `questIndex`, `originalText`, `editedText`, `daysPassed`

---

## 5.9 `journal/migrate.lua`

### Responsabilidades

- importar entries antigas quando o mod for instalado em save existente
- registrar `migrationDone`
- nunca reimportar duas vezes o mesmo conjunto

### API publica

```lua
local M = {}

function M.needsMigration(state) end
function M.run() end
function M.importDialogue(dialogue) end

return M
```

### Regras

- acessar `info.text` uma unica vez por entry durante a migracao
- salvar progresso em batches se a migracao for longa
- nunca presumir data real da entrada migrada

### Validacao local

- usar save com quests antigas
- rodar migracao
- confirmar que `migrationDone` foi marcado
- confirmar que abrir o livro mostra entries antigas

---

## 5.10 `journal/render.lua`

### Responsabilidades

- converter entries persistidas do save em HTML valido para `showBookMenu`
- aplicar modo de visualizacao: diario, quests, busca, filtrado
- construir cabecalhos, separadores e blocos coerentes

### API publica

```lua
local M = {}

function M.renderBook(entries, context) end
function M.renderEntry(entry, context) end
function M.renderHeader(entry, context) end

return M
```

### Regras

- sempre terminar o HTML com `<br>`
- nunca inserir texto do jogador sem sanitizacao
- manter a renderizacao deterministica para o mesmo conjunto de entries

### Validacao local

- abrir livro com 1 entry, 10 entries e 100 entries
- confirmar que o livro abre sem quebrar o renderer
- confirmar que texto com caracteres especiais nao some

---

## 5.11 `journal/mapping.lua`

### Responsabilidades

- coletar blocos visiveis de `MenuBook_page_1` e `MenuBook_page_2`
- mapear elementos visiveis para `entryId` e `field`
- manter `lastKnownPage` e cache minimo de paginas visitadas

### API publica

```lua
local M = {}

function M.collectVisibleBlocks(menu, state) end
function M.findBlockByEntryId(blocks, entryId) end
function M.updatePageCache(state, pageNumber, blocks) end

return M
```

### Regras

- mapping nunca altera texto persistido
- mapping depende do livro aberto e deve ser recalculado a cada page turn
- heuristicas de chave devem ser simples e previsiveis

### Validacao local

- abrir livro, virar paginas e verificar que o modulo registra `entryId -> page`
- confirmar que a selecao volta para uma entry conhecida apos rebuild

---

## 5.12 `journal/book.lua`

### Responsabilidades

- abrir o livro via `tes3ui.showBookMenu`
- fechar via `tes3ui.closeBookMenu`
- reconstruir o livro preservando contexto
- disparar recolha de mapping apos abertura e virada de pagina

### API publica

```lua
local M = {}

function M.open() end
function M.close() end
function M.rebuild(preserveContext) end
function M.restoreContext() end
function M.goToEntry(entryId) end

return M
```

### Regras

- `open()` nunca deve depender do `MenuJournal`
- `rebuild()` deve ser idempotente
- `preserveContext` deve tentar restaurar entry selecionada, pagina conhecida e modo atual

### Validacao local

- abrir o livro pelo keybind
- virar algumas paginas e confirmar que o rebuild preserva contexto relevante
- forcar rebuild apos selecao, troca de pagina ou mudanca de contexto
- fechar e reabrir sem perder estado relevante

---

## 5.13 `journal/input.lua`

### Responsabilidades

- capturar teclado para selecao navegavel dentro do spread visivel
- mover selecao entre entries visiveis no spread aberto
- resolver transicoes de selecao ao trocar pagina ou spread
- expor ganchos para futura edicao sem decidir ainda entre journal ou modal
- impedir que a selecao vaze para blocos fora do spread atual

### API publica

```lua
local M = {}

function M.ensure(menu) end
function M.resolveSelection(blocks, selectedEntryId, selectedSpreadStart) end
function M.moveSelection(blocks, selectedEntryId, direction) end
function M.beginEdit(entryId, block) end
function M.commitEdit() end
function M.cancelEdit() end
function M.onKeyDown(e, blocks, selectedEntryId) end
function M.onKeyPress(e, blocks, selectedEntryId) end

return M
```

### Regras

- a selecao navegavel so funciona dentro dos blocos explicitamente visiveis no spread aberto
- ao trocar pagina ou spread, a selecao deve ser limpa ou revalidada
- a decisao entre edicao no proprio journal e editor modal permanece em aberto ate o fim da Fase 7
- o destaque visual deve apontar para o texto correto da entry, nao para rotulos tecnicos repetidos

### Validacao local

- selecionar a primeira entry visivel
- navegar para uma entry do meio e para a ultima entry visivel
- trocar pagina e confirmar limpeza ou revalidacao da selecao
- confirmar que a selecao nao vaza para fora do spread aberto

---

## 5.14 `journal/search.lua`

### Responsabilidades

- pesquisar no estado persistido do save, nao no texto visivel da pagina
- manter resultados em memoria
- navegar para o proximo ou anterior resultado

### API publica

```lua
local M = {}

function M.setQuery(query) end
function M.getResults() end
function M.nextResult() end
function M.prevResult() end
function M.clear() end

return M
```

### Regras

- busca deve usar `editedText`
- filtros e modos visuais devem ser respeitados
- navegar para resultado deve reaproveitar `journal.book.goToEntry`

### Validacao local

- buscar texto presente em uma entry distante
- confirmar que o livro navega ate ela
- confirmar wrap-around para proximo/anterior resultado

---

## 5.15 `journal/order.lua`

### Responsabilidades

- ordenar entries para exibicao
- suportar ordem cronologica, por quest e ordem custom
- preparar base para filtros por tag e tipo

### API publica

```lua
local M = {}

function M.getRenderableEntries(state, mode) end
function M.moveEntryBefore(entryId, otherEntryId) end
function M.moveEntryAfter(entryId, otherEntryId) end
function M.rebuildCustomOrder(entries) end

return M
```

### Regras

- reordenacao afeta apenas a exibicao do journal do mod
- ordem interna do engine nao e alterada

### Validacao local

- mover uma nota do jogador para cima e para baixo
- reabrir livro e confirmar persistencia da ordem

---

## 5.16 `journal/compat.lua`

### Responsabilidades

- interceptar keybind do journal
- suprimir `MenuJournal` vanilla quando habilitado
- ser o unico modulo que conhece essa camada de compatibilidade

### API publica

```lua
local M = {}

function M.register(openBookCallback) end
function M.registerKeybindRedirect(openBookCallback) end
function M.registerVanillaJournalSuppression() end

return M
```

### Regras

- suprimir `MenuJournal` so quando `enableVanillaJournalBlock = true`
- durante desenvolvimento, deve ser possivel desligar esta camada rapidamente

### Validacao local

- com flag desligada, o vanilla abre normalmente
- com flag ligada, a tecla de journal abre o livro do mod
- se algum sistema tentar abrir `MenuJournal`, ele e destruido sem travar o jogo

---

## 6. Modelo de dados persistido no save

```json
{
  "schemaVersion": 1,
  "migrationDone": false,
  "viewMode": "diary",
  "entries": {
    "entry_001": {
      "id": "entry_001",
      "questId": "ms_caius",
      "questIndex": 10,
      "originalText": "Caius Cosades me deu...",
      "editedText": "O velho me deu ordens estranhissimas.",
      "displayDate": "16 Hearthfire",
      "daysPassed": 23,
      "source": "engine",
      "deleted": false,
      "customOrder": 120,
      "tags": ["mainquest"],
      "lastKnownPage": 8
    }
  }
}
```

### Estado de sessao nao persistido

- `selectedEntryId`
- `lastSearch`
- `pageCache`
- blocos visiveis, selecao temporaria e drafts da modal

### Invariantes obrigatorias

1. `id` sempre unico.
2. `editedText` nunca vazio por acidente; se o usuario apagar tudo, isso precisa ser deliberado.
3. `source` so aceita `engine` ou `player`.
4. `deleted` nunca apaga fisicamente do estado persistido do save.
5. `customOrder` pode ser `nil`, mas quando existir deve ser numerico.
6. `lastKnownPage` e apenas cache persistido por conveniencia; nunca e fonte da verdade.

---

## 7. Roadmap incremental com validacao por etapa

### Lista objetiva dos passos

1. Fase 0 — Fundacao e nome do pacote. Status: concluida.
2. Fase 1 — Persistencia por save sem UI. Status: concluida e validada em jogo.
3. Fase 2 — Captura do engine journal. Status: concluida e validada em jogo.
4. Fase 3 — Redirecionar o keybind sem bloquear vanilla permanentemente. Status: concluida e validada em jogo.
5. Fase 4 — Livro estatico gerado a partir do estado persistido do save. Status: concluida e validada em jogo.
6. Fase 5 — Migracao de saves existentes. Status: pendente.
7. Fase 6 — Mapeamento de blocos visiveis na pagina. Status: pendente.
8. Fase 7 — Selecao navegavel. Status: pendente.
9. Fase 8 — Edicao real, criacao contextual e persistencia em modal dedicado. Status: implementada no codigo; validacao em jogo pendente.
10. Fase 9 — Datas persistidas e entradas de data no estilo vanilla. Status: implementada no codigo; validacao em jogo pendente.
11. Fase 10 — Atalhos finais e help contextual no journal. Status: implementada no codigo; validacao em jogo pendente.
12. Fase 11 — MCM e hardening final. Status: implementada no codigo; validacao em jogo pendente.
13. Fase 12 — Compatibilidade final de paginacao por setas. Status: implementada no codigo; validacao em jogo pendente.
14. Fase 13 — Feedback sonoro de escrita. Status: implementada no codigo; validacao em jogo pendente.

### Decisoes recentes de escopo

- **Foco imediato**: estabilizar as Fases 6 e 7 e endurecer o keybind para nao abrir o journal em contexto de texto, save/load ou dialogo.
- **Escopo da versao 1.0**: fechar as Fases 8 a 13 com modal dedicado, datas editaveis, atalhos descobriveis, MCM basico, paginacao por setas e feedback sonoro de escrita.
- **UX de edicao mantida**: a Fase 8 segue com editor modal dedicado; o `MenuBook` permanece como superficie de leitura, selecao e contexto.
- **Referencias externas**: o Scribo continua como referencia para modal e audio; o MWSE 2.1 Journal vira referencia para o botao de help e para futuras features de imagem; nenhum dos dois resolve sozinho selecao de blocos ou paginacao do `MenuBook`.

### Backlog pos versao 1.0

- Busca sobre o estado persistido do save.
- Ordem custom, tags e filtros.
- Opcao no MCM para a primeira entry de uma nova data sempre comecar na pagina seguinte.
- Insercao de imagens encontradas no jogo, inspirada no MWSE 2.1 Journal.
- Insercao de imagens custom. Proposta: a modal salva um alias ASCII do asset dentro do proprio mod, mais legenda opcional, escala e alinhamento; o renderer resolve esse alias por uma whitelist local e injeta o markup validado no livro.
- MCM para customizar o maximo possivel de formatacao.
- Integracao opcional com consumo de tinta e caderno.
- Opcao no MCM para ocultar entries padrao.
- Opcoes no proprio journal para ocultar entries padrao e/ou entries do jogador.
- Expansao do fluxo de edicao e criacao de entries alem do modal base da 1.0.
- Importação trazer entradas custom, se houver.

### Sugestoes adicionais pos-1.0

- Favoritos e entries fixadas no topo do journal.
- Exportar e importar o journal em texto simples para backup ou migracao manual.
- Snapshots antes de apagar ou reescrever entries, para permitir undo seguro.
- Templates rapidos de nota para viagem, loot, pistas e alquimia.

## Fase 0 — Fundacao e nome do pacote

### Objetivo

Deixar o pacote visivel com o nome correto e preparar a base de modulos.

### Arquivos

- `journal_custom/journal_custom-metadata.toml`
- `main.lua`
- `config.lua`
- `util/logger.lua`

### Entrega

- nome visivel correto
- logger centralizado
- config com feature flags

### Como validar no editor

- metadata com nome correto
- `main.lua` usando o nome novo no logger

### Como validar no jogo

- o log mostra `Mod 1 - Journal Customizado`

### Criterio de pronto

- o mod inicializa e nao faz mais nada alem de logar

---

## Fase 1 — Persistencia por save sem UI

### Objetivo

Criar `journal.data` e provar que o mod consegue ler e manter estado proprio por save, com commit apenas quando o jogo salvar.

### Arquivos

- `journal/data.lua`
- `config.lua`

### Entrega

- estado do journal carregado do save atual
- API de load/save funcionando com commit no evento de save

### Como validar no editor

- sem erros novos nos arquivos Lua tocados

### Como validar no jogo

- iniciar o jogo carrega o mod
- acao debug cria uma nota ficticia no estado em memoria do journal
- salvar o jogo, fechar e abrir o mesmo save preserva a nota

### Criterio de pronto

- o journal e persistido com integridade dentro do save

### Sinal de falha

- alteracoes somem mesmo apos salvar o jogo
- estrutura muda de forma imprevisivel entre saves

---

## Fase 2 — Captura do engine journal

### Objetivo

Persistir cada nova entrada do engine no estado do journal do save sem mexer em UI.

### Arquivos

- `journal/capture.lua`
- `journal/data.lua`

### Entrega

- quest progression gera entries no estado persistido do save

### Como validar no jogo

1. iniciar save de teste
2. acionar uma etapa de quest conhecida
3. verificar log de captura
4. salvar o jogo e confirmar a entry gravada no save carregado depois

### Criterio de pronto

- cada progresso de quest novo gera ou atualiza uma entry coerente

### Sinal de falha

- entries duplicadas em excesso
- `questId` ou `editedText` inconsistentes

---

## Fase 3 — Redirecionar o keybind sem bloquear vanilla permanentemente

### Objetivo

Abrir um ponto de entrada do mod pelo keybind de journal, mas com flag de compatibilidade desligavel.

### Arquivos

- `journal/compat.lua`
- `main.lua`

### Entrega

- tecla de journal chama callback do mod
- suppression controlada por flag

### Como validar no jogo

- flag desligada: journal vanilla abre
- flag ligada: callback do mod executa e o vanilla nao abre

### Criterio de pronto

- comportamento alterna corretamente pela flag

---

## Fase 4 — Livro estatico gerado a partir do estado persistido do save

### Objetivo

Provar que o journal do mod pode ser lido como livro nativo.

### Arquivos

- `journal/render.lua`
- `journal/book.lua`
- `util/text.lua`

### Entrega

- `showBookMenu` abre com HTML do journal do save atual

### Como validar no jogo

- pressionar journal com `enableBookMode = true`
- livro abre com 1, 10 e 50 entries
- pagina seguinte e anterior funcionam

### Criterio de pronto

- o livro abre sem quebrar e o texto e legivel

### Sinal de falha

- livro em branco
- renderizacao quebrada por HTML invalido

---

## Fase 5 — Migracao de saves existentes

### Objetivo

Importar diario anterior ao mod.

### Arquivos

- `journal/migrate.lua`
- `journal/data.lua`

### Entrega

- entries antigas aparecem no livro do mod

### Como validar no jogo

- usar save com quests avancadas
- rodar migracao uma unica vez
- confirmar `migrationDone`

### Criterio de pronto

- livro passa a refletir o historico antigo do save

### Sinal de falha

- migracao roda toda vez
- texto importado quebra o livro

---

## Fase 6 — Mapping de blocos visiveis

### Objetivo

Saber qual entry esta visivel em cada pagina e comecar a selecionar blocos.

### Arquivos

- `journal/mapping.lua`
- `journal/book.lua`

### Entrega

- lista `visibleBlocks`
- `lastKnownPage` atualizado

### Como validar no jogo

- abrir livro
- virar varias paginas
- confirmar no log quais `entryId`s estao visiveis

### Criterio de pronto

- o mod sabe localizar uma entry na pagina aberta com confianca razoavel

---

## Fase 7 — Selecao navegavel

### Objetivo

Permitir selecao por teclado entre entries explicitamente visiveis no spread aberto, com destaque visual confiavel e transicoes claras entre paginas.

### Arquivos

- `journal/input.lua`
- `journal/mapping.lua`
- `journal/book.lua`

### Entrega

- selecao por teclado restrita as entries explicitamente visiveis no spread aberto
- desselecao ao trocar spread ou pagina
- destaque visual aplicado ao texto correto da entry, nao a rotulos tecnicos repetidos
- suporte a casos em que a primeira linha visivel da entry nao comeca pelo identificador tecnico

### Como validar no jogo

1. selecionar a primeira entry visivel do spread aberto
2. navegar para a proxima, para uma entry intermediaria e para a ultima entry visivel
3. virar pagina e confirmar desselecao
4. voltar para o spread anterior e confirmar que nao ha selecao residual em bloco errado
5. confirmar que o destaque visual acompanha o texto correto da entry, nao uma linha tecnica repetida

### Criterio de pronto

- a selecao navegavel funciona sem corromper o estado visual do livro
- a desselecao ao trocar pagina e correta
- o destaque visual e confiavel mesmo quando a primeira linha visivel nao mostra o identificador tecnico completo

### Sinal de falha

- a selecao vaza para blocos ocultos ou para outro spread
- trocar pagina deixa selecao residual
- o destaque visual aponta para o primeiro rotulo repetido da pagina, e nao para o texto da entry

---

## Fase 8 — Edicao real, criacao contextual e persistencia

### Objetivo

Implementar o fluxo real de edicao, criacao, apagar e rebuild do livro preservando contexto, usando editor modal dedicado e insercao relativa a partir da entry selecionada.

### Arquivos

- `journal/input.lua`
- `journal/data.lua`
- `journal/book.lua`
- `journal/editor.lua`

### Entrega

- modal abre a partir da entry selecionada
- texto inicial do modal reflete `editedText`
- `Shift+N` abre uma nota nova do jogador no mesmo fluxo modal
- a insercao padrao cria a nota depois da entry selecionada
- a modal oferece uma acao explicita para inserir a nova nota antes da entry selecionada
- salvar edicao
- cancelar edicao com rollback visual
- apagar via soft delete no journal do mod
- reabrir livro perto da mesma regiao

### Como validar no jogo

- iniciar edicao em uma entry selecionada
- apertar `Shift+N` e criar uma nota nova do jogador
- salvar uma nota nova e confirmar que ela entrou depois da entry selecionada
- usar a acao de inserir antes e confirmar que a nota entra na posicao anterior
- confirmar que o rascunho do modal nao persiste cedo demais
- salvar a edicao, salvar o jogo e confirmar persistencia no save
- cancelar e confirmar rollback visual
- apagar entry e confirmar que desaparece do journal do mod, nao do engine
- confirmar que o livro reabre proximo da entry editada ou apagada

### Criterio de pronto

- fluxo completo de selecao -> criacao/edicao -> persistencia ou rollback e confiavel

---

## Fase 9 — Datas persistidas e entradas de data no estilo vanilla

### Objetivo

Transformar a data em um tipo de conteudo de primeira classe no journal do mod, persistindo a data do jogo para entries do engine e do jogador e permitindo criar, editar e apagar entradas de data.

### Arquivos

- `journal/data.lua`
- `journal/capture.lua`
- `journal/render.lua`
- `journal/book.lua`
- `journal/editor.lua`

### Entrega

- entries vindas do engine e criadas pelo jogador salvam a data do jogo em que foram inseridas
- a primeira nota inserida em um novo dia cria ou garante uma entry de data como no journal vanilla
- a entry de data fica a uma linha da primeira nota do dia e a duas linhas da entrada anterior
- `Shift+D` abre o fluxo para inserir uma entry de data com data escolhida
- a entry de data pode ser selecionada, editada e apagada
- a entry de data usa a mesma formatacao visual do journal original

### Organizacao recomendada para o agente

- separar **stamp real capturado** de **label visual**: `calendarDay`, `calendarMonth`, `calendarYear`, `daysPassed` e `dateKey` definem a data real; o texto visivel da data fica derivado disso ou em override explicito quando o jogador editar a entry de data
- tratar entries de data em dois grupos: `auto` para cabecalhos gerados a partir da primeira nota real de um dia, e `manual` para entries criadas por `Shift+D`
- entries antigas herdadas de saves sem stamp real nao devem ganhar data retroativa; so entries capturadas depois desta fase entram no fluxo automatico de datas
- o formato visual padrao das datas deve seguir o journal vanilla: `28 Last Seed (Day 13)`; o horario e o dia da semana do menu de rest nao entram no journal nesta fase
- `Shift+J` deve ser excecao de compatibilidade, abrindo o `MenuJournal` vanilla sem desmontar a interceptacao normal do keybind `J`

### Como validar no jogo

- inserir a primeira nota de um novo dia e confirmar que a data aparece uma unica vez
- inserir outra nota no mesmo dia e confirmar que a data nao duplica
- criar uma entry de data com `Shift+D`, editar, apagar e confirmar que o fluxo funciona
- salvar o jogo, recarregar e confirmar que as entries do engine e do jogador preservam a data do jogo em que foram inseridas

### Criterio de pronto

- a camada de datas se comporta como conteudo persistido de primeira classe e fica visualmente coerente com o journal vanilla

---

## Fase 10 — Atalhos finais e help contextual no journal

### Objetivo

Fechar os atalhos da 1.0 e torna-los descobriveis dentro do proprio journal, reduzindo conflito com digitacao normal e deixando o fluxo autoexplicativo.

### Arquivos

- `journal/input.lua`
- `journal/book.lua`
- `journal/editor.lua`
- `journal/render.lua`

### Entrega

- `Shift+N` substitui `N` como atalho oficial para nova nota
- `Shift+D` abre o fluxo de data escolhida
- o journal passa a exibir um botao de help com os atalhos disponiveis
- o botao de help toma como referencia o padrao visual do MWSE 2.1 Journal, adaptado ao `journal_custom`
- o texto de ajuda cobre criacao, insercao antes/depois, edicao, apagar, salvar e cancelar

### Como validar no jogo

- confirmar que `N` sozinho nao cria mais nota nova
- confirmar que `Shift+N` e `Shift+D` disparam os fluxos corretos
- abrir o help e verificar que os atalhos listados batem com o comportamento real
- confirmar que o help fica acessivel sem quebrar a leitura do livro

### Criterio de pronto

- os atalhos ficam descobriveis, coerentes com a UX da 1.0 e sem colidir com digitacao normal

---

## Fase 11 — MCM e hardening final

### Objetivo

Expor configuracoes finais da 1.0 e endurecer a compatibilidade para que o mod seja seguro em contextos de UI concorrentes.

### Arquivos

- `mcm.lua`
- `journal/compat.lua`
- `journal/book.lua`
- `journal/input.lua`

### Entrega

- MCM usavel
- logs reduzidos
- flags maduras
- keybind do journal ignorado com seguranca durante digitacao, save/load, dialogo e menus equivalentes
- rebuilds internos do `MenuBook` sem efeitos colaterais de som ou reabertura inesperada

### Como validar no jogo

- alterar keybinds
- desligar features por MCM
- confirmar que cada parte pode ser desligada sem quebrar o mod
- abrir a tela de save e confirmar que `J` volta a ser digitacao normal
- abrir dialogo com NPC e confirmar que o journal nao abre em cima da conversa
- mover a selecao no livro e confirmar que nao toca som de abrir journal a cada rebuild

### Criterio de pronto

- mod utilizavel sem editar codigo

---

## Fase 12 — Compatibilidade final de paginacao por setas

### Objetivo

Garantir que o livro do journal_custom responda de forma confiavel as setas esquerda e direita para trocar de pagina.

### Arquivos

- `journal/book.lua`
- `journal/compat.lua`
- `journal/mapping.lua`

### Entrega

- seta esquerda volta pagina
- seta direita avanca pagina
- mapping continua coerente apos a troca de pagina por teclado
- selecao e entradas de data continuam coerentes apos a troca de pagina

### Como validar no jogo

- abrir o livro do journal_custom
- usar seta direita para avancar varias paginas
- usar seta esquerda para voltar
- confirmar no log que o mapping continua mudando com a pagina aberta
- confirmar que a selecao nao fica presa em entry invisivel apos a paginacao

### Criterio de pronto

- a navegacao por setas funciona sem quebrar o livro, sem corromper o texto e sem perder o contexto atual

---

## Fase 13 — Feedback sonoro de escrita

### Objetivo

Adicionar um som de pena escrevendo enquanto o jogador estiver no fluxo de escrita, reforcando o feedback imersivo.

### Arquivos

- `journal/input.lua`
- `journal/book.lua`
- `journal_custom` assets de som, se necessario

### Entrega

- som curto de escrita ao digitar
- inicio e parada coerentes com o fluxo de escrita
- nenhuma repeticao agressiva ou sobreposicao quebrada de audio
- rebuilds silenciosos do livro, com o feedback focado na escrita e nao na reabertura do journal

### Como validar no jogo

- abrir uma entry no fluxo de escrita
- digitar continuamente por alguns segundos
- parar de digitar
- confirmar que o som acompanha a escrita e para sem ficar preso tocando
- confirmar que salvar, cancelar ou mover o cursor nao reapresenta som de abrir journal em loop

### Criterio de pronto

- o feedback sonoro reforca a escrita sem incomodar, sem vazar apos sair do fluxo de escrita e sem degradar a responsividade

---

## 8. Matriz de validacao continua

Esta matriz deve ser rodada sempre que uma fase tocar o comportamento correspondente.

| Area | Validacao minima |
|---|---|
| Persistencia | save grava, recarrega e preserva invariantes do journal |
| Captura | nova quest update aparece no journal persistido do save |
| Keybind | o binding do journal aciona o mod corretamente e nao dispara em contexto inseguro |
| Livro | abre, pagina e responde as setas sem tela vazia |
| Mapping | `selectedEntryId` aponta para bloco visivel coerente |
| Edicao | preview, inserir antes/depois, salvar e cancelar funcionam |
| Datas | a primeira nota do dia gera a entry de data correta e sem duplicacao |
| Atalhos e help | `Shift+N`, `Shift+D` e o help refletem o comportamento real |
| Audio | som de escrita acompanha digitacao, para corretamente e nao reabre o journal por audio |
| Delecao | entry some do journal do mod e continua existindo no engine |
| Compatibilidade | desligar flags retorna a um comportamento seguro |

---

## 9. O que nao fazer

1. Nao usar o `MenuJournal` como base da experiencia principal; o renderer de livro e o alvo visual correto.
2. Nao tratar o livro como fonte de verdade; a fonte de verdade e o estado persistente do journal no save atual.
3. Nao duplicar tudo no journal vanilla por padrao; isso complica mais do que ajuda.
4. Nao implementar varias features novas na mesma fase; cada etapa precisa ter validacao curta e barata.
5. Nao salvar texto do jogador sem sanitizacao de HTML.
6. Nao prosseguir para a fase seguinte se a atual ainda exigir debug manual frequente.

---

## 10. Resultado esperado na versao 1.0

Ao final da versao 1.0, o jogador tera:

- um diario com visual nativo de livro
- entradas do jogo capturadas automaticamente
- notas proprias
- edicao e criacao por modal dedicado, com insercao contextual antes ou depois da selecao
- datas persistidas e entradas de data editaveis, no estilo do journal vanilla
- atalhos descobriveis por help dentro do proprio journal
- MCM basico para operacao sem editar codigo
- paginacao confiavel por setas
- feedback sonoro de escrita sem sons espurios de reabertura
- delecao visual segura

E o projeto tera:

- modulos pequenos e isolados
- APIs claras por arquivo
- fases implementaveis uma por vez
- caminho de validacao objetivo para nao perder controle durante o desenvolvimento
- backlog pos-1.0 explicito para busca, organizacao, imagens, formatacao avancada e integracoes opcionais
