<#
 Wuppa för Windows (Windows PowerShell 5.1 eller PowerShell 7). Fungerar även i pwsh på macOS/Linux.
 Installerar Wuppa och kusinerna Uppa, Puppa, Muppa, Euppa och Ruppa. Kör igen = allt uppdateras:
   irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/install.ps1 | iex
 Från en lokal kopia:  ./install.ps1   (finns ..\uppa, ..\puppa, ..\muppa, ..\euppa, ..\ruppa bredvid används de också)
 Styr källan med $env:WUPPA_REPO = 'ägare/repo' och $env:WUPPA_BRANCH = 'gren eller tagg'.
 $env:WUPPA_ONLY = '1' installerar bara Wuppa. $env:WUPPA_SKIP = 'muppa puppa' hoppar över kusiner.
 Inga frågor.

 Wuppa och kusinerna är Python-skript utan beroenden. Saknas Python 3.8+ installeras det:
   1. med winget (per användare), annars
   2. direkt från python.org (per användare, inga adminrättigheter).
#>
$ErrorActionPreference = 'Stop'
$Clock = [Diagnostics.Stopwatch]::StartNew()
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSEdition -ne 'Core') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
$Repo   = if ($env:WUPPA_REPO)   { $env:WUPPA_REPO }   else { 'pipebreak33/wuppa' }
$Branch = if ($env:WUPPA_BRANCH) { $env:WUPPA_BRANCH } else { 'main' }
$OnWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
$Dir = Join-Path $HOME '.wuppa'
$App = Join-Path $Dir 'app'
$PyVersion = '3.12.8'

# Language: TRUPPA_LANG, else ~/.truppa/config.json (shared by the whole troupe), else English
$TL = $env:TRUPPA_LANG
if (-not $TL) { try { $TL = (Get-Content -Raw -LiteralPath (Join-Path $HOME '.truppa/config.json') -ErrorAction Stop | ConvertFrom-Json).lang } catch { } }
function T([string]$en, [string]$sv) { if ("$TL" -like 'sv*') { $sv } else { $en } }
function Say($m)  { Write-Host "  W› $m" -ForegroundColor Yellow }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }

function Update-SessionPath {
    if (-not $OnWindows) { return }
    $env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'),
                   [Environment]::GetEnvironmentVariable('Path', 'User'),
                   (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')) | Where-Object { $_ }) -join ';'
}

function Test-Python($exe, $extra) {
    try {
        & $exe @($extra + @('-c', 'import sys; sys.exit(sys.version_info < (3,8))')) 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Find-Python {
    $candidates = if ($OnWindows) { @(@('py', '-3'), @('python'), @('python3')) } else { @(@('python3'), @('python')) }
    foreach ($c in $candidates) {
        $cmd = Get-Command $c[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        $extra = @($c | Select-Object -Skip 1)
        # Microsoft Store-aliaset python.exe startar inget riktigt Python – Test-Python sorterar bort det
        if (Test-Python $cmd.Source $extra) { return , (@($cmd.Source) + $extra) }
    }
    if ($OnWindows) {
        foreach ($p in @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
                         "$env:LOCALAPPDATA\Programs\Python\Launcher\py.exe")) {
            if (Test-Path $p) {
                $extra = if ($p -like '*py.exe') { @('-3') } else { @() }
                if (Test-Python $p $extra) { return , (@($p) + $extra) }
            }
        }
    }
    return $null
}

function Install-Python {
    if (-not $OnWindows) {
        throw (T 'Python 3.8+ is missing. macOS: xcode-select --install (or brew install python). Linux: sudo apt install python3.' 'Python 3.8+ saknas. macOS: xcode-select --install (eller brew install python). Linux: sudo apt install python3.')
    }
    Update-SessionPath
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Say (T 'Installing Python 3 with winget' 'Installerar Python 3 med winget')
        winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { Update-SessionPath; return }
        Warn (T 'winget could not install Python, trying python.org' 'winget kunde inte installera Python, provar python.org')
    }
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { '-arm64' } 'x86' { '' } default { '-amd64' } }
    $url = "https://www.python.org/ftp/python/$PyVersion/python-$PyVersion$arch.exe"
    $exe = Join-Path $env:TEMP "python-$PyVersion-setup.exe"
    Say (T "Fetching Python $PyVersion from python.org" "Hämtar Python $PyVersion från python.org")
    Invoke-WebRequest $url -OutFile $exe -UseBasicParsing
    $p = Start-Process $exe -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1',
                                         'Include_test=0', 'Shortcuts=0' -Wait -PassThru
    Remove-Item $exe -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Python-installationen misslyckades (kod $($p.ExitCode))." }
    Update-SessionPath
}

function Invoke-Py([string[]]$more) {
    & $py[0] @(@($py | Select-Object -Skip 1) + $more)
}

# 1. Python
$py = Find-Python
if (-not $py) {
    Install-Python
    $py = Find-Python
    if (-not $py) { throw (T 'Python was installed but is not visible yet. Open a NEW PowerShell window and run the installation again.' 'Python installerades men syns inte än. Öppna ett NYTT PowerShell-fönster och kör installationen igen.') }
}

# 2. Källan: en lokal checkout bredvid skriptet, annars arkivet från GitHub
$src = $null
$tmp = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'wuppa.py')) -and $env:WUPPA_FROM_WEB -ne '1') {
    $src = $PSScriptRoot
    Say (T "Installing from $src" "Installerar från $src")
}
try {
    if (-not $src) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("wuppa-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'wuppa.zip'
        Say (T "Fetching Wuppa from github.com/$Repo ($Branch)" "Hämtar Wuppa från github.com/$Repo ($Branch)")
        Invoke-WebRequest "https://github.com/$Repo/archive/$Branch.zip" -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $found = Get-ChildItem -Path $tmp -Filter 'wuppa.py' -Recurse -Depth 2 | Select-Object -First 1
        if (-not $found) { throw (T 'The archive does not contain Wuppa.' 'Arkivet innehåller inte Wuppa.') }
        $src = $found.DirectoryName
    }
    Invoke-Py @('-c', 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read())', (Join-Path $src 'wuppa.py'))
    if ($LASTEXITCODE -ne 0) { throw (T 'wuppa.py is broken.' 'wuppa.py är trasig.') }

    # 3. Byt ut programmet (~/.wuppa/app)
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $new = "$App.new"
    if (Test-Path $new) { Remove-Item $new -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $new | Out-Null
    Copy-Item (Join-Path $src 'wuppa.py') $new -Force
    foreach ($f in 'README.md', 'LICENSE') { $s = Join-Path $src $f; if (Test-Path $s) { Copy-Item $s $new -Force } }
    if (Test-Path $App) { Remove-Item $App -Recurse -Force }
    Move-Item $new $App
} finally {
    if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
$target = Join-Path $App 'wuppa.py'

# 4. Startkommando + PATH
if ($OnWindows) {
    $bin = Join-Path $Dir 'bin'
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    # Citera bara exe-filen: py-startaren skickar annars vidare ett citerat "-3" till python.exe
    $launcher = '"' + $py[0] + '"' + ((@($py | Select-Object -Skip 1) | ForEach-Object { " $_" }) -join '') +
                ' "%USERPROFILE%\.wuppa\app\wuppa.py" %*'
    Set-Content -Path (Join-Path $bin 'wuppa.cmd') -Value "@echo off`r`n$launcher" -Encoding ASCII
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $user) { $user = '' }
    if (($user -split ';') -notcontains $bin) {
        [Environment]::SetEnvironmentVariable('Path', (($user.TrimEnd(';') + ';' + $bin).TrimStart(';')), 'User')
        Say 'La till Wuppa i din PATH.'
    }
    if (($env:Path -split ';') -notcontains $bin) { $env:Path += ";$bin" }
} else {
    $bin = Join-Path $HOME '.local/bin'
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $shim = Join-Path $bin 'wuppa'
    # En ev. gammal symlänk tas bort först – skriv aldrig genom den
    if (Test-Path $shim) { Remove-Item $shim -Force }
    Set-Content -Path $shim -Value "#!/usr/bin/env sh`nexec `"$($py[0])`" `"$target`" `"`$@`"`n" -NoNewline
    chmod +x $shim
    if ((($env:PATH -split ':') -notcontains $bin)) {
        Warn (T "Add $bin to PATH (e.g. in ~/.zshrc: export PATH=`"`$HOME/.local/bin:`$PATH`")" "Lägg till $bin i PATH (t.ex. i ~/.zshrc: export PATH=`"`$HOME/.local/bin:`$PATH`")")
    }
}

$ver = Invoke-Py @($target, '--version') 2>$null
Write-Host (T "  ✔ $ver installed." "  ✔ $ver installerad.") -ForegroundColor Green

# 5. Kusinerna: kör var och ens egen installer i en egen process (ett fel där stoppar inte de andra)
$failed = @()
if ($env:WUPPA_ONLY -ne '1') {
    $owner = $Repo.Split('/')[0]
    $skip = @(if ($env:WUPPA_SKIP) { $env:WUPPA_SKIP -split '[\s,;]+' })
    $ps = if ($OnWindows) { 'powershell.exe' } else { 'pwsh' }
    $env:RUPPA_NO_OPEN = '1'          # Ruppa: öppna inte appen mitt i installationen
    foreach ($name in 'uppa', 'puppa', 'muppa', 'euppa', 'ruppa') {
        if ($skip -contains $name) { continue }
        Write-Host ''
        $localDir = if ($PSScriptRoot) { Join-Path (Split-Path $PSScriptRoot -Parent) $name } else { $null }
        if ($src -eq $PSScriptRoot -and $localDir -and (Test-Path (Join-Path $localDir 'install.ps1')) -and
                ((Test-Path (Join-Path $localDir "$name.py")) -or (Test-Path (Join-Path $localDir 'Cargo.toml')))) {
            Say (T "$name from $localDir" "$name från $localDir")
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $localDir 'install.ps1')
        } else {
            Say (T "$name from github.com/$owner/$name" "$name från github.com/$owner/$name")
            & $ps -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/$owner/$name/main/install.ps1 | iex"
        }
        if ($LASTEXITCODE -ne 0) { $failed += $name }
    }
}
if ($OnWindows) { Update-SessionPath }

Write-Host ''
$Clock.Stop(); $took = if ($Clock.Elapsed.TotalSeconds -ge 60) { '{0} min {1} s' -f [int][math]::Floor($Clock.Elapsed.TotalMinutes), $Clock.Elapsed.Seconds } else { '{0} s' -f [int]$Clock.Elapsed.TotalSeconds }
if ($failed) {
    Warn ((T "This did not work ($took): " "Det här gick inte ($took): ") + ($failed -join ', ') + (T ". Run the same line again in a while, or: wuppa install " ". Kör samma rad igen om en stund, eller: wuppa install ") + ($failed -join ' '))
} else {
    Write-Host (T "  W› Done in $took! Open a new terminal and run wuppa for the menu, or uppa, puppa, muppa, euppa and ruppa directly." "  W› Klart på $took! Öppna en ny terminal och kör wuppa för menyn, eller uppa, puppa, muppa, euppa och ruppa direkt.") -ForegroundColor Yellow
    Write-Host (T "  Uninstall: irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.ps1 | iex   (asks about the whole troupe)`n" "  Avinstallera: irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.ps1 | iex   (frågar om hela släkten)`n") -ForegroundColor DarkGray
}
