# AI Terminal - Windows Installation Script
# PowerShell installation for Windows users
#
# This file is saved as UTF-8 with a byte order mark. Windows PowerShell 5.1 reads a BOM-less file
# in the ANSI code page, where the emoji below turn into quote characters and break the parser.

param(
    [switch]$Force
)

function Get-AITerminalModuleRoot {
    # Folder the module is installed into. Windows PowerShell 5.1 and PowerShell 7 search different
    # folders, so it depends on the edition that runs the installer. The Documents folder is asked
    # from Windows because it is often redirected (for example to OneDrive).
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('AllUsers', 'CurrentUser')]
        [string]$Scope,
        [string]$Edition = $PSVersionTable.PSEdition,
        [string]$Documents = [Environment]::GetFolderPath('MyDocuments'),
        [string]$ProgramFiles = $env:ProgramFiles
    )

    $editionFolder = if ($Edition -eq 'Core') { 'PowerShell' } else { 'WindowsPowerShell' }
    $base = if ($Scope -eq 'AllUsers') { $ProgramFiles } else { $Documents }
    return [System.IO.Path]::Combine($base, $editionFolder, 'Modules', 'AITerminal')
}

function Get-AITerminalManifest {
    # Text of the manifest for the installed module. The export lists and the version are read from
    # the module file, so every alias has its function exported and nothing has to be kept in sync.
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ModulePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) { throw "Cannot parse ${ModulePath}: $($errors[0].Message)" }

    $export = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Export-ModuleMember' }, $true) | Select-Object -First 1
    if (-not $export) { throw "No Export-ModuleMember call found in $ModulePath" }

    $lists = @{ function = @(); alias = @() }
    $elements = @($export.CommandElements)
    for ($i = 1; $i -lt $elements.Count - 1; $i++) {
        if ($elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        $key = $elements[$i].ParameterName.ToLowerInvariant()
        if (-not $lists.ContainsKey($key)) { continue }
        $lists[$key] = @($elements[$i + 1].FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
    }
    if ($lists.function.Count -eq 0) { throw "Export-ModuleMember in $ModulePath exports no functions" }

    $version = '0.0.0'
    if ((Get-Content -Path $ModulePath -Raw) -match '\$script:ModuleVersion\s*=\s*''([0-9]+(\.[0-9]+){1,3})''') { $version = $Matches[1] }

    $functionList = ($lists.function | ForEach-Object { "'$_'" }) -join ', '
    $aliasList = ($lists.alias | ForEach-Object { "'$_'" }) -join ', '

    return @"
@{
    RootModule = 'AITerminal.psm1'
    ModuleVersion = '$version'
    GUID = '0a6ed99e-3d36-4a02-95c9-044f3bf85204'
    Author = 'AI Terminal Team'
    Description = 'Natural Language AI Terminal - Convert plain English to CLI commands'
    PowerShellVersion = '5.0'
    FunctionsToExport = @($functionList)
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @($aliasList)
}
"@
}

Write-Host "🤖 AI Terminal - Windows Installation" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $Force) {
    Write-Host "⚠️  For best experience, run as Administrator to install system-wide." -ForegroundColor Yellow
    Write-Host "   Use -Force to install for current user only." -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Continue with user installation? [y/N]"
    if ("$choice".ToLower() -ne 'y') {
        Write-Host "Installation cancelled. Run as Administrator or use -Force flag." -ForegroundColor Red
        exit 1
    }
}

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "❌ PowerShell 5.0 or higher is required." -ForegroundColor Red
    Write-Host "   Please update PowerShell: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}

# Check if Ollama is installed
$ollamaPath = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaPath) {
    Write-Host "❌ Ollama is required but not installed." -ForegroundColor Red
    Write-Host "📦 Installing Ollama..." -ForegroundColor Yellow

    # Check if winget is available
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) {
        # winget is a native program: it reports failure through its exit code, not an exception.
        & winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to install via winget (exit code $LASTEXITCODE). Please install manually:" -ForegroundColor Red
            Write-Host "   https://ollama.com/download/windows" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "❌ Please install Ollama manually from: https://ollama.com/download/windows" -ForegroundColor Red
        Write-Host "   Then run this script again." -ForegroundColor Yellow
        exit 1
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# Start Ollama service
Write-Host "🚀 Starting Ollama service..." -ForegroundColor Cyan
try {
    $ollamaProcess = Get-Process ollama -ErrorAction SilentlyContinue
    if (-not $ollamaProcess) {
        Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
    }
} catch {
    Write-Host "⚠️  Could not start Ollama service automatically." -ForegroundColor Yellow
    Write-Host "   Please start Ollama manually before using AI Terminal." -ForegroundColor Gray
}

# Pull required model
Write-Host "📥 Downloading AI model (llama3.2:1b)..." -ForegroundColor Cyan
try {
    & ollama pull llama3.2:1b
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to pull model"
    }
} catch {
    Write-Host "❌ Failed to download AI model. Please run 'ollama pull llama3.2:1b' manually." -ForegroundColor Red
}

# Determine installation path
$scope = if ($isAdmin -and -not $Force) { "AllUsers" } else { "CurrentUser" }
$modulePath = Get-AITerminalModuleRoot -Scope $scope

# Create module directory
Write-Host "📦 Installing AI Terminal module to $scope ($modulePath)..." -ForegroundColor Cyan
if (-not (Test-Path $modulePath)) {
    New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
}

# Copy module file
$sourceModule = Join-Path $PSScriptRoot "NewTerminal-AI.psm1"
if (Test-Path $sourceModule) {
    Copy-Item $sourceModule -Destination (Join-Path $modulePath "AITerminal.psm1") -Force
} else {
    Write-Host "❌ Source module not found: $sourceModule" -ForegroundColor Red
    exit 1
}

# Create module manifest
$manifestPath = Join-Path $modulePath "AITerminal.psd1"
Get-AITerminalManifest -ModulePath $sourceModule | Out-File -FilePath $manifestPath -Encoding UTF8

# Update PowerShell profile
$profilePath = $PROFILE.CurrentUserAllHosts
if (-not $profilePath) {
    $profilePath = Join-Path (Split-Path (Get-AITerminalModuleRoot -Scope CurrentUser) -Parent | Split-Path -Parent) "profile.ps1"
}

$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# Add auto-import to profile. The module starts its prompt only in an interactive console, so this
# line does not affect scripts or 'pwsh -Command'.
$importLine = "Import-Module AITerminal -Force"
if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -notmatch [regex]::Escape($importLine)) {
        Add-Content -Path $profilePath -Value "`n# AI Terminal Auto-Load`n$importLine"
    }
} else {
    "# AI Terminal Auto-Load`n$importLine" | Out-File -FilePath $profilePath -Encoding UTF8
}

# Create desktop shortcut for the PowerShell edition the module was installed for
if ($isAdmin -or $Force) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "AI Terminal.lnk"
    $hostExecutable = (Get-Process -Id $PID).Path

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $hostExecutable
    $shortcut.Arguments = "-NoExit -Command `"Import-Module AITerminal -Force`""
    $shortcut.Description = "AI Terminal - Natural Language Interface"
    $shortcut.IconLocation = "$hostExecutable,0"
    $shortcut.Save()
}

Write-Host ""
Write-Host "✅ Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "🚀 Usage:" -ForegroundColor Yellow
Write-Host "   • Open a new PowerShell window (AI Terminal will auto-start)" -ForegroundColor Cyan
Write-Host "   • Or use the desktop shortcut 'AI Terminal'" -ForegroundColor Cyan
Write-Host "   • Or run: Import-Module AITerminal" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 The AI Terminal starts automatically in natural language mode." -ForegroundColor Green
Write-Host "   Just describe what you want to do in plain English!" -ForegroundColor Green
Write-Host ""
Write-Host "Examples:" -ForegroundColor Yellow
Write-Host "   'list all files in this directory'" -ForegroundColor Gray
Write-Host "   'show my git status'" -ForegroundColor Gray
Write-Host "   'create a new folder called projects'" -ForegroundColor Gray
