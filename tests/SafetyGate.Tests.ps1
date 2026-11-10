# Pester tests for the destructive-command safety gate (Test-CommandSafety / Get-CommandRisk).
# Run with: Invoke-Pester -Path ./tests
#
# Every row in a "Regression" block is one command that the previous regex denylist classified
# wrongly. Those tests fail against the old module and pass against the AST-based gate.
# Nothing here executes the commands: the gate only parses them.

BeforeDiscovery {
    function New-GateCase {
        # One test case per command. Label is the command made printable for the test name.
        param([string[]]$Command)
        foreach ($c in $Command) {
            @{ Command = $c; Label = (($c -replace "`r?`n", '\n') -replace '[\p{Cc}\p{Cf}]', '?') }
        }
    }

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('ri ~ -r -fo'))
    $lf = [string][char]10
    $enDash = [string][char]0x2013
    $emDash = [string][char]0x2014
    $escape = [string][char]27
    $rightToLeftOverride = [string][char]0x202E
    $zeroWidthSpace = [string][char]0x200B

    $script:DeleteVariants = New-GateCase @(
        'ri -r -fo C:\Users'
        'rd -r -fo C:\Users'
        'del -Recurse -Force ~'
        'erase -r -fo $HOME'
        'rm -r -fo ~'
        'rmdir -Recurse -Force .\src'
        'Remove-Item -Recurse -Force ~'
        'Remove-Item -r -fo C:\Users'
        'Remove-Item -Rec -For C:\Users'
        'remove-item C:/Users -recurse -force'
        'Remove-Item -Path / -Recurse -Force'
        'Remove-Item D:\ -Recurse -Force'
        'Remove-Item -Recurse:$true -Force:$true ~'
        'Remove-Item * -Recurse -Force'
        'Remove-Item $HOME -Recurse -Force'
        'Remove-Item C:\Users -Recurse'
        'Microsoft.PowerShell.Management\Remove-Item ~ -Recurse -Force'
        'rm -rf ~'
        'rm -fr /'
        'rm -r -f /'
        'rm --recursive --force /'
        'rm -rf --no-preserve-root /'
        'rm -rf *'
        '/bin/rm -rf ~'
        '$p=@{Path="~";Recurse=$true;Force=$true}; Remove-Item @p'
        'Remove-Item ./build.log'
        'del notes.txt'
    )

    $script:PipelinesAndDotNet = New-GateCase @(
        'Get-ChildItem ~ -Recurse | Remove-Item -Force'
        'gci -r | ri -fo'
        'ls | % { ri $_ -r -fo }'
        'Get-ChildItem -Recurse | ForEach-Object { $_.Delete() }'
        'Get-ChildItem | % Delete'
        'Get-ChildItem | ForEach-Object -MemberName Delete'
        '(Get-ChildItem).ForEach("Delete")'
        '(Get-Item x).Delete()'
        '[System.IO.Directory]::Delete("C:\Users", $true)'
        '[IO.File]::WriteAllText("$HOME/.bashrc", "")'
        '[IO.File]::Delete("x")'
        '$a=[IO.File]; $a::Delete("x")'
        '[IO.File]::("Del"+"ete")("x")'
        '$m="Delete"; (Get-Item x).$m()'
        '(Get-Item x).PSObject.Methods["Delete"].Invoke()'
        '[IO.File].GetMethod("Delete").Invoke($null,@("x"))'
        '(Get-Service spooler).Stop()'
        '$xml.Save("config.xml")'
    )

    $script:DynamicInvocation = New-GateCase @(
        "Invoke-Expression 'ri -r -fo ~'"
        'iex "ri -r -fo ~"'
        "iex ('Rem'+'ove-Item C:\ -Rec'+'urse -Fo'+'rce')"
        "& ([scriptblock]::Create('ri -r -fo ~'))"
        ". ([scriptblock]::Create('ri -r -fo ~'))"
        "& 'Remove-Item' ~ -Recurse -Force"
        "& ('Remove'+'-Item') 'C:\' -Recurse -Force"
        '$c="Remove"+"-Item"; & $c C:\ -Recurse -Force'
        'Invoke-Command -ScriptBlock { ri ~ -r -fo }'
        '& { ri ~ -r -fo }'
        '"ri ~ -r -fo" | iex'
        '$ExecutionContext.InvokeCommand.InvokeScript("ri ~ -r -fo")'
        '$ExecutionContext.InvokeCommand.ExpandString(''$(ri x)'')'
        "iex ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$encoded')))"
        '[powershell]::Create().AddScript("ri x").Invoke()'
        'Set-Alias x Remove-Item; x ~ -Recurse -Force'
        '$alias:x = "Remove-Item"; x ~ -Recurse'
        'New-Item -Path alias:x -Value Remove-Item'
        'function f { ri ~ -r -fo }; f'
        'Invoke-History 3'
        'Add-Type -TypeDefinition $src'
        'using module ./evil.psm1'
    )

    $script:ShellsAndProcesses = New-GateCase @(
        "powershell -enc $encoded"
        "pwsh -e $encoded"
        "powershell.exe -NoProfile -EncodedCommand $encoded"
        'pwsh -c "ri ~ -r -fo"'
        '& "C:\Program Files\PowerShell\7\pwsh.exe" -c "ri x"'
        "Start-Process cmd -ArgumentList '/c rd /s /q C:\Users'"
        'Start-Process -WindowStyle Hidden cmd "/c rd /s /q C:\Users"'
        'Start-Process -FilePath powershell -ArgumentList "-NoProfile","-Command","ri ~ -r -fo"'
        'Start-Process $shell'
        'Start-Process notepad -Verb RunAs'
        'Invoke-Item evil.exe'
        'ii .\x.ps1'
        'Get-ChildItem *.bat | Invoke-Item'
        "saps pwsh '-c ri ~ -r -fo'"
        'cmd /c rd /s /q C:\Users'
        'cmd /c del /f /s /q C:\Users\*'
        'cmd /c "del /q /s C:\*"'
        'cmd /c format D: /y'
        'C:\Windows\System32\cmd.exe /c del x'
        "bash -c 'rm -rf ~'"
        'sh -c "rm -fr /"'
        'wsl rm -rf ~'
        'Start-Job { ri ~ -r -fo }'
        'python -c "import shutil; shutil.rmtree(''/home'')"'
        '"import shutil" | python'
        'perl -pe "unlink glob q(*)" x'
        'node -e "require(''fs'').rmSync(''/home'',{recursive:true})"'
        "[Diagnostics.Process]::Start('cmd','/c rd /s /q C:\Users')"
        "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='cmd /c rd /s /q C:\Users'}"
        '(New-Object -ComObject WScript.Shell).Run("cmd /c rd /s /q C:\Users")'
        'New-Object System.Diagnostics.ProcessStartInfo'
        '([wmiclass]"Win32_Process").Create("cmd /c del x")'
        'env FOO=1 rm -rf ~'
        'nohup rm -rf ~'
        'gci -n | xargs rm -rf'
        'timeout 5 rm -rf ~'
    )

    $script:DiskAndPower = New-GateCase @(
        'Format-Volume -DriveLetter D -Confirm:$false'
        'Clear-Disk -Number 0 -RemoveData -Confirm:$false'
        'Remove-Partition -DriveLetter D -Confirm:$false'
        'Initialize-Disk -Number 1'
        'diskpart /s wipe.txt'
        'format d: /q'
        'dd if=/dev/zero of=/dev/sda bs=1M'
        'mkfs.ext4 /dev/sda1'
        'Sto`p-Computer -Force'
        'Re`start-Computer'
        'sudo reboot'
        'poweroff'
        'systemctl poweroff'
        'systemctl stop sshd'
        'service nginx stop'
        'logoff'
        'Get-CimInstance Win32_OperatingSystem | Invoke-CimMethod -MethodName Reboot'
        '(Get-WmiObject Win32_OperatingSystem).Reboot()'
        'Restore-Computer -RestorePoint 1'
        'Stop-Process -Name * -Force'
        'taskkill /f /im explorer.exe'
        'Stop-Service -Name * -Force'
        'chmod -R 000 /'
    )

    $script:Overwrites = New-GateCase @(
        'Set-Content -Path $PROFILE -Value ""'
        'Clear-Content C:\Users\me\Documents\thesis.docx'
        '"" | Out-File C:\Windows\System32\drivers\etc\hosts'
        '"" > important.txt'
        '"x" 2> errors.txt'
        'Move-Item important.txt $null'
        'Move-Item important.txt NUL'
        'mv important.txt /dev/null'
        'New-Item -ItemType File -Path important.txt -Force'
        '"" | Tee-Object -FilePath important.txt'
        'Clear-RecycleBin -Force'
        'Copy-Item empty.txt important.txt -Force'
        'Get-Process | Export-Csv procs.csv'
        'Invoke-WebRequest https://example.com/y -OutFile $PROFILE'
        'Expand-Archive x.zip -DestinationPath . -Force'
        'Uninstall-Module Pester'
        'find . -name "*.log" -delete'
        'find / -exec rm {} \;'
        'robocopy empty C:\Users /MIR'
        'rsync -a --delete empty/ ~/'
    )

    $script:Registry = New-GateCase @(
        'Remove-Item -Path HKLM:\SOFTWARE\Foo -Recurse'
        'Remove-ItemProperty -Path HKCU:\Software\Foo -Name Bar'
        'reg delete HKCU\Software\Foo /f'
        'reg.exe delete "HKEY_LOCAL_MACHINE\SOFTWARE\Foo" /f'
        'reg add HKLM\Software\X /v Y /d 1 /f'
        "[Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree('SOFTWARE\Foo')"
        'Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\X -Name Y -Value 0'
    )

    $script:Git = New-GateCase @(
        'git reset --hard HEAD~5'
        'git clean -fdx'
        'git clean -f -d'
        'git -C .. reset --hard'
        'git checkout -- .'
        'git checkout -f'
        'git restore .'
        'git restore -s HEAD~1 file.txt'
        'git push --force origin main'
        'git push origin :main'
        'git push origin +main'
        'git branch -D feature'
        'git stash clear'
        'git rm -r .'
        'git reflog expire --expire=now --all'
        'git -c alias.x="!rm -rf ~" x'
        'git config --global alias.x "!rm -rf ~"'
        'git reset --har'
        'git push --forc origin main'
        'git push -fu origin main'
        'git branch -df feature'
        'git checkout main file.txt'
        'git checkout --for main'
    )

    $script:OtherTools = New-GateCase @(
        'docker system prune -af'
        'docker rm -f $(docker ps -aq)'
        'kubectl delete namespace prod'
        'terraform destroy -auto-approve'
        'az group delete -n prod --yes'
        'npm uninstall -g everything'
        'kubeadm reset'
        'net user bob /delete'
        'Invoke-RestMethod -Method Delete https://api.example.com/items/1'
        'docker exec web sh -c "rm -r /data"'
        'docker exec web rmdir /data'
        'conhost cmd /c del x'
        'script -c "rm -rf ~"'
        'curl -sSLo ~/.bashrc https://example.com/x'
        'wget -O ~/.bashrc https://example.com/x'
        'pwsh-preview -c "ri x"'
        'apt-get remove nginx'
        'sudo apt-get purge nginx'
        'crontab -r'
        'Start-Transcript -Path notes.txt'
        'Register-ScheduledTask -TaskName x -Action $action'
    )

    $script:ChainingAndObfuscation = New-GateCase @(
        'Get-Date; ri ~ -r -fo'
        'Get-Date && ri ~ -r -fo'
        'Get-Item nope || ri ~ -r -fo'
        "Get-Date${lf}ri ~ -r -fo"
        "Remove-Item ``${lf} -Recurse ``${lf} -Force ``${lf} ~"
        'Remove-Item <# x #> -Recurse <# y #> -Force ~'
        "Remove-Item ${enDash}Recurse ${enDash}Force C:\Users"
        "Remove-Item ${emDash}Recurse ${emDash}Force C:\Users"
        'Write-Output $(ri ~ -r -fo)'
        'Write-Output "x $(ri ~ -r -fo)"'
        'Remove-I`tem C:\Users -Recurse -Force'
        "Remove-Item ('C:' + '\') -Recurse -Force"
        'if ($true) { ri ~ -r -fo }'
        'try { Get-Date } finally { ri ~ -r -fo }'
    )

    $script:FailClosed = New-GateCase @(
        'Remove-Item ~ -Recurse -Force )'
        'Get-ChildItem | '
        '"unterminated'
        "Get-Date${escape}[2K${escape}[1A"
        "Get-Date ${rightToLeftOverride}"
        "Get-${zeroWidthSpace}Date"
    )

    # Harmless commands the old denylist blocked because they merely contain a keyword.
    $script:FormerFalsePositives = New-GateCase @(
        'Get-Help Stop-Computer'
        'Get-Command Restart-Computer'
        'Get-Date # rm -rf /'
        'Write-Output "format c: is dangerous"'
        'Get-Service | Where-Object Name -like "*restart*"'
        'Get-EventLog System -Newest 5 | Where-Object Message -match "shutdown"'
        'Select-String -Pattern "shutdown" -Path *.log'
        'git log --grep restart'
    )

    # Destructive commands the old denylist already caught: they must stay flagged.
    $script:StillFlagged = New-GateCase @(
        'rm -rf /'
        'sudo rm -Rf /'
        'Remove-Item -Path C:\ -Recurse -Force'
        'Remove-Item -Recurse -Force C:\Windows'
        'del /s /q c:\'
        'format c:'
        'Stop-Computer'
        'Restart-Computer -Force'
        'shutdown /s /t 0'
        'shutdown /r /t 0'
        'reg delete HKLM\Software\Foo /f'
        'Remove-Item $env:SystemRoot\System32 -Recurse'
        'Remove-Item $env:ProgramFiles\App'
        'ssh host "rm -rf /"'
        'Restart-Service spooler'
        'Restart-C`omputer'
        'docker exec web sh -c "rm -rf /data"'
    )

    # Everyday commands that must keep running without a confirmation.
    $script:Benign = New-GateCase @(
        'Get-ChildItem'
        'Get-Date'
        'Get-PSDrive -PSProvider FileSystem'
        'New-Item -ItemType File -Name "notes.txt"'
        'New-Item -ItemType File -Path notes.txt -Value "hello"'
        'New-Item -ItemType Directory -Path x -Force'
        'Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free,@{Name=''Size(GB)'';Expression={[math]::Round(($_.Used+$_.Free)/1GB,2)}},@{Name=''FreeSpace(GB)'';Expression={[math]::Round($_.Free/1GB,2)}}'
        'Get-Process'
        'Get-Service'
        'Get-ComputerInfo'
        'Get-NetIPAddress'
        'whoami'
        '(Get-CimInstance Win32_OperatingSystem).LastBootUpTime'
        'Get-ChildItem -Name "filename*" -Recurse'
        'Test-Path "filename.ext"'
        'Get-Content "filename.ext"'
        'Copy-Item "source.ext" "destination.ext"'
        'Move-Item "old.ext" "new.ext"'
        'Rename-Item old.txt new.txt'
        "Write-Host 'Current AI Model: llama3.2:1b' -ForegroundColor Green"
        'Get-Process | Sort-Object CPU -Descending | Select-Object -First 5'
        'Get-ChildItem -Recurse -Force | Where-Object { $_.Length -gt 100MB }'
        'Get-ChildItem | Measure-Object -Property Length -Sum'
        'Get-Content x.log | Select-String "error"'
        'Get-ChildItem -Path C:\ -Filter *.log -Recurse -ErrorAction SilentlyContinue'
        'ls -la'
        'dir'
        'cd ..'
        'Set-Location ~'
        'mkdir test'
        'git status'
        'git log --oneline -5'
        'git diff'
        'git add .'
        'git commit -m "msg"'
        'git push'
        'git push origin main'
        'git pull'
        'git checkout main'
        'git checkout -b feature'
        'git stash'
        'git reset --soft HEAD~1'
        'git restore --staged file.txt'
        'git branch -d merged'
        'git clean -n'
        'git -C .. status'
        'git checkout -b feature origin/main'
        'git reset --mixed HEAD~1'
        'git push --follow-tags'
        'git commit -m "msg"'
        'docker exec web ls /data'
        'docker run alpine echo "hello world"'
        'curl -fsSL https://example.com'
        'wget https://example.com/file.zip'
        'brew install fish'
        'docker-compose up -d'
        'apt-get update'
        'docker ps'
        'npm install'
        'npm run build'
        'python script.py'
        'python --version'
        'Get-Content data.json | python -m json.tool'
        'pip list'
        'Get-Date -Format "yyyy-MM-dd"'
        '[math]::Round(5.5)'
        '[datetime]::Now'
        '[System.IO.Path]::GetFileName("a/b.txt")'
        '[Environment]::GetFolderPath("Desktop")'
        '[IO.File]::ReadAllText("a.txt")'
        '[pscustomobject]@{a=1}'
        'New-Object System.Collections.ArrayList'
        '$env:PATH -split ";"'
        '$x = Get-Process; $x.Count'
        'Get-Process > $null'
        'Get-ChildItem 2>$null'
        '"x" >> log.txt'
        'Add-Content log.txt "x"'
        'Get-Process | Tee-Object -Variable p'
        'Get-Service | Where-Object Status -eq "Running"'
        'Select-String -Pattern "delete" -Path *.log'
        'echo "rm -rf ~"'
        'grep -r "delete" .'
        'tail -f app.log'
        'find . -name "*.txt"'
        'Test-Connection google.com -Count 2'
        'ping google.com'
        'curl https://example.com'
        'Get-ChildItem | ForEach-Object { $_.Name }'
        'gci | % Name'
        '1..10 | ForEach-Object { $_ * 2 }'
        'Get-Content file.txt | Measure-Object -Line'
        'Get-Content a.txt -Tail 20 -Wait'
        '"hello".ToUpper()'
        '(Get-Date).AddDays(7)'
        'Get-ChildItem | Where-Object { $_.Name.Replace("a","b") -like "*.txt" }'
        'Get-ChildItem | Sort-Object Length | Format-Table Name, Length'
        'Get-ChildItem | Select-Object -ExpandProperty FullName'
        'Get-Item . | Format-List *'
        'if (Test-Path x) { Get-Content x }'
        'Start-Process notepad'
        'Start-Process "https://example.com/search?q=a&hl=en"'
        'code .'
        'explorer .'
        'Get-ChildItem Env:'
        'Get-Alias'
        'Get-History'
        'Clear-Host'
        'cls'
        'Start-Sleep 1'
        'Get-Process | Out-String'
        'Get-Process | ConvertTo-Json'
        'Get-NetAdapter | Format-List'
        'Get-EventLog System -Newest 5'
        'Import-Module Pester -Force'
        'Compress-Archive -Path src -DestinationPath out.zip'
        'systemctl status nginx'
        'reg query HKLM\Software'
        'df -h'
        'ps aux'
    )
}

BeforeAll {
    $env:NEWTERMINAL_AI_NO_AUTOSTART = '1'
    $script:ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'NewTerminal-AI.psm1'
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module NewTerminal-AI -Force -ErrorAction SilentlyContinue
    Remove-Item Env:NEWTERMINAL_AI_NO_AUTOSTART -ErrorAction SilentlyContinue
}

Describe 'Safety gate: commands the old regex denylist let through' -Tag 'Regression' {
    Context 'delete aliases and parameter variants' {
        It 'flags: <Label>' -ForEach $script:DeleteVariants {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'pipelines and .NET method calls' {
        It 'flags: <Label>' -ForEach $script:PipelinesAndDotNet {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'code built or invoked at run time' {
        It 'flags: <Label>' -ForEach $script:DynamicInvocation {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'encoded commands, nested shells and new processes' {
        It 'flags: <Label>' -ForEach $script:ShellsAndProcesses {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'disks, power and processes' {
        It 'flags: <Label>' -ForEach $script:DiskAndPower {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'overwrites and the null device' {
        It 'flags: <Label>' -ForEach $script:Overwrites {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'registry' {
        It 'flags: <Label>' -ForEach $script:Registry {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'git' {
        It 'flags: <Label>' -ForEach $script:Git {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'other command-line tools' {
        It 'flags: <Label>' -ForEach $script:OtherTools {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'statement chains and obfuscation' {
        It 'flags: <Label>' -ForEach $script:ChainingAndObfuscation {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }
    }

    Context 'fails closed' {
        It 'flags what it cannot parse or display faithfully: <Label>' -ForEach $script:FailClosed {
            InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
        }

        It 'flags the command when the analysis itself throws' {
            InModuleScope NewTerminal-AI {
                Mock Get-NamedCommandRisk { throw 'boom' }
                Test-CommandSafety -Command 'Get-Date' | Should -BeFalse
                Get-CommandRisk -Command 'Get-Date' | Should -Match 'could not be analysed'
            }
        }
    }
}

Describe 'Safety gate: harmless commands the old regex denylist blocked' -Tag 'Regression' {
    It 'allows: <Label>' -ForEach $script:FormerFalsePositives {
        InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeTrue }
    }
}

Describe 'Safety gate: reasons' -Tag 'Regression' {
    It 'returns no reason for a safe command' {
        InModuleScope NewTerminal-AI {
            @(Get-CommandRisk -Command 'Get-ChildItem').Count | Should -Be 0
            @(Get-CommandRisk -Command '').Count | Should -Be 0
        }
    }

    It 'names the resolved cmdlet behind an alias' {
        InModuleScope NewTerminal-AI {
            Get-CommandRisk -Command 'gci -r | ri -fo' | Should -Match 'remove-item'
        }
    }

    It 'reports every distinct problem in a chain once' {
        InModuleScope NewTerminal-AI {
            $reasons = @(Get-CommandRisk -Command 'ri a; ri b; "" > c.txt; iex $x')
            $reasons.Count | Should -Be 3
            ($reasons -join '|') | Should -Match 'remove-item'
            ($reasons -join '|') | Should -Match 'redirection'
            ($reasons -join '|') | Should -Match 'invoke-expression'
        }
    }

    It 'explains a parse failure' {
        InModuleScope NewTerminal-AI {
            Get-CommandRisk -Command 'Get-Date )' | Should -Match 'cannot be parsed'
        }
    }

    It 'reports what a wrapper or Start-Process would launch' {
        InModuleScope NewTerminal-AI {
            Get-CommandRisk -Command "Start-Process cmd -ArgumentList '/c del x'" | Should -Match 'start-process launches: cmd'
            Get-CommandRisk -Command 'env FOO=1 rm -rf ~' | Should -Match 'env runs: remove-item'
        }
    }
}

Describe 'Safety gate: unchanged verdicts' {
    It 'still flags: <Label>' -ForEach $script:StillFlagged {
        InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeFalse }
    }

    It 'still allows: <Label>' -ForEach $script:Benign {
        InModuleScope NewTerminal-AI -Parameters @{ C = $Command } { param($C) Test-CommandSafety -Command $C | Should -BeTrue }
    }
}
