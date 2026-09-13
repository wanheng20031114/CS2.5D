[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [switch]$SkipImport,
    [switch]$Archive
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$buildRoot = Join-Path $projectRoot 'builds'
$logRoot = Join-Path $buildRoot 'logs'
$executable = Join-Path $buildRoot 'Mirage.exe'
$pack = Join-Path $buildRoot 'Mirage.pck'
$candidates = @($GodotPath, $env:GODOT_PATH, 'C:/Program Files/Godot/Godot_console.exe', 'C:/Program Files/Godot/Godot.exe')
foreach ($commandName in @('Godot_console.exe', 'godot', 'Godot.exe')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
}
$engine = $null
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $engine = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (-not $engine) { throw 'Godot was not found. Install Godot 4.6.3 or pass -GodotPath.' }

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Invoke-GodotStep {
    param([string]$StepName, [string[]]$Arguments)
    $stdout = Join-Path $logRoot ($StepName + '.stdout.log')
    $stderr = Join-Path $logRoot ($StepName + '.stderr.log')
    $parameters = @{
        FilePath = $engine
        ArgumentList = $Arguments
        WorkingDirectory = $projectRoot
        WindowStyle = 'Hidden'
        Wait = $true
        PassThru = $true
        RedirectStandardOutput = $stdout
        RedirectStandardError = $stderr
    }
    $ownedProcess = Start-Process @parameters
    if ($ownedProcess.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Tail 25 | Write-Host }
        throw "Godot step '$StepName' failed with code $($ownedProcess.ExitCode). Logs: $logRoot"
    }
}

Invoke-GodotStep -StepName 'version' -Arguments @('--version')
$versionText = (Get-Content -LiteralPath (Join-Path $logRoot 'version.stdout.log') -Raw).Trim()
if ($versionText -notmatch '^4\.6\.3\.') {
    throw "This preset targets Godot 4.6.3 with matching export templates; found '$versionText'."
}

if (-not $SkipImport) {
    Write-Host 'Importing native project resources...'
    Invoke-GodotStep -StepName 'import' -Arguments @('--headless', '--path', ('"' + $projectRoot + '"'), '--editor', '--import', '--quit')
}

Write-Host 'Exporting Windows x64...'
Invoke-GodotStep -StepName 'export' -Arguments @('--headless', '--path', ('"' + $projectRoot + '"'), '--export-release', '"Windows Desktop"', ('"' + $executable + '"'))
if (-not (Test-Path -LiteralPath $executable -PathType Leaf) -or -not (Test-Path -LiteralPath $pack -PathType Leaf)) {
    throw "Export did not produce both Mirage.exe and Mirage.pck. See $logRoot"
}
if ((Get-Item -LiteralPath $executable).Length -lt 1000000 -or (Get-Item -LiteralPath $pack).Length -lt 100000) {
    throw "Export output is unexpectedly small. See $logRoot"
}
$readme = Join-Path $buildRoot 'README.zh-CN.md'
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $readme -Force
$deliverables = @($executable, $pack, $readme)
$buildDocs = Join-Path $buildRoot 'docs'
New-Item -ItemType Directory -Path $buildDocs -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'docs') -Filter '*.md' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $buildDocs -Force
}
if ($Archive) {
    $archivePath = Join-Path $buildRoot 'Mirage-Windows-x64.zip'
    Compress-Archive -LiteralPath ($deliverables + $buildDocs) -DestinationPath $archivePath -CompressionLevel Optimal -Force
    $deliverables += $archivePath
}
Get-Item -LiteralPath $deliverables | Select-Object FullName, Length
Write-Host 'Build complete. Run builds/Mirage.exe; keep its .pck beside it.'
