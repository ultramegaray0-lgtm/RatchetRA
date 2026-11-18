<#
.SYNOPSIS
  Installs the rivet_hook version of ARSENAL_RESTORED next to the Rift Apart randomizer (8.1; v0.60).

.DESCRIPTION
  rivet_hook loads loose asset mods only from the folders (or .stage files) listed under
  [assets] paths in rivet.toml. A mod folder copied into <game>\mods but not listed there is
  never loaded, which is the usual reason the mod "does nothing".

  This script, given the ARSENAL_RESTORED zip (or its extracted folder, or its .stage file):
    1. finds the mod's assets in it: a folder holding info.json (Overstrike layout) or a .stage
       file, and copies it to <game>\mods\ARSENAL_RESTORED (or <game>\mods\ARSENAL_RESTORED.stage),
    2. copies the mod's own Lua scripts (*.lua) into <game>\scripts, next to the randomizer's;
       a script with the same name as one of the randomizer's files is never overwritten,
    3. adds the path to [assets] paths in <game>\rivet.toml (the old file is kept as rivet.toml.bak).
  It prints every step. Nothing else is changed. Restart the game afterwards.

  The randomizer's restored_weapons = "auto" (04_rando_settings.lua) then puts its weapons in the
  seed's pool: the companion finds the mod through rivet.toml.

.EXAMPLE
  Install-ArsenalRestored.bat "<your downloads folder>\ARSENAL RESTORED 5.7 Beta (RIVET HOOK VERSION).zip"
#>
param(
    [string]$Source = "",
    [string]$GameDir = ""
)
$ErrorActionPreference = "Stop"
function Say([string]$text) { Write-Host $text }

# the game's folder: -GameDir, the folder above this companion folder, or the running game
function Find-Game {
    if ($GameDir -ne "") { return $GameDir }
    $up = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $up "RiftApart.exe")) { return $up }
    $proc = Get-Process -Name "RiftApart" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { return (Split-Path -Parent $proc.Path) }
    return (Read-Host "The game's folder (the one with RiftApart.exe)").Trim('"')
}

$game = Find-Game
if (-not (Test-Path -LiteralPath (Join-Path $game "RiftApart.exe"))) { throw "RiftApart.exe is not in '$game'" }
if ($Source -eq "") { $Source = (Read-Host "Drag the ARSENAL_RESTORED zip (or folder, or .stage) here and press Enter").Trim('"') }
if (-not (Test-Path -LiteralPath $Source)) { throw "'$Source' does not exist" }
Say "game:   $game"
Say "source: $Source"

# 1. the source as a folder
$work = $Source
$temp = $null
if ((Test-Path -LiteralPath $Source -PathType Leaf) -and $Source.ToLowerInvariant().EndsWith(".zip")) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("arsenal_" + [guid]::NewGuid().ToString("N"))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Source, $temp)
    $work = $temp
    Say "extracted to $temp"
}

try {
    $mods = Join-Path $game "mods"
    if (-not (Test-Path -LiteralPath $mods)) { New-Item -ItemType Directory -Path $mods | Out-Null }
    $entry = ""
    if ((Test-Path -LiteralPath $work -PathType Leaf) -and $work.ToLowerInvariant().EndsWith(".stage")) {
        Copy-Item -LiteralPath $work -Destination (Join-Path $mods "ARSENAL_RESTORED.stage") -Force
        $entry = "mods/ARSENAL_RESTORED.stage"
        Say "assets: copied the .stage to $entry"
    } else {
        # the shallowest folder holding info.json; else a .stage inside
        $infos = @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter "info.json" -ErrorAction SilentlyContinue |
                   Sort-Object { $_.FullName.Length })
        $stages = @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter "*.stage" -ErrorAction SilentlyContinue)
        if ($infos.Count -gt 0) {
            $from = $infos[0].DirectoryName
            $to = Join-Path $mods "ARSENAL_RESTORED"
            if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }
            Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
            $entry = "mods/ARSENAL_RESTORED"
            Say "assets: copied $from to $entry"
        } elseif ($stages.Count -gt 0) {
            Copy-Item -LiteralPath $stages[0].FullName -Destination (Join-Path $mods "ARSENAL_RESTORED.stage") -Force
            $entry = "mods/ARSENAL_RESTORED.stage"
            Say "assets: copied $($stages[0].Name) to $entry"
        } else {
            Say "assets: no info.json folder and no .stage found - nothing copied to mods"
        }

        # 2. the mod's Lua scripts
        # v0.60: every randomizer script is protected by its name pattern (NN_rando_*.lua, enemy.lua, dev(*).lua),
        # not by a fixed list (v0.54's list missed 15_rando_hub.lua and every later file)
        $ours = @("enemy.lua")
        $scripts = Join-Path $game "scripts"
        if (-not (Test-Path -LiteralPath $scripts)) { New-Item -ItemType Directory -Path $scripts | Out-Null }
        foreach ($lua in @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter "*.lua" -ErrorAction SilentlyContinue)) {
            $n = $lua.Name.ToLowerInvariant()
            if (($ours -contains $n) -or ($n -match '^\d\d_rando_.*\.lua$') -or ($n -match '^dev\(.*\)\.lua$')) { Say "lua: skipped $($lua.Name) (a randomizer file has that name)"; continue }
            Copy-Item -LiteralPath $lua.FullName -Destination (Join-Path $scripts $lua.Name) -Force
            Say "lua: copied $($lua.Name) to scripts"
        }
        foreach ($toml in @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter "rivet.toml" -ErrorAction SilentlyContinue)) {
            Say "note: the mod ships its own $($toml.FullName.Substring($work.Length)) - not copied (the randomizer's rivet.toml is kept; only the path below is added)"
        }
    }

    # 3. rivet.toml
    if ($entry -ne "") {
        $tomlPath = Join-Path $game "rivet.toml"
        if (-not (Test-Path -LiteralPath $tomlPath)) { throw "no rivet.toml in $game (install the randomizer first)" }
        $text = [System.IO.File]::ReadAllText($tomlPath)
        if ($text.Contains('"' + $entry + '"')) {
            Say "rivet.toml: already lists $entry"
        } else {
            Copy-Item -LiteralPath $tomlPath -Destination ($tomlPath + ".bak") -Force
            $section = [regex]::Match($text, '(?ms)^\[assets\].*?(?=^\[|\z)')
            if (-not $section.Success) {
                $text = $text.TrimEnd() + "`r`n`r`n[assets]`r`nenabled = true`r`npaths = [`"mods/default`", `"$entry`"]`r`n"
            } else {
                $body = $section.Value
                $arr = [regex]::Match($body, 'paths\s*=\s*\[([^\]]*)\]')
                if ($arr.Success) {
                    $inside = $arr.Groups[1].Value.TrimEnd().TrimEnd(',')
                    $newArr = "paths = [" + $inside + $(if ($inside.Trim() -ne "") { ", " } else { "" }) + "`"$entry`"]"
                    $body = $body.Substring(0, $arr.Index) + $newArr + $body.Substring($arr.Index + $arr.Length)
                } else {
                    $body = $body.TrimEnd() + "`r`npaths = [`"mods/default`", `"$entry`"]`r`n`r`n"
                }
                $body = [regex]::Replace($body, '(?m)^enabled\s*=\s*false', 'enabled = true')
                $text = $text.Substring(0, $section.Index) + $body + $text.Substring($section.Index + $section.Length)
            }
            [System.IO.File]::WriteAllText($tomlPath, $text)
            Say "rivet.toml: added $entry to [assets] paths (old file: rivet.toml.bak)"
        }
    }
} finally {
    if ($temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
Say ""
Say "Done. Restart the game. rivet.log should show: [loader] mod path $entry is overstrike format."
Say "With restored_weapons = `"auto`" the companion now reports ARSENAL_RESTORED as installed."
