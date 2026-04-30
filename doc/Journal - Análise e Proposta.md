# Journal de Morrowind — Análise Profunda e Proposta de Mod

---

## 1. Os mods de referência disponíveis

### 1.1 Journal Enhanced (v1.1 — Aerelorn, ~2004)
**Tipo:** ESP + DLL externa (Morrowind Enhanced / MWE)

O mod mais antigo do conjunto. Funcionava antes da era MWSE-Lua: o jogador precisava instalar o executável "Morrowind Enhanced" (um DLL injector pré-MWSE), depois equipar um objeto físico (pena + tinteiro) para abrir um messagebox de digitação. Ao confirmar, a entrada era injetada no journal via script MWScript.

**Limitações técnicas:**
- Limite de ~650 caracteres por entrada (uma página de journal).
- Dependência de ferramenta externa (MWE) que já não existe ativamente.
- A UI era um messagebox — sem campo de texto real, sem edição, sem formatação.
- Lag visível ao digitar rápido (framerate caía com o messagebox ativo).

**Valor histórico:** Primeiro a provar que é possível injetar texto do jogador no journal. Conceitualmente correto, implementação limitada pela tecnologia disponível na época.

---

### 1.2 D-I-Y Journal Keeping (2xStrange, ~2004)
**Tipo:** ESP puro

Deleta o texto de *todas* as entradas de journal do jogo base (Morrowind + Tribunal + Bloodmoon), deixando-as com texto vazio. Quando uma entrada é ativada, o jogo encontra texto vazio e não adiciona nem a data — o journal do jogador fica em branco para ele mesmo escrever, usando o Journal Enhanced.

**Intenção:** Roleplay hardcore — o personagem do jogador escreve o diário do próprio punho.

**Problemas:**
- Depende inteiramente do Journal Enhanced para qualquer funcionalidade.
- Incompatível com a maioria dos mods que adicionam entradas de journal.
- Nenhum componente Lua; puro ESP.

**Valor:** Demonstra um conceito interessante de journal imersivo — o jogador como narrador. Pode inspirar feature de "modo diário" onde entradas automáticas do jogo são escondidas e o foco é o texto do próprio jogador.

---

### 1.3 Update My Journal (KRX — MWSE-Lua moderno)
**Tipo:** MWSE-Lua puro, arquivo único (`main.lua`, ~80 linhas)

O mod mais simples do conjunto. Quando o journal está aberto, registra `keyDown`. Ao pressionar `Alt+Enter`, cria um menu fixo com `tes3ui.createMenu` contendo um `createParagraphInput`. O jogador digita, confirma com `Alt+Enter` novamente, e o texto é salvo via `tes3.addJournalEntry({ text = inputText })`. O journal é fechado e reaberto programaticamente para mostrar a nova entrada.

**Código relevante:**
```lua
inputCapture = inputBlock:createParagraphInput{}
inputCapture.widget.lengthLimit = 450

-- ao salvar:
tes3.addJournalEntry({ text = inputText })
```

**Pontos fortes:**
- Código limpo, didático, boa base para aprender a mecânica.
- Funciona sem ESP, sem dependências.
- Usa a API moderna corretamente.

**Limitações:**
- Limite hardcoded de 450 caracteres.
- Não persiste — entra como entrada permanente do journal (não pode ser editada depois).
- Sem título, sem categoria, sem data customizável.
- Fecha e abre o journal após salvar, o que é visualmente abrupto.
- Sem MCM, sem keybind configurável.

---

### 1.4 MWSE 2.1 Journal Search and Edit (Svengineer99 — SVE)
**Tipo:** MWSE-Lua avançado (`main.lua` ~1600 linhas + `config.lua` + `mcm.lua`)

O mod mais completo do conjunto. O próprio autor adverte no cabeçalho que o código "não é bem otimizado, organizado ou comentado". Apesar disso, a *funcionalidade* implementada é impressionante e revela os limites reais de trabalhar com o journal via MWSE.

**Features implementadas:**
1. **Busca em tempo real** — campo de texto integrado no MenuJournal, busca pelo texto das entradas na página visível, avança páginas automaticamente segurando a tecla.
2. **Edição in-place** — seleciona entradas editáveis na página atual, abre o campo de input com o texto original, salva modificações.
3. **Páginas inseridas** — divide a página atual em duas halvs (esquerda/direita) e injeta uma página customizada do lado oposto.
4. **Inserção de imagens** — imagens coletadas de livros lidos (`BookArt/`) podem ser inseridas nas páginas customizadas com escala ajustável.
5. **Headers com data** — páginas inseridas recebem header automático com dia/mês do in-game.
6. **Compressão de espaços** — reduz o espaçamento excessivo entre entradas de tópicos diferentes.
7. **Ocultação de headers redundantes** — oculta headers de data duplicados na mesma página.
8. **MCM completo** — todos os atalhos são reconfiguraveis, com opção de restaurar defaults.
9. **Persistência via JSON** — edições são salvas em `mwse.saveConfig`/`loadConfig` e reaplicadas cada vez que o journal é aberto.

**Como a persistência funciona:**
```lua
-- Estrutura salva em JSON:
journalEdits = {
    insertedPage = {          -- journal principal
        ["1"] = "texto...",   -- conteúdo da página 1
        ["1H"] = "header...", -- header da página 1
        ["1I"] = { contentPath = "...", width = ..., height = ... }
    },
    insertedPagequests = { ... }, -- aba de quests
    hyperText = { ["topic"] = true }, -- hyperlinks conhecidos
    bookArtImages = { ... },
    customImageScaling = { ["path"] = 1.0 }
}
```

---

## 2. As dificuldades inerentes do journal de Morrowind

Esta é a parte mais importante para definir o escopo do que é viável.

### 2.1 O journal é read-only a nível de engine
`tes3.addJournalEntry()` **adiciona** entradas permanentemente. Não existe API para editar ou deletar uma entrada que já foi adicionada. Qualquer "edição" que um mod faz é uma **ilusão de UI**: o texto verdadeiro da entrada permanece no savegame, e a modificação visível é reaplicada toda vez que o journal é aberto.

A saída adotada por este mod é o **shadow copy**: toda entrada adicionada pelo engine é interceptada via `tes3.event.journal`, copiada como uma entrada do jogador (`source = "engine_copy"`), e a entrada original do engine é ocultada permanentemente na UI. O jogador vê e edita apenas as cópias. O texto original fica salvo em `originalText` no JSON como chave imutável de lookup para o hide.

Consequência: exportar o journal completo exporta apenas as cópias (já com edições do jogador), limpas de notação HTML e hyperlinks.

### 2.2 Renderização page-by-page, sem acesso ao array completo
O journal renderiza suas entradas em páginas de livro. Não há API para "me dê todas as entradas como array". Para buscar no journal inteiro, é preciso paginar programaticamente — virando página por página via `triggerEvent("mouseClick")` nos botões de navegação, o que é lento e visualmente intrusivo (a SVE faz exatamente isso durante busca).

### 2.3 O texto das entradas usa HTML parcial com hyperlinks proprietários
Entradas de journal usam um subconjunto de HTML e a notação proprietária `@TopicName#` para criar hyperlinks de tópico. Qualquer manipulação de string precisa preservar ou reconstruir essa notação, ou hyperlinks quebram. A SVE implementou `restoreHyperLinks()` para lidar com isso.

Caracteres `<` e `>` em texto livre podem corromper a renderização (são interpretados como tags HTML).

### 2.4 A UI do journal não foi projetada para edição
`MenuJournal` é essencialmente um livro somente leitura. Para tornar texto editável, a SVE recorre a uma abordagem de "field overlay": coloca um `ParagraphInput` invisível sobre o texto da página e sincroniza o conteúdo, o que resulta em código complexo e frágil. Não há API de "entra em modo de edição neste elemento".

### 2.5 Limite de comprimento por entrada
`tes3.addJournalEntry` aceita texto longo, mas a *renderização* de uma entrada é limitada pelo tamanho da página do livro. Texto longo transborda para a página seguinte de forma automática, o que fragmenta entradas longas do jogador de forma imprevisível.

### 2.6 Não há índice de entradas do jogador
Entradas adicionadas via `tes3.addJournalEntry` entram em ordem cronológica junto com todas as outras entradas do jogo. Não existe uma "aba" separada para notas pessoais do jogador fora da aba principal do journal.

### 2.7 Fechar/reabrir o journal = perda de estado de UI
Qualquer elemento UI criado dentro do `MenuJournal` é destruído quando o journal fecha. Tudo precisa ser recriado na próxima abertura. Isso torna qualquer feature que precise de estado de UI (como "estava editando a entrada X") complicada de preservar.

---

## 3. O que é possível, o que é difícil e o que é impossível

| Feature | Viabilidade | Observações |
|---|---|---|
| Adicionar novas entradas | ✅ Simples | `tes3.addJournalEntry` |
| Busca em texto | ✅ Possível | Exige paginar UI ou limitar à página atual |
| Edição visual in-place | ✅ Possível | Complexo; SVE prova que funciona |
| Duplicar entrada | ✅ Possível | Copiar texto e chamar `addJournalEntry` |
| Exportar journal para arquivo | ✅ Possível | `io.open` do LuaJIT ou MWSE `lfs` |
| Importar entradas de arquivo | ✅ Possível | Ler JSON/texto e chamar `addJournalEntry` |
| Tags/categorias em entradas | ✅ Possível | Metadados salvos em JSON separado |
| Filtrar por tipo (jogador vs jogo) | ✅ Possível | Marcar entradas do jogador no JSON |
| Atalho para adicionar entrada rapidamente | ✅ Simples | `keyDown` fora do menu |
| Apagar entrada do jogador / cópia de engine | ✅ Simples | Flag `deleted = true` no JSON + hide na abertura |
| Mover entrada para o fim da timeline | ✅ Possível | Delete + re-insert como nova entrada |
| Apagar entrada original do engine | ❌ Impossível | Não existe API; é ocultada pelo shadow copy, não apagada |
| Reordenação para posição histórica arbitrária | ❌ Impossível | Engine não permite inserção retroativa na timeline |
| Aba separada nativa no journal | ❌ Impossível | UI hardcoded no engine |
| Rich text (negrito, itálico, tamanhos) | ❌ Impossível | Renderer do journal não suporta |
| Busca sem paginar o journal | ❌ Impossível | Não há acesso ao array de entradas |
| Undo/Redo robusto | ⚠️ Difícil | Exigiria stack de estados; possível mas custoso |
| Auto-save de rascunho | ✅ Possível | Timer + JSON periódico |
| Múltiplos "cadernos" | ⚠️ Difícil | Pode simular com abas UI customizadas, mas fora do journal nativo |

---

## 4. Proposta: Journal Imersivo — features e arquitetura

Com base na análise acima, segue uma proposta de mod que seria o mais completo e coeso possível dentro das limitações do engine.

### 4.1 Princípio de design
O objetivo não é substituir o journal do jogo, mas **torná-lo um diário real** que o jogador queira abrir e escrever. A ideia central é: **tudo o que o jogador vê é editável**. Entradas do engine são copiadas como shadow copies e ocultadas na fonte; entradas criadas pelo jogador entram diretamente como cópias. Do ponto de vista do usuário não existe distinção — há apenas "o journal", e ele pode editar, apagar e reorganizar qualquer coisa nele.

### 4.2 Features propostas (do mais simples ao mais complexo)

---

#### Feature 1 — Adicionar entrada rápida (dentro ou fora do journal)
**Como funciona:** Tecla configurável (padrão: `Alt+J` fora de menus, ou `N` dentro do journal) abre um overlay compacto com `ParagraphInput`. O jogador digita e confirma. A entrada é salva com `tes3.addJournalEntry` e marcada internamente (JSON) como "entrada do jogador" com timestamp in-game.

**Melhoria sobre Update My Journal:**
- Sem fechar/reabrir o journal.
- Prefixo automático configurável (ex.: "[Nota —]" ou o nome do personagem).
- Limite de comprimento configurável no MCM (padrão: 800 chars).
- Data in-game adicionada automaticamente como prefixo opcional.

---

#### Feature 2 — Busca inteligente
**Como funciona:** Campo de busca sempre visível no topo ou rodapé do journal. Busca nas entradas da página atual com highlight imediato. Teclas `[` e `]` avançam para a ocorrência anterior/próxima. Se não encontrar na página, pagina automaticamente (como SVE, mas mais suave: usa timer com feedback visual).

**Melhoria sobre SVE:**
- Indicador de "X ocorrências encontradas" no total (calculado ao paginar).
- Wrap-around: ao chegar ao fim, volta ao início com aviso.
- Modo "busca só nas minhas notas" (filtra por marcador de entrada do jogador).

---

#### Feature 3 — Edição de qualquer entrada
**Como funciona:** Todas as entradas visíveis no journal são shadow copies do jogador — não há distinção de UI entre "entrada do jogo" e "entrada pessoal". Tecla configurável (padrão: `E`) coloca a entrada sob o cursor em modo de edição (ParagraphInput overlay com o `editedText` atual). Ao salvar, `editedText` é persistido em JSON e reaplicado na próxima abertura do journal. O `originalText` nunca é alterado e serve como chave de lookup para o hide da entrada original do engine.

Fluxo de interceptação no evento `journal`:
```lua
event.register(tes3.event.journal, function(e)
    -- 1. Salva a cópia no JSON com originalText = e.text
    -- 2. Agenda addJournalEntry na próxima frame (não pode chamar durante o evento)
    -- 3. Na abertura do journal, oculta os elementos cujo texto == originalText
end)
```

---

#### Feature 4 — Duplicar entrada do jogador
**Como funciona:** Com entrada do jogador selecionada (modo edição ativo), tecla configurável duplica o texto como nova entrada `tes3.addJournalEntry`, marcada também como "do jogador". Útil para criar variações de uma nota ou fazer cópias de referência.

---

#### Feature 5 — Exportar / Importar (formato texto limpo)
**Como funciona:**

- **Exportar:** No MCM ou por tecla, gera um arquivo `.txt` ou `.json` em `Data Files\MWSE\config\renan\journal\export\` com todas as entradas marcadas como "do jogador" (texto limpo, sem HTML). Pode incluir ou não as entradas do jogo (opção).
- **Importar:** Lê um arquivo `.txt` do mesmo diretório. Cada linha (ou bloco separado por linha em branco) é tratada como uma entrada. O mod pede confirmação antes de inserir.

**Implementação:** `io.open` do LuaJIT, que MWSE expõe diretamente.

```lua
-- Export simplificado
local file = io.open("Data Files\\MWSE\\config\\renan\\journal\\export.txt", "w")
for _, entry in ipairs(playerEntries) do
    file:write("[" .. entry.date .. "]\n" .. entry.text .. "\n\n")
end
file:close()
```

---

#### Feature 6 — Tags e filtragem
**Como funciona:** Ao criar/editar uma entrada, o jogador pode associar uma tag (ex.: "quest", "mapa", "pista", "pessoal"). As tags ficam no JSON de metadados. Uma UI de filtro no journal (botão lateral simples) permite mostrar apenas entradas com determinada tag. Entradas sem tag mostram normalmente.

**Interface:** Botões de filtro horizontais abaixo dos botões de aba do journal (Quests, Tópicos, Main) — adicionados como elementos UI via `uiActivated`.

---

#### Feature 7 — Backup automático
**Como funciona:** Ao salvar o jogo (evento `save`), o mod salva uma cópia do JSON de entradas do jogador em `...journal\backup\save_NomeSalvo.json`. Mantém os últimos N backups (configurável no MCM). Protege contra corrupção acidental.

---

#### Feature 8 — Apagar e reorganizar entradas
**Apagar:**
Tecla configurável (padrão: `Delete`) com confirmação (`Sim/Não`) marca a entrada selecionada com `deleted = true` no JSON. Na próxima abertura do journal, o hide processa tanto a entrada original do engine quanto a cópia do jogador — o par desaparece completamente. A operação é reversível: o dado existe no JSON e uma opção no MCM ("Mostrar entradas apagadas") pode revelar tudo.

**Reorganizar por deleção:**
Apagar entradas intermediárias é a forma natural de reorganizar. Ao ocultar uma entrada entre A e C, essas duas entradas passam a aparecer adjacentes no journal. O fluxo narrativo se fecha sem buracos visíveis.

**Mover para o fim (recortar e colar):**
Com entrada selecionada, tecla `M` (configurável) executa:
1. Marca a entrada como `deleted = true` (some do lugar atual)
2. Cria nova entrada `addJournalEntry` com o mesmo `editedText`, marcada com `movedFrom = "uuid-original"`
3. A nova entrada aparece no fim da timeline com a data atual

**Limitação de reorganização:**
Não é possível inserir uma entrada em uma posição histórica arbitrária (entre o dia 5 e o dia 10 quando hoje é o dia 50). A timeline do engine é estritamente cronológica. "Mover" sempre significa mover para o fim.

---

### 4.3 Arquitetura proposta

```
MWSE/mods/journal_custom/
├── main.lua          — bootstrap, registro de eventos
├── config.lua        — defaults + mwse.loadConfig
├── mcm.lua           — MCM completo
├── journal/
│   ├── core.lua      — lógica central (add, edit, tags, persistência)
│   ├── ui.lua        — construção/manipulação da UI do journal
│   ├── search.lua    — feature de busca
│   └── io.lua        — export/import de arquivos
└── util/
    └── logger.lua    — wrapper de log
```

**Estrutura JSON de dados:**
```json
{
  "entries": {
    "uuid-1234": {
      "originalText": "Caius Cosades me deu...",
      "editedText": "O velho me deu uma missão estranha...",
      "date": "16 Hearthfire",
      "daysPassed": 23,
      "source": "engine_copy",
      "tags": ["quest", "mainquest"],
      "deleted": false,
      "movedFrom": null
    },
    "uuid-5678": {
      "originalText": "Cheguei a Balmora.",
      "editedText": "Cheguei a Balmora. Preciso descansar.",
      "date": "17 Hearthfire",
      "daysPassed": 24,
      "source": "player_original",
      "tags": [],
      "deleted": false,
      "movedFrom": null
    }
  },
  "migrationDone": false
}
```

- `originalText` — imutável; texto do engine no momento da interceptação. Chave de lookup para o hide.
- `editedText` — versão atual visível no journal. Começa igual ao `originalText`.
- `source` — `"engine_copy"` para entradas interceptadas do evento `journal`; `"player_original"` para entradas criadas diretamente pelo jogador.
- `deleted` — se `true`, tanto a entrada original do engine quanto a cópia são ocultadas.
- `movedFrom` — UUID da entrada original quando esta é uma cópia criada por "mover para o fim".
- `migrationDone` — flag para o processo único de migração de playthrough existente (paginar o journal e criar cópias de todas as entradas já presentes).

---

## 5. O que NÃO fazer (lições aprendidas dos mods existentes)

1. **Mascarar entradas do engine é o mecanismo central — fazê-lo com robustez** — o hide precisa usar `originalText` como chave imutável, nunca o `editedText`. Se o lookup falhar, a entrada original do engine aparece duplicada ao lado da cópia do jogador. O hide deve ser reaplicado a cada abertura de página, não apenas na abertura do journal.

2. **Não usar messagebox para input de texto** — lag, limite severo, experiência ruim. Sempre usar `createParagraphInput`.

3. **Não fechar/reabrir o journal para atualizar a UI** — visualmente abrupto e causa inconsistências de estado. Usar `updateLayout()` no menu existente.

4. **Não tentar busca full-journal em tempo real** — a paginação programática é lenta e trava a UI. Busca deve ser lazy (página por página sob demanda do usuário).

5. **Não colocar tudo em um arquivo único** — o main.lua da SVE com 1600 linhas é um problema real de manutenção. Modularizar desde o início.

6. **Não hardcodar keybinds** — tudo configurável via MCM desde a primeira versão.

---

## 6. Referências de implementação por feature

| Feature | Referência primária | Referência secundária |
|---|---|---|
| Adicionar entrada | `Update My Journal/main.lua` | SVE `newEdit(3)` |
| Busca | SVE `searchOpenPages()` + `searchJournal()` | — |
| Edição in-place | SVE `saveEdit()` + `newEdit()` | — |
| ParagraphInput / UI | `Update My Journal/main.lua` | Clocks/mcm.lua (padrões MCM) |
| Export/Import arquivo | `lfs` (`C:\dev\Morrowind-ref\MWSE-ref`) + `io` LuaJIT | — |
| MCM keybinds | SVE `mcm.lua` | Clocks/mcm.lua |
| Persistência JSON | SVE `config.lua` (`mwse.loadConfig`) | — |
| UI injection no journal | SVE `onMenuJournalActivated()` | — |
