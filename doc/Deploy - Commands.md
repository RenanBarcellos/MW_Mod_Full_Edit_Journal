# Deploy - Commands

Most commonly used deploy commands for this project:

```powershell
.\deploy.ps1 -List
.\deploy.ps1 -DryRun
.\deploy.ps1
.\deploy.ps1 -Clean
.\deploy.ps1 -Mod journal_custom -DryRun
```

Quick summary:

- `-List`: shows the valid mod found at the repository root
- `-Mod <id>`: optional; explicitly validates the mod id before deploy
- `-DryRun`: shows what would be copied without writing to the destination
- `-Clean`: clears the destination folder before copying

Required layout for the project to be accepted:

```text
<repo-root>\
  doc\...
  <mod-id>-metadata.toml
  MWSE\mods\<mod-id>\main.lua
```

Support files and folders such as `doc\`, `.github\`, `.vscode\`, `deploy.ps1`, `.gitignore`, and `README.md` are not included in the deployed package.