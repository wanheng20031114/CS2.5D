[CmdletBinding()]
param(
    [switch]$Editor,
    [switch]$Source,
    [switch]$Compatibility,
    [string]$GodotPath = '',
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$gameExecutable = Join-Path $projectRoot 'builds/Mirage.exe'
$gamePack = Join-Path $projectRoot 'builds/Mirage.pck'
$nativeArguments = @()

if (-not $Editor -and -not $Source -and (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $gamePack -PathType Leaf)) {
        throw 'Mirage.pck is missing. Keep Mirage.exe and Mirage.pck together, or run with -Source.'
    }
    $launchPath = $gameExecutable
    $workingDirectory = Split-Path -Parent $gameExecutable
} else {
    $candidates = @($GodotPath, $env:GODOT_PATH, 'C:/Program Files/Godot/Godot.exe', 'C:/Program Files/Godot/Godot_console.exe')
    foreach ($commandName in @('godot', 'Godot.exe', 'Godot_console.exe')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    $launchPath = $null
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $launchPath = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
    }
    if (-not $launchPath) {
        throw 'Godot was not found. Install Godot 4.6.3 or pass -GodotPath C:/path/to/Godot.exe.'
    }
    # The GUI executable keeps a normal user-initiated game/editor window without a console.
    $guiPath = Join-Path (Split-Path -Parent $launchPath) 'Godot.exe'
    if ((Split-Path -Leaf $launchPath) -eq 'Godot_console.exe' -and (Test-Path -LiteralPath $guiPath)) {
        $launchPath = $guiPath
    }
    $workingDirectory = $projectRoot
    $nativeArguments += @('--path', ('"' + $projectRoot + '"'))
    if ($Editor) { $nativeArguments += '--editor' }
    $classCache = Join-Path $projectRoot '.godot/global_script_class_cache.cfg'
    if (-not $Editor -and -not (Test-Path -LiteralPath $classCache -PathType Leaf)) {
        Write-Host 'Importing resources for the first source launch...'
        $importParameters = @{
            FilePath = $launchPath
            ArgumentList = @('--headless', '--path', ('"' + $projectRoot + '"'), '--editor', '--import', '--quit')
            WorkingDirectory = $projectRoot
            WindowStyle = 'Hidden'
            Wait = $true
            PassThru = $true
        }
        $importProcess = Start-Process @importParameters
        if ($importProcess.ExitCode -ne 0) { throw 'Godot resource import failed. Open with -Editor to inspect the project.' }
    }
}

if ($Compatibility) { $nativeArguments += @('--rendering-method', 'gl_compatibility') }
$launchParameters = @{
    FilePath = $launchPath
    WorkingDirectory = $workingDirectory
    WindowStyle = 'Normal'
    PassThru = $true
}
if ($nativeArguments.Count -gt 0) { $launchParameters.ArgumentList = $nativeArguments }
if ($Wait) { $launchParameters.Wait = $true }
$process = Start-Process @launchParameters
if ($Wait -and $process.ExitCode -ne 0) { throw "Game exited with code $($process.ExitCode)." }
Write-Host ("Launched: {0} (PID {1})" -f $launchPath, $process.Id)
