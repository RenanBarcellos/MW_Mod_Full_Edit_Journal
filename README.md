# MW_Mod_Full_Edit_Journal

MWSE project focused on a custom journal for Morrowind, following a one-mod-per-repository layout.

## Project Structure

```text
MW_Mod_Full_Edit_Journal/
├── doc/
├── deploy.ps1
├── journal_custom-metadata.toml
└── MWSE/mods/journal_custom/
```

## Main Commands

```powershell
.\deploy.ps1 -List
.\deploy.ps1 -DryRun
.\deploy.ps1
.\deploy.ps1 -Clean
```

## Useful Automation

- VS Code task: `Morrowind: Generate New MWSE Project`
- VS Code task: `Morrowind: Validate Current Project Placeholders`
- generator shortcut: `C:\dev\Morrowind-ref\scripts\new-mwse-mod.bat`
- placeholder validator: `C:\dev\Morrowind-ref\scripts\Test-MWSEProjectPlaceholders.ps1`

## External References

- `C:\dev\Morrowind-ref\MWSE-ref`
- `C:\dev\Morrowind-ref\Mods de exemplo`
- `C:\dev\Morrowind-ref\Snippets`
- `C:\dev\Morrowind-ref\OpenMW-ref` as a future reference for OpenMW projects

## Internal Documentation

- `doc\Automation - Commands.md`
- `doc\Project Structure.md`
- `doc\Deploy - Commands.md`
- `doc\Release - Checklist.md`

## Status

- single mod in the repository: `journal_custom`
- metadata at the repository root
- deploy validated in single-mod mode