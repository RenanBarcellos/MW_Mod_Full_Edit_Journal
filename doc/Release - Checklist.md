# Release - Checklist

Checklist curto para validar o mod antes de um deploy real.

## Estrutura

1. Confirmar que o metadata na raiz e `journal_custom-metadata.toml`.
2. Confirmar que `[tools.mwse].lua-mod = "journal_custom"`.
3. Confirmar que o codigo Lua do mod esta em `MWSE\mods\journal_custom\`.
4. Confirmar que a documentacao relevante esta em `doc\`.

## Validacao local

1. Rodar `./deploy.ps1 -List`.
2. Rodar `./deploy.ps1 -DryRun`.
3. Revisar se o dry-run copia apenas `journal_custom-metadata.toml` e `MWSE\mods\journal_custom\...`.

## Validacao em jogo

1. Fazer deploy real apenas depois do dry-run estar correto.
2. Abrir o jogo e confirmar que o mod inicializa sem erro fatal.
3. Conferir o `MWSE.log` para mensagens do `journal_custom`.

## Documentacao e manutencao

1. Atualizar o `README.md` quando mudarem objetivo, status ou comandos importantes.
2. Atualizar `doc\` quando a estrutura do projeto ou o fluxo de deploy mudarem.
3. Consultar `C:\dev\Morrowind-ref\Snippets` e `C:\dev\Morrowind-ref\MWSE-ref` antes de duplicar boilerplate.