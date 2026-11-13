<#
.SYNOPSIS
  Rift Apart Randomizer companion (10.0): saves and restores randomizer progress, remembers a
  random seed, writes the spoiler log, and tells the game whether ARSENAL_RESTORED is installed.

.DESCRIPTION
  The randomizer runs as a rivet_hook Lua script, and rivet_hook's Lua has no file access.
  Without this companion, progress (Gold Bolts collected, rewards given) is lost whenever
  the scripts reload (Pause) or the game restarts.

  The companion talks to rivet_hook's pipe bridge (needs [bridge] enabled = true in rivet.toml):
    - after a reload or game start it restores the saved progress for the current seed,
    - whenever progress changes it saves it to  <SaveDir>\rando_<fingerprint>.lua
      (the previous save is kept as .bak),
    - when you start a New Game the randomizer starts the seed over (run 2, 3, ...); the
      previous run's file is kept as rando_<fingerprint>.run<N>.lua.
  It only calls the randomizer's own functions (rando_bridge_status, rando_export_chunk,
  rando_import_state, rando_mark_restored, rando_seed_mode, rando_use_seed, rando_spoiler_*,
  rando_arsenal_mode, rando_set_arsenal). It does not change game files or game saves.

  restored_weapons = "auto" in 04_rando_settings.lua: the companion looks for ARSENAL_RESTORED next
  to RiftApart.exe (found from the running game, or -GameDir): first the rivet_hook version (a
  folder or .stage listed under [assets] paths in rivet.toml), then the Overstrike version (the
  asset id of its added Mr. Zurkon item config in the game's toc). Found: its 9 weapons join the
  seed's pool. Not found: they stay out. Found in mods\ but not listed in rivet.toml: it says so.

  seed = "random" in 04_rando_settings.lua: the companion hands the game the seed kept in
  <SaveDir>\random_seed.txt (a new one is made and kept the first time). For a new random
  seed, start the companion with -NewRandomSeed (or delete random_seed.txt).
  Spoiler logs go to <SaveDir>\spoilers\<seed>_<fingerprint>.txt (open only if you want spoilers).

  Start it before or after the game; leave the window open while playing. Ctrl+C stops it.
  To start a seed over, delete its rando_<fingerprint>.lua file while the game is closed.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\RandoCompanion.ps1
#>
param(
    [string]$PipeName = "rivet_hook",
    [string]$SaveDir = "",
    [int]$IntervalMs = 2000,
    [int]$Iterations = 0,           # 0 = run until stopped (tests use a small number)
    [switch]$NewRandomSeed,
    [string]$GameDir = ""           # the folder of RiftApart.exe (default: found from the running game)
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Core
if ($SaveDir -eq "") { $SaveDir = Join-Path $PSScriptRoot "randomizer_saves" }
if (-not (Test-Path -LiteralPath $SaveDir)) { New-Item -ItemType Directory -Path $SaveDir | Out-Null }

function Write-Line([string]$text) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $text) }

function Read-Exactly([System.IO.Stream]$stream, [int]$count) {
    $buffer = New-Object byte[] $count
    $read = 0
    while ($read -lt $count) {
        $n = $stream.Read($buffer, $read, $count - $read)
        if ($n -le 0) { throw "pipe closed mid-message" }
        $read += $n
    }
    return ,$buffer
}

# one request -> one JSON response; rivet_hook serves one client at a time and rebuilds the
# pipe between connections, so a refused connection is retried
function Invoke-Bridge([string]$request) {
    $last = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $pipe.Connect(2000)
            $payload = [System.Text.Encoding]::UTF8.GetBytes($request)
            $header = [BitConverter]::GetBytes([uint32]$payload.Length)
            $pipe.Write($header, 0, 4)
            $pipe.Write($payload, 0, $payload.Length)
            $pipe.Flush()
            $lenBytes = Read-Exactly $pipe 4
            $length = [BitConverter]::ToUInt32($lenBytes, 0)
            $body = Read-Exactly $pipe ([int]$length)
            return ([System.Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json)
        } catch {
            $last = $_
            Start-Sleep -Milliseconds (200 * ($attempt + 1))
        } finally {
            $pipe.Dispose()
        }
    }
    throw "could not reach \\.\pipe\$PipeName ($last)"
}

function Invoke-Lua([string]$chunk) {
    $r = Invoke-Bridge ("script.exec " + $chunk)
    if (-not $r.ok) { throw "lua: $($r.error)" }
    return [string]$r.result.value
}

function Get-Status {
    $s = Invoke-Lua "return rando_bridge_status()"
    $p = $s.Split("|")
    if ($p.Length -eq 6) { throw "the game runs randomizer 1.x scripts - install this kit's scripts (scripts\*_rando_*.lua)" }
    if ($p.Length -ne 8) { throw "unexpected status '$s'" }
    return [pscustomobject]@{ Fingerprint = $p[0]; Boot = $p[1]; Version = [int]$p[2]
                              Restored = ($p[3] -eq "1"); Length = [int]$p[4]; Chunks = [int]$p[5]
                              Ready = $p[6]; Seed = $p[7] }
}

$randomFile = Join-Path $SaveDir "random_seed.txt"
if ($NewRandomSeed -and (Test-Path -LiteralPath $randomFile)) {
    Remove-Item -LiteralPath $randomFile
    Write-Line "a new random seed will be made"
}

# 7.0 restored_weapons = "auto": is ARSENAL_RESTORED installed? Its Mr. Zurkon item config is an
# asset only the mod adds (asset id B9CBAD67F39CCC3F, data/game_db.json "arsenal_marker"); an
# installed Overstrike mod is listed in the game's toc, which stores asset ids as little-endian
# 64-bit numbers. Returns "true", "false" or "unknown: <why>".
$script:ArsenalWhere = ""
$ArsenalMarker = [byte[]](0x3F, 0xCC, 0x9C, 0xF3, 0x67, 0xAD, 0xCB, 0xB9)
# 8.1: the rivet_hook version of ARSENAL_RESTORED is not in the toc: rivet_hook loads it from a
# folder (Overstrike layout, with info.json) or a .stage file listed in rivet.toml's
# [assets] paths. Such a path counts when its name, its info.json, or a file name inside it
# names ARSENAL_RESTORED or holds the marker asset id. Returns the path found, or "".
function Get-RivetAssetPaths([string]$dir) {
    $toml = Join-Path $dir "rivet.toml"
    if (-not (Test-Path -LiteralPath $toml)) { return @() }
    # the [assets] table's text (rivet_hook may rewrite the array over several lines on exit)
    $section = ""
    $inAssets = $false
    foreach ($line in [System.IO.File]::ReadAllLines($toml)) {
        $t = ($line -replace '#.*$', '').Trim()
        if ($t -match '^\[([^\]]+)\]$') { $inAssets = ($Matches[1].Trim() -eq "assets"); continue }
        if ($inAssets) { $section += " " + $t }
    }
    $out = @()
    $m = [regex]::Match($section, 'paths\s*=\s*\[([^\]]*)\]')
    if ($m.Success) {
        foreach ($q in [regex]::Matches($m.Groups[1].Value, '"([^"]*)"')) { $out += $q.Groups[1].Value }
    }
    return $out
}
function Test-ArsenalPath([string]$path) {
    $markerHex = "b9cbad67f39ccc3f"
    $leaf = Split-Path -Leaf $path
    if ($leaf -match 'arsenal') { return $true }
    if (Test-Path -LiteralPath $path -PathType Container) {
        $info = Join-Path $path "info.json"
        if ((Test-Path -LiteralPath $info) -and ((Get-Content -LiteralPath $info -Raw) -match 'arsenal')) { return $true }
        $hit = Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name.ToLowerInvariant().Contains($markerHex) } | Select-Object -First 1
        return [bool]$hit
    }
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and $path.ToLowerInvariant().EndsWith(".stage")) {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
            try {
                foreach ($e in $zip.Entries) {
                    $n = $e.FullName.ToLowerInvariant()
                    if ($n.Contains($markerHex)) { return $true }
                    if ($n -eq "info.json") {
                        $r = New-Object System.IO.StreamReader($e.Open())
                        try { if ($r.ReadToEnd() -match 'arsenal') { return $true } } finally { $r.Dispose() }
                    }
                }
            } finally { $zip.Dispose() }
        } catch { }
    }
    return $false
}
function Find-LooseArsenal([string]$dir) {
    foreach ($rel in (Get-RivetAssetPaths $dir)) {
        $full = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $dir $rel }
        if ((Test-Path -LiteralPath $full) -and (Test-ArsenalPath $full)) { return $rel }
    }
    return ""
}
# an ARSENAL_RESTORED in <game>\mods that rivet.toml does not list (rivet_hook would not load it)
function Find-UnlistedArsenal([string]$dir) {
    $mods = Join-Path $dir "mods"
    if (-not (Test-Path -LiteralPath $mods)) { return "" }
    $listed = Get-RivetAssetPaths $dir | ForEach-Object { ($_ -replace '\\', '/').TrimEnd('/').ToLowerInvariant() }
    foreach ($item in Get-ChildItem -LiteralPath $mods -ErrorAction SilentlyContinue) {
        $rel = ("mods/" + $item.Name).ToLowerInvariant()
        if ($listed -contains $rel) { continue }
        if (Test-ArsenalPath $item.FullName) { return "mods/" + $item.Name }
    }
    return ""
}
function Get-GameFolder {
    $dir = $GameDir
    if ($dir -eq "") {
        $proc = Get-Process -Name "RiftApart" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path) { $dir = Split-Path -Parent $proc.Path }
    }
    return $dir
}
function Test-ArsenalRestored {
    $dir = Get-GameFolder
    if ($dir -eq "") { return "unknown: the game's folder was not found (start the game, or use -GameDir)" }
    $loose = ""
    try { $loose = Find-LooseArsenal $dir } catch { $loose = "" }
    if ($loose -ne "") { $script:ArsenalWhere = "rivet_hook, $loose"; return "true" }
    try {
        $unlisted = Find-UnlistedArsenal $dir
        if ($unlisted -ne "") {
            Write-Line "ARSENAL_RESTORED found in $unlisted but rivet.toml does not load it: add `"$unlisted`" to paths under [assets] in rivet.toml, then restart the game"
        }
    } catch { }
    $toc = Join-Path $dir "toc"
    if (-not (Test-Path -LiteralPath $toc)) { return "unknown: no toc in $dir" }
    $bytes = [System.IO.File]::ReadAllBytes($toc)
    $latin = [System.Text.Encoding]::GetEncoding(28591)
    $text = $latin.GetString($bytes)
    if ($text.IndexOf($latin.GetString($ArsenalMarker), [System.StringComparison]::Ordinal) -ge 0) { $script:ArsenalWhere = "Overstrike"; return "true" }
    $head = $latin.GetString($bytes, 0, [Math]::Min(64, $bytes.Length))
    if ($head.IndexOf("1TAD", [System.StringComparison]::Ordinal) -lt 0) { return "unknown: the toc's format is not the one expected" }
    return "false"
}
function Provide-Arsenal {
    $mode = Invoke-Lua "return rando_arsenal_mode and rando_arsenal_mode() or 'fixed'"
    if ($mode -ne "auto") { return }
    $found = "unknown: check failed"
    try { $found = Test-ArsenalRestored } catch { $found = "unknown: " + $_.Exception.Message }
    $flag = if ($found -eq "true") { "true" } else { "false" }
    [void](Invoke-Lua "return rando_set_arsenal($flag)")
    if ($found -eq "true") { Write-Line "ARSENAL_RESTORED is installed ($script:ArsenalWhere): its weapons are in this seed's pool" }
    elseif ($found -eq "false") { Write-Line "ARSENAL_RESTORED is not installed: its weapons stay out" }
    else { Write-Line "ARSENAL_RESTORED: $found - its weapons stay out" }
}

# seed = "random": give the game the remembered seed, or let it make one and remember that
function Provide-Seed($st) {
    $mode = Invoke-Lua "return rando_seed_mode()"
    if ($mode -ne "random") { return }
    $known = ""
    if (Test-Path -LiteralPath $randomFile) { $known = [System.IO.File]::ReadAllText($randomFile).Trim() }
    $escaped = $known.Replace('\', '\\').Replace('"', '\"')
    $seed = Invoke-Lua ('return rando_use_seed("' + $escaped + '")')
    if ($seed -ne "generating" -and $seed -ne "" -and $seed -ne $known) {
        [System.IO.File]::WriteAllText($randomFile, $seed, (New-Object System.Text.UTF8Encoding $false))
        Write-Line "new random seed: $seed (kept in $randomFile)"
    } elseif ($known -ne "") {
        Write-Line "continuing random seed: $known"
    }
}

function Save-Spoiler($st) {
    $dir = Join-Path $SaveDir "spoilers"
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $safe = ($st.Seed -replace '[^A-Za-z0-9_.-]', '_')
    $file = Join-Path $dir ($safe + "_" + $st.Fingerprint + ".txt")
    if (Test-Path -LiteralPath $file) { return }
    $p = (Invoke-Lua "return rando_spoiler_status()").Split("|")
    $parts = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -le [int]$p[1]; $i++) { $parts.Add((Invoke-Lua "return rando_spoiler_chunk($i)")) }
    $text = [string]::Join("", $parts)
    if ($text.Length -ne [int]$p[0]) { throw "spoiler export was incomplete" }
    [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
    Write-Line "spoiler log written to $file (contains every placement)"
}

function Save-State($st) {
    $parts = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -le $st.Chunks; $i++) { $parts.Add((Invoke-Lua "return rando_export_chunk($i)")) }
    $text = [string]::Join("", $parts)
    $again = Get-Status
    if ($again.Version -ne $st.Version -or $again.Boot -ne $st.Boot) { return $false }   # changed while reading
    if ($text.Length -ne $st.Length -or -not $text.StartsWith("return {")) {
        throw "export was incomplete ($($text.Length) of $($st.Length) characters)"
    }
    $file = Join-Path $SaveDir ("rando_" + $st.Fingerprint + ".lua")
    $tmp = $file + ".tmp"
    [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $file) {
        # 4.0: a New Game starts a new run of the seed; the finished run's file is kept
        $oldRun = Get-Run ([System.IO.File]::ReadAllText($file))
        $newRun = Get-Run $text
        if ($oldRun -ne "" -and $newRun -ne "" -and $oldRun -ne $newRun) {
            $keep = Join-Path $SaveDir ("rando_" + $st.Fingerprint + ".run" + $oldRun + ".lua")
            Copy-Item -LiteralPath $file -Destination $keep -Force
            Write-Line "new game: run $newRun of this seed starts; run $oldRun kept as $keep"
        }
        Copy-Item -LiteralPath $file -Destination ($file + ".bak") -Force
    }
    Move-Item -LiteralPath $tmp -Destination $file -Force
    return $true
}

function Get-Run([string]$text) {
    $m = [regex]::Match($text, '\["run"\]=(\d+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Test-SaveText([string]$text) { return $text.StartsWith("return {") -and $text.EndsWith("}") }

function Restore-State($st) {
    $file = Join-Path $SaveDir ("rando_" + $st.Fingerprint + ".lua")
    if (Test-Path -LiteralPath $file) {
        $text = [System.IO.File]::ReadAllText($file).Trim()
        $from = $file
        if (-not (Test-SaveText $text)) {
            # a save cut off (power loss, disk full): the previous save is kept as .bak
            $bak = $file + ".bak"
            $btext = if (Test-Path -LiteralPath $bak) { [System.IO.File]::ReadAllText($bak).Trim() } else { "" }
            if (-not (Test-SaveText $btext)) {
                if (-not $script:damagedWarned) {
                    Write-Line "ERROR: $file is damaged and there is no usable .bak. Progress is NOT restored or saved until you fix or delete that file (then restart the companion)."
                    $script:damagedWarned = $true
                }
                return
            }
            Write-Line "WARNING: $file is damaged - using the previous save $bak"
            $text = $btext; $from = $bak
        }
        $ok = Invoke-Lua ("return tostring(rando_import_state((function() " + $text + " end)()))")
        if ($ok -eq "true") { Write-Line "restored progress from $from" }
        else {
            # 8.5: the refused file is kept aside first - the next save replaces this file (and its
            # .bak two saves later), and the progress in it would otherwise be gone
            $aside = $file + ".refused-" + (Get-Date -Format "yyyyMMdd-HHmmss")
            Copy-Item -LiteralPath $from -Destination $aside -Force
            Write-Line "the game refused $from (different seed?) - kept as $aside, starting fresh"
            [void](Invoke-Lua "return rando_mark_restored()")
        }
    } else {
        [void](Invoke-Lua "return rando_mark_restored()")
        Write-Line "no saved progress for seed $($st.Fingerprint) yet; starting fresh"
    }
}

Write-Line "Rift Apart randomizer companion (10.0) - saves to $SaveDir"
$lastBoot = ""; $lastVersion = -1; $waiting = $false; $count = 0
while ($true) {
    try {
        $st = Get-Status
        if ($waiting) { Write-Line "connected to the game"; $waiting = $false }
        if ($st.Ready -ne "ready") {
            if ($st.Ready -eq "waiting") { Provide-Arsenal; Provide-Seed $st }
        } elseif (-not $st.Restored) {
            Save-Spoiler $st
            Restore-State $st
            $lastBoot = ""; $lastVersion = -1
        } elseif ($st.Boot -ne $lastBoot -or $st.Version -ne $lastVersion) {
            if (Save-State $st) {
                $lastBoot = $st.Boot; $lastVersion = $st.Version
                Write-Line ("saved (version {0}, {1} characters)" -f $st.Version, $st.Length)
            }
        }
    } catch {
        if (-not $waiting) { Write-Line "waiting for the game / randomizer scripts ($($_.Exception.Message))"; $waiting = $true }
    }
    $count++
    if ($Iterations -gt 0 -and $count -ge $Iterations) { break }
    Start-Sleep -Milliseconds $IntervalMs
}
