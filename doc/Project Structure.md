# Project Structure

This repository follows the one-mod-per-project model.

## Expected Layout

```text
MW_Mod_Full_Edit_Journal\
├── doc\
├── journal_custom-metadata.toml
└── MWSE\mods\journal_custom\
```

Practical rules:

- all internal documentation stays in `doc\`
- the mod metadata lives at the repository root
- the Lua mod code lives in `MWSE\mods\<mod-id>\`
- `[tools.mwse].lua-mod` must match `<mod-id>`
- `deploy.ps1` always works from the single valid mod found at the root

## External References

- `C:\dev\Morrowind-ref\MWSE-ref`: MWSE documentation and references
- `C:\dev\Morrowind-ref\Mods de exemplo`: example mods for consultation
- `C:\dev\Morrowind-ref\Snippets`: reusable MWSE and OpenMW snippets and notes
- `C:\dev\Morrowind-ref\OpenMW-ref`: future reference location for OpenMW projects, even if it does not exist locally yet

## Shared Tools

1. `C:\dev\Morrowind-ref\scripts\New-MWSEModProject.ps1`: generates a new project from the central template.
2. `C:\dev\Morrowind-ref\MWSE-Mod-Template\README.md`: standardized starting point for new mods.
3. `doc\Release - Checklist.md`: local checklist to validate structure, dry-run output, and logs before a real deploy.
4. `C:\dev\Morrowind-ref\Snippets`: shared hub for reusable MWSE and OpenMW snippets and notes.