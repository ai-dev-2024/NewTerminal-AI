# Repository-level tests: file encodings, the sample profile, the installers and stale files.
# Run with: Invoke-Pester -Path ./tests
#
# Nothing here installs anything: install.ps1 is only parsed (its functions are loaded from the
# syntax tree, the script body never runs) and install.sh runs in a throwaway HOME with stub tools.

BeforeAll {
    $env:NEWTERMINAL_AI_NO_AUTOSTART = '1'
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:RepoRoot 'NewTerminal-AI.psm1'
    $script:ProfilePath = Join-Path $script:RepoRoot 'Microsoft.PowerShell_profile.ps1'
    $script:InstallPs1 = Join-Path $script:RepoRoot 'install.ps1'
    $script:InstallSh = Join-Path $script:RepoRoot 'install.sh'
    Import-Module $script:ModulePath -Force

    function Get-ScriptAst {
        param([string]$Path)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) { throw "Cannot parse ${Path}: $($errors[0].Message)" }
        return $ast
    }
}

AfterAll {
    Remove-Module NewTerminal-AI -Force -ErrorAction SilentlyContinue
    Remove-Item Env:NEWTERMINAL_AI_NO_AUTOSTART -ErrorAction SilentlyContinue
}

Describe 'PowerShell file encoding' -Tag 'Regression' {
    It 'every PowerShell file with non-ASCII characters starts with a UTF-8 byte order mark' {
        # Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page. Bytes of an emoji then
        # decode to quote characters, which ends string literals early and breaks the parser.
        $offenders = Get-ChildItem -Path $script:RepoRoot -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            Where-Object {
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
                $hasNonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
                $hasNonAscii -and -not $hasBom
            } |
            ForEach-Object { $_.FullName.Substring($script:RepoRoot.Length + 1) }

        $offenders | Should -BeNullOrEmpty
    }
}

Describe 'Sample profile' -Tag 'Regression' {
    BeforeAll {
        $script:ProfileAst = Get-ScriptAst -Path $script:ProfilePath
        $script:ProfileCommands = @($script:ProfileAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    }

    It 'only calls commands that exist' {
        $defined = @($script:ProfileAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
        $missing = $script:ProfileCommands |
            ForEach-Object { $_.GetCommandName() } |
            Where-Object { $_ } |
            Sort-Object -Unique |
            Where-Object { $defined -notcontains $_ -and -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) }

        $missing | Should -BeNullOrEmpty
    }

    It 'registers tab completion for a parameter the commands really have' {
        $register = @($script:ProfileCommands | Where-Object { $_.GetCommandName() -eq 'Register-ArgumentCompleter' })
        $register.Count | Should -BeGreaterThan 0

        foreach ($call in $register) {
            $elements = @($call.CommandElements)
            $values = @{}
            for ($i = 1; $i -lt $elements.Count - 1; $i++) {
                if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $values[$elements[$i].ParameterName] = @($elements[$i + 1].FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
                }
            }
            $values['CommandName'] | Should -Not -BeNullOrEmpty
            foreach ($commandName in $values['CommandName']) {
                (Get-Command -Name $commandName).Parameters.Keys | Should -Contain $values['ParameterName'][0]
            }
        }
    }

    It 'does not read and execute input itself' {
        # Everything the model generates has to go through the module, and therefore through the gate.
        $names = @($script:ProfileCommands | ForEach-Object { $_.GetCommandName() })
        $names | Should -Not -Contain 'Invoke-Expression'
        $names | Should -Not -Contain 'iex'
        $names | Should -Not -Contain 'Read-Host'
    }
}

Describe 'install.ps1' -Tag 'Regression' {
    BeforeAll {
        # Load only the function definitions. The body of the installer is never executed.
        $installAst = Get-ScriptAst -Path $script:InstallPs1
        foreach ($definition in $installAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    It 'installs for <Scope> under <Edition> into <Expected>' -TestCases @(
        @{ Scope = 'CurrentUser'; Edition = 'Core';    Expected = 'D:/Docs/PowerShell/Modules/AITerminal' }
        @{ Scope = 'CurrentUser'; Edition = 'Desktop'; Expected = 'D:/Docs/WindowsPowerShell/Modules/AITerminal' }
        @{ Scope = 'AllUsers';    Edition = 'Core';    Expected = 'C:/Program Files/PowerShell/Modules/AITerminal' }
        @{ Scope = 'AllUsers';    Edition = 'Desktop'; Expected = 'C:/Program Files/WindowsPowerShell/Modules/AITerminal' }
    ) {
        param($Scope, $Edition, $Expected)
        $root = Get-AITerminalModuleRoot -Scope $Scope -Edition $Edition -Documents 'D:\Docs' -ProgramFiles 'C:\Program Files'
        ($root -replace '\\', '/') | Should -Be $Expected
    }

    It 'writes a manifest that exports every function and alias of the module' {
        $installed = Join-Path $TestDrive 'AITerminal'
        New-Item -ItemType Directory -Path $installed | Out-Null
        Copy-Item -Path $script:ModulePath -Destination (Join-Path $installed 'AITerminal.psm1')
        $manifestPath = Join-Path $installed 'AITerminal.psd1'
        Get-AITerminalManifest -ModulePath $script:ModulePath | Out-File -FilePath $manifestPath -Encoding UTF8

        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $module = Get-Module NewTerminal-AI
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be @($module.ExportedFunctions.Keys | Sort-Object)
        @($manifest.AliasesToExport | Sort-Object) | Should -Be @($module.ExportedAliases.Keys | Sort-Object)
        $manifest.ModuleVersion | Should -Be (InModuleScope NewTerminal-AI { $script:ModuleVersion })
        [version]$manifest.ModuleVersion | Should -BeGreaterThan ([version]'0.0.0')
        [guid]$manifest.GUID | Should -Not -Be ([guid]::Empty)
    }

    It 'produces an installed module whose aliases all resolve' {
        $installed = Join-Path $TestDrive 'AITerminal-import'
        New-Item -ItemType Directory -Path $installed | Out-Null
        $moduleDir = Join-Path $installed 'AITerminal'
        New-Item -ItemType Directory -Path $moduleDir | Out-Null
        Copy-Item -Path $script:ModulePath -Destination (Join-Path $moduleDir 'AITerminal.psm1')
        Get-AITerminalManifest -ModulePath $script:ModulePath | Out-File -FilePath (Join-Path $moduleDir 'AITerminal.psd1') -Encoding UTF8

        try {
            $imported = Import-Module (Join-Path $moduleDir 'AITerminal.psd1') -Force -PassThru
            foreach ($alias in $imported.ExportedAliases.Values) {
                $imported.ExportedFunctions.Keys | Should -Contain $alias.Definition
            }
            $imported.ExportedAliases.Keys | Should -Contain 'aia'
            $imported.ExportedAliases.Keys | Should -Contain 'nl'
        } finally {
            Remove-Module AITerminal -Force -ErrorAction SilentlyContinue
            Import-Module $script:ModulePath -Force
        }
    }
}

Describe 'install.sh' -Tag 'Regression' {
    It 'is executable, so ./install.sh from the README works' -Skip:$IsWindows {
        & test -x $script:InstallSh
        $LASTEXITCODE | Should -Be 0
    }

    Context 'run in a sandbox with stub tools' {
        BeforeAll {
            $script:CanRun = (-not $IsWindows) -and [bool](Get-Command bash -ErrorAction SilentlyContinue)
            if ($script:CanRun) {
                $script:Sandbox = Join-Path $TestDrive 'home'
                $stubs = Join-Path $TestDrive 'stubs'
                $script:BinDir = Join-Path $TestDrive 'bin'
                $profileDir = Join-Path $script:Sandbox '.config/powershell'
                New-Item -ItemType Directory -Path $script:Sandbox, $stubs, $profileDir -Force | Out-Null

                # Stub tools: pwsh and ollama "exist"; sudo always fails, so nothing can be written
                # outside the sandbox.
                Set-Content -Path (Join-Path $stubs 'pwsh') -Value "#!/bin/sh`nexit 0"
                Set-Content -Path (Join-Path $stubs 'ollama') -Value "#!/bin/sh`necho `"`$@`" >> `"`$HOME/ollama.log`"`nexit 0"
                Set-Content -Path (Join-Path $stubs 'sudo') -Value "#!/bin/sh`nexit 1"
                & chmod +x (Join-Path $stubs 'pwsh') (Join-Path $stubs 'ollama') (Join-Path $stubs 'sudo')

                $script:SandboxProfile = Join-Path $profileDir 'Microsoft.PowerShell_profile.ps1'
                Set-Content -Path $script:SandboxProfile -Value "Set-Alias ll Get-ChildItem`n# my own profile"

                $script:InstallRuns = foreach ($run in 1, 2) {
                    $output = & /usr/bin/env -i "HOME=$($script:Sandbox)" "PATH=${stubs}:/usr/bin:/bin" "NEWTERMINAL_AI_BIN_DIR=$($script:BinDir)" bash $script:InstallSh 2>&1
                    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
                }
            }
        }

        It 'succeeds, twice in a row' -Skip:$IsWindows {
            $script:CanRun | Should -BeTrue
            $script:InstallRuns[0].ExitCode | Should -Be 0 -Because $script:InstallRuns[0].Output
            $script:InstallRuns[1].ExitCode | Should -Be 0 -Because $script:InstallRuns[1].Output
        }

        It 'keeps the existing PowerShell profile and adds the import line once' -Skip:$IsWindows {
            $content = Get-Content -Path $script:SandboxProfile -Raw
            $content | Should -Match 'Set-Alias ll Get-ChildItem'
            $content | Should -Match '# my own profile'
            ([regex]::Matches($content, 'Import-Module AITerminal -Force')).Count | Should -Be 1
        }

        It 'installs the module, pulls the model and creates an executable launcher' -Skip:$IsWindows {
            Join-Path $script:Sandbox '.local/share/powershell/Modules/AITerminal/AITerminal.psm1' | Should -Exist
            Get-Content -Path (Join-Path $script:Sandbox 'ollama.log') -Raw | Should -Match 'pull llama3\.2:1b'
            $launcher = Join-Path $script:BinDir 'ai-terminal'
            $launcher | Should -Exist
            & test -x $launcher
            $LASTEXITCODE | Should -Be 0
        }
    }
}

Describe 'Stale files' {
    It 'has no leftover copy of the module under another name' -Tag 'Regression' {
        $copies = Get-ChildItem -Path $script:RepoRoot -Recurse -File -Filter *.psm1 |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -ne $script:ModulePath }
        $copies | Should -BeNullOrEmpty
    }

    It 'does not mention NewTerminal-AI-fixed.psm1 in the documentation' -Tag 'Regression' {
        $mentions = Get-ChildItem -Path $script:RepoRoot -Recurse -File -Include *.md |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Name -ne 'CHANGELOG.md' } |
            Select-String -Pattern 'NewTerminal-AI-fixed' -SimpleMatch
        $mentions | Should -BeNullOrEmpty
    }

    It 'has no broken relative link in <Name>' -TestCases @(
        @{ Name = 'README.md' }
        @{ Name = 'CONTRIBUTING.md' }
    ) {
        param($Name)
        $text = Get-Content -Path (Join-Path $script:RepoRoot $Name) -Raw
        $targets = @([regex]::Matches($text, '\]\(([^)#\s]+)(#[^)]*)?\)') | ForEach-Object { $_.Groups[1].Value }) +
            @([regex]::Matches($text, '(?:src|href)="([^"#]+)"') | ForEach-Object { $_.Groups[1].Value })
        $broken = $targets |
            Where-Object { $_ -notmatch '^(https?:|mailto:)' } |
            Where-Object { -not (Test-Path -Path (Join-Path $script:RepoRoot $_)) }
        $broken | Should -BeNullOrEmpty
    }
}
