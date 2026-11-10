# NewTerminal-AI - Enhanced PowerShell Module with Natural Language Interface
# Version: 2.2
# Description: Provides natural language to PowerShell command conversion using local Ollama AI

# Global variables
# Both can be overridden via environment variables before importing the module
$script:ModuleVersion = '2.2.0'
$script:OllamaBaseUrl = if ($env:NEWTERMINAL_AI_OLLAMA_URL) { $env:NEWTERMINAL_AI_OLLAMA_URL.TrimEnd('/') } else { "http://localhost:11434" }
$script:OllamaModel = if ($env:NEWTERMINAL_AI_MODEL) { $env:NEWTERMINAL_AI_MODEL } else { "llama3.2:1b" }
$script:UserHistory = @()
$script:SystemInfo = @{
    OS = [System.Environment]::OSVersion.Platform
    UserName = [System.Environment]::UserName
    MachineName = [System.Environment]::MachineName
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
}

function Write-AIResponse {
    param(
        [string]$Message,
        [string]$Type = "info"
    )

    $colors = @{
        "success" = "Green"
        "error" = "Red"
        "warning" = "Yellow"
        "info" = "Cyan"
        "command" = "White"
    }

    $color = $colors[$Type.ToLower()]
    if (-not $color) { $color = "White" }

    $prefix = switch ($Type.ToLower()) {
        "success" { "[SUCCESS $(Get-Date -Format 'HH:mm:ss')]" }
        "error" { "[ERROR $(Get-Date -Format 'HH:mm:ss')]" }
        "warning" { "[WARN $(Get-Date -Format 'HH:mm:ss')]" }
        "info" { "[INFO $(Get-Date -Format 'HH:mm:ss')]" }
        "command" { "[COMMAND $(Get-Date -Format 'HH:mm:ss')]" }
        default { "[$(Get-Date -Format 'HH:mm:ss')]" }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Test-OllamaConnection {
    try {
        Invoke-RestMethod -Uri "$script:OllamaBaseUrl/api/tags" -Method Get -TimeoutSec 5 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-OllamaAPI {
    param(
        [string]$Prompt,
        [string]$SystemPrompt = "",
        [string]$Model = $script:OllamaModel
    )

    $body = @{
        model = $Model
        prompt = $Prompt
        system = $SystemPrompt
        stream = $false
        options = @{
            temperature = 0.1
            top_p = 0.9
            num_predict = 1000
        }
    } | ConvertTo-Json -Depth 3

    try {
        # The explicit charset matters on Windows PowerShell 5.1, which otherwise sends a string body as
        # ISO-8859-1 and garbles any non-ASCII character in the request.
        $response = Invoke-RestMethod -Uri "$script:OllamaBaseUrl/api/generate" -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 30
        return $response.response
    }
    catch {
        throw "Ollama API call failed: $($_.Exception.Message)"
    }
}

function Show-ThinkingAnimation {
    param(
        [string]$Message = "Thinking",
        [int]$DurationMs = 2000
    )

    $frames = @("[*]", "[+]", "[x]", "[+]")
    $startTime = Get-Date
    $frameIndex = 0

    while ((Get-Date) - $startTime -lt [TimeSpan]::FromMilliseconds($DurationMs)) {
        Write-Host "`r$($frames[$frameIndex]) $Message..." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Milliseconds 200
        $frameIndex = ($frameIndex + 1) % $frames.Length
    }

    Write-Host "`r" -NoNewline
    Write-Host (" " * ($Message.Length + 20)) -NoNewline
    Write-Host "`r" -NoNewline
}

function Get-ContextInfo {
    $currentPath = Get-Location
    $pathType = "General Directory"
    $gitBranch = $null
    $gitStatus = $null

    if (Test-Path ".git") {
        $pathType = "Git Repository"
        try {
            # 'git branch --show-current' prints nothing on a detached HEAD, so the result can be $null.
            $branchOutput = git branch --show-current 2>$null
            $gitBranch = if ($branchOutput) { "$branchOutput".Trim() } else { $null }
            if (-not $gitBranch) {
                $shortHash = git rev-parse --short HEAD 2>$null
                $gitBranch = if ($shortHash) { "detached@$("$shortHash".Trim())" } else { "unknown" }
            }
            $gitStatusOutput = git status --porcelain 2>$null
            $gitStatus = if ($gitStatusOutput) { "Modified files present" } else { "Clean" }
        }
        catch {
            $gitBranch = "unknown"
            $gitStatus = "unknown"
        }
    }
    elseif (Test-Path "package.json") {
        $pathType = "Node.js Project"
    }
    elseif ((Test-Path "*.sln") -or (Test-Path "*.csproj")) {
        $pathType = ".NET Project"
    }
    elseif ((Test-Path "requirements.txt") -or (Test-Path "*.py")) {
        $pathType = "Python Project"
    }

    return @{
        Path = $currentPath.Path
        PathType = $pathType
        GitBranch = $gitBranch
        GitStatus = $gitStatus
    }
}

function Get-CommandSuggestion {
    param(
        [string]$NaturalLanguage
    )

    $context = Get-ContextInfo

    # Answer questions about the AI model locally. The wording has to point at the AI itself:
    # "what is the model of this laptop" is a hardware question and must go to the LLM.
    if ($NaturalLanguage -match "(?i)\b(what|which|tell me|show me)\b.*\b(ai model|llm|language model)\b" -or
        $NaturalLanguage -match "(?i)\b(what|which)\b.*\bmodel\s+(are you|do you|you are|you use|am i)\b" -or
        $NaturalLanguage -match "(?i)\b(what|which)\b.*\bmodel\s+is\s+(this|running)\s*\??\s*$") {
        return "Write-Host 'Current AI Model: $script:OllamaModel' -ForegroundColor Green"
    }

    $systemPrompt = @"
You are a PowerShell command generator. Convert natural language requests into PowerShell commands.

CRITICAL: Return ONLY the PowerShell command. No explanations, no markdown, no code blocks, no additional text.

Rules:
1. Generate ONLY the PowerShell command, nothing else
2. NO markdown formatting (no ```, no code blocks)
3. NO explanations or descriptions
4. Use simple, direct PowerShell cmdlets when possible
5. For common tasks, prefer these patterns:
   - Date/time: Get-Date
   - File listing: Get-ChildItem or ls
   - Disk space: Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free,@{Name='Size(GB)';Expression={[math]::Round((`$_.Used+`$_.Free)/1GB,2)}},@{Name='FreeSpace(GB)';Expression={[math]::Round(`$_.Free/1GB,2)}}
   - Disk usage simple: Get-PSDrive -PSProvider FileSystem
   - Processes: Get-Process
   - Services: Get-Service
   - System info: Get-ComputerInfo
   - Network info: Get-NetIPAddress
   - Current user: whoami
   - System uptime: (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
   - Create file: New-Item -ItemType File -Name "filename.ext"
   - Create empty file: New-Item -ItemType File -Path "filename.ext"
   - Create file with content: New-Item -ItemType File -Path "filename.ext" -Value "content"
   - Append to file: Add-Content -Path "filename.ext" -Value "content"
   - Overwrite a file: Set-Content -Path "filename.ext" -Value "content"
   - Find/search file: Get-ChildItem -Name "filename*" -Recurse
   - Check if file exists: Test-Path "filename.ext"
   - Read file content: Get-Content "filename.ext"
   - Delete file: Remove-Item "filename.ext"
   - Copy file: Copy-Item "source.ext" "destination.ext"
   - Move/rename file: Move-Item "old.ext" "new.ext"
6. Avoid complex WMI queries unless specifically needed
7. Use PowerShell 5+ compatible syntax
8. Generate complete, working commands
9. For disk space, always show human-readable format
10. For file operations, always use appropriate cmdlets (New-Item, Get-ChildItem, Test-Path, etc.)
11. Never add -Force, -Recurse or -Confirm:`$false unless the user explicitly asked for it

System Context:
OS: $($script:SystemInfo.OS)
Current Directory: $($context.Path)
Directory Type: $($context.PathType)

Examples:
Input: "show disk space"
Output: Get-PSDrive -PSProvider FileSystem

Input: "create a file named test.txt"
Output: New-Item -ItemType File -Name "test.txt"

Input: "find file test.txt"
Output: Get-ChildItem -Name "test.txt" -Recurse

Input: "list all files"
Output: Get-ChildItem
"@

    if ($context.GitBranch) {
        $systemPrompt += "`nGit Branch: $($context.GitBranch) ($($context.GitStatus))"
    }

    try {
        $response = Invoke-OllamaAPI -Prompt $NaturalLanguage -SystemPrompt $systemPrompt
        return $response.Trim()
    }
    catch {
        throw "Failed to generate command: $($_.Exception.Message)"
    }
}

function ConvertTo-CleanCommand {
    # Reduces a model response to the command it contains.
    # - If the reply has a Markdown fenced block, the command is the body of the first block and any
    #   prose around it is dropped (otherwise "Here is the command:" would be executed too).
    # - A reply wrapped in inline backticks (`Get-Date`) is unwrapped.
    param([string]$Response)

    if (-not $Response) { return "" }

    $text = ($Response -replace "`r`n", "`n").Trim()

    $fenced = [regex]::Match($text, '(?s)```[^\n`]*\n(.*?)(\n```|$)')
    if ($fenced.Success) {
        return $fenced.Groups[1].Value.Trim()
    }

    if ($text -match '^`{1,3}([^`]+)`{1,3}$') {
        return $Matches[1].Trim()
    }

    $lines = $text -split "`n" | Where-Object { $_.Trim() -notmatch '^```' }
    return ($lines -join "`n").Trim()
}

#region Safety gate
# ---------------------------------------------------------------------------------------------
# The gate decides whether a generated command may run without an explicit confirmation.
#
# It parses the command with the PowerShell parser and walks the whole syntax tree, so aliases,
# abbreviated parameters, backtick escapes, comments, statement chains, nested script blocks and
# subexpressions are all seen the way PowerShell will execute them. It fails closed: anything that
# cannot be parsed or analysed is flagged.
#
# The tables below are static on purpose. The verdict must not depend on the aliases, PATH or files
# of the machine it runs on, so it is the same on Windows, Linux and macOS.
#
# This is a review gate, not a sandbox. It does not inspect what a script, executable or
# user-defined function does when it is run by name.
# ---------------------------------------------------------------------------------------------

# Aliases (and same-named native tools) mapped to the cmdlet whose rules apply.
$script:GateAlias = @{
    'ri' = 'remove-item'; 'rm' = 'remove-item'; 'rmdir' = 'remove-item'; 'rd' = 'remove-item'; 'del' = 'remove-item'; 'erase' = 'remove-item'
    'rp' = 'remove-itemproperty'; 'clc' = 'clear-content'; 'cli' = 'clear-item'; 'clp' = 'clear-itemproperty'
    'iex' = 'invoke-expression'; 'icm' = 'invoke-command'; 'saps' = 'start-process'; 'start' = 'start-process'
    'sc' = 'set-content'; 'mi' = 'move-item'; 'mv' = 'move-item'; 'move' = 'move-item'
    'ci' = 'copy-item'; 'cp' = 'copy-item'; 'copy' = 'copy-item'; 'cpi' = 'copy-item'; 'ni' = 'new-item'
    'si' = 'set-item'; 'sp' = 'set-itemproperty'; 'rni' = 'rename-item'; 'ren' = 'rename-item'
    '%' = 'foreach-object'; 'foreach' = 'foreach-object'; 'tee' = 'tee-object'
    'kill' = 'stop-process'; 'spps' = 'stop-process'; 'spsv' = 'stop-service'; 'epcsv' = 'export-csv'
    'sal' = 'set-alias'; 'nal' = 'new-alias'; 'ipal' = 'import-alias'
    'iwr' = 'invoke-webrequest'; 'irm' = 'invoke-restmethod'
    'r' = 'invoke-history'; 'ihy' = 'invoke-history'; 'ii' = 'invoke-item'
}

# Any cmdlet with one of these verbs is flagged, except the harmless ones listed below.
$script:GateDestructiveVerb = @{
    'remove'    = 'deletes something'
    'clear'     = 'erases content'
    'format'    = 'formats a volume'
    'uninstall' = 'uninstalls software'
    'reset'     = 'resets state'
    'stop'      = 'stops a process, a service or the computer'
    'restart'   = 'restarts a service or the computer'
}
$script:GateVerbExempt = @(
    'clear-host', 'clear-variable', 'clear-history', 'remove-variable', 'remove-module', 'remove-job',
    'remove-event', 'remove-typedata', 'remove-psbreakpoint', 'remove-pssession',
    'format-table', 'format-list', 'format-wide', 'format-custom', 'format-hex',
    'stop-job', 'stop-transcript'
)

# Cmdlets flagged whatever their arguments are.
$script:GateFlaggedCmdlet = @{
    'invoke-expression'        = 'executes a string as code'
    'add-type'                 = 'compiles and loads code'
    'invoke-history'           = 're-runs an earlier command'
    'invoke-item'              = 'opens a file with its default handler, which runs executables and scripts'
    'set-alias'                = 'redefines a command name'
    'new-alias'                = 'redefines a command name'
    'import-alias'             = 'redefines command names'
    'invoke-cimmethod'         = 'calls a CIM/WMI method'
    'invoke-wmimethod'         = 'calls a CIM/WMI method'
    'set-content'              = 'overwrites a file'
    'out-file'                 = 'overwrites a file'
    'export-csv'               = 'overwrites a file'
    'export-clixml'            = 'overwrites a file'
    'initialize-disk'          = 're-initialises a disk'
    'initialize-volume'        = 're-initialises a volume'
    'set-partition'            = 'changes a partition'
    'resize-partition'         = 'changes a partition'
    'set-disk'                 = 'changes a disk'
    'restore-computer'         = 'rolls the system back to a restore point'
    'unregister-scheduledtask' = 'deletes a scheduled task'
    'start-transcript'         = 'overwrites a file'
    'register-scheduledtask'   = 'schedules a command to run later, where the gate cannot check it'
    'register-scheduledjob'    = 'schedules a command to run later, where the gate cannot check it'
    'new-service'              = 'installs a service that runs a command the gate cannot check'
}

# Verbs that mark a Verb-Noun name as a PowerShell command. A hyphenated name with any other first
# part (apt-get, docker-compose, pwsh-preview) is a native program and gets the native rules.
$script:GateKnownVerb = @(
    'add', 'approve', 'assert', 'backup', 'block', 'build', 'checkpoint', 'clear', 'close', 'compare', 'complete',
    'compress', 'confirm', 'connect', 'convert', 'convertfrom', 'convertto', 'copy', 'debug', 'deny', 'deploy',
    'disable', 'disconnect', 'dismount', 'edit', 'enable', 'enter', 'exit', 'expand', 'export', 'find', 'format',
    'get', 'grant', 'group', 'hide', 'import', 'initialize', 'install', 'invoke', 'join', 'limit', 'lock', 'measure',
    'merge', 'mount', 'move', 'new', 'open', 'optimize', 'out', 'ping', 'pop', 'protect', 'publish', 'push', 'read',
    'receive', 'redo', 'register', 'remove', 'rename', 'repair', 'request', 'reset', 'resize', 'resolve', 'restart',
    'restore', 'resume', 'revoke', 'save', 'search', 'select', 'send', 'set', 'show', 'skip', 'split', 'start', 'step',
    'stop', 'submit', 'suspend', 'switch', 'sync', 'test', 'trace', 'unblock', 'undo', 'uninstall', 'unlock',
    'unprotect', 'unpublish', 'unregister', 'update', 'use', 'wait', 'watch', 'write',
    'foreach', 'where', 'sort', 'tee'
)

# -Force on a cmdlet with one of these verbs only widens what is read (e.g. Get-ChildItem -Force).
$script:GateReadOnlyVerb = @(
    'get', 'test', 'select', 'where', 'sort', 'group', 'format', 'measure', 'find', 'show', 'resolve',
    'import', 'write', 'read', 'convertto', 'convertfrom', 'join', 'split', 'compare', 'foreach', 'search'
)

# Native programs flagged whatever their arguments are.
$script:GateNativeAlways = @{}
foreach ($name in 'sudo', 'doas', 'su', 'runas', 'gsudo', 'pkexec') { $script:GateNativeAlways[$name] = 'runs a command with elevated rights' }
$script:GateShell = @('powershell', 'pwsh', 'cmd', 'bash', 'sh', 'zsh', 'dash', 'ksh', 'csh', 'tcsh', 'fish', 'wsl', 'ssh')
foreach ($name in $script:GateShell) { $script:GateNativeAlways[$name] = 'starts a nested shell the gate cannot inspect' }
foreach ($name in 'mshta', 'wscript', 'cscript', 'rundll32', 'regsvr32', 'wmic', 'forfiles', 'schtasks', 'at', 'crontab') { $script:GateNativeAlways[$name] = 'launches code the gate cannot inspect' }
foreach ($name in 'unlink', 'shred', 'srm', 'sdelete', 'wipe', 'truncate') { $script:GateNativeAlways[$name] = 'deletes or truncates files' }
foreach ($name in 'format', 'diskpart', 'fdisk', 'sfdisk', 'gdisk', 'parted', 'wipefs', 'dd', 'mkswap', 'cipher', 'fsutil', 'bcdedit', 'vssadmin', 'wbadmin') { $script:GateNativeAlways[$name] = 'modifies disks or volumes' }
foreach ($name in 'shutdown', 'reboot', 'poweroff', 'halt', 'logoff', 'init', 'telinit') { $script:GateNativeAlways[$name] = 'shuts down or restarts the system' }
foreach ($name in 'pkill', 'killall', 'taskkill', 'tskill') { $script:GateNativeAlways[$name] = 'kills processes' }
foreach ($name in 'regedit') { $script:GateNativeAlways[$name] = 'modifies the registry' }

# Interpreters, with the single-letter switches (case-sensitive) that make them run inline code.
$script:GateInterpreter = @{
    'python' = 'c'; 'python2' = 'c'; 'python3' = 'c'; 'py' = 'c'; 'perl' = 'eE'; 'ruby' = 'e'
    'node' = 'ep'; 'nodejs' = 'ep'; 'bun' = 'ep'; 'deno' = ''; 'php' = 'r'; 'lua' = 'e'; 'osascript' = 'e'
}

# Programs that run another program: the inner command is checked as well.
$script:GateWrapper = @('env', 'nohup', 'nice', 'ionice', 'time', 'command', 'exec', 'xargs', 'stdbuf', 'timeout', 'watch', 'busybox', 'setsid')

# Programs that are only allowed with a read-only subcommand.
$script:GateSafeSubcommand = @{
    'reg'       = @('query', 'compare')
    'systemctl' = @('status', 'list-units', 'list-unit-files', 'list-timers', 'list-sockets', 'list-jobs', 'list-dependencies', 'is-active', 'is-enabled', 'is-failed', 'show', 'cat', 'get-default', 'help')
    'diskutil'  = @('list', 'info')
    'launchctl' = @('list', 'print')
}

# Programs that only read, search or print: their arguments are data, so the word heuristic is skipped.
$script:GateReadOnlyNative = @(
    'grep', 'egrep', 'fgrep', 'rg', 'ag', 'ack', 'findstr', 'cat', 'type', 'more', 'less', 'head', 'tail', 'wc', 'sort',
    'uniq', 'cut', 'tr', 'echo', 'printf', 'man', 'which', 'where', 'whereis', 'whoami', 'hostname', 'date', 'ls', 'dir',
    'tree', 'ps', 'top', 'df', 'du', 'free', 'uname', 'ping', 'tracert', 'traceroute', 'nslookup', 'dig', 'ipconfig',
    'ifconfig', 'netstat', 'lsblk', 'id'
)

# For any other unknown program, an argument that is one of these whole words flags the command.
$script:GateDestructiveWord = '^(delete|del|destroy|purge|prune|remove|rm|rmi|rb|rmdir|rd|unlink|shred|srm|sdelete|uninstall|drop|wipe|wipefs|erase\w*|format|mkfs\S*|diskpart|fdisk|parted|dd|mkswap|kill|pkill|killall|taskkill|truncate|reset|force|hard|mirror|overwrite|nuke|stop|restart|shutdown|reboot|poweroff|halt)$'

# Instance methods flagged by name (a computed method name is always flagged).
$script:GateMemberDeny = '^(Delete\w*|Remove\w*|Clear\w*|Kill|Terminate\w*|Stop\w*|Restart\w*|Reboot|Shutdown|Win32Shutdown\w*|CloseMainWindow|Uninstall\w*|Format|Truncate|Erase\w*|Purge\w*|Wipe\w*|Drop\w*|Destroy\w*|Create\w*|Open\w*|Save\w*|MoveTo|CopyTo|Start|Run|Exec\w*|ShellExecute\w*|Invoke\w*|DynamicInvoke|NewScriptBlock|ExpandString|GetMethods?|GetMembers?|GetConstructors?|Load\w*|Download\w*|Encrypt|SetLength|SetAccessControl|SetValue)$'

# .NET types whose static members may be called. '.' allows every member; otherwise a member regex.
$script:GateSafeType = @{}
foreach ($name in 'math', 'string', 'char', 'int', 'int16', 'int32', 'int64', 'long', 'uint32', 'uint64', 'double', 'single', 'float',
    'decimal', 'bool', 'boolean', 'byte', 'bigint', 'numerics.biginteger', 'datetime', 'datetimeoffset', 'timespan', 'timezoneinfo',
    'guid', 'version', 'semver', 'convert', 'bitconverter', 'array', 'enum', 'uri', 'regex', 'text.regularexpressions.regex',
    'text.encoding', 'text.stringbuilder', 'io.path', 'console', 'ipaddress', 'net.ipaddress', 'net.dns', 'net.webutility',
    'web.httputility', 'cultureinfo', 'globalization.cultureinfo', 'runtime.interopservices.runtimeinformation',
    'pscustomobject', 'psobject', 'hashtable', 'ordered', 'object', 'random', 'collections.arraylist',
    'collections.generic.list', 'collections.generic.dictionary', 'collections.generic.hashset', 'linq.enumerable',
    'diagnostics.stopwatch', 'net.networkinformation.networkinterface', 'net.networkinformation.ipglobalproperties') {
    $script:GateSafeType[$name] = '.'
}
$script:GateSafeType['environment'] = '^(NewLine|MachineName|UserName|UserDomainName|OSVersion|ProcessorCount|Is64Bit\w+|GetEnvironmentVariables?|ExpandEnvironmentVariables|GetFolderPath|CurrentDirectory|TickCount(64)?|Version|SystemDirectory|GetLogicalDrives|ProcessId|ProcessPath|CommandLine|GetCommandLineArgs|UserInteractive|WorkingSet|SystemPageSize)$'
$script:GateSafeType['io.file'] = '^(Exists|ReadAll(Text|Lines|Bytes)|ReadLines|GetAttributes|Get(LastWrite|LastAccess|Creation)Time(Utc)?)$'
$script:GateSafeType['io.directory'] = '^(Exists|GetFiles|GetDirectories|GetFileSystemEntries|Enumerate\w+|GetCurrentDirectory|GetParent|GetLogicalDrives|GetDirectoryRoot|Get(LastWrite|LastAccess|Creation)Time(Utc)?)$'
$script:GateSafeType['io.driveinfo'] = '^GetDrives$'
$script:GateSafeType['security.principal.windowsidentity'] = '^GetCurrent$'

$script:GateNullDevice = '^(nul:?|/dev/null|\\\\\.\\nul|\$null)$'
$script:GateRegistryPath = '^(registry::|hk(lm|cu|cr|u|cc):|hkey_)'
$script:GateAstNamespace = 'System.Management.Automation.Language.'

function ConvertTo-GateToken {
    # Turns one command element into a token the rules can reason about:
    #   Kind = param | const | null | block | dyn, Text = its text, Flag = the switch name if it looks like one.
    param($Element)

    $ns = $script:GateAstNamespace
    $typeName = $Element.GetType().FullName

    if ($typeName -eq "${ns}CommandParameterAst") {
        $argumentText = $null
        if ($Element.Argument) { $argumentText = $Element.Argument.Extent.Text }
        return [pscustomobject]@{ Kind = 'param'; Text = ('-' + $Element.ParameterName); Flag = $Element.ParameterName.ToLowerInvariant(); Arg = $argumentText }
    }
    if ($typeName -eq "${ns}StringConstantExpressionAst") {
        $value = [string]$Element.Value
        $flag = $null
        # Quoted or double-dashed switches ('-c', --force) are not parameter nodes, but still switches.
        if ($value -match '^[-\u2013\u2014\u2015]{1,2}([^-\u2013\u2014\u2015].*)$') { $flag = $Matches[1].ToLowerInvariant() }
        return [pscustomobject]@{ Kind = 'const'; Text = $value; Flag = $flag; Arg = $null }
    }
    if ($typeName -eq "${ns}VariableExpressionAst" -and $Element.VariablePath.UserPath -eq 'null') {
        return [pscustomobject]@{ Kind = 'null'; Text = '$null'; Flag = $null; Arg = $null }
    }
    if ($typeName -eq "${ns}ScriptBlockExpressionAst") {
        return [pscustomobject]@{ Kind = 'block'; Text = '{}'; Flag = $null; Arg = $null }
    }
    if ($typeName -eq "${ns}ConstantExpressionAst") {
        return [pscustomobject]@{ Kind = 'const'; Text = [string]$Element.Value; Flag = $null; Arg = $null }
    }
    if ($typeName -eq "${ns}ArrayLiteralAst") {
        $items = foreach ($item in $Element.Elements) { ConvertTo-GateToken -Element $item }
        return $items
    }
    # Variables, subexpressions, strings with embedded expressions: the value is only known at run time.
    return [pscustomobject]@{ Kind = 'dyn'; Text = '<dynamic>'; Flag = $null; Arg = $null }
}

function ConvertTo-GateTextToken {
    # Same token shape, built from a plain word (used for the argument strings of Start-Process).
    param([string]$Text)

    $flag = $null
    if ($Text -match '^-{1,2}([^-].*)$') { $flag = $Matches[1].ToLowerInvariant() }
    return [pscustomobject]@{ Kind = 'const'; Text = $Text; Flag = $flag; Arg = $null }
}

function Test-GateFlag {
    # True when a switch is present, in full or abbreviated to at least $Min characters (-Recurse, -Rec, -r).
    param($Tokens, [string]$Full, [int]$Min = 1)

    foreach ($token in $Tokens) {
        if (-not $token.Flag) { continue }
        $flagName = ($token.Flag -split '[:=]')[0]
        if ($flagName.Length -ge $Min -and $Full.StartsWith($flagName)) { return $true }
    }
    return $false
}

function Get-GateFlagValue {
    # The literal value given to a parameter (-ItemType Directory, -ItemType:Directory), or $null.
    param($Tokens, [string]$Full, [int]$Min = 1)

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = $Tokens[$i]
        if ($token.Kind -ne 'param' -or $token.Flag.Length -lt $Min -or -not $Full.StartsWith($token.Flag)) { continue }
        if ($token.Arg) { return $token.Arg.Trim('"', "'") }
        if ($i + 1 -lt $Tokens.Count) { return $Tokens[$i + 1].Text }
    }
    return $null
}

function Test-GitLongOption {
    # git accepts any unambiguous abbreviation of a long option (--har for --hard).
    param([string[]]$Word, [string[]]$Name)

    foreach ($current in $Word) {
        if ($current -notlike '--?*') { continue }
        $option = ($current.Substring(2) -split '=')[0].ToLowerInvariant()
        if ($option.Length -lt 2) { continue }
        foreach ($candidate in $Name) {
            if ($candidate.StartsWith($option)) { return $true }
        }
    }
    return $false
}

function Get-GitCommandRisk {
    # git is the native tool generated most often, so it gets precise rules instead of the word heuristic.
    param([string[]]$Word, [bool]$HasDynamic)

    if ($HasDynamic) { return 'git is called with arguments that are only known at run time' }

    # Skip global options to find the subcommand.
    $i = 0
    while ($i -lt $Word.Count) {
        $current = $Word[$i]
        if ($current -cin '-c', '--config-env', '--exec-path' -or $current -like '--exec-path=*' -or $current -like '--config-env=*') {
            return 'git -c / --exec-path can redefine what git runs'
        }
        if ($current -cin '-C', '--git-dir', '--work-tree', '--namespace') { $i += 2; continue }
        if ($current -like '-*') { $i++; continue }
        break
    }
    if ($i -ge $Word.Count) { return $null }

    $sub = $Word[$i].ToLowerInvariant()
    $rest = @()
    if ($i + 1 -lt $Word.Count) { $rest = @($Word[($i + 1)..($Word.Count - 1)]) }
    $restLower = @($rest | ForEach-Object { $_.ToLowerInvariant() })
    # Letters of the single-dash switches, case kept: "-df" and "-d -f" both give "df".
    $short = -join @($rest | Where-Object { $_ -cmatch '^-[a-zA-Z]+$' } | ForEach-Object { $_.Substring(1) })
    $positional = @($rest | Where-Object { $_ -notlike '-*' })

    switch ($sub) {
        'reset' { if (Test-GitLongOption -Word $rest -Name 'hard', 'merge', 'keep') { return 'git reset --hard discards local work' } }
        'clean' { if ($short -cnotmatch 'n' -and -not (Test-GitLongOption -Word $rest -Name 'dry-run')) { return 'git clean deletes untracked files' } }
        'checkout' {
            if ($rest -contains '--' -or $rest -contains '.' -or $short -cmatch 'f' -or (Test-GitLongOption -Word $rest -Name 'force')) {
                return 'git checkout discards local changes'
            }
            # "git checkout main file.txt" overwrites the file; "-b new start" just creates a branch.
            $createsBranch = $short -cmatch '[bBt]' -or (Test-GitLongOption -Word $rest -Name 'orphan', 'track')
            if ($positional.Count -ge 2 -and -not $createsBranch) { return 'git checkout overwrites files with another version' }
        }
        'switch' { if ($short -cmatch '[fC]' -or (Test-GitLongOption -Word $rest -Name 'force', 'discard-changes', 'force-create')) { return 'git switch discards local changes' } }
        'restore' {
            $staged = $short -cmatch 'S' -or (Test-GitLongOption -Word $rest -Name 'staged')
            $worktree = $short -cmatch 'W' -or (Test-GitLongOption -Word $rest -Name 'worktree')
            if (-not $staged -or $worktree) { return 'git restore discards local changes' }
        }
        'push' {
            if ($short -cmatch '[fd]' -or (Test-GitLongOption -Word $rest -Name 'force', 'force-with-lease', 'force-if-includes', 'delete', 'mirror', 'prune') -or $rest -match '^(\+.*|:.+)$') {
                return 'git push rewrites or deletes remote refs'
            }
        }
        'branch' {
            $delete = $short -cmatch 'd' -or (Test-GitLongOption -Word $rest -Name 'delete')
            $force = $short -cmatch 'f' -or (Test-GitLongOption -Word $rest -Name 'force')
            if ($short -cmatch 'D' -or ($delete -and $force)) { return 'git branch -D force-deletes a branch' }
        }
        'stash' { if ($restLower -match '^(drop|clear)$') { return 'git stash drop/clear deletes stashed work' } }
        'rm' { if (-not (Test-GitLongOption -Word $rest -Name 'cached')) { return 'git rm deletes files' } }
        'reflog' { if ($restLower -match '^(expire|delete)$') { return 'git reflog expire/delete removes recovery data' } }
        'gc' { if (Test-GitLongOption -Word $rest -Name 'prune') { return 'git gc --prune removes recovery data' } }
        'worktree' { if ($restLower -match '^(remove|prune)$') { return 'git worktree remove deletes a working tree' } }
        'submodule' { if ($restLower -contains 'deinit') { return 'git submodule deinit removes submodule work trees' } }
        'update-ref' { if ($rest -ccontains '-d') { return 'git update-ref -d deletes a ref' } }
        'config' { if ($restLower -match '^alias\.') { return 'git config alias can make git run arbitrary commands' } }
        { $_ -in 'filter-branch', 'filter-repo' } { return "git $sub rewrites history" }
    }
    return $null
}

function Get-NamedCommandRisk {
    # Returns the reason a command (name plus argument tokens) is flagged, or $null when no rule matches.
    param(
        [string]$Name,
        $Tokens,
        [bool]$Piped = $false,
        [int]$Depth = 0
    )

    $Tokens = @($Tokens | Where-Object { $_ })
    if ($Depth -gt 6) { return 'commands are nested too deeply to analyse' }

    # "Module\Remove-Item", "/bin/rm" and "C:\Windows\System32\cmd.exe" all reduce to the bare name.
    $n = ($Name -split '[\\/]')[-1].ToLowerInvariant() -replace '\.(exe|com|bat|cmd)$', ''
    if (-not $n) { return $null }
    if ($script:GateAlias.ContainsKey($n)) { $n = $script:GateAlias[$n] }

    $consts = @($Tokens | Where-Object { $_.Kind -eq 'const' } | ForEach-Object { $_.Text })
    $hasDynamic = @($Tokens | Where-Object { $_.Kind -eq 'dyn' }).Count -gt 0
    $words = @($Tokens | Where-Object { $_.Kind -eq 'const' -or $_.Kind -eq 'param' } | ForEach-Object { $_.Text })
    $lower = @($words | ForEach-Object { $_.ToLowerInvariant() })

    # ---- PowerShell cmdlets -------------------------------------------------------------------
    if ($script:GateFlaggedCmdlet.ContainsKey($n)) { return "$n $($script:GateFlaggedCmdlet[$n])" }

    if ($n -match '^([a-z]+)-(\w+)$' -and $script:GateKnownVerb -contains $Matches[1]) {
        $verb = ($n -split '-')[0]

        if ($script:GateDestructiveVerb.ContainsKey($verb) -and $script:GateVerbExempt -notcontains $n) {
            return "$n $($script:GateDestructiveVerb[$verb])"
        }
        if (Test-GateFlag -Tokens $Tokens -Full 'confirm' -Min 4) { return "$n overrides its confirmation prompt" }

        switch ($n) {
            'new-item' {
                $itemType = Get-GateFlagValue -Tokens $Tokens -Full 'itemtype' -Min 1
                if (-not $itemType) { $itemType = Get-GateFlagValue -Tokens $Tokens -Full 'type' -Min 2 }
                if ((Test-GateFlag -Tokens $Tokens -Full 'force' -Min 1) -and "$itemType" -notmatch '^(directory|container)$') {
                    return 'new-item -Force replaces an existing file'
                }
                if ($lower -match '^(alias|function):') { return 'new-item redefines a command name' }
                return $null
            }
            'tee-object' {
                $toVariable = Test-GateFlag -Tokens $Tokens -Full 'variable' -Min 1
                $appends = Test-GateFlag -Tokens $Tokens -Full 'append' -Min 1
                if (-not $toVariable -and -not $appends) { return 'tee-object overwrites a file' }
                return $null
            }
            { $_ -eq 'copy-item' -or $_ -eq 'move-item' } {
                foreach ($token in $Tokens) {
                    if ($token.Kind -eq 'null' -or ($token.Kind -eq 'const' -and $token.Text -match $script:GateNullDevice)) {
                        return "$n to or from the null device destroys the file"
                    }
                    if (-not $token.Flag) { continue }
                    $isForce = $token.Flag -match '^(f|fo|for|forc|force)$'
                    # Native clusters such as -rf / -fv, but not -Filter or -FromSession.
                    $isCluster = $token.Flag -match '^[a-z]{2,4}$' -and $token.Flag -match 'f' -and $token.Flag -notmatch '^(fi|fro)'
                    if ($isForce -or $isCluster) { return "$n -Force overwrites the destination" }
                }
                if ($lower -match $script:GateRegistryPath) { return "$n writes to the registry" }
                if ($lower -match '^(alias|function):') { return "$n redefines a command name" }
                return $null
            }
            'foreach-object' {
                # ForEach-Object Delete / -MemberName Delete calls that method on every input object.
                foreach ($const in $consts) {
                    if ($const -match $script:GateMemberDeny) { return "foreach-object calls the member '$const' on each object" }
                }
                return $null
            }
            'new-object' {
                if (Test-GateFlag -Tokens $Tokens -Full 'comobject' -Min 1) { return 'new-object -ComObject creates a COM object the gate cannot inspect' }
                $typeName = Get-GateFlagValue -Tokens $Tokens -Full 'typename' -Min 1
                if (-not $typeName -and $consts.Count) { $typeName = $consts[0] }
                $key = ("$typeName".ToLowerInvariant() -replace '^system\.', '' -replace '\[.*$', '')
                if (-not $script:GateSafeType.ContainsKey($key)) { return "new-object creates the unvetted type '$typeName'" }
                return $null
            }
            'start-process' {
                if ($hasDynamic) { return 'start-process is given a target or arguments that are only known at run time' }
                if (Test-GateFlag -Tokens $Tokens -Full 'verb' -Min 1) { return 'start-process -Verb can elevate the new process' }
                # The target can sit anywhere among the arguments, so every word is tried as a command name.
                $flat = @()
                foreach ($const in $consts) { $flat += @($const -split '\s+' | Where-Object { $_ }) }
                for ($i = 0; $i -lt [Math]::Min($flat.Count, 24); $i++) {
                    if ($flat[$i] -match '^-' -or $flat[$i] -notmatch '^[\w.\\/:~-]+$') { continue }
                    $rest = @()
                    if ($i + 1 -lt $flat.Count) { $rest = @($flat[($i + 1)..($flat.Count - 1)] | ForEach-Object { ConvertTo-GateTextToken -Text $_ }) }
                    $inner = Get-NamedCommandRisk -Name $flat[$i] -Tokens $rest -Depth ($Depth + 1)
                    if ($inner) { return "start-process launches: $inner" }
                }
                return $null
            }
            { $_ -eq 'invoke-webrequest' -or $_ -eq 'invoke-restmethod' } {
                if (Test-GateFlag -Tokens $Tokens -Full 'outfile' -Min 1) { return "$n -OutFile overwrites a file" }
                if ("$(Get-GateFlagValue -Tokens $Tokens -Full 'method' -Min 1)" -match '^delete$') { return "$n sends a DELETE request" }
                return $null
            }
        }

        if ($verb -in 'set', 'new', 'rename', 'move', 'copy') {
            if ($lower -match $script:GateRegistryPath) { return "$n writes to the registry" }
            if ($lower -match '^(alias|function):') { return "$n redefines a command name" }
        }
        if ($script:GateReadOnlyVerb -notcontains $verb -and (Test-GateFlag -Tokens $Tokens -Full 'force' -Min 2)) {
            return "$n -Force overrides a safety check"
        }
        return $null
    }

    # ---- Native programs ----------------------------------------------------------------------
    if ($script:GateNativeAlways.ContainsKey($n)) { return "$n $($script:GateNativeAlways[$n])" }
    if ($n -like 'pwsh*' -or $n -like 'powershell*') { return "$n starts a nested shell the gate cannot inspect" }
    if ($n -like 'mkfs*') { return "$n formats a filesystem" }

    if ($script:GateInterpreter.ContainsKey($n)) {
        $letters = $script:GateInterpreter[$n]
        foreach ($token in $Tokens) {
            if ($token.Text -in '--eval', '--command', '--print', '--exec', '--execute' -or $token.Text -eq '-') { return "$n runs inline code the gate cannot inspect" }
            if ($n -eq 'deno' -and $token.Text -eq 'eval') { return "$n runs inline code the gate cannot inspect" }
            if ($letters -and $token.Text -cmatch '^-[a-zA-Z]{1,4}$' -and $token.Text.Substring(1) -cmatch "[$letters]") { return "$n runs inline code the gate cannot inspect" }
        }
        $hasScriptArgument = @($Tokens | Where-Object { $_.Kind -ne 'param' -and -not $_.Flag }).Count -gt 0
        if ($Piped -and -not $hasScriptArgument) { return "$n reads its program from the pipeline" }
        return $null
    }

    if ($script:GateWrapper -contains $n) {
        for ($i = 0; $i -lt $Tokens.Count; $i++) {
            $token = $Tokens[$i]
            if ($token.Kind -eq 'dyn') { return "$n runs a command that is only known at run time" }
            if ($token.Kind -ne 'const' -or $token.Flag -or $token.Text -match '=' -or $token.Text -match '^[\d.]+[smhd]?$') { continue }
            $rest = @()
            if ($i + 1 -lt $Tokens.Count) { $rest = @($Tokens[($i + 1)..($Tokens.Count - 1)]) }
            $inner = Get-NamedCommandRisk -Name $token.Text -Tokens $rest -Depth ($Depth + 1)
            if ($inner) { return "$n runs: $inner" }
        }
        return $null
    }

    if ($script:GateSafeSubcommand.ContainsKey($n)) {
        if ($Tokens.Count -eq 0) { return $null }
        $subcommand = @($Tokens | Where-Object { $_.Kind -eq 'const' -and -not $_.Flag -and $_.Text -notmatch '^/' }) | Select-Object -First 1
        if (-not $subcommand -or $script:GateSafeSubcommand[$n] -notcontains $subcommand.Text.ToLowerInvariant()) {
            return "$n is used with a subcommand that is not on its read-only list"
        }
        return $null
    }
    if ($n -eq 'service') {
        if ($lower -contains 'status' -or $lower -contains '--status-all') { return $null }
        return 'service changes the state of a system service'
    }
    if ($n -eq 'find') {
        if ($lower -match '^-(delete|exec|execdir|ok|okdir|fprint\w*|fls)$') { return 'find -delete / -exec deletes files or runs commands' }
        return $null
    }
    if ($n -in 'chmod', 'chown', 'chgrp') {
        foreach ($word in $words) {
            if ($word -cmatch '^-[a-zA-Z]*R' -or $word -eq '--recursive') { return "$n -R changes permissions recursively" }
        }
        return $null
    }
    if ($n -eq 'robocopy') {
        if ($lower -match '^/(mir|purge|move|mov)$') { return 'robocopy deletes files at the destination or the source' }
        return $null
    }
    if ($n -eq 'rsync') {
        if ($lower -match '^--(delete|remove-source-files)') { return 'rsync deletes files' }
        return $null
    }
    if ($n -eq 'git') { return Get-GitCommandRisk -Word $words -HasDynamic $hasDynamic }

    # Downloads written to a named file replace whatever is there (curl -o, wget -O).
    if ($n -eq 'curl' -and ($words -cmatch '^(-[a-zA-Z]*[oO][a-zA-Z]*|--output|--output-dir|--remote-name(-all)?)$')) { return 'curl writes its download to a file' }
    if ($n -eq 'wget' -and ($words -cmatch '^(-[a-zA-Z]*O[a-zA-Z]*|--output-document.*)$')) { return 'wget writes its download to a file' }

    if ($script:GateReadOnlyNative -notcontains $n) {
        for ($i = 0; $i -lt $lower.Count; $i++) {
            $word = $lower[$i]
            if (($word -replace '^(--?|/)', '') -match $script:GateDestructiveWord) {
                return "$n is called with the destructive-sounding argument '$word'"
            }
            # "docker exec web sh -c ...", "conhost cmd /c ...": a shell that is handed a command line.
            $bare = ($word -split '[\\/]')[-1] -replace '\.(exe|com|bat|cmd)$', ''
            if ($script:GateShell -contains $bare -and $i + 1 -lt $lower.Count -and $lower[$i + 1] -match '^(-c|/c|/k|-command|-e|-ec|-enc\w*)$') {
                return "$n hands a command line to the shell '$bare'"
            }
        }
        # A quoted argument that is itself a command line: script -c "rm -rf ~".
        foreach ($const in $consts) {
            $parts = @($const -split '\s+' | Where-Object { $_ })
            if ($parts.Count -lt 2 -or $parts[0] -notmatch '^[\w.\\/:~-]+$') { continue }
            $partTokens = @($parts[1..($parts.Count - 1)] | ForEach-Object { ConvertTo-GateTextToken -Text $_ })
            $inner = Get-NamedCommandRisk -Name $parts[0] -Tokens $partTokens -Depth ($Depth + 1)
            if ($inner) { return "$n is given a command line: $inner" }
        }
    }
    return $null
}

function Get-CommandRisk {
    # Returns the reasons a command must not run without confirmation. An empty result means "safe".
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return @() }

    $reasons = New-Object System.Collections.Generic.List[string]
    try {
        # Escape sequences, bidi overrides and zero-width characters can make the prompt show something
        # other than what would run.
        if ($Command -match '[\p{Cc}\p{Cf}-[\t\r\n]]') { $reasons.Add('contains control or invisible formatting characters') }

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $reasons.Add("cannot be parsed, so it cannot be checked ($($errors[0].Message))")
            return $reasons.ToArray()
        }

        $ns = $script:GateAstNamespace
        foreach ($node in $ast.FindAll({ $true }, $true)) {
            $typeName = $node.GetType().FullName

            if ($typeName -eq "${ns}CommandAst") {
                $name = $node.GetCommandName()
                $elements = @($node.CommandElements)
                if (-not $name) {
                    # '& { ... }' is fine: the block is walked like any other node.
                    if ($elements[0].GetType().FullName -ne "${ns}ScriptBlockExpressionAst") {
                        $reasons.Add('invokes a command whose name is only known at run time')
                    }
                    continue
                }
                $commandTokens = @()
                for ($i = 1; $i -lt $elements.Count; $i++) { $commandTokens += @(ConvertTo-GateToken -Element $elements[$i]) }
                $pipeline = $node.Parent
                $piped = $pipeline -and $pipeline.GetType().FullName -eq "${ns}PipelineAst" -and $pipeline.PipelineElements.Count -gt 1 -and -not [object]::ReferenceEquals($pipeline.PipelineElements[0], $node)
                $risk = Get-NamedCommandRisk -Name $name -Tokens $commandTokens -Piped ([bool]$piped)
                if ($risk) { $reasons.Add($risk) }
            }
            elseif ($typeName -eq "${ns}FileRedirectionAst") {
                if (-not $node.Append) {
                    $target = $node.Location
                    $targetType = $target.GetType().FullName
                    $toNull = ($targetType -eq "${ns}VariableExpressionAst" -and $target.VariablePath.UserPath -eq 'null') -or
                        ($targetType -eq "${ns}StringConstantExpressionAst" -and $target.Value -match $script:GateNullDevice)
                    if (-not $toNull) { $reasons.Add("'>' redirection overwrites a file") }
                }
            }
            elseif ($typeName -eq "${ns}InvokeMemberExpressionAst") {
                if ($node.Member.GetType().FullName -ne "${ns}StringConstantExpressionAst") {
                    $reasons.Add('calls a method whose name is only known at run time')
                    continue
                }
                $member = [string]$node.Member.Value
                if ($node.Static) {
                    if ($node.Expression.GetType().FullName -ne "${ns}TypeExpressionAst") {
                        $reasons.Add('calls a static method on a type that is only known at run time')
                        continue
                    }
                    $fullTypeName = $node.Expression.TypeName.FullName
                    $key = ($fullTypeName.ToLowerInvariant() -replace '^system\.', '' -replace '\[.*$', '')
                    $allowed = $script:GateSafeType.ContainsKey($key)
                    if ($allowed -and $member -eq 'new') { $allowed = $script:GateSafeType[$key] -eq '.' }
                    elseif ($allowed) { $allowed = $member -match $script:GateSafeType[$key] }
                    if (-not $allowed) { $reasons.Add("calls [$fullTypeName]::$member, which is not on the vetted list") }
                }
                else {
                    $firstArgument = $null
                    if ($node.Arguments -and $node.Arguments.Count -gt 0) { $firstArgument = $node.Arguments[0] }
                    if ($member -match $script:GateMemberDeny) {
                        $reasons.Add("calls the method .$member()")
                    }
                    elseif ($member -in 'ForEach', 'Where' -and $firstArgument -and $firstArgument.GetType().FullName -eq "${ns}StringConstantExpressionAst" -and $firstArgument.Value -match $script:GateMemberDeny) {
                        $reasons.Add("calls the method .$($firstArgument.Value)() through .$member()")
                    }
                    elseif ($member -eq 'GetType' -and $firstArgument) {
                        $reasons.Add('looks up a type by name at run time')
                    }
                }
            }
            elseif ($typeName -eq "${ns}VariableExpressionAst") {
                if ($node.VariablePath.IsDriveQualified -and $node.VariablePath.DriveName -eq 'alias') {
                    $reasons.Add('uses the alias: drive, which can redefine command names')
                }
            }
            elseif ($typeName -eq "${ns}UsingStatementAst") {
                $reasons.Add('loads a module or assembly with a using statement')
            }
        }
    }
    catch {
        $reasons.Add("could not be analysed ($($_.Exception.Message))")
    }

    return @($reasons | Select-Object -Unique)
}

function Test-CommandSafety {
    # $true only when the gate found nothing to flag. Parse failures and analysis errors return $false.
    param([string]$Command)

    return (@(Get-CommandRisk -Command $Command).Count -eq 0)
}

function Show-CommandRisk {
    param(
        [string]$Command,
        [string[]]$Risk
    )

    Write-Host "⚠️  Potentially harmful command detected" -ForegroundColor Red
    Write-Host "   $Command" -ForegroundColor Yellow
    foreach ($reason in $Risk) {
        Write-Host "   - $reason" -ForegroundColor Yellow
    }
}

function Confirm-FlaggedCommand {
    # A flagged command only runs after the full word "yes"; a reflexive "y" is not enough.
    param(
        [string]$Command,
        [string[]]$Risk
    )

    Show-CommandRisk -Command $Command -Risk $Risk
    $answer = Read-Host "Type 'yes' to run it anyway"
    return ("$answer".Trim() -eq 'yes')
}
#endregion Safety gate

function Add-ToHistory {
    param(
        [string]$Request,
        [string]$Command,
        [bool]$Executed
    )

    $entry = @{
        Timestamp = Get-Date
        Request = $Request
        Command = $Command
        Executed = $Executed
        Context = Get-ContextInfo
    }

    $script:UserHistory += $entry

    # Keep only last 50 entries
    if ($script:UserHistory.Count -gt 50) {
        $script:UserHistory = $script:UserHistory | Select-Object -Last 50
    }
}

function Show-CommandHistory {
    param([int]$Last = 10)

    if ($script:UserHistory.Count -eq 0) {
        Write-AIResponse "No command history available" "info"
        return
    }

    $recentHistory = @($script:UserHistory | Select-Object -Last $Last)

    Write-AIResponse "Recent Command History:" "info"
    Write-Host ""

    for ($i = 0; $i -lt $recentHistory.Count; $i++) {
        $entry = $recentHistory[$i]
        if ($entry -and $entry.Timestamp) {
            $status = if ($entry.Executed) { "[OK]" } else { "[FAIL]" }
            $timeStr = $entry.Timestamp.ToString("HH:mm:ss")

            Write-Host "[$($i+1)] " -NoNewline -ForegroundColor Cyan
            Write-Host "$status " -NoNewline
            Write-Host "$timeStr " -NoNewline -ForegroundColor Gray
            Write-Host "'$($entry.Request)'" -ForegroundColor Yellow
            Write-Host "    -> " -NoNewline -ForegroundColor Gray
            Write-Host "$($entry.Command)" -ForegroundColor White

            if ($entry.Context -and $entry.Context.PathType -ne "General Directory") {
                Write-Host "    [DIR] $($entry.Context.PathType)" -ForegroundColor DarkGray
            }
            Write-Host ""
        }
    }
}

function Clear-CommandHistory {
    $script:UserHistory = @()
    Write-AIResponse "Command history cleared" "success"
}

function Write-CommandOutput {
    # Prints formatter output line by line, dropping the blank lines Out-String puts around tables.
    param([Parameter(ValueFromPipeline = $true)][string]$Line)

    begin {
        $started = $false
        $pendingBlank = 0
    }
    process {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            if ($started) { $pendingBlank++ }
            return
        }
        while ($pendingBlank -gt 0) { Write-Host ""; $pendingBlank-- }
        $started = $true
        Write-Host $Line
    }
}

function Invoke-GeneratedCommand {
    # Runs a command that passed the safety gate or was explicitly confirmed, and records it.
    # Every entry point (ai, aia, nl, AI> REPL) executes through here.
    param(
        [string]$Request,
        [string]$Command,
        [switch]$Quiet
    )

    # $LASTEXITCODE keeps the exit code of the last native program, possibly one from long before this
    # command. Clear it so that only this command's exit code is reported.
    Set-Variable -Name LASTEXITCODE -Value 0 -Scope Global

    try {
        # Out-String applies the normal PowerShell formatting (tables, lists, error records).
        # Passing objects straight to Write-Host would print only their ToString() value.
        Invoke-Expression $Command 2>&1 | Out-String -Stream | Write-CommandOutput

        $exitCode = $LASTEXITCODE
        if ($exitCode) {
            if ($Quiet) {
                Write-Host "❌ Exit code: $exitCode" -ForegroundColor Red
            } else {
                Write-AIResponse "Command completed with exit code: $exitCode" "warning"
            }
        } elseif (-not $Quiet) {
            Write-AIResponse "Command executed successfully" "success"
        }

        Add-ToHistory -Request $Request -Command $Command -Executed $true
    } catch {
        if ($Quiet) {
            Write-Host "❌ $($_.Exception.Message)" -ForegroundColor Red
        } else {
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-AIResponse "Execution failed" "error"
        }
        Add-ToHistory -Request $Request -Command $Command -Executed $false
    }
}

function Invoke-AICommand {
    # -AutoExecute     run a command that passes the safety gate without asking
    # -CleanOutput     compact output
    # -ConfirmFlagged  with -AutoExecute: ask for a typed "yes" on a flagged command instead of refusing it
    param(
        [string]$NaturalLanguage,
        [switch]$AutoExecute,
        [switch]$CleanOutput,
        [switch]$ConfirmFlagged
    )

    if (-not "$NaturalLanguage".Trim()) {
        if (-not $CleanOutput) {
            Write-AIResponse "Please provide a command request" "warning"
        }
        return
    }

    # Silent connection check for clean output mode
    if (-not (Test-OllamaConnection)) {
        if ($CleanOutput) {
            Write-Host "⚠️  Ollama not running" -ForegroundColor Yellow
        } else {
            Write-AIResponse "Ollama is not running. Please start Ollama first." "error"
            Write-AIResponse "Tip: Run 'ollama serve' in another terminal" "info"
        }
        return
    }

    if (-not $CleanOutput) {
        $context = Get-ContextInfo
        Write-AIResponse "Context: $($context.PathType)" "info"
        if ($context.GitBranch) {
            Write-AIResponse "Git: $($context.GitBranch) - $($context.GitStatus)" "info"
        }
        Show-ThinkingAnimation -Message "Analyzing your request" -DurationMs 1500
    }

    # A failed generation (model not pulled, timeout, server error) must not take the caller down:
    # the REPLs run this in a loop, and one of them starts while the module is being imported.
    $command = $null
    try {
        $command = Get-CommandSuggestion -NaturalLanguage $NaturalLanguage
    } catch {
        if ($CleanOutput) {
            Write-Host "❌ $($_.Exception.Message)" -ForegroundColor Red
        } else {
            Write-AIResponse "$($_.Exception.Message)" "error"
            Write-AIResponse "Tip: check that the model is pulled ('ollama pull $script:OllamaModel')" "info"
        }
        Add-ToHistory -Request $NaturalLanguage -Command "" -Executed $false
        return
    }

    if ($command) {
        $command = ConvertTo-CleanCommand -Response $command
    }

    if (-not $command) {
        if ($CleanOutput) {
            Write-Host "❌ Could not understand: '$NaturalLanguage'" -ForegroundColor Red
        } else {
            Write-AIResponse "Could not generate command for: '$NaturalLanguage'" "error"
            Write-AIResponse "Tip: Try rephrasing your request or being more specific" "info"
        }
        Add-ToHistory -Request $NaturalLanguage -Command "" -Executed $false
        return
    }

    if (-not $CleanOutput) {
        Write-AIResponse "Generated Command:" "command"
        Write-Host "    $command" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host ""
    }

    $risk = @(Get-CommandRisk -Command $command)

    if ($AutoExecute) {
        if ($risk.Count -gt 0) {
            if ($ConfirmFlagged) {
                if (Confirm-FlaggedCommand -Command $command -Risk $risk) {
                    Invoke-GeneratedCommand -Request $NaturalLanguage -Command $command -Quiet:$CleanOutput
                } else {
                    Write-Host "Command cancelled" -ForegroundColor Gray
                    Add-ToHistory -Request $NaturalLanguage -Command $command -Executed $false
                }
                return
            }

            # Auto-execute modes never run a flagged command.
            Show-CommandRisk -Command $command -Risk $risk
            Write-Host "   Not run. Use 'ai `"<request>`"' to review and confirm it." -ForegroundColor Gray
            Add-ToHistory -Request $NaturalLanguage -Command $command -Executed $false
            return
        }

        # Show the command being executed for educational purposes
        if ($CleanOutput) {
            Write-Host "💻 " -NoNewline -ForegroundColor Cyan
            Write-Host "$command" -ForegroundColor Yellow
        }

        Invoke-GeneratedCommand -Request $NaturalLanguage -Command $command -Quiet:$CleanOutput
        return
    }

    if ($risk.Count -gt 0) {
        if (Confirm-FlaggedCommand -Command $command -Risk $risk) {
            Invoke-GeneratedCommand -Request $NaturalLanguage -Command $command -Quiet:$CleanOutput
        } else {
            Write-AIResponse "Command cancelled by user" "info"
            Add-ToHistory -Request $NaturalLanguage -Command $command -Executed $false
        }
        return
    }

    $confirmation = Read-Host "Execute this command? [y/N/e(dit)]"

    switch ("$confirmation".ToLower()) {
        'y' {
            Write-AIResponse "Executing command..." "info"
            Invoke-GeneratedCommand -Request $NaturalLanguage -Command $command -Quiet:$CleanOutput
        }
        'e' {
            Write-Host "Edit command: " -NoNewline -ForegroundColor Cyan
            $editedCommand = Read-Host
            if ("$editedCommand".Trim()) {
                # An edited command goes through the same gate as a generated one.
                $editedRisk = @(Get-CommandRisk -Command $editedCommand)
                if ($editedRisk.Count -gt 0 -and -not (Confirm-FlaggedCommand -Command $editedCommand -Risk $editedRisk)) {
                    Write-AIResponse "Command cancelled by user" "info"
                    Add-ToHistory -Request $NaturalLanguage -Command $editedCommand -Executed $false
                } else {
                    Write-AIResponse "Executing edited command..." "info"
                    Invoke-GeneratedCommand -Request $NaturalLanguage -Command $editedCommand -Quiet:$CleanOutput
                }
            }
        }
        default {
            Write-AIResponse "Command cancelled by user" "info"
            Add-ToHistory -Request $NaturalLanguage -Command $command -Executed $false
        }
    }
}

function Start-ReplLoop {
    # Shared loop behind Start-NLMode and Start-AITerminal.
    param(
        [string]$Title,
        [string]$Hint,
        [string]$PromptPrefix = "",
        [switch]$ConfirmFlagged
    )

    Write-Host $Title -ForegroundColor Green
    Write-Host $Hint -ForegroundColor Gray
    Write-Host ""

    :repl while ($true) {
        $context = Get-ContextInfo

        # Clean prompt with minimal context
        $prompt = if ($PromptPrefix) { "$PromptPrefix>" } else { ">" }
        if ($context.GitBranch) {
            $prompt = if ($PromptPrefix) { "$PromptPrefix($($context.GitBranch))>" } else { "($($context.GitBranch)) >" }
        }

        Write-Host "$prompt " -NoNewline -ForegroundColor Cyan
        $userInput = Read-Host

        # Read-Host returns $null at end of input (closed or redirected stdin): leave instead of spinning.
        if ($null -eq $userInput) {
            break repl
        }

        switch ($userInput.ToLower().Trim()) {
            'exit' {
                Write-Host "👋 Goodbye!" -ForegroundColor Green
                break repl
            }
            'history' {
                Show-CommandHistory -Last 10
                continue
            }
            'clear' {
                Clear-Host
                Write-Host $Title -ForegroundColor Green
                Write-Host $Hint -ForegroundColor Gray
                Write-Host ""
                continue
            }
            'help' {
                Write-Host "Available commands:" -ForegroundColor Yellow
                Write-Host "  exit     - Exit AI terminal" -ForegroundColor Cyan
                Write-Host "  history  - Show command history" -ForegroundColor Cyan
                Write-Host "  clear    - Clear screen" -ForegroundColor Cyan
                Write-Host "  help     - Show this help" -ForegroundColor Cyan
                Write-Host "  Or describe what you want to do in natural language!" -ForegroundColor Green
                continue
            }
            default {
                if ($userInput.Trim()) {
                    Invoke-AICommand -NaturalLanguage $userInput -AutoExecute -CleanOutput -ConfirmFlagged:$ConfirmFlagged
                    Write-Host ""
                }
            }
        }
    }
}

function Start-NLMode {
    # Lightweight REPL: runs safe commands, refuses flagged ones.
    Start-ReplLoop -Title "🤖 AI Terminal" -Hint "Type commands in natural language. Type 'exit' to quit."
}

# Create wrapper function for auto-execution with clean output
function Invoke-AICommandAuto {
    param([string]$NaturalLanguage)
    Invoke-AICommand -NaturalLanguage $NaturalLanguage -AutoExecute -CleanOutput
}

# Aliases
Set-Alias -Name "ai" -Value "Invoke-AICommand"
Set-Alias -Name "aia" -Value "Invoke-AICommandAuto"
Set-Alias -Name "nl" -Value "Start-NLMode"

function Start-AITerminal {
    # Main REPL: runs safe commands, asks for a typed "yes" before a flagged one.
    Start-ReplLoop -Title "🤖 AI Terminal - Natural Language Interface" -Hint "Describe what you want to do in plain English. Type 'exit' to quit." -PromptPrefix "AI" -ConfirmFlagged
}

function Test-InteractiveSession {
    # True when a person is at the console to answer Read-Host. The REPL must not start when the module
    # is imported by 'pwsh -Command ...', 'pwsh -File ...', a script, an editor host or a CI job;
    # a profile that imports this module would otherwise hang every one of those.
    try {
        if ($Host.Name -ne 'ConsoleHost') { return $false }
        if (-not [Environment]::UserInteractive) { return $false }
        if ([Console]::IsInputRedirected) { return $false }

        $arguments = @([Environment]::GetCommandLineArgs() | Select-Object -Skip 1)
        # Switches start with '-' everywhere and also with '/' on Windows (where '/' is not a path root).
        $switch = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { '^[-/]' } else { '^-' }
        # -NoExit keeps the console open after -Command, which is how the launchers start the REPL.
        if ($arguments -match "${switch}noe") { return $true }
        if ($arguments.Count -gt 0 -and $arguments[0] -notmatch $switch) { return $false }   # pwsh script.ps1
        if ($arguments -match "${switch}(noni\w*|c|com\w*|cwa|f|fi\w*|e|ec|enc\w*)$") { return $false }
        return $true
    } catch {
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Invoke-AICommand',
    'Invoke-AICommandAuto',
    'Start-NLMode',
    'Start-AITerminal',
    'Test-OllamaConnection',
    'Show-CommandHistory',
    'Clear-CommandHistory',
    'Get-ContextInfo',
    'Add-ToHistory',
    'Show-ThinkingAnimation'
) -Alias @('ai', 'aia', 'nl')

# Welcome message and auto-start in interactive sessions
# (set NEWTERMINAL_AI_NO_AUTOSTART=1 to import without starting the REPL)
if (-not $env:NEWTERMINAL_AI_NO_AUTOSTART -and (Test-InteractiveSession)) {
    Write-Host "[SUCCESS $(Get-Date -Format 'HH:mm:ss')] AI Terminal $script:ModuleVersion loaded! Starting natural language interface..." -ForegroundColor Green
    Start-Sleep -Milliseconds 500
    Start-AITerminal
}
