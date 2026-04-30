# Fase 8 - Plano v1

Data: 2026-04-29

## Objetivo deste documento

Definir a implementacao da Fase 8 depois da estabilizacao da selecao navegavel.
O foco agora e sair do estado "edicao a definir" e escolher um fluxo concreto, pequeno e validavel para editar, salvar, cancelar e apagar entries do journal_custom sem reabrir os problemas de paginacao da Fase 7.

---

## Decisao principal

### UX escolhida

A Fase 8 deve usar um editor modal dedicado, separado do `MenuBook`.

Em vez de tentar editar texto diretamente dentro do livro, o fluxo passa a ser:

1. jogador seleciona uma entry no `MenuBook`
2. jogador aciona editar
3. o mod abre um modal com campo de texto multi-linha
4. salvar ou cancelar fecha o modal
5. o livro e reconstruido perto do mesmo contexto

### Motivo tecnico

Esta decisao segue diretamente do estado atual do codigo:

1. `book.lua` ja sabe preservar `selectedEntryId` e `restoreSpreadStart` em rebuild.
2. `data.lua` ja tem `updateEditedText()` e `markDeleted()`.
3. `input.lua` ja separa navegacao de selecao e tem stubs claros para `beginEdit()`, `commitEdit()` e `cancelEdit()`.
4. `render.lua` ja usa `editedText` e ignora entries com `deleted = true`.

Ou seja: a menor expansao segura e adicionar um fluxo modal ao redor de capacidades que ja existem.

### O que estamos evitando de proposito

Nao editar dentro do `MenuBook` evita reabrir estes riscos:

- captura de teclado competindo com navegacao por seta
- reflow do HTML do livro a cada tecla
- invalidez do mapping no meio da digitacao
- necessidade de highlight ou cursor dentro de texto paginado
- regressao do spread atual enquanto o jogador escreve

O `MenuBook` continua sendo superficie de leitura, selecao e contexto.
O modal vira a superficie de escrita.

---

## Escopo da Fase 8

### Dentro do escopo

1. Abrir o editor para a entry atualmente selecionada.
2. Preencher o campo com `editedText` atual da entry.
3. Salvar alteracoes explicitamente.
4. Cancelar sem persistir rascunho.
5. Apagar a entry no journal do mod com `deleted = true`.
6. Criar nota nova do jogador via modal dedicado e inserir abaixo da entry selecionada, ou no final se nao houver selecao.
7. Reabrir o livro perto do mesmo spread apos salvar ou apagar.
8. Revalidar selecao apos a operacao.

### Fora do escopo

1. Edicao inline dentro do `MenuBook`.
2. Busca, tags, filtros ou ordem custom.
3. Sincronizar a edicao de volta para o journal vanilla.
4. Preview ao vivo dentro do livro enquanto o jogador digita.

---

## Estado atual do codigo que a Fase 8 herda

### `journal/input.lua`

- `moveSelection()` ja navega apenas por `activeVisibleBlocks`.
- `onKeyDown()` ja e o ponto natural para ligar o comando de abrir editor e criar nota.

### `journal/book.lua`

- `applySelection()` ja persiste `selectedEntryId`.
- `resolveContext()` e `rebuild()` ja conhecem preservacao de contexto.
- `renderCurrentBook()` ja sabe restaurar spread depois de rebuild.

### `journal/data.lua`

- `updateEditedText(id, text)` ja altera `editedText`.
- `markDeleted(id, deleted)` ja faz soft delete.
- `createPlayerEntry(params)` ja oferece o ponto natural para persistir nota nova do jogador.
- o estado persistido ainda nao tem conceito de rascunho, o que e bom: rascunho deve ficar apenas em memoria de UI.

### `journal/render.lua`

- a renderizacao ja privilegia `editedText`.
- deletar uma entry do mod ja a remove visualmente do livro ao rebuildar.

---

## Arquitetura recomendada

## Fase 8A - Estado de edicao em memoria

Criar um estado transitorio de edicao, em memoria, sem persistir no JSON:

```lua
local editSession = {
    active = false,
    entryId = nil,
    originalText = nil,
    draftText = nil,
    restoreSpreadStart = nil,
}
```

### Regras

1. `draftText` nunca vai para `data.lua` antes de salvar.
2. `originalText` serve para rollback local no cancelar.
3. `restoreSpreadStart` e capturado antes de abrir o modal.
4. Se o modal fechar por cancelamento, o livro volta sem side effects.
5. Mesmo depois de `Salvar` no modal, a escrita em disco do JSON so acontece quando o jogador salva o jogo.

### Local ideal

O mais limpo e extrair esse comportamento para um novo modulo `journal/editor.lua`, deixando:

- `input.lua` decidir quando iniciar ou finalizar a edicao
- `editor.lua` cuidar do modal e do draft
- `book.lua` cuidar do rebuild e da restauracao de contexto
- `data.lua` continuar apenas como persistencia

Se for necessario reduzir a primeira entrega, o estado pode nascer em `book.lua`, mas isso deve ser tratado como etapa provisoria.

---

## Fase 8B - Abrir o editor da entry selecionada

### Regra funcional

So e permitido editar a entry atualmente selecionada.
Sem selecao valida, nao abre editor.

### Fluxo

1. pegar `selectedEntryId`
2. buscar entry em `data.getEntry()`
3. capturar `currentSpreadStart`
4. abrir modal com campo multi-linha preenchido com `entry.editedText`
5. adquirir foco de texto explicitamente

### Decisao de UX

O modal precisa ser simples:

- titulo com identificacao da entry
- area de texto
- botao `Salvar`
- botao `Cancelar`
- botao `Apagar`

Nada de preview vivo no livro nesta primeira rodada.

### Regra de seguranca

Enquanto o modal estiver ativo:

- input de selecao do livro deve ignorar setas
- rebuild do livro deve ser bloqueado, exceto no fechamento do fluxo de edicao
- nao pode existir mais de um modal de edicao ativo

---

## Fase 8C - Salvar

### Fluxo esperado

1. validar que existe `editSession.active`
2. ler `draftText` do campo de texto
3. normalizar texto minimo apenas se necessario
4. chamar `data.updateEditedText(entryId, draftText)`
5. garantir `data.markDeleted(entryId, false)` caso esteja restaurando entry previamente apagada
6. marcar o estado do journal como alterado, sem gravar em disco imediatamente
7. fechar modal
8. reaplicar `selectedEntryId`
9. `book.rebuild(true, restoreSpreadStart, "editSave")`

### Regra importante

Salvar e a unica operacao que aplica `editedText` ao estado do mod.
Persistencia em disco do JSON so acontece quando o jogador salva o jogo.
Fechar modal por qualquer outro caminho nao persiste nada.

### Edge cases

1. Texto vazio pode ser permitido, mas `render.lua` continuara mostrando `(sem texto)`.
2. Se a entry nao existir mais, abortar com log e fechar sessao de edicao com seguranca.
3. Se o `data.save()` falhar, nao fechar silenciosamente sem feedback de log.

---

## Fase 8D - Cancelar

### Fluxo esperado

1. descartar `draftText`
2. fechar modal
3. limpar `editSession`
4. reabrir ou focar o livro no mesmo spread
5. manter a selecao da mesma entry

### Regra importante

Cancelar nao chama `data.updateEditedText()` nem `data.save()`.

### Validacao mental simples

Se o jogador abrir o editor, apagar todo o texto e cancelar, o JSON deve permanecer byte a byte como estava antes.

---

## Fase 8E - Apagar

### Modelo de exclusao

A Fase 8 deve fazer soft delete no journal do mod.
Nao apagar nada do engine journal.

### Fluxo esperado

1. confirmar que existe `entryId`
2. chamar `data.markDeleted(entryId, true)`
3. marcar o estado do journal como alterado, sem gravar em disco imediatamente
4. fechar modal
5. rebuildar o livro com `restoreSpreadStart`
6. escolher nova selecao valida no mesmo spread, se existir
7. se nao existir vizinho visivel, limpar selecao

### Regra de fallback de selecao

Ao apagar a entry selecionada:

1. preferir a proxima entry visivel do spread atual
2. se nao houver, preferir a anterior
3. se o spread ficar vazio, limpar selecao

Essa regra evita rebuild com `selectedEntryId` apontando para item invisivel ou apagado.

---

## Fase 8F - Teclas e contratos de input

### Comandos minimos recomendados

1. `Enter` ou tecla dedicada abre o editor da entry selecionada.
2. `N` dentro do journal abre uma nota nova do jogador.
3. `Esc` cancela quando o modal estiver aberto.
4. `Ctrl+Enter` ou botao `Salvar` confirma.
5. `J` nao deve fechar o journal enquanto o modal estiver ativo.
6. `Delete` fica opcional; o botao `Apagar` no modal ja cobre o fluxo.

### Contrato entre modulos

`input.lua` nao deve manipular texto diretamente.
Ele so decide:

1. se existe contexto valido para iniciar edicao
2. se um comando de salvar/cancelar precisa ser encaminhado
3. se o livro deve ignorar input porque o modal esta ativo

---

## Sequencia recomendada de implementacao

1. Criar o estado de edicao e o modal sem persistir nada ainda.
2. Fazer `beginEdit()` abrir o modal com o texto atual da entry selecionada.
3. Implementar `cancelEdit()` com rollback total e retorno ao livro.
4. Implementar `commitEdit()` salvando `editedText` e rebuildando no mesmo spread.
5. Implementar `delete` como soft delete com fallback de selecao.
6. Implementar criacao de nota do jogador reaproveitando o mesmo modal e inserindo abaixo da selecao atual ou no final.
7. Adiar escrita em disco do JSON para o evento de save do jogo.
8. Travar input do livro enquanto o modal estiver aberto, incluindo a tecla do journal.
9. Adicionar logs curtos para `editOpen`, `editSave`, `editCancel`, `editDelete` e `noteCreate`.

---

## Definicao de pronto para a Fase 8

A Fase 8 so deve ser considerada pronta quando todos os pontos abaixo forem verdadeiros:

1. O editor so abre quando ha uma entry selecionada.
2. O texto inicial do modal corresponde ao `editedText` atual da entry.
3. `N` abre uma nota nova do jogador sem depender de entry selecionada.
4. Cancelar nunca persiste rascunho.
5. Salvar atualiza o estado do mod e aparece no livro apos rebuild.
6. O JSON so vai para disco quando o jogador salva o jogo.
7. Apagar remove a entry do livro do mod sem afetar o journal do engine.
8. Nota nova entra abaixo da entry selecionada ou no final se nao houver selecao.
9. O livro volta para o mesmo spread ou para uma regiao coerente apos salvar, apagar ou criar nota.
10. O modal nao deixa a navegacao por seta nem a tecla do journal interferirem durante a digitacao.
11. Nao existe crash ou fechamento indevido do jogo ao alternar entre livro e modal.

---

## Validacao em jogo

### Caso 1 - Salvar alteracao simples

1. abrir o journal_custom
2. selecionar uma entry visivel
3. abrir editor
4. trocar uma palavra facil de reconhecer
5. salvar
6. confirmar no livro e no JSON que o texto novo persistiu

### Caso 2 - Cancelar sem persistir

1. abrir editor na mesma entry
2. alterar varias linhas
3. cancelar
4. confirmar que o livro mostra o texto antigo
5. confirmar que o JSON nao mudou

### Caso 3 - Apagar

1. abrir editor
2. apagar a entry
3. confirmar que ela desaparece do livro do mod
4. confirmar que o quest progress do engine nao foi removido
5. confirmar que a selecao cai em vizinho valido ou e limpa

### Caso 4 - Criar nota nova

1. abrir o journal_custom
2. apertar `N`
3. digitar uma nota facil de reconhecer
4. salvar
5. confirmar que a nova nota aparece no livro logo abaixo da entry selecionada, ou no final se nao havia selecao
6. confirmar que ela fica no JSON como `source = "player"` so depois que o jogador salvar o jogo
7. confirmar que apertar `J` durante esse modal nao fecha o journal
8. confirmar que cancelar esse mesmo fluxo nao cria nada

### Caso 5 - Contexto apos rebuild

1. repetir salvar e apagar em spreads mais avancados
2. confirmar que o livro volta perto da mesma regiao
3. confirmar que a restauracao de spread nao quebra a selecao

---

## Anti-meta da Fase 8

1. Nao editar texto diretamente no `MenuBook`.
2. Nao persistir rascunho a cada tecla.
3. Nao misturar estado temporario de UI com o JSON salvo.
4. Nao usar delete fisico de entry quando `deleted = true` resolve o caso.
5. Nao abrir a Fase 9 antes de salvar, cancelar e apagar estarem estaveis.

---

## Resumo curto para abrir o proximo chat

A Fase 8 deve seguir com editor modal dedicado.
O `MenuBook` continua so para leitura, selecao e contexto.
Salvar, cancelar e apagar precisam operar sobre a entry selecionada, e `N` deve abrir uma nota nova do jogador no mesmo modal, sempre com rascunho apenas em memoria e rebuild preservando spread no final.