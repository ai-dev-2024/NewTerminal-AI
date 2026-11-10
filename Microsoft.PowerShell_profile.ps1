# NewTerminal-AI sample PowerShell profile
#
# Copy the parts you want into your own profile ($PROFILE), or dot-source this file from it.
# It loads the module from the folder this file is in and adds tab completion for common requests.
#
# Importing the module starts the AI> prompt only in an interactive console. Scripts,
# 'pwsh -Command', 'pwsh -File' and editor hosts are left alone. To load the commands without
# the prompt even in a console, set this before the import:
#   $env:NEWTERMINAL_AI_NO_AUTOSTART = '1'

# Tab completion for the request text of ai / aia. Registered before the import, because the
# import does not return until you leave the AI> prompt.
Register-ArgumentCompleter -CommandName 'Invoke-AICommand', 'Invoke-AICommandAuto' -ParameterName 'NaturalLanguage' -ScriptBlock {
    # Completer arguments: command name, parameter name, word to complete, command AST, bound parameters.
    $wordToComplete = "$($args[2])".Trim('"', "'")

    $suggestions = @(
        'list running processes',
        'show system information',
        'find large files',
        'check disk space',
        'show network connections',
        'list installed programs',
        'show environment variables',
        'find files by extension',
        'show services status',
        'check memory usage'
    )

    $suggestions | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new("'$_'", $_, 'ParameterValue', $_)
    }
}

$newTerminalModule = Join-Path $PSScriptRoot 'NewTerminal-AI.psm1'
if (Test-Path $newTerminalModule) {
    Import-Module $newTerminalModule -Force
} else {
    Write-Warning "NewTerminal-AI module not found at $newTerminalModule"
}
