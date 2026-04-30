# Automation - Commands

Quick guide with the most useful commands for the current project and for creating new projects that follow the same layout.

## 1. Commands for the current project

Run these commands from the root of `C:\dev\MW_Mod_Full_Edit_Journal`.

### Deploy

```powershell
.\deploy.ps1 -List
.\deploy.ps1 -DryRun
.\deploy.ps1
.\deploy.ps1 -Clean
.\deploy.ps1 -Mod journal_custom -DryRun
```

Quick summary:

- `-List`: shows the valid mod found at the repository root
- `-DryRun`: shows what would be copied without writing to `G:\Modding\Outlander\mods`
- no flags: deploys the single mod in the project
- `-Clean`: clears the destination folder before copying
- `-Mod journal_custom`: explicitly validates the expected mod id

### Validate project placeholders

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\Morrowind-ref\scripts\Test-MWSEProjectPlaceholders.ps1 -ProjectRoot C:\dev\MW_Mod_Full_Edit_Journal
```

Use this command to confirm that the project no longer contains leftover `mod_template` or `Mod Template` placeholders.

## 2. Create a new mod project

### Short shortcut

```bat
C:\dev\Morrowind-ref\scripts\new-mwse-mod.bat MW_Mod_Example example_mod "Example Mod" Renan
```

Format:

```bat
new-mwse-mod.bat <ProjectName> <ModId> <PackageName> [Author] [DestinationRoot]
```

### Full PowerShell command

```powershell
C:\dev\Morrowind-ref\scripts\New-MWSEModProject.ps1 `
  -ProjectName MW_Mod_Example `
  -ModId example_mod `
  -PackageName "Example Mod" `
  -Author "Renan" `
  -DestinationRoot "C:\dev"
```

Practical rules:

- `ProjectName`: the project folder name
- `ModId`: the technical id in `snake_case`
- `PackageName`: the visible mod name
- `Author`: optional, defaults to `Renan`
- `DestinationRoot`: optional, defaults to `C:\dev`

## 3. Validate a newly generated project

Move to the root of the generated project and run:

```powershell
.\deploy.ps1 -List
.\deploy.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\Morrowind-ref\scripts\Test-MWSEProjectPlaceholders.ps1 -ProjectRoot .
```

Expected result:

- `-List` finds exactly one mod
- `-DryRun` copies only `<mod-id>-metadata.toml` and `MWSE\mods\<mod-id>\...`
- the validator reports that it found no template placeholders

## 4. Use through VS Code

Open the Command Palette or the tasks menu and run:

- `Tasks: Run Task` -> `Morrowind: Generate New MWSE Project`
- `Tasks: Run Task` -> `Morrowind: Validate Current Project Placeholders`

These tasks are already available in the current project and also in the template at `C:\dev\Morrowind-ref\MWSE-Mod-Template`.

## 5. Useful references

- `C:\dev\Morrowind-ref\MWSE-ref`: MWSE docs and references
- `C:\dev\Morrowind-ref\Mods de exemplo`: example mods
- `C:\dev\Morrowind-ref\Snippets`: reusable MWSE and OpenMW snippets
- `C:\dev\Morrowind-ref\OpenMW-ref`: future reference location for OpenMW projects