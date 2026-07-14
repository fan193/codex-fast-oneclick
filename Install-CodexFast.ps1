#requires -Version 5.1

[CmdletBinding()]
param(
    [switch] $NoLaunch,
    [string] $DestinationRoot = (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex-Fast')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Write-Step {
    param([string] $Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function New-PaddedTrueExpression {
    param(
        [Parameter(Mandatory = $true)][string] $Original,
        [string] $Prefix = ''
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $start = $Prefix + '!0/*'
    $end = '*/'
    $fillerLength = $utf8.GetByteCount($Original) - $utf8.GetByteCount($start) - $utf8.GetByteCount($end)
    if ($fillerLength -lt 0) {
        throw "Cannot build an equal-length replacement for: $Original"
    }
    return $start + ('x' * $fillerLength) + $end
}

function New-PaddedTrueFunction {
    param([Parameter(Mandatory = $true)][string] $Original)

    $openBrace = $Original.IndexOf('{')
    if ($openBrace -lt 0) {
        throw 'Request gate function has no opening brace.'
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $start = $Original.Substring(0, $openBrace + 1) + 'return!0/*'
    $end = '*/}'
    $fillerLength = $utf8.GetByteCount($Original) - $utf8.GetByteCount($start) - $utf8.GetByteCount($end)
    if ($fillerLength -lt 0) {
        throw 'Request gate function is too short for an equal-length replacement.'
    }
    return $start + ('x' * $fillerLength) + $end
}

if (-not ('CodexFast.BytePattern' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

namespace CodexFast
{
    public static class BytePattern
    {
        public static int[] FindAll(byte[] data, byte[] pattern)
        {
            if (data == null) throw new ArgumentNullException("data");
            if (pattern == null || pattern.Length == 0) throw new ArgumentException("Pattern is empty.", "pattern");

            var results = new List<int>();
            if (pattern.Length > data.Length) return results.ToArray();

            var shift = new int[256];
            for (int i = 0; i < shift.Length; i++) shift[i] = pattern.Length;
            for (int i = 0; i < pattern.Length - 1; i++) shift[pattern[i]] = pattern.Length - 1 - i;

            int offset = 0;
            int last = pattern.Length - 1;
            int limit = data.Length - pattern.Length;
            while (offset <= limit)
            {
                int index = last;
                while (index >= 0 && data[offset + index] == pattern[index]) index--;
                if (index < 0)
                {
                    results.Add(offset);
                    offset += 1;
                }
                else
                {
                    offset += Math.Max(1, shift[data[offset + last]]);
                }
            }

            return results.ToArray();
        }

        public static void ReplaceAt(byte[] data, int offset, byte[] replacement)
        {
            if (offset < 0 || offset + replacement.Length > data.Length) throw new ArgumentOutOfRangeException("offset");
            Buffer.BlockCopy(replacement, 0, data, offset, replacement.Length);
        }
    }
}
'@
}

function Invoke-PatchGroup {
    param(
        [Parameter(Mandatory = $true)][byte[]] $Data,
        [Parameter(Mandatory = $true)] $Group
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $states = @()

    foreach ($alternative in $Group.Alternatives) {
        $fromBytes = $utf8.GetBytes([string] $alternative.From)
        $toBytes = $utf8.GetBytes([string] $alternative.To)
        if ($fromBytes.Length -ne $toBytes.Length) {
            throw "$($Group.Name): replacement is not equal length."
        }

        $fromHits = [CodexFast.BytePattern]::FindAll($Data, $fromBytes)
        $toHits = [CodexFast.BytePattern]::FindAll($Data, $toBytes)
        if ($fromHits.Count -gt 1 -or $toHits.Count -gt 1) {
            throw "$($Group.Name): target is not unique (original=$($fromHits.Count), patched=$($toHits.Count))."
        }

        if ($fromHits.Count -eq 1 -or $toHits.Count -eq 1) {
            $states += [pscustomobject]@{
                Alternative = $alternative
                FromBytes = $fromBytes
                ToBytes = $toBytes
                FromHits = $fromHits
                ToHits = $toHits
            }
        }
    }

    if ($states.Count -ne 1) {
        throw "$($Group.Name): no single supported signature matched. This Codex version is not supported safely."
    }

    $state = $states[0]
    if ($state.FromHits.Count -eq 1 -and $state.ToHits.Count -eq 0) {
        [CodexFast.BytePattern]::ReplaceAt($Data, $state.FromHits[0], $state.ToBytes)
        return [pscustomobject]@{
            Name = $Group.Name
            Status = 'patched'
            Offset = $state.FromHits[0]
            Bytes = $state.ToBytes.Length
        }
    }

    if ($state.FromHits.Count -eq 0 -and $state.ToHits.Count -eq 1) {
        return [pscustomobject]@{
            Name = $Group.Name
            Status = 'already-patched'
            Offset = $state.ToHits[0]
            Bytes = $state.ToBytes.Length
        }
    }

    throw "$($Group.Name): ambiguous original/patched state."
}

function Set-RootServiceTierFast {
    param(
        [Parameter(Mandatory = $true)][string] $ConfigPath,
        [Parameter(Mandatory = $true)][string] $BackupDirectory
    )

    $configDirectory = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $configDirectory)) {
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = Join-Path $BackupDirectory ("config.toml.before-fast.$stamp")
        Copy-Item -LiteralPath $ConfigPath -Destination $backupPath
        $content = [IO.File]::ReadAllText($ConfigPath)
    }
    else {
        $content = ''
    }

    $sectionMatch = [regex]::Match($content, '(?m)^\s*\[')
    $rootLength = if ($sectionMatch.Success) { $sectionMatch.Index } else { $content.Length }
    $root = $content.Substring(0, $rootLength)
    $sections = $content.Substring($rootLength)
    $tierMatches = [regex]::Matches($root, '(?m)^\s*service_tier\s*=.*$')

    if ($tierMatches.Count -gt 1) {
        throw 'config.toml has multiple root service_tier values.'
    }

    if ($tierMatches.Count -eq 1) {
        $match = $tierMatches[0]
        $root = $root.Substring(0, $match.Index) + 'service_tier = "fast"' + $root.Substring($match.Index + $match.Length)
    }
    else {
        if ($root.Length -gt 0 -and -not $root.EndsWith("`n")) {
            $root += [Environment]::NewLine
        }
        $root += 'service_tier = "fast"' + [Environment]::NewLine
        if ($sections.Length -gt 0 -and -not $root.EndsWith([Environment]::NewLine + [Environment]::NewLine)) {
            $root += [Environment]::NewLine
        }
    }

    $newContent = $root + $sections
    $temporaryPath = "$ConfigPath.codex-fast-writing"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($temporaryPath, $newContent, $utf8)
    Copy-Item -LiteralPath $temporaryPath -Destination $ConfigPath -Force
    Remove-Item -LiteralPath $temporaryPath -Force
}

function Get-CodexProcessesFromRoot {
    param([Parameter(Mandatory = $true)][string] $Root)

    return @(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $false
        }
    })
}

Write-Step 'Detecting Microsoft Store Codex installation'
$package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) {
    throw 'OpenAI.Codex Microsoft Store package was not found for the current user.'
}

$version = $package.Version.ToString()
$sourceApp = [IO.Path]::GetFullPath((Join-Path $package.InstallLocation 'app'))
$destinationBase = [IO.Path]::GetFullPath($DestinationRoot)
$versionRoot = [IO.Path]::GetFullPath((Join-Path $destinationBase $version))
$destinationApp = [IO.Path]::GetFullPath((Join-Path $versionRoot 'app'))
if (-not $destinationApp.StartsWith($destinationBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination escaped the configured Codex-Fast root.'
}

$sourceAsar = Join-Path $sourceApp 'resources\app.asar'
$destinationAsar = Join-Path $destinationApp 'resources\app.asar'
$fastExe = Join-Path $destinationApp 'ChatGPT.exe'
if (-not (Test-Path -LiteralPath $sourceAsar)) {
    throw "Source app.asar was not found: $sourceAsar"
}

Write-Host "Codex version: $version"
Write-Host "Source: $sourceApp"
Write-Host "Destination: $destinationApp"

Write-Step 'Copying Codex to a user-writable directory'
New-Item -ItemType Directory -Path $destinationApp -Force | Out-Null
$robocopy = (Get-Command robocopy.exe -ErrorAction Stop).Source
$robocopyArgs = @(
    $sourceApp,
    $destinationApp,
    '/E',
    '/COPY:DAT',
    '/DCOPY:DAT',
    '/R:2',
    '/W:1',
    '/NFL',
    '/NDL',
    '/NP',
    '/NJH',
    '/NJS'
)
& $robocopy @robocopyArgs
$robocopyExit = $LASTEXITCODE
if ($robocopyExit -ge 8) {
    throw "robocopy failed with exit code $robocopyExit"
}

if (-not (Test-Path -LiteralPath $destinationAsar) -or -not (Test-Path -LiteralPath $fastExe)) {
    throw 'The copied Codex application is incomplete.'
}

$originalBackup = Join-Path $destinationApp 'resources\app.asar.original'
Copy-Item -LiteralPath $sourceAsar -Destination $originalBackup -Force

Write-Step 'Validating and applying four equal-length Fast patches'
$allowlistCurrent = 'u?n.has(r.model):!r.hidden'
$allowlistOlder = 's?t.has(n.model):!n.hidden'
$uiCurrent = 'p=o&&!f&&u!=null&&u?.requirements?.featureRequirements?.fast_mode!==!1'
$uiOlder = 'f=a&&!u&&c!=null&&c?.requirements?.featureRequirements?.fast_mode!==!1'
$requestCurrent = 'async function T(e,t){let n=await x(e,t);if(n!==`chatgpt`)return!1;let r=await v(t,{priority:`critical`});return e.query.setData(g,{authMethod:n,hostId:t},r),r.requirements?.featureRequirements?.fast_mode!==!1}'
$requestOlder = 'return n===`chatgpt`?(await e.query.fetch(c,{authMethod:n,hostId:t})).requirements?.featureRequirements?.fast_mode!==!1:!1'

$groups = @(
    [pscustomobject]@{
        Name = 'hidden models default'
        Alternatives = @(
            [pscustomobject]@{ From = 'useHiddenModels:!1'; To = 'useHiddenModels:!0' }
        )
    },
    [pscustomobject]@{
        Name = 'model allowlist gate'
        Alternatives = @(
            [pscustomobject]@{ From = $allowlistCurrent; To = (New-PaddedTrueExpression -Original $allowlistCurrent) },
            [pscustomobject]@{ From = $allowlistOlder; To = (New-PaddedTrueExpression -Original $allowlistOlder) }
        )
    },
    [pscustomobject]@{
        Name = 'Fast UI gate'
        Alternatives = @(
            [pscustomobject]@{ From = $uiCurrent; To = (New-PaddedTrueExpression -Original $uiCurrent -Prefix 'p=') },
            [pscustomobject]@{ From = $uiOlder; To = (New-PaddedTrueExpression -Original $uiOlder -Prefix 'f=') }
        )
    },
    [pscustomobject]@{
        Name = 'Fast request gate'
        Alternatives = @(
            [pscustomobject]@{ From = $requestCurrent; To = (New-PaddedTrueFunction -Original $requestCurrent) },
            [pscustomobject]@{ From = $requestOlder; To = (New-PaddedTrueExpression -Original $requestOlder -Prefix 'return ') }
        )
    }
)

$asarBytes = [IO.File]::ReadAllBytes($destinationAsar)
$patchResults = @()
foreach ($group in $groups) {
    $patchResults += Invoke-PatchGroup -Data $asarBytes -Group $group
}

foreach ($result in $patchResults) {
    Write-Host ("{0}: {1} ({2} bytes at {3})" -f $result.Name, $result.Status, $result.Bytes, $result.Offset)
}

if (@($patchResults | Where-Object { $_.Status -eq 'patched' }).Count -gt 0) {
    $temporaryAsar = "$destinationAsar.codex-fast-writing"
    try {
        [IO.File]::WriteAllBytes($temporaryAsar, $asarBytes)
        if ((Get-Item -LiteralPath $temporaryAsar).Length -ne (Get-Item -LiteralPath $destinationAsar).Length) {
            throw 'Patched app.asar changed size unexpectedly.'
        }
        Copy-Item -LiteralPath $temporaryAsar -Destination $destinationAsar -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryAsar) {
            Remove-Item -LiteralPath $temporaryAsar -Force
        }
    }
}

Write-Step 'Setting the root service_tier to fast'
$configPath = Join-Path $HOME '.codex\config.toml'
Set-RootServiceTierFast -ConfigPath $configPath -BackupDirectory $versionRoot

Write-Step 'Creating the desktop Codex shortcut'
$desktop = [IO.Path]::GetFullPath([Environment]::GetFolderPath('Desktop'))
$desktopShortcut = [IO.Path]::GetFullPath((Join-Path $desktop 'Codex.lnk'))
$oldFastShortcut = [IO.Path]::GetFullPath((Join-Path $desktop 'Codex Fast.lnk'))
$storeShortcutBackup = Join-Path $versionRoot 'Codex Store.lnk'
$markerPath = Join-Path $versionRoot 'codex-fast-install.json'
$shell = New-Object -ComObject WScript.Shell

$shortcutExistedBefore = $null
if (Test-Path -LiteralPath $markerPath) {
    try {
        $previousMarker = [IO.File]::ReadAllText($markerPath) | ConvertFrom-Json
        $shortcutStateProperty = $previousMarker.PSObject.Properties['desktop_shortcut']
        if ($shortcutStateProperty -and $shortcutStateProperty.Value) {
            $existedProperty = $shortcutStateProperty.Value.PSObject.Properties['existed_before']
            if ($existedProperty) {
                $shortcutExistedBefore = [bool] $existedProperty.Value
            }
        }
    }
    catch {
        Write-Warning 'The previous install marker could not be read; shortcut state will be inferred.'
    }
}

$desktopShortcutExistsNow = Test-Path -LiteralPath $desktopShortcut
$alreadyFast = $false
if ($desktopShortcutExistsNow) {
    $existingShortcut = $shell.CreateShortcut($desktopShortcut)
    $existingTarget = $existingShortcut.TargetPath
    $alreadyFast = $existingTarget -and $existingTarget.StartsWith($destinationBase, [StringComparison]::OrdinalIgnoreCase)
}

if ($null -eq $shortcutExistedBefore) {
    if (Test-Path -LiteralPath $storeShortcutBackup) {
        $shortcutExistedBefore = $true
    }
    elseif ($desktopShortcutExistsNow -and -not $alreadyFast) {
        $shortcutExistedBefore = $true
    }
    else {
        $shortcutExistedBefore = $false
    }
}

if ($desktopShortcutExistsNow) {
    if (-not $alreadyFast -and -not (Test-Path -LiteralPath $storeShortcutBackup)) {
        Copy-Item -LiteralPath $desktopShortcut -Destination $storeShortcutBackup
    }
}

$shortcut = $shell.CreateShortcut($desktopShortcut)
$shortcut.TargetPath = $fastExe
$shortcut.WorkingDirectory = $destinationApp
$shortcut.IconLocation = "$fastExe,0"
$shortcut.Description = "Codex (Fast enabled, $version)"
$shortcut.Save()

if (Test-Path -LiteralPath $oldFastShortcut) {
    Remove-Item -LiteralPath $oldFastShortcut -Force
}

$marker = [ordered]@{
    version = $version
    installed_at = [DateTime]::UtcNow.ToString('o')
    source_app = $sourceApp
    destination_app = $destinationApp
    source_asar_sha256 = (Get-FileHash -LiteralPath $sourceAsar -Algorithm SHA256).Hash
    patched_asar_sha256 = (Get-FileHash -LiteralPath $destinationAsar -Algorithm SHA256).Hash
    desktop_shortcut = [ordered]@{
        existed_before = [bool] $shortcutExistedBefore
        backup_saved = Test-Path -LiteralPath $storeShortcutBackup
    }
    patches = @($patchResults)
}
$markerJson = $marker | ConvertTo-Json -Depth 5
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($markerPath, $markerJson, $utf8NoBom)

Write-Step 'Verification'
$verifiedShortcut = $shell.CreateShortcut($desktopShortcut)
if ($verifiedShortcut.TargetPath -ne $fastExe) {
    throw 'Desktop shortcut verification failed.'
}
if ((Get-Item -LiteralPath $destinationAsar).Length -ne (Get-Item -LiteralPath $originalBackup).Length) {
    throw 'Patched and original app.asar sizes differ.'
}
$serviceTierLine = Get-Content -LiteralPath $configPath | Where-Object { $_ -match '^\s*service_tier\s*=\s*"fast"\s*$' }
if (@($serviceTierLine).Count -lt 1) {
    throw 'service_tier verification failed.'
}

Write-Host "`nCodex Fast is installed successfully." -ForegroundColor Green
Write-Host "Desktop shortcut: $desktopShortcut"
Write-Host "Patched app: $destinationApp"
Write-Host "Original app.asar backup: $originalBackup"

if (-not $NoLaunch) {
    $fastProcesses = Get-CodexProcessesFromRoot -Root $destinationApp
    if ($fastProcesses.Count -eq 0) {
        $storeProcesses = Get-CodexProcessesFromRoot -Root $sourceApp
        if ($storeProcesses.Count -gt 0) {
            Write-Host "`nClose all currently running Codex windows. The patched Codex will open automatically." -ForegroundColor Yellow
            $deadline = [DateTime]::UtcNow.AddMinutes(15)
            do {
                Start-Sleep -Seconds 1
                $storeProcesses = Get-CodexProcessesFromRoot -Root $sourceApp
            } while ($storeProcesses.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
        }

        if ((Get-CodexProcessesFromRoot -Root $sourceApp).Count -eq 0) {
            Start-Process -FilePath $fastExe -WorkingDirectory $destinationApp
        }
        else {
            Write-Warning 'Timed out waiting for the Store Codex to close. Use the desktop Codex shortcut after closing it.'
        }
    }
}
