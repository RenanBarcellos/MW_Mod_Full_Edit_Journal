# Deploy - Comandos

Comandos mais usados do deploy do projeto:

```powershell
.\deploy.ps1 -List
.\deploy.ps1 -DryRun
.\deploy.ps1
.\deploy.ps1 -Clean
.\deploy.ps1 -Mod journal_custom -DryRun
```

Resumo rapido:

- `-List`: mostra o mod valido encontrado na raiz do projeto.
- `-Mod <id>`: opcional; valida explicitamente o id do mod antes do deploy.
- `-DryRun`: mostra o que seria copiado, sem escrever no destino.
- `-Clean`: limpa a pasta de destino do mod antes de copiar.

Layout exigido para o projeto ser aceito:

```text
<repo-root>\
  doc\...
  <mod-id>-metadata.toml
  MWSE\mods\<mod-id>\main.lua
```

Arquivos e pastas de apoio como `doc\`, `.github\`, `.vscode\`, `deploy.ps1` e `.gitignore` nao entram no pacote deployado.