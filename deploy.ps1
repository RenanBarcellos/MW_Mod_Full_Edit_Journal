[CmdletBinding(DefaultParameterSetName = "Default")]
param(
    [Parameter(ParameterSetName = "List")]
    [switch]$List,

    [Parameter(ParameterSetName = "Single")]
    [string]$Mod,

    [Parameter(ParameterSetName = "All")]
    [switch]$All,

    [switch]$Clean,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The deploy script only packages the single mod that lives at the repository
# root and mirrors it into the MO2 mods directory.
$repoRoot = $PSScriptRoot
$modsDestinationRoot = "G:\Modding\Outlander\mods"

$excludeNamesInsideMod = @(
    ".git",
    ".github",
    ".vscode",
    "doc",
    "Thumbs.db",
    ".DS_Store"
)

$excludeTopLevelFiles = @(
    "deploy.ps1",
    ".gitignore",
    "README.md"
)

# Read the few TOML keys the deploy needs without depending on an external TOML
# parser module.
function Get-TomlString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $currentSection = ""

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            continue
        }

        if ($currentSection -ne $Section) {
            continue
        }

        $pattern = '^{0}\s*=\s*"([^"]+)"$' -f [regex]::Escape($Key)
        if ($trimmed -match $pattern) {
            return $matches[1]
        }
    }

    return $null
}

# A valid project exposes exactly one metadata file at the root plus its
# matching MWSE/mods/<mod-id>/main.lua entry point.
function Get-ProjectMods {
    Get-ChildItem -Path $repoRoot -File -Filter "*-metadata.toml" |
        ForEach-Object {
            $modId = $_.BaseName -replace '-metadata$', ''
            $metadataPath = $_.FullName
            $luaRoot = Join-Path $repoRoot "MWSE\mods\$modId"
            $mainPath = Join-Path $luaRoot "main.lua"

            if ((Test-Path $metadataPath) -and (Test-Path $luaRoot) -and (Test-Path $mainPath)) {
                $packageName = Get-TomlString -Path $metadataPath -Section "package" -Key "name"
                $luaMod = Get-TomlString -Path $metadataPath -Section "tools.mwse" -Key "lua-mod"

                [pscustomobject]@{
                    Id = $modId
                    PackageName = if ($packageName) { $packageName } else { $modId }
                    Root = $repoRoot
                    MetadataPath = $metadataPath
                    LuaRoot = $luaRoot
                    MainPath = $mainPath
                    LuaMod = $luaMod
                }
            }
        }
}

    # Enforce the one-mod-per-project layout before any files are copied.
function Ensure-ValidModLayout {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ModInfo
    )

    if ($ModInfo.LuaMod -ne $ModInfo.Id) {
        throw "Invalid mod '$($ModInfo.Id)': lua-mod '$($ModInfo.LuaMod)' must match the folder id '$($ModInfo.Id)'."
    }

    if (-not (Test-Path $ModInfo.MainPath)) {
        throw "Invalid mod '$($ModInfo.Id)': missing entry point at '$($ModInfo.MainPath)'."
    }
}

# Dry-run mode still needs to show the directory work that would happen.
function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($DryRun) {
        Write-Host "[DryRun] ensure directory $Path"
        return
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Clean deploys remove the existing target contents before the copy phase.
function Clear-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($DryRun) {
        Write-Host "[DryRun] clean $Path"
        return
    }

    if (Test-Path $Path) {
        Get-ChildItem -Path $Path -Force | Remove-Item -Recurse -Force
    }
    else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Filter out repo-only files and support directories so the deployed mod only
# contains runtime assets.
function Should-ExcludeInsideMod {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $segments = @($RelativePath -split '[\\/]+' | Where-Object { $_ -ne "" })

    foreach ($segment in $segments) {
        if ($excludeNamesInsideMod -contains $segment) {
            return $true
        }
    }

    if (($segments.Count -eq 1) -and ($excludeTopLevelFiles -contains $segments[0])) {
        return $true
    }

    if ($Item.Name -like "*.code-workspace") {
        return $true
    }

    return $false
}

# Copy the current repository layout into the final mod folder while preserving
# relative paths under the repository root.
function Copy-Mod {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ModInfo
    )

    Ensure-ValidModLayout -ModInfo $ModInfo

    $destination = Join-Path $modsDestinationRoot $ModInfo.Id

    if ($Clean) {
        Clear-Directory -Path $destination
    }
    else {
        Ensure-Directory -Path $destination
    }

    Write-Host "Deploy: $($ModInfo.Id) -> $destination"

    Get-ChildItem -Path $ModInfo.Root -Recurse -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($ModInfo.Root.Length).TrimStart([char[]]@('\', '/'))

        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            return
        }

        if (Should-ExcludeInsideMod -Item $_ -RelativePath $relativePath) {
            return
        }

        $destPath = Join-Path $destination $relativePath

        if ($_.PSIsContainer) {
            if ($DryRun) {
                Write-Host "[DryRun] mkdir $destPath"
            }
            elseif (-not (Test-Path $destPath)) {
                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
            }

            return
        }

        $destDir = Split-Path -Parent $destPath

        if ($DryRun) {
            Write-Host "[DryRun] copy $relativePath"
        }
        else {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Copy-Item -Path $_.FullName -Destination $destPath -Force
        }
    }

    Write-Host "Done: $($ModInfo.Id)"
}

# Resolve the one valid mod, then either list it or deploy it according to the
# selected parameter set.
$mods = @(Get-ProjectMods)

if ($mods.Count -eq 0) {
    throw "No valid mod found. Expected at the project root: <mod-id>-metadata.toml and MWSE\\mods\\<mod-id>\\main.lua."
}

if ($mods.Count -gt 1) {
    $foundMods = ($mods | Sort-Object Id | ForEach-Object { $_.Id }) -join ", "
    throw "More than one valid mod was found at the project root: $foundMods. This repository must contain only one mod."
}

$mods | ForEach-Object { Ensure-ValidModLayout -ModInfo $_ }

if ($List) {
    Write-Host "Available mods:"
    $mods | Sort-Object Id | ForEach-Object {
        Write-Host ("- {0} [{1}]" -f $_.Id, $_.PackageName)
    }
    return
}

$selectedMods = @()

if ($All) {
    $selectedMods = $mods
}
elseif ($Mod) {
    $selectedMods = @(
        $mods | Where-Object {
            $_.Id -ieq $Mod -or $_.PackageName -ieq $Mod
        }
    )

    if ($selectedMods.Count -eq 0) {
        Write-Host "Available mods:"
        $mods | Sort-Object Id | ForEach-Object {
            Write-Host ("- {0} [{1}]" -f $_.Id, $_.PackageName)
        }
        throw "Mod '$Mod' not found."
    }
}
else {
    if ($mods.Count -eq 1) {
        $selectedMods = $mods
    }
    else {
        Write-Host "Available mods:"
        $mods | Sort-Object Id | ForEach-Object {
            Write-Host ("- {0} [{1}]" -f $_.Id, $_.PackageName)
        }
        throw "Use -Mod <id> or -All."
    }
}

foreach ($modInfo in $selectedMods) {
    Copy-Mod -ModInfo $modInfo
}

Write-Host "Deploy completed."
