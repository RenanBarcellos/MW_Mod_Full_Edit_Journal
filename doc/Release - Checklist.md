# Release - Checklist

Short checklist to validate the mod before a real deploy.

## Structure

1. Confirm that the root metadata file is `journal_custom-metadata.toml`.
2. Confirm that `[tools.mwse].lua-mod = "journal_custom"`.
3. Confirm that the Lua mod code lives in `MWSE\mods\journal_custom\`.
4. Confirm that relevant documentation lives in `doc\`.

## Local Validation

1. Run `./deploy.ps1 -List`.
2. Run `./deploy.ps1 -DryRun`.
3. Review whether the dry-run copies only `journal_custom-metadata.toml` and `MWSE\mods\journal_custom\...`.

## In-Game Validation

1. Perform a real deploy only after the dry-run output is correct.
2. Launch the game and confirm that the mod initializes without a fatal error.
3. Check `MWSE.log` for messages from `journal_custom`.

## Documentation and Maintenance

1. Update `README.md` whenever the goal, status, or important commands change.
2. Update `doc\` whenever the project structure or deploy flow changes.
3. Check `C:\dev\Morrowind-ref\Snippets` and `C:\dev\Morrowind-ref\MWSE-ref` before duplicating boilerplate.