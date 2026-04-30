# MW_Mod_Full_Edit_Journal

Projeto MWSE focado em um journal customizado para Morrowind, no modelo de um mod por repositorio.

## Estrutura do projeto

```text
MW_Mod_Full_Edit_Journal/
├── doc/
├── deploy.ps1
├── journal_custom-metadata.toml
└── MWSE/mods/journal_custom/
```

## Comandos principais

```powershell
.\deploy.ps1 -List
.\deploy.ps1 -DryRun
.\deploy.ps1
.\deploy.ps1 -Clean
```

## Referencias externas

- `C:\dev\Morrowind-ref\MWSE-ref`
- `C:\dev\Morrowind-ref\Mods de exemplo`
- `C:\dev\Morrowind-ref\Snippets`
- `C:\dev\Morrowind-ref\OpenMW-ref` como referencia futura para projetos OpenMW

## Documentacao interna

- `doc\Estrutura do Projeto.md`
- `doc\Deploy - Comandos.md`
- `doc\Release - Checklist.md`

## Status

- mod unico do projeto: `journal_custom`
- metadata na raiz do repositorio
- deploy validado no modelo single-mod