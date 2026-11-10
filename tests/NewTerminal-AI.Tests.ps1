# Pester tests for NewTerminal-AI.psm1
# Run with: Invoke-Pester -Path ./tests
# No Ollama server is required: network calls are mocked.

BeforeAll {
    $env:NEWTERMINAL_AI_NO_AUTOSTART = '1'
    $script:ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'NewTerminal-AI.psm1'
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module NewTerminal-AI -Force -ErrorAction SilentlyContinue
    Remove-Item Env:NEWTERMINAL_AI_NO_AUTOSTART -ErrorAction SilentlyContinue
}

Describe 'Module import' {
    It 'imports without starting the interactive REPL when NEWTERMINAL_AI_NO_AUTOSTART is set' {
        Get-Module NewTerminal-AI | Should -Not -BeNullOrEmpty
    }

    It 'exports <Name>' -TestCases @(
        @{ Name = 'Invoke-AICommand' }
        @{ Name = 'Invoke-AICommandAuto' }
        @{ Name = 'Start-NLMode' }
        @{ Name = 'Start-AITerminal' }
        @{ Name = 'Test-OllamaConnection' }
        @{ Name = 'Show-CommandHistory' }
        @{ Name = 'Clear-CommandHistory' }
        @{ Name = 'Get-ContextInfo' }
    ) {
        param($Name)
        (Get-Command -Module NewTerminal-AI -Name $Name -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'exports alias <Alias> -> <Target>' -TestCases @(
        @{ Alias = 'ai';  Target = 'Invoke-AICommand' }
        @{ Alias = 'aia'; Target = 'Invoke-AICommandAuto' }
        @{ Alias = 'nl';  Target = 'Start-NLMode' }
    ) {
        param($Alias, $Target)
        (Get-Alias -Name $Alias).ResolvedCommandName | Should -Be $Target
    }

    It 'does not export internal helpers' {
        Get-Command -Module NewTerminal-AI -Name 'Invoke-OllamaAPI' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Configuration via environment variables' {
    AfterEach {
        Remove-Item Env:NEWTERMINAL_AI_MODEL, Env:NEWTERMINAL_AI_OLLAMA_URL -ErrorAction SilentlyContinue
        Import-Module $script:ModulePath -Force
    }

    It 'defaults to llama3.2:1b on localhost:11434' {
        Import-Module $script:ModulePath -Force
        InModuleScope NewTerminal-AI {
            $script:OllamaModel | Should -Be 'llama3.2:1b'
            $script:OllamaBaseUrl | Should -Be 'http://localhost:11434'
        }
    }

    It 'honours NEWTERMINAL_AI_MODEL and NEWTERMINAL_AI_OLLAMA_URL' {
        $env:NEWTERMINAL_AI_MODEL = 'phi3:mini'
        $env:NEWTERMINAL_AI_OLLAMA_URL = 'http://ollama.internal:8080/'
        Import-Module $script:ModulePath -Force
        InModuleScope NewTerminal-AI {
            $script:OllamaModel | Should -Be 'phi3:mini'
            $script:OllamaBaseUrl | Should -Be 'http://ollama.internal:8080'
        }
    }
}

Describe 'ConvertTo-CleanCommand' {
    It 'returns <Expected> for <Name>' -TestCases @(
        @{ Name = 'plain command';          Response = 'Get-Date';                                Expected = 'Get-Date' }
        @{ Name = 'surrounding whitespace'; Response = "  Get-Process `n";                        Expected = 'Get-Process' }
        @{ Name = 'fenced block';           Response = "``````powershell`nGet-ChildItem`n``````"; Expected = 'Get-ChildItem' }
        @{ Name = 'bare fence, CRLF';       Response = "``````\`r`nGet-Service`r`n``````";       Expected = 'Get-Service' }
        @{ Name = 'empty string';           Response = '';                                        Expected = '' }
        @{ Name = 'unclosed fence';         Response = "``````powershell`nGet-Date";              Expected = 'Get-Date' }
        @{ Name = 'backtick line continuation kept'; Response = "Get-ChildItem ```n  -Recurse";   Expected = "Get-ChildItem ```n  -Recurse" }
    ) {
        param($Response, $Expected)
        InModuleScope NewTerminal-AI -Parameters @{ R = $Response; E = $Expected } {
            param($R, $E)
            ConvertTo-CleanCommand -Response $R | Should -BeExactly $E
        }
    }
}

Describe 'Test-CommandSafety' {
    It 'flags dangerous command: <Command>' -TestCases @(
        @{ Command = 'rm -rf /' }
        @{ Command = 'Remove-Item -Path C:\ -Recurse -Force' }
        @{ Command = 'Remove-Item -Recurse -Force C:\Windows' }
        @{ Command = 'del /s /q c:\' }
        @{ Command = 'format c:' }
        @{ Command = 'Stop-Computer' }
        @{ Command = 'Restart-Computer -Force' }
        @{ Command = 'shutdown /s /t 0' }
        @{ Command = 'reg delete HKLM\Software\Foo /f' }
        @{ Command = 'Remove-Item $env:SystemRoot\System32 -Recurse' }
        @{ Command = 'Remove-Item $env:ProgramFiles\App' }
    ) {
        param($Command)
        InModuleScope NewTerminal-AI -Parameters @{ C = $Command } {
            param($C)
            Test-CommandSafety -Command $C | Should -BeFalse
        }
    }

    It 'allows safe command: <Command>' -TestCases @(
        @{ Command = 'Get-ChildItem' }
        @{ Command = 'Get-Date' }
        @{ Command = 'Get-PSDrive -PSProvider FileSystem' }
        @{ Command = 'New-Item -ItemType File -Name "notes.txt"' }
        @{ Command = 'git status' }
    ) {
        param($Command)
        InModuleScope NewTerminal-AI -Parameters @{ C = $Command } {
            param($C)
            Test-CommandSafety -Command $C | Should -BeTrue
        }
    }
}

Describe 'Get-ContextInfo' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Push-Location $dir
    }
    AfterEach { Pop-Location }

    It 'detects a general directory' {
        (Get-ContextInfo).PathType | Should -Be 'General Directory'
    }

    It 'detects a Node.js project' {
        Set-Content package.json '{}'
        (Get-ContextInfo).PathType | Should -Be 'Node.js Project'
    }

    It 'detects a .NET project' {
        Set-Content app.csproj '<Project />'
        (Get-ContextInfo).PathType | Should -Be '.NET Project'
    }

    It 'detects a Python project' {
        Set-Content main.py 'print(1)'
        (Get-ContextInfo).PathType | Should -Be 'Python Project'
    }

    It 'detects a Git repository with its branch and status' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        git init -q -b ci-branch . 2>$null
        Set-Content untracked.txt 'x'
        $ctx = Get-ContextInfo
        $ctx.PathType | Should -Be 'Git Repository'
        $ctx.GitBranch | Should -Be 'ci-branch'
        $ctx.GitStatus | Should -Be 'Modified files present'
    }
}

Describe 'Get-CommandSuggestion' {
    It 'answers "<Question>" locally without calling Ollama' -TestCases @(
        @{ Question = 'what model are you using' }
        @{ Question = 'which model is running' }
        @{ Question = 'What AI model is this?' }
    ) {
        param($Question)
        InModuleScope NewTerminal-AI -Parameters @{ Q = $Question } {
            param($Q)
            Mock Invoke-OllamaAPI { throw 'should not be called' }
            Get-CommandSuggestion -NaturalLanguage $Q | Should -Match 'Current AI Model: llama3\.2:1b'
            Should -Invoke Invoke-OllamaAPI -Times 0 -Exactly
        }
    }

    It 'sends the request and a system prompt to Ollama and trims the reply' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-OllamaAPI { "  Get-Date `n" }
            Get-CommandSuggestion -NaturalLanguage 'show the date' | Should -BeExactly 'Get-Date'
            Should -Invoke Invoke-OllamaAPI -Times 1 -Exactly -ParameterFilter {
                $Prompt -eq 'show the date' -and $SystemPrompt -match 'PowerShell command generator'
            }
        }
    }

    It 'wraps API failures in a descriptive error' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-OllamaAPI { throw 'connection refused' }
            { Get-CommandSuggestion -NaturalLanguage 'list files' } | Should -Throw '*Failed to generate command*connection refused*'
        }
    }
}

Describe 'Invoke-OllamaAPI' {
    It 'posts a non-streaming generate request for the configured model' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-RestMethod { [pscustomobject]@{ response = 'Get-Process' } }
            Invoke-OllamaAPI -Prompt 'list processes' -SystemPrompt 'sys' | Should -Be 'Get-Process'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $body = $Body | ConvertFrom-Json
                $Uri -eq 'http://localhost:11434/api/generate' -and $Method -eq 'Post' -and
                $body.model -eq 'llama3.2:1b' -and $body.stream -eq $false -and $body.prompt -eq 'list processes'
            }
        }
    }
}

Describe 'Test-OllamaConnection' {
    It 'returns $true when the tags endpoint responds' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-RestMethod { @{ models = @() } }
            Test-OllamaConnection | Should -BeTrue
            Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -eq 'http://localhost:11434/api/tags' }
        }
    }

    It 'returns $false when the request fails' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-RestMethod { throw 'unreachable' }
            Test-OllamaConnection | Should -BeFalse
        }
    }
}

Describe 'Command history' {
    BeforeEach { InModuleScope NewTerminal-AI { $script:UserHistory = @() } }

    It 'keeps only the last 50 entries' {
        InModuleScope NewTerminal-AI {
            1..55 | ForEach-Object { Add-ToHistory -Request "req $_" -Command 'Get-Date' -Executed $true }
            $script:UserHistory.Count | Should -Be 50
            $script:UserHistory[0].Request | Should -Be 'req 6'
            $script:UserHistory[-1].Request | Should -Be 'req 55'
        }
    }

    It 'shows a single history entry' {
        Add-ToHistory -Request 'show the date' -Command 'Get-Date' -Executed $true
        $output = (Show-CommandHistory 6>&1 | Out-String)
        $output | Should -Match "'show the date'"
        $output | Should -Match 'Get-Date'
    }

    It 'clears the history' {
        Add-ToHistory -Request 'x' -Command 'Get-Date' -Executed $true
        Clear-CommandHistory 6>&1 | Out-Null
        InModuleScope NewTerminal-AI { $script:UserHistory.Count | Should -Be 0 }
    }
}

Describe 'Invoke-AICommand' {
    BeforeEach { InModuleScope NewTerminal-AI { $script:UserHistory = @() } }

    It 'stops early when Ollama is not reachable' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $false }
            Mock Get-CommandSuggestion { 'Get-Date' }
            Invoke-AICommand -NaturalLanguage 'show the date' -AutoExecute -CleanOutput 6>&1 | Out-Null
            Should -Invoke Get-CommandSuggestion -Times 0 -Exactly
        }
    }

    It 'refuses to auto-execute a command flagged as dangerous' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Restart-Computer -Force' }
            Mock Invoke-Expression { }
            Invoke-AICommand -NaturalLanguage 'reboot' -AutoExecute -CleanOutput 6>&1 | Out-Null
            Should -Invoke Invoke-Expression -Times 0 -Exactly
            $script:UserHistory[-1].Executed | Should -BeFalse
        }
    }

    It 'auto-executes a safe, de-fenced command and records it' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { "``````powershell`nGet-Date`n``````" }
            Mock Invoke-Expression { 'ran' }
            Invoke-AICommand -NaturalLanguage 'show the date' -AutoExecute -CleanOutput 6>&1 | Out-Null
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -eq 'Get-Date' }
            $script:UserHistory[-1].Command | Should -Be 'Get-Date'
            $script:UserHistory[-1].Executed | Should -BeTrue
        }
    }
}

Describe 'Interactive REPL' {
    It '<Name> returns when the user types exit' -TestCases @(
        @{ Name = 'Start-AITerminal' }
        @{ Name = 'Start-NLMode' }
    ) {
        param($Name)
        InModuleScope NewTerminal-AI -Parameters @{ N = $Name } {
            param($N)
            $script:reads = 0
            Mock Read-Host {
                $script:reads++
                if ($script:reads -gt 1) { throw 'REPL did not exit' }
                'exit'
            }
            & $N 6>&1 | Out-Null
            $script:reads | Should -Be 1
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Regression tests. Each one fails against the module as it was before the fix it covers.
# ---------------------------------------------------------------------------------------------

Describe 'ConvertTo-CleanCommand keeps only the command' -Tag 'Regression' {
    It 'drops prose around a fenced block' {
        InModuleScope NewTerminal-AI {
            $reply = "Here is the command:`n``````powershell`nGet-Date`n```````nThis prints the date."
            ConvertTo-CleanCommand -Response $reply | Should -BeExactly 'Get-Date'
        }
    }

    It 'unwraps <Name>' -TestCases @(
        @{ Name = 'inline backticks';        Response = '`Get-Date`' }
        @{ Name = 'a one-line triple fence'; Response = '```Get-Date```' }
    ) {
        param($Response)
        InModuleScope NewTerminal-AI -Parameters @{ R = $Response } {
            param($R)
            ConvertTo-CleanCommand -Response $R | Should -BeExactly 'Get-Date'
        }
    }
}

Describe 'Get-CommandSuggestion sends hardware questions to the model' -Tag 'Regression' {
    It 'does not answer "<Question>" with the AI model name' -TestCases @(
        @{ Question = 'what is the model of this laptop' }
        @{ Question = 'what cpu model does this machine have' }
        @{ Question = 'which graphics card model is running hot' }
    ) {
        param($Question)
        InModuleScope NewTerminal-AI -Parameters @{ Q = $Question } {
            param($Q)
            Mock Invoke-OllamaAPI { 'Get-CimInstance Win32_ComputerSystem' }
            Get-CommandSuggestion -NaturalLanguage $Q | Should -BeExactly 'Get-CimInstance Win32_ComputerSystem'
            Should -Invoke Invoke-OllamaAPI -Times 1 -Exactly
        }
    }

    It 'does not teach the model to create files with -Force' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-OllamaAPI { 'Get-Date' }
            Get-CommandSuggestion -NaturalLanguage 'create a file' | Out-Null
            Should -Invoke Invoke-OllamaAPI -Times 1 -Exactly -ParameterFilter { $SystemPrompt -notmatch 'New-Item[^\r\n]*-Force' }
        }
    }
}

Describe 'Invoke-OllamaAPI encoding' -Tag 'Regression' {
    It 'declares the request body as UTF-8' {
        InModuleScope NewTerminal-AI {
            Mock Invoke-RestMethod { [pscustomobject]@{ response = 'Get-ChildItem' } }
            Invoke-OllamaAPI -Prompt 'liste les fichiers' | Out-Null
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $ContentType -match 'charset=utf-8' }
        }
    }
}

Describe 'Get-ContextInfo on a detached HEAD' -Tag 'Regression' {
    It 'still reports the working-tree status' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Push-Location $dir
        try {
            git init -q -b main . 2>$null
            git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m init 2>$null
            git checkout -q --detach 2>$null
            $ctx = Get-ContextInfo
            $ctx.GitStatus | Should -Be 'Clean'
            $ctx.GitBranch | Should -Match '^detached@[0-9a-f]+$'
        } finally {
            Pop-Location
        }
    }
}

Describe 'Running a generated command' {
    BeforeEach { InModuleScope NewTerminal-AI { $script:UserHistory = @() } }

    It 'does not report a stale exit code left by an earlier native program' -Tag 'Regression' {
        InModuleScope NewTerminal-AI {
            Set-Variable -Name LASTEXITCODE -Value 7 -Scope Global
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Get-Date' }
            Mock Invoke-Expression { 'ok' }
            $out = Invoke-AICommand -NaturalLanguage 'date' -AutoExecute -CleanOutput 6>&1 | Out-String
            $out | Should -Not -Match 'Exit code'
        }
    }

    It 'reports the exit code of the command itself' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'git status' }
            Mock Invoke-Expression { Set-Variable -Name LASTEXITCODE -Value 3 -Scope Global; 'fatal' }
            $out = Invoke-AICommand -NaturalLanguage 'status' -AutoExecute -CleanOutput 6>&1 | Out-String
            $out | Should -Match 'Exit code: 3'
            Set-Variable -Name LASTEXITCODE -Value 0 -Scope Global
        }
    }

    It 'renders objects with the PowerShell formatter instead of ToString()' -Tag 'Regression' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Get-Thing' }
            Mock Invoke-Expression {
                [pscustomobject]@{ Name = 'alpha'; Size = 42 }
                [pscustomobject]@{ Name = 'beta'; Size = 7 }
            }
            $out = Invoke-AICommand -NaturalLanguage 'show things' -AutoExecute -CleanOutput 6>&1 | Out-String
            $out | Should -Match 'Name\s+Size'
            $out | Should -Match 'alpha\s+42'
            $out | Should -Not -Match '@\{'
        }
    }
}

Describe 'Flagged commands by entry point' {
    BeforeEach { InModuleScope NewTerminal-AI { $script:UserHistory = @() } }

    It 'aia refuses a command the gate flags and says why' -Tag 'Regression' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'gci -r | ri -fo' }
            Mock Invoke-Expression { }
            Mock Read-Host { throw 'aia must not prompt' }
            $out = Invoke-AICommandAuto -NaturalLanguage 'tidy up' 6>&1 | Out-String
            Should -Invoke Invoke-Expression -Times 0 -Exactly
            $out | Should -Match 'remove-item'
            $script:UserHistory[-1].Executed | Should -BeFalse
        }
    }

    It 'ai runs a flagged command only after the word yes' -Tag 'Regression' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Restart-Computer -Force' }
            Mock Show-ThinkingAnimation { }
            Mock Invoke-Expression { }
            Mock Read-Host { 'yes' }
            Invoke-AICommand -NaturalLanguage 'reboot' 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 1 -Exactly
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -eq 'Restart-Computer -Force' }
            $script:UserHistory[-1].Executed | Should -BeTrue
        }
    }

    It 'ai does not accept "<Answer>" for a flagged command' -Tag 'Regression' -TestCases @(
        @{ Answer = 'y' }
        @{ Answer = '' }
        @{ Answer = 'e' }
    ) {
        param($Answer)
        InModuleScope NewTerminal-AI -Parameters @{ A = $Answer } {
            param($A)
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Restart-Computer -Force' }
            Mock Show-ThinkingAnimation { }
            Mock Invoke-Expression { }
            $script:answer = $A
            Mock Read-Host { $script:answer }
            Invoke-AICommand -NaturalLanguage 'reboot' 6>&1 | Out-Null
            Should -Invoke Read-Host -Times 1 -Exactly
            Should -Invoke Invoke-Expression -Times 0 -Exactly
            $script:UserHistory[-1].Executed | Should -BeFalse
        }
    }

    It 'ai re-checks an edited command' -Tag 'Regression' {
        InModuleScope NewTerminal-AI {
            $script:reads = 0
            Mock Read-Host {
                $script:reads++
                switch ($script:reads) { 1 { 'e' } 2 { 'Restart-Computer -Force' } default { 'n' } }
            }
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Get-Date' }
            Mock Show-ThinkingAnimation { }
            Mock Invoke-Expression { }
            Invoke-AICommand -NaturalLanguage 'date' 6>&1 | Out-Null
            Should -Invoke Invoke-Expression -Times 0 -Exactly
            $script:reads | Should -Be 3
        }
    }

    It 'ai runs an edited command that is safe' {
        InModuleScope NewTerminal-AI {
            $script:reads = 0
            Mock Read-Host {
                $script:reads++
                switch ($script:reads) { 1 { 'e' } 2 { 'Get-Process' } default { throw 'unexpected prompt' } }
            }
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Get-Date' }
            Mock Show-ThinkingAnimation { }
            Mock Invoke-Expression { }
            Invoke-AICommand -NaturalLanguage 'date' 6>&1 | Out-Null
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -eq 'Get-Process' }
        }
    }

    It 'the AI> REPL needs "yes", not "<Answer>", for a flagged command' -Tag 'Regression' -TestCases @(
        @{ Answer = 'y';   Runs = 0 }
        @{ Answer = 'yes'; Runs = 1 }
    ) {
        param($Answer, $Runs)
        InModuleScope NewTerminal-AI -Parameters @{ A = $Answer; N = $Runs } {
            param($A, $N)
            $script:reads = 0
            $script:answer = $A
            Mock Read-Host {
                $script:reads++
                switch ($script:reads) { 1 { 'reboot now' } 2 { $script:answer } 3 { 'exit' } default { throw 'REPL did not exit' } }
            }
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Restart-Computer -Force' }
            Mock Invoke-Expression { }
            Start-AITerminal 6>&1 | Out-Null
            Should -Invoke Invoke-Expression -Times $N -Exactly
            $script:reads | Should -Be 3
        }
    }

    It 'the nl REPL refuses a flagged command without prompting' {
        InModuleScope NewTerminal-AI {
            $script:reads = 0
            Mock Read-Host {
                $script:reads++
                switch ($script:reads) { 1 { 'reboot now' } 2 { 'exit' } default { throw 'REPL did not exit' } }
            }
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { 'Restart-Computer -Force' }
            Mock Invoke-Expression { }
            Start-NLMode 6>&1 | Out-Null
            Should -Invoke Invoke-Expression -Times 0 -Exactly
            $script:reads | Should -Be 2
        }
    }
}

Describe 'Generation failures' -Tag 'Regression' {
    BeforeEach { InModuleScope NewTerminal-AI { $script:UserHistory = @() } }

    It 'Invoke-AICommand reports a failed generation instead of throwing' {
        InModuleScope NewTerminal-AI {
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { throw "Failed to generate command: model 'llama3.2:1b' not found" }
            Mock Invoke-Expression { }
            { $script:captured = Invoke-AICommand -NaturalLanguage 'list files' -AutoExecute -CleanOutput 6>&1 | Out-String } | Should -Not -Throw
            $script:captured | Should -Match 'not found'
            Should -Invoke Invoke-Expression -Times 0 -Exactly
            $script:UserHistory[-1].Executed | Should -BeFalse
        }
    }

    It '<Name> keeps running after a failed generation' -TestCases @(
        @{ Name = 'Start-AITerminal' }
        @{ Name = 'Start-NLMode' }
    ) {
        param($Name)
        InModuleScope NewTerminal-AI -Parameters @{ N = $Name } {
            param($N)
            $script:reads = 0
            Mock Read-Host {
                $script:reads++
                switch ($script:reads) { 1 { 'list files' } 2 { 'exit' } default { throw 'REPL did not exit' } }
            }
            Mock Test-OllamaConnection { $true }
            Mock Get-CommandSuggestion { throw 'Failed to generate command: timeout' }
            $script:repl = $N
            { & $script:repl 6>&1 | Out-Null } | Should -Not -Throw
            $script:reads | Should -Be 2
        }
    }
}

Describe 'REPL end of input' -Tag 'Regression' {
    It '<Name> returns when Read-Host yields $null' -TestCases @(
        @{ Name = 'Start-AITerminal' }
        @{ Name = 'Start-NLMode' }
    ) {
        param($Name)
        InModuleScope NewTerminal-AI -Parameters @{ N = $Name } {
            param($N)
            $script:reads = 0
            Mock Read-Host {
                $script:reads++
                if ($script:reads -gt 1) { throw 'REPL did not exit' }
                $null
            }
            $script:repl = $N
            { & $script:repl 6>&1 | Out-Null } | Should -Not -Throw
            $script:reads | Should -Be 1
        }
    }
}

Describe 'Auto-start on import' -Tag 'Regression' {
    It 'does not start the REPL when a non-interactive pwsh imports the module' {
        $pwsh = (Get-Process -Id $PID).Path
        $stdin = Join-Path $TestDrive 'stdin.txt'
        $stdout = Join-Path $TestDrive 'stdout.txt'
        $stderr = Join-Path $TestDrive 'stderr.txt'
        Set-Content -Path $stdin -Value ''

        $command = "Import-Module '$($script:ModulePath -replace "'", "''")'; 'IMPORT-COMPLETED'"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

        # The child must decide for itself: the opt-out variable is removed for its lifetime only.
        $saved = $env:NEWTERMINAL_AI_NO_AUTOSTART
        Remove-Item Env:NEWTERMINAL_AI_NO_AUTOSTART -ErrorAction SilentlyContinue
        try {
            $process = Start-Process -FilePath $pwsh -ArgumentList '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded `
                -RedirectStandardInput $stdin -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru
            $exited = $process.WaitForExit(30000)
            if (-not $exited) { $process.Kill() }
        } finally {
            $env:NEWTERMINAL_AI_NO_AUTOSTART = $saved
        }

        $exited | Should -BeTrue -Because 'the import must return instead of waiting in the REPL'
        $output = Get-Content -Path $stdout -Raw
        $output | Should -Match 'IMPORT-COMPLETED'
        $output | Should -Not -Match 'Natural Language Interface'
    }
}
