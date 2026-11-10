# Runs PSScriptAnalyzer over every PowerShell file in the repository.
# - Error- and Warning-severity findings both fail the run.
# - The rules excluded below conflict with how an interactive terminal tool works.
#   Exits non-zero when findings are reported.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    throw "PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser"
}

$settings = @{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                        # coloured interactive output is the UI
        'PSAvoidUsingInvokeExpression',                 # executing the generated command is the core feature
        'PSUseShouldProcessForStateChangingFunctions'   # interactive helpers; nothing here is scripted with -WhatIf
    )
}

$findings = @(Invoke-ScriptAnalyzer -Path $root -Recurse -Settings $settings)

if ($findings.Count -gt 0) {
    $findings | Format-Table ScriptName, Line, Severity, RuleName, Message -AutoSize | Out-String -Width 250 | Write-Output
    Write-Error "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    exit 1
}

Write-Output "PSScriptAnalyzer: no findings."
