# PowerShell 7 local profile
# This file is the main interactive config loaded by your network bootstrap profile.
# Goals:
# 1) Keep startup responsive (lazy-load heavy integrations).
# 2) Keep your advanced PSReadLine experience intact.
# 3) Keep behavior easy to understand with explicit section comments.
#
# Optional diagnostics:
#   $env:POWERSHELL_PROFILE_TIMING = '1'
#   -> prints profile step timings at startup.

$script:ProfileTimingEnabled = $env:POWERSHELL_PROFILE_TIMING -eq '1'
if ($script:ProfileTimingEnabled) {
    $script:ProfileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:ProfileTimings = [System.Collections.Generic.List[object]]::new()

    function Add-ProfileTiming {
        param(
            [Parameter(Mandatory)] [string] $Step,
            [Parameter(Mandatory)] [double] $StartMs
        )

        $elapsed = $script:ProfileStopwatch.Elapsed.TotalMilliseconds - $StartMs
        $script:ProfileTimings.Add([PSCustomObject]@{
            Step = $Step
            Ms   = [Math]::Round($elapsed, 2)
        }) | Out-Null
    }
}

# Fast command-availability cache used by lazy init sections.
$script:CommandExistsCache = @{}
function Test-CommandExists {
    param([Parameter(Mandatory)] [string] $Name)

    if ($script:CommandExistsCache.ContainsKey($Name)) {
        return $script:CommandExistsCache[$Name]
    }

    $exists = $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
    $script:CommandExistsCache[$Name] = $exists
    return $exists
}

# ------------------------------------------------------------
# Prompt engine: starship
# ------------------------------------------------------------
# We keep this eager so the prompt is ready immediately.
# Cache path is resolved defensively to avoid startup failures.
$startMs = if ($script:ProfileTimingEnabled) { $script:ProfileStopwatch.Elapsed.TotalMilliseconds } else { 0 }
if (Test-CommandExists -Name 'starship') {
    if (-not $env:STARSHIP_CACHE) {
        $cacheCandidates = @()
        if ($env:LOCALAPPDATA) { $cacheCandidates += (Join-Path $env:LOCALAPPDATA 'starship\cache') }
        if ($env:TEMP) { $cacheCandidates += (Join-Path $env:TEMP 'starship\cache') }
        if ($HOME) { $cacheCandidates += (Join-Path $HOME '.cache\starship') }

        foreach ($candidate in $cacheCandidates) {
            try {
                New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
                $env:STARSHIP_CACHE = $candidate
                break
            } catch {
                continue
            }
        }
    } else {
        try {
            New-Item -ItemType Directory -Path $env:STARSHIP_CACHE -Force -ErrorAction Stop | Out-Null
        } catch {
            # Continue even if cache creation fails.
        }
    }

    Invoke-Expression (& starship init powershell)
}
if ($script:ProfileTimingEnabled) {
    Add-ProfileTiming -Step 'starship init' -StartMs $startMs
}

# ------------------------------------------------------------
# File listing UX: eza (replaces Terminal-Icons style output)
# ------------------------------------------------------------
# Why:
# - eza gives rich listing output (icons, tree, better metadata) directly.
# - This makes Terminal-Icons module unnecessary for ls/ll/la style workflows.
# - If eza is not installed, PowerShell default ls/dir behavior stays intact.
$startMs = if ($script:ProfileTimingEnabled) { $script:ProfileStopwatch.Elapsed.TotalMilliseconds } else { 0 }
if (Test-CommandExists -Name 'eza') {
    # Remove built-in ls alias so our function takes precedence.
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue

    # Base args shared by list commands. Tweak here if you want a different default.
    $script:EzaBaseArgs = @('--group-directories-first', '--icons=auto')

    # `ls` -> compact listing with icons.
    function global:ls {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Args)
        & eza @script:EzaBaseArgs @Args
    }

    # `ll` -> long listing (permissions/size/date), human-readable sizes.
    function global:ll {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Args)
        & eza @script:EzaBaseArgs --long --header --git --time-style=long-iso @Args
    }

    # `la` -> include hidden files + long format.
    function global:la {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Args)
        & eza @script:EzaBaseArgs --long --header --all --git --time-style=long-iso @Args
    }

    # `lt`/`tree` -> directory tree view.
    function global:lt {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Args)
        & eza @script:EzaBaseArgs --tree --level=2 @Args
    }

    function global:tree {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Args)
        & eza @script:EzaBaseArgs --tree --level=2 @Args
    }

    # Quick alias: `l` behaves like `ll`.
    Set-Alias -Name l -Value ll -Scope Global -Option AllScope
}
if ($script:ProfileTimingEnabled) {
    Add-ProfileTiming -Step 'eza aliases' -StartMs $startMs
}

# ------------------------------------------------------------
# PSReadLine: restore your keybindings and behavior
# ------------------------------------------------------------
# We only apply this for interactive console hosts to avoid errors in
# redirected/non-interactive sessions.
$startMs = if ($script:ProfileTimingEnabled) { $script:ProfileStopwatch.Elapsed.TotalMilliseconds } else { 0 }
if ($Host.Name -eq 'ConsoleHost') {
    try {
        Import-Module PSReadLine -ErrorAction SilentlyContinue

        if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
            Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
            Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
            Set-PSReadLineKeyHandler -Key Enter -Function ValidateAndAcceptLine

            $PSReadLineOptions = @{
                EditMode                      = 'Windows'
                HistoryNoDuplicates           = $true
                HistorySearchCursorMovesToEnd = $true
                PredictionSource              = 'HistoryAndPlugin'
                PredictionViewStyle           = 'ListView'
            }
            Set-PSReadLineOption @PSReadLineOptions

            # This key handler shows the filtered history in Out-GridView and
            # inserts the selected entry back into the current command line.
            Set-PSReadLineKeyHandler -Key F7 `
                                     -BriefDescription History `
                                     -LongDescription 'Show command history' `
                                     -ScriptBlock {
                $pattern = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
                if ($pattern) {
                    $pattern = [regex]::Escape($pattern)
                }

                $history = [System.Collections.ArrayList]@(
                    $last = ''
                    $lines = ''
                    foreach ($line in [System.IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath)) {
                        if ($line.EndsWith('`')) {
                            $line = $line.Substring(0, $line.Length - 1)
                            $lines = if ($lines) { "$lines`n$line" } else { $line }
                            continue
                        }

                        if ($lines) {
                            $line = "$lines`n$line"
                            $lines = ''
                        }

                        if (($line -cne $last) -and (!$pattern -or ($line -match $pattern))) {
                            $last = $line
                            $line
                        }
                    }
                )
                $history.Reverse()

                $command = $history | Out-GridView -Title History -PassThru
                if ($command) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($command -join "`n"))
                }
            }

            # Clear both session history and persisted PSReadLine history file.
            Set-PSReadLineKeyHandler -Key Alt+F7 `
                                     -BriefDescription ClearHistory `
                                     -LongDescription 'Clear command history' `
                                     -ScriptBlock {
                if (Test-Path (Get-PSReadLineOption).HistorySavePath) {
                    Remove-Item -EA Stop (Get-PSReadLineOption).HistorySavePath
                    $null = New-Item -Type File -Path (Get-PSReadLineOption).HistorySavePath
                }
                Clear-History
                [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
            }

            # Quick macro to run dotnet build in current directory.
            Set-PSReadLineKeyHandler -Key Ctrl+Shift+b `
                                     -BriefDescription BuildCurrentDirectory `
                                     -LongDescription 'Build the current directory' `
                                     -ScriptBlock {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert('dotnet build')
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
            }

            # Token-aware word navigation/editing.
            Set-PSReadLineKeyHandler -Key Alt+d -Function ShellKillWord
            Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord
            Set-PSReadLineKeyHandler -Key Alt+b -Function ShellBackwardWord
            Set-PSReadLineKeyHandler -Key Alt+f -Function ShellForwardWord
            Set-PSReadLineKeyHandler -Key Alt+B -Function SelectShellBackwardWord
            Set-PSReadLineKeyHandler -Key Alt+F -Function SelectShellForwardWord

            # Smart paired braces / quotes insertion.
            Set-PSReadLineKeyHandler -Key '(','{','[' `
                                     -BriefDescription InsertPairedBraces `
                                     -LongDescription 'Insert matching braces' `
                                     -ScriptBlock {
                param($key, $arg)

                $closeChar = switch ($key.KeyChar) {
                    <#case#> '(' { [char]')'; break }
                    <#case#> '{' { [char]'}'; break }
                    <#case#> '[' { [char]']'; break }
                }

                $selectionStart = $null
                $selectionLength = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

                $line = $null
                $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                if ($selectionStart -ne -1) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $selectionStart,
                        $selectionLength,
                        $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar
                    )
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
                } else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                }
            }

            Set-PSReadLineKeyHandler -Key ')',']','}' `
                                     -BriefDescription SmartCloseBraces `
                                     -LongDescription 'Insert closing brace or skip' `
                                     -ScriptBlock {
                param($key, $arg)

                $line = $null
                $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                if ($cursor -lt $line.Length -and $line[$cursor] -eq $key.KeyChar) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                } else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
                }
            }

            Set-PSReadLineKeyHandler -Key Backspace `
                                     -BriefDescription SmartBackspace `
                                     -LongDescription 'Delete previous character or matching quotes/parens/braces' `
                                     -ScriptBlock {
                param($key, $arg)

                $line = $null
                $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                if ($cursor -gt 0) {
                    $toMatch = $null
                    if ($cursor -lt $line.Length) {
                        switch ($line[$cursor]) {
                            <#case#> '"' { $toMatch = '"'; break }
                            <#case#> "'" { $toMatch = "'"; break }
                            <#case#> ')' { $toMatch = '('; break }
                            <#case#> ']' { $toMatch = '['; break }
                            <#case#> '}' { $toMatch = '{'; break }
                        }
                    }

                    if ($toMatch -ne $null -and $line[$cursor - 1] -eq $toMatch) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
                    } else {
                        [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
                    }
                }
            }

            # History policy:
            # - ignore empty lines
            # - optionally skip failed commands
            # - optionally skip consecutive duplicates
            # - keep noisy tooling commands in memory only (not persisted to file)
            # - never persist sensitive-looking commands
            #
            # Customization knobs:
            #   $script:SkipFailedCommandsInHistory     = $true/$false
            #   $script:SkipDuplicateConsecutiveHistory = $true/$false
            $script:SkipFailedCommandsInHistory = $true
            $script:SkipDuplicateConsecutiveHistory = $true

            # Commands here are ignored entirely (not even session history).
            $script:HistorySkipExact = @(
                'cd','dc','chdir','ls','ll','la','pwd','cls','clear','history','h','exit'
            )

            # Commands here stay in memory only (session), not persisted to file.
            $script:HistoryMemoryOnlyExact = @(
                'git','ng','npm','npx','pnpm','yarn','dotnet','winget','code','explorer','kubectl','k','docker','claude'
            )

            # Prefix-based memory-only rules for command families.
            $script:HistoryMemoryOnlyPrefixes = @(
                'git ','ng ','npm ','npx ','pnpm ','yarn ','dotnet ','winget ','code ','explorer ',
                'kubectl ','k ','docker ','claude ','cd ','z ','zi '
            )

            # Security guardrails: if line looks like it may contain secrets, do not save it.
            $script:HistorySensitiveRegex = @(
                '(?i)(password|passwd|token|apikey|api[_-]?key|secret|connectionstring)\\s*[:=]\\s*\\S+'
                '(?i)--password(\\s+|=)\\S+'
                '(?i)authorization\\s*[:=]\\s*bearer\\s+\\S+'
            )

            Set-PSReadLineOption -AddToHistoryHandler {
                param([string]$line)

                $trimmed = $line.Trim()
                if ($trimmed.Length -eq 0) {
                    return $false
                }

                if ($script:SkipFailedCommandsInHistory -and -not $?) {
                    return $false
                }

                if ($script:SkipDuplicateConsecutiveHistory) {
                    $last = (Get-History -Count 1 -ErrorAction SilentlyContinue).CommandLine
                    if ($last -and $last.Trim() -eq $trimmed) {
                        return $false
                    }
                }

                foreach ($rx in $script:HistorySensitiveRegex) {
                    if ($trimmed -match $rx) {
                        return $false
                    }
                }

                if ($script:HistorySkipExact -contains $trimmed) {
                    return $false
                }

                if ($script:HistoryMemoryOnlyExact -contains $trimmed) {
                    return 'MemoryOnly'
                }

                foreach ($prefix in $script:HistoryMemoryOnlyPrefixes) {
                    if ($trimmed.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return 'MemoryOnly'
                    }
                }

                return $true
            }
            # Tab behavior preferences.
            Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious
            Set-PSReadLineKeyHandler -Key Ctrl+Tab -Function TabCompleteNext
            Set-PSReadLineKeyHandler -Key Tab -Function Complete
            Set-PSReadLineOption -BellStyle None
        }
    } catch {
        # If host capabilities do not support a setting, do not block shell startup.
    }
}
if ($script:ProfileTimingEnabled) {
    Add-ProfileTiming -Step 'psreadline config' -StartMs $startMs
}

# ------------------------------------------------------------
# Argument completers (winget, dotnet)
# ------------------------------------------------------------
# Keep these explicit for better CLI experience.
$startMs = if ($script:ProfileTimingEnabled) { $script:ProfileStopwatch.Elapsed.TotalMilliseconds } else { 0 }
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
    $localWord = $wordToComplete.Replace('"', '""')
    $localAst = $commandAst.ToString().Replace('"', '""')

    winget complete --word="$localWord" --commandline "$localAst" --position $cursorPosition |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)

    dotnet complete --position $cursorPosition "$wordToComplete" |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}
if ($script:ProfileTimingEnabled) {
    Add-ProfileTiming -Step 'native completers' -StartMs $startMs
}

# ------------------------------------------------------------
# Lazy-load posh-git (on first git command)
# ------------------------------------------------------------
$script:PoshGitLoaded = $false
$script:GitExePath = (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source

function Import-PoshGitLazy {
    if ($script:PoshGitLoaded) {
        return
    }

    $script:PoshGitLoaded = $true
    if (Get-Module -ListAvailable -Name posh-git) {
        Import-Module posh-git -ErrorAction SilentlyContinue | Out-Null
    }

    Remove-Item Function:\git -ErrorAction SilentlyContinue
}

if ($script:GitExePath) {
    function global:git {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $CommandArgs)

        Import-PoshGitLazy
        & $script:GitExePath @CommandArgs
    }
}

# ------------------------------------------------------------
# Lazy-load zoxide (on first z/zi)
# ------------------------------------------------------------
$script:ZoxideLoaded = $false
function Initialize-ZoxideLazy {
    if ($script:ZoxideLoaded) {
        return
    }

    $script:ZoxideLoaded = $true
    if (Test-CommandExists -Name 'zoxide') {
        Invoke-Expression (& zoxide init powershell | Out-String)
    }

    Remove-Item Function:\z -ErrorAction SilentlyContinue
    Remove-Item Function:\zi -ErrorAction SilentlyContinue
}

if (Test-CommandExists -Name 'zoxide') {
    function global:z {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $CommandArgs)

        Initialize-ZoxideLazy
        $zCommand = Get-Command -Name z -CommandType Function -ErrorAction SilentlyContinue
        if ($zCommand) {
            & $zCommand @CommandArgs
        }
    }

    function global:zi {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $CommandArgs)

        Initialize-ZoxideLazy
        $ziCommand = Get-Command -Name zi -CommandType Function -ErrorAction SilentlyContinue
        if ($ziCommand) {
            & $ziCommand @CommandArgs
        }
    }
}

# ------------------------------------------------------------
# Lazy-load fnm env (on first node/npm/npx)
# ------------------------------------------------------------
$script:FnmEnvLoaded = $false
$script:NodeExePath = (Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$script:NpmExePath  = (Get-Command -Name npm  -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$script:NpxExePath  = (Get-Command -Name npx  -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source

function Initialize-FnmLazy {
    if ($script:FnmEnvLoaded) {
        return
    }

    $script:FnmEnvLoaded = $true
    if (Test-CommandExists -Name 'fnm') {
        $fnmScript = & fnm env --use-on-cd --version-file-strategy=recursive --shell powershell
        if ($LASTEXITCODE -eq 0 -and $fnmScript) {
            Invoke-Expression ($fnmScript | Out-String)
        }
    }

    Remove-Item Function:\node -ErrorAction SilentlyContinue
    Remove-Item Function:\npm  -ErrorAction SilentlyContinue
    Remove-Item Function:\npx  -ErrorAction SilentlyContinue
}

if ($script:NodeExePath) {
    function global:node {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $CommandArgs)

        Initialize-FnmLazy
        & $script:NodeExePath @CommandArgs
    }
}

if ($script:NpmExePath) {
    function global:npm {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $CommandArgs)

        Initialize-FnmLazy
        & $script:NpmExePath @CommandArgs
    }
}

if ($script:NpxExePath) {
    function global:npx {
        param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $CommandArgs)

        Initialize-FnmLazy
        & $script:NpxExePath @CommandArgs
    }
}

if ($script:ProfileTimingEnabled) {
    $script:ProfileStopwatch.Stop()
    Add-ProfileTiming -Step 'total profile' -StartMs 0

    Write-Host ''
    Write-Host '[PowerShell profile timings]' -ForegroundColor Cyan
    $script:ProfileTimings | Sort-Object -Property Ms -Descending | Format-Table -AutoSize
}


