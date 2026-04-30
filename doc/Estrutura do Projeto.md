# Estrutura do Projeto

Este repositorio segue o modelo de um unico mod por projeto.

## Layout esperado

```text
MW_Mod_Full_Edit_Journal\
├── doc\
├── journal_custom-metadata.toml
└── MWSE\mods\journal_custom\
```

Regras praticas:

- toda documentacao interna fica em `doc\`
- o metadata do mod fica na raiz do repositorio
- o codigo Lua do mod fica em `MWSE\mods\<mod-id>\`
- o valor de `[tools.mwse].lua-mod` deve bater com `<mod-id>`
- o `deploy.ps1` trabalha sempre sobre o unico mod valido encontrado na raiz

## Referencias externas

- `C:\dev\Morrowind-ref\MWSE-ref`: documentacao e referencias MWSE
- `C:\dev\Morrowind-ref\Mods de exemplo`: mods de exemplo para consulta
- `C:\dev\Morrowind-ref\Snippets`: snippets e notas reutilizaveis de MWSE e OpenMW
- `C:\dev\Morrowind-ref\OpenMW-ref`: referencia futura para projetos OpenMW, mesmo que ainda nao exista localmente

## Ferramentas compartilhadas

1. `C:\dev\Morrowind-ref\scripts\New-MWSEModProject.ps1`: gera um novo projeto a partir do template central.
2. `C:\dev\Morrowind-ref\MWSE-Mod-Template\README.md`: ponto de partida padronizado para novos mods.
3. `doc\Release - Checklist.md`: checklist local para validar estrutura, dry-run e log antes do deploy real.
4. `C:\dev\Morrowind-ref\Snippets`: hub de snippets e notas reutilizaveis para MWSE e OpenMW.