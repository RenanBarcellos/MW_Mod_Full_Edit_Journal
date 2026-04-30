## Project Rules

- Treat `G:\Modding\Outlander\mods` and all of its subfolders as read-only.
- Never create, edit, overwrite, move, rename, or delete files inside `G:\Modding\Outlander\mods`.
- Never run scripts, deploys, or commands that write into `G:\Modding\Outlander\mods`.
- Allowed operations in that tree: list, read, search, and copy files from it into this workspace.
- All code changes, file organization, and reference files for this project must live in `C:\Dev\MW_Mod_Full_Edit_Journal`, unless the user explicitly changes that rule.
- This workspace represents a single mod per project. Do not create a second mod folder at the repository root.
- The technical mod identifier must be ASCII, lowercase, and space-free, preferably in `snake_case`.
- The required structure for this project is:
	`doc\...`
	`<mod-id>-metadata.toml`
	`MWSE\mods\<mod-id>\...`
- The value of `[tools.mwse].lua-mod` must match `<mod-id>`.
- Deploy must operate on the single mod at the project root and must not assume a collection of mods in subfolders.
- External MWSE and example mod references live in `C:\dev\Morrowind-ref` and must be treated as read-only reference material unless the user explicitly says otherwise.
- Use `C:\dev\Morrowind-ref\MWSE-ref` for MWSE API and documentation reference, and `C:\dev\Morrowind-ref\Mods de exemplo` for implementation examples.
- Use `C:\dev\Morrowind-ref\Snippets` for reusable snippets and notes before recreating boilerplate.
- Also consider `C:\dev\Morrowind-ref\OpenMW-ref` as the reference location for future OpenMW projects, even if it does not exist on disk yet.
- All internal project documentation must live in `doc\`.