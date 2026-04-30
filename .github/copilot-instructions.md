## Regras do projeto

- Trate `G:\Modding\Outlander\mods` e todas as subpastas como somente leitura.
- Nunca criar, editar, sobrescrever, mover, renomear ou apagar arquivos dentro de `G:\Modding\Outlander\mods`.
- Nunca executar scripts, deploys ou comandos que escrevam em `G:\Modding\Outlander\mods`.
- Operacoes permitidas nessa arvore: listar, ler, buscar e copiar arquivos dela para dentro deste workspace.
- Toda modificacao de codigo, organizacao de arquivos e arquivos de referencia deste projeto deve acontecer em `C:\Dev\MW_Mod_Full_Edit_Journal`, a menos que o usuario mude essa regra explicitamente.
- Este workspace representa um unico mod por projeto. Nao criar uma segunda pasta de mod na raiz.
- O identificador tecnico do mod deve ser ASCII, minusculo e sem espacos, preferencialmente em `snake_case`.
- A estrutura obrigatoria deste projeto e:
	`doc\...`
	`<mod-id>-metadata.toml`
	`MWSE\mods\<mod-id>\...`
- O valor de `[tools.mwse].lua-mod` deve ser igual ao `<mod-id>`.
- O deploy deve operar no mod unico da raiz do projeto, nunca esperando uma colecao de mods em subpastas.
- As referencias externas de MWSE e mods de exemplo ficam em `C:\dev\Morrowind-ref` e devem ser tratadas como leitura/consulta, salvo instrucao explicita do usuario.
- Consulte `C:\dev\Morrowind-ref\MWSE-ref` para API/documentacao MWSE e `C:\dev\Morrowind-ref\Mods de exemplo` para exemplos de implementacao.
- Consulte `C:\dev\Morrowind-ref\Snippets` para snippets e notas reutilizaveis antes de recriar boilerplate.
- Considere tambem `C:\dev\Morrowind-ref\OpenMW-ref` como local de consulta para projetos OpenMW futuros, mesmo que essa referencia ainda nao exista no disco.
- Toda documentacao interna do projeto deve ficar em `doc\`.