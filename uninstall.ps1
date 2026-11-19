<#
 Avinstallera Wuppa på Windows (fungerar även i pwsh på macOS/Linux):
   irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.ps1 | iex
 Från en lokal kopia:  ./uninstall.ps1

 Tar bort programmet (~/.wuppa/app), kommandot wuppa och PATH-posten.
 Behåller Wuppas inställningar (~/.wuppa).
 $env:WUPPA_PURGE = '1' tar bort även .wuppa med dina data. $env:WUPPA_YES = '1' hoppar över frågan.
 Har Wuppa installerat släkten frågar den om de ska bort också ($env:WUPPA_ALL = '1' = ja).
#>
$ErrorActionPreference = 'Stop'
$Clock = [Diagnostics.Stopwatch]::StartNew()
$OnWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
$Dir = Join-Path $HOME '.wuppa'
$Bin = Join-Path $Dir 'bin'
$Shim = if ($OnWindows) { Join-Path $Bin 'wuppa.cmd' } else { Join-Path $HOME '.local/bin/wuppa' }

# Language: TRUPPA_LANG, else ~/.truppa/config.json (shared by the whole troupe), else English
$TL = $env:TRUPPA_LANG
if (-not $TL) { try { $TL = (Get-Content -Raw -LiteralPath (Join-Path $HOME '.truppa/config.json') -ErrorAction Stop | ConvertFrom-Json).lang } catch { } }
function T([string]$en, [string]$sv) { if ("$TL" -like 'sv*') { $sv } else { $en } }
function Say($m) { Write-Host "  W› $m" -ForegroundColor Yellow }
function Ask($q) { $s = Read-Host "  $q $(T '[y/N]' '[j/N]')"; return ($s -match '^(j|ja|y|yes)$') }

# Hela släkten? ($env:WUPPA_ALL = '1' svarar ja). Varje verktyg avinstalleras med sitt eget skript.
$family = @()
foreach ($n in 'uppa', 'puppa', 'muppa', 'euppa', 'ruppa') {
    $exe = if ($n -eq 'ruppa') { Join-Path $HOME ".ruppa/bin/$(if ($OnWindows) { 'ruppa.exe' } else { 'ruppa' })" }
           elseif ($OnWindows) { Join-Path $HOME ".$n/bin/$n.cmd" } else { Join-Path $HOME ".local/bin/$n" }
    if (Test-Path $exe) { $family += $n }
}
$all = $false
if ($family) {
    if ($env:WUPPA_ALL -eq '1') { $all = $true }
    elseif ($env:WUPPA_YES -ne '1') {
        Write-Host (T "`n  Installed tools from the troupe: $($family -join ', ')" "`n  Installerat av släkten: $($family -join ', ')")
        $all = Ask (T 'Remove them too (their data is kept)?' 'Ta bort dem också (deras data behålls)?')
    }
}

$targets = @()
if ($env:WUPPA_PURGE -eq '1') {
    if (Test-Path $Dir) { $targets += $Dir }
} else {
    foreach ($p in @('app', 'bin')) { $x = Join-Path $Dir $p; if (Test-Path $x) { $targets += $x } }
}
# startkommandot på macOS/Linux: bara om det är vårt (pekar på ~/.wuppa)
if (-not $OnWindows -and (Test-Path $Shim) -and ((Get-Content $Shim -Raw) -like "*/.wuppa/*")) { $targets += $Shim }
$user = if ($OnWindows) { [Environment]::GetEnvironmentVariable('Path', 'User') } else { '' }
if (-not $user) { $user = '' }
$inPath = ($user -split ';') -contains $Bin

if (-not $targets -and -not $inPath) { Say (T 'Wuppa is not installed here. Nothing to remove.' 'Wuppa är inte installerad här. Inget att ta bort.'); return }
Write-Host (T "`n  This is removed:" "`n  Det här tas bort:")
$targets | ForEach-Object { Write-Host "    $_" }
if ($inPath) { Write-Host "    $Bin i din PATH" }
if ($env:WUPPA_PURGE -ne '1') { Write-Host (T '  Kept: the Wuppa settings (~/.wuppa).' '  Behålls: Wuppas inställningar (~/.wuppa).') }
Write-Host ''
if ($env:WUPPA_YES -ne '1') {
    if (-not (Ask (T 'Uninstall Wuppa?' 'Avinstallera Wuppa?'))) { Say (T 'Cancelled. Nothing has been removed.' 'Avbrutet. Ingenting har tagits bort.'); return }
}

if ($all) {
    $ps = if ($OnWindows) { 'powershell.exe' } else { 'pwsh' }
    $failed = @()
    foreach ($n in $family) {
        Write-Host ''
        $local = if ($PSScriptRoot) { Join-Path (Split-Path $PSScriptRoot -Parent) "$n/uninstall.ps1" } else { $null }
        Set-Item "Env:$($n.ToUpper())_YES" '1'
        if ($local -and (Test-Path $local)) { & $ps -NoProfile -ExecutionPolicy Bypass -File $local }
        else { & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/pipebreak33/$n/main/uninstall.ps1 | iex" }
        if ($LASTEXITCODE -ne 0) { $failed += $n }
    }
    if ($failed) { Write-Host (T "  ! Could not uninstall: $($failed -join ', ')" "  ! Gick inte att avinstallera: $($failed -join ', ')") -ForegroundColor Yellow }
}

foreach ($t in $targets) { Remove-Item $t -Recurse -Force }
if ($inPath) {
    [Environment]::SetEnvironmentVariable('Path', (($user -split ';' | Where-Object { $_ -and $_ -ne $Bin }) -join ';'), 'User')
}
if ((Test-Path $Dir) -and -not (Get-ChildItem $Dir -Force)) { Remove-Item $Dir -Force }

$Clock.Stop()
Write-Host (T "`n  ✔ Wuppa is uninstalled$(if ($all) { ', with the whole troupe' }) ($([int]$Clock.Elapsed.TotalSeconds) s).`n" "`n  ✔ Wuppa är avinstallerad$(if ($all) { ', med släkten' }) ($([int]$Clock.Elapsed.TotalSeconds) s).`n") -ForegroundColor Green
