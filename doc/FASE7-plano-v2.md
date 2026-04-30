# Fase 7 - Plano v2

Data: 2026-04-28

## Objetivo deste documento

Este documento substitui o raciocinio acumulado e ruidoso das ultimas tentativas da Fase 7.
A ideia e servir como ponto de partida limpo para um novo chat.

O foco aqui e:
- estabilizar a selecao navegavel no journal em MenuBook
- remover as regressos introduzidas pelas ultimas tentativas
- definir uma estrategia robusta para highlight e mapeamento
- tirar controle de viuvas e orfas do caminho critico ate a selecao ficar estavel

---

## Estado atual observado

### Sintomas confirmados

1. O texto ficou corrompido em varios pontos com caracteres estranhos como `A`, vindos das tentativas de mexer com HTML / espacamento nao separavel.
2. Nas paginas 1 e 2 o highlight funciona quase sempre, mas as vezes pega uma linha da entrada seguinte.
3. Ao cruzar da pagina 1 para a 2, o highlight pode atingir tambem uma linha de outra entrada no meio da pagina 2.
4. Nas paginas 3 e 4, apertar seta para cima pode fechar o jogo.
5. A partir das paginas 5 e 6 a selecao deixa de funcionar ou fica muito inconsistente.
6. O save runtime mostra `selectedEntryId` sendo atualizado, entao a navegacao nao esta totalmente morta; o problema principal esta entre highlight visual e mapeamento em spreads mais adiante.
7. O save runtime ainda mostrou `pageCache["3"]` com assinatura antiga baseada em `header`, enquanto as primeiras paginas ja estavam sendo gravadas com `body`.

### O que isso significa

- O input nao e o maior problema neste momento.
- O maior problema e a estrategia visual e o matching entre texto renderizado e entries.
- O controle de viuvas e orfas por HTML / entidades / espacos especiais esta introduzindo mais regressao do que beneficio.
- As paginas mais avancadas nao estao sendo mapeadas de forma confiavel.

---

## Conclusoes tecnicas

### 1. O highlight atual esta no nivel errado

As ultimas tentativas alternaram entre:
- mexer na cor de nos de texto
- injetar `rect` / overlays
- detectar fragmentos de texto para descobrir o que destacar

Tudo isso continua fragil porque depende do resultado final da paginacao do MenuBook.
Quando uma entry quebra de maneira diferente, o sistema destaca o fragmento errado, destaca fragmentos demais, ou interfere no layout.

### 2. Matching por fragmento visivel e necessario para mapping, mas insuficiente para highlight

Matching por trechos de texto e aceitavel para responder:
- quais entries parecem estar visiveis neste spread?
- em qual pagina da abertura atual essas entries cairam?

Mas esse mesmo matching nao e suficiente para responder com seguranca:
- quais linhas exatas devem receber highlight?
- onde começa e termina visualmente uma entry apos a paginacao?

Ou seja:
- `mapping` pode continuar aproximado
- `highlight` nao deve depender dessa mesma aproximacao linha a linha

### 3. `&nbsp;`, NBSP e hacks tipograficos nao sao seguros aqui

As tentativas de evitar viuvas e orfas usando entidades HTML ou espacos nao separaveis geraram texto corrompido.
No estado atual, isso deve ser considerado proibido para a Fase 7.

### 4. O crash em 3/4 e o sinal mais importante

Fechar o jogo ao apertar seta para cima em 3/4 indica que ainda estamos fazendo alguma operacao insegura demais no pipeline de UI.
Enquanto isso existir, nao faz sentido continuar refinando visualmente o highlight atual.

---

## Decisao recomendada

### Decisao principal

Parar de tentar resolver a Fase 7 com highlight pos-render baseado em fragmentos de texto do MenuBook.

### Nova direcao

A estrategia mais promissora agora e:

1. Usar `mapping.lua` apenas para descobrir quais entries estao visiveis no spread atual.
2. Manter a navegacao restrita ao spread atual.
3. Tirar o highlight do DOM pos-render e mover o destaque para o HTML gerado em `render.lua`.
4. Rebuildar o livro quando a selecao mudar, preservando o spread atual.

Em outras palavras:
- o MenuBook deve fazer a paginacao do texto ja destacado
- o codigo nao deve ficar pintando fragmentos depois que o texto ja foi quebrado em linhas e paginas

Isso muda a pergunta de:
- "qual no eu preciso pintar agora?"

Para:
- "qual entry esta selecionada antes da renderizacao?"

Essa segunda pergunta e muito mais estavel.

---

## Solucao proposta

## Fase 7A - Reset de seguranca

Antes de tentar a nova abordagem, fazer um reset controlado:

1. Remover toda logica de NBSP / `&nbsp;` / protecao tipografica em `render.lua` e `util/text.lua`.
2. Remover overlays `rect` e qualquer highlight por injecao de elementos em `book.lua`.
3. Remover highlight por cor em nos individuais, se ele continuar dependendo de matching de fragmento.
4. Manter apenas:
   - `selectedEntryId`
   - `selectedSpreadStart`
   - `mapping.collectVisibleBlocks`
   - limpeza de selecao ao trocar spread
   - navegacao por `activeVisibleBlocks`

A meta da Fase 7A e deixar o journal sem crash e sem corromper layout, mesmo que temporariamente sem highlight.

---

## Fase 7B - Highlight por HTML, nao por UI tree

### Ideia

Cada entry deve ser renderizada em `render.lua` com um wrapper proprio.
Se a entry estiver selecionada, esse wrapper recebe uma versao visualmente destacada.

Exemplo conceitual:

- entry normal: texto preto normal
- entry selecionada: texto com leve destaque ou moldura discreta, gerada no proprio HTML

Como a pagina e quebrada pelo MenuBook depois disso, o destaque acompanha naturalmente a quebra entre paginas.
Nao e preciso descobrir depois onde esta cada linha.

### Requisito importante

Para isso funcionar sem ser irritante, o rebuild precisa preservar o spread atual.

Entao a cadeia correta passa a ser:

1. jogador aperta seta
2. `input.lua` escolhe nova `selectedEntryId` dentro de `activeVisibleBlocks`
3. `book.lua` salva a selecao
4. `book.lua` rebuilda o livro
5. o rebuild reabre o livro no mesmo spread
6. `render.lua` gera a entry selecionada com destaque no HTML

---

## Como preservar o spread no rebuild

Aqui esta o ponto mais importante da proxima rodada.

Hoje o sistema ja sabe qual spread esta aberto via:
- `MenuBook_page_number_1`
- `blocks.spreadStart`
- `selectedSpreadStart`
- `pageCache`

O novo trabalho da Fase 7 deve priorizar um mecanismo explicito de restauracao de pagina/spread apos rebuild.

### Abordagem recomendada

1. Antes do rebuild, capturar `currentSpreadStart` do livro aberto.
2. Depois de reabrir o livro, navegar programaticamente ate esse spread.
3. So depois confirmar `scheduleVisibleBlockCollection`.

Se isso nao for possivel de forma estavel com MenuBook, entao a alternativa aceitavel da Fase 7 e:
- manter highlight apenas quando o livro e aberto
- ou ate deixar sem highlight
- mas nunca mais voltar para overlays que podem quebrar layout ou crashar o jogo

Melhor sem highlight do que com crash.

---

## O que fazer com `mapping.lua`

`mapping.lua` nao precisa identificar a geometria exata do highlight.
Ele precisa fazer so tres coisas:

1. descobrir o conjunto de entries visiveis no spread atual
2. atribuir corretamente `spreadStart`
3. manter `pageCache` coerente com o que foi visto

### Problema atual em `mapping.lua`

O runtime mostrou um spread posterior ainda sendo persistido com `header`, enquanto os spreads iniciais ja estavam em `body`.
Isso sugere uma destas hipoteses:

- o spread 3 nunca foi regravado apos a mudanca de codigo
- o matching de `body` falhou nesse spread e caiu num caminho antigo
- o estado persistido ficou defasado em parte do cache

### Correcao recomendada

1. Adicionar logging mais forte para spreads posteriores:
   - `spreadStart`
   - `pageText` resumido
   - `entryId` matchado
   - `field`
   - `confidence`
2. Em caso de `#blocks == 0`, nunca reaproveitar silenciosamente assinatura antiga.
3. Ao visitar um spread, sobrescrever sempre o cache daquele spread com a assinatura nova observada naquela abertura.
4. Continuar com janelas por caracteres e por palavras, mas usar isso apenas para decidir visibilidade, nao highlight.

---

## O que fazer com `input.lua`

`input.lua` deve voltar a ser simples.

### Regras desejadas

1. Navegacao apenas entre as entries explicitamente visiveis no spread atual.
2. Seta para cima / baixo nao pode tentar selecionar nada fora de `activeVisibleBlocks`.
3. Se o spread muda, a selecao e limpa.
4. `input.lua` nao deve conhecer highlight, overlay, HTML ou pageCache.

### Regra de seguranca

Se houver qualquer duvida entre:
- navegar para mais longe
- ou manter a coerencia do spread atual

Escolher coerencia do spread atual.

---

## Viuvas e orfas

### Decisao recomendada

Tirar esse assunto da linha critica da Fase 7.

### Motivo

No contexto atual do MenuBook:
- nao temos controle real de line breaking final
- hacks com entidades / unicode ja corromperam texto
- cada tentativa de arrumar tipografia piorou a estabilidade

### Regra para a proxima rodada

Durante a Fase 7:
- nao usar `&nbsp;`
- nao usar NBSP unicode
- nao usar caracteres invisiveis especiais
- nao mexer no texto visivel com substituicoes tipograficas

Se quiser retomar viuvas e orfas depois, isso deve virar uma fase propria, baseada em medicao de linhas e layout previsivel, nao em entidades HTML.

---

## Sequencia recomendada de implementacao no proximo chat

1. Reverter os hacks tipograficos e qualquer resto de HTML especial.
2. Remover overlays e highlight pos-render inseguros.
3. Garantir que paginas 3/4 deixem de crashar ao apertar seta para cima.
4. Instrumentar `mapping.lua` com logs curtos para spreads 3/4 e 5/6.
5. Confirmar que `activeVisibleBlocks` funciona nesses spreads.
6. So depois implementar highlight por HTML com rebuild preservando spread.
7. Se a preservacao de spread nao ficar estavel, congelar a Fase 7 sem highlight visual e seguir com a navegacao funcional.

---

## Definicao de pronto para a Fase 7

A Fase 7 so deve ser considerada pronta quando todos os pontos abaixo forem verdadeiros:

1. Seta para cima e para baixo nunca fecham o jogo.
2. A selecao funciona nas paginas 1/2, 3/4, 5/6 e spreads seguintes.
3. Ao trocar de spread, a selecao e limpa ou revalidada corretamente.
4. Nenhum caractere estranho aparece no texto renderizado.
5. O highlight nao altera layout, nao apaga texto e nao pega linhas de entries vizinhas.
6. Entry quebrada entre duas paginas continua destacada de forma coerente.
7. `pageCache` refletiu os spreads visitados com assinatura coerente e atual.

---

## Anti-meta: o que nao fazer de novo

1. Nao usar `&nbsp;` ou unicode especial para controlar tipografia.
2. Nao fazer highlight linha a linha tentando adivinhar fragmentos soltos.
3. Nao injetar elementos dentro do fluxo local do texto para destacar a entry.
4. Nao aceitar crash em troca de um highlight mais bonito.
5. Nao continuar refinando o visual antes de estabilizar 3/4 e 5/6.

---

## Arquivos que provavelmente precisarao ser tocados no proximo chat

- `MWSE/mods/journal_custom/journal/book.lua`
- `MWSE/mods/journal_custom/journal/mapping.lua`
- `MWSE/mods/journal_custom/journal/render.lua`
- `MWSE/mods/journal_custom/util/text.lua`
- possivelmente `MWSE/mods/journal_custom/journal/input.lua`

---

## Resumo curto para abrir o proximo chat

A Fase 7 entrou num estado em que:
- o input ainda existe
- o highlight visual esta fragil
- hacks de tipografia quebraram texto
- spreads mais avancados ainda falham

A recomendacao e reiniciar a Fase 7 com esta ordem:
- resetar hacks visuais inseguros
- estabilizar mapping em 3/4 e 5/6
- depois migrar highlight para HTML + rebuild preservando spread
- deixar viuvas e orfas para depois
