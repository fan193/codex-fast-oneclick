#requires -Version 5.1

[CmdletBinding()]
param(
    [string] $FastRoot = (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex-Fast'),
    [string] $DesktopPath = [Environment]::GetFolderPath('Desktop'),
    [string] $ConfigPath = (Join-Path $HOME '.codex\config.toml')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$fastRootFull = [IO.Path]::GetFullPath($FastRoot)
$desktopFull = [IO.Path]::GetFullPath($DesktopPath)
$desktopShortcut = [IO.Path]::GetFullPath((Join-Path $desktopFull 'Codex.lnk'))
if (-not $desktopShortcut.StartsWith($desktopFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unexpected desktop shortcut path.'
}

$versions = @(Get-ChildItem -LiteralPath $fastRootFull -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
$selectedVersion = $versions | Select-Object -First 1
$backupShortcut = $null
$shortcutExistedBefore = $null

if ($selectedVersion) {
    $markerPath = Join-Path $selectedVersion.FullName 'codex-fast-install.json'
    if (Test-Path -LiteralPath $markerPath) {
        try {
            $marker = [IO.File]::ReadAllText($markerPath) | ConvertFrom-Json
            $shortcutStateProperty = $marker.PSObject.Properties['desktop_shortcut']
            if ($shortcutStateProperty -and $shortcutStateProperty.Value) {
                $existedProperty = $shortcutStateProperty.Value.PSObject.Properties['existed_before']
                if ($existedProperty) {
                    $shortcutExistedBefore = [bool] $existedProperty.Value
                }
            }
        }
        catch {
            Write-Warning 'The install marker could not be read; using compatibility fallback.'
        }
    }
}

foreach ($version in $versions) {
    $candidate = Join-Path $version.FullName 'Codex Store.lnk'
    if (Test-Path -LiteralPath $candidate) {
        $backupShortcut = $candidate
        break
    }
}

$shell = New-Object -ComObject WScript.Shell
if ($backupShortcut) {
    Copy-Item -LiteralPath $backupShortcut -Destination $desktopShortcut -Force
    Write-Host 'Restored the saved Microsoft Store Codex desktop shortcut.'
}
elseif ($shortcutExistedBefore -eq $false) {
    if (Test-Path -LiteralPath $desktopShortcut) {
        $currentShortcut = $shell.CreateShortcut($desktopShortcut)
        $currentTarget = $currentShortcut.TargetPath
        if ($currentTarget -and $currentTarget.StartsWith($fastRootFull, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $desktopShortcut -Force
            Write-Host 'Removed the Codex shortcut created by the Fast installer.'
        }
        else {
            Write-Warning 'The desktop Codex shortcut was changed after installation, so it was left untouched.'
        }
    }
    else {
        Write-Host 'No desktop Codex shortcut existed before installation; nothing to restore.'
    }
}
else {
    $package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) {
        Write-Warning 'Microsoft Store Codex is not installed, so a Store shortcut could not be created.'
    }
    else {
        $manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
        [xml] $manifest = Get-Content -Raw -LiteralPath $manifestPath
        $application = @($manifest.Package.Applications.Application) | Select-Object -First 1
        if (-not $application -or -not $application.Id) {
            throw 'Could not determine the Microsoft Store Codex application ID.'
        }

        $appUserModelId = "$($package.PackageFamilyName)!$($application.Id)"
        $storeShortcut = $shell.CreateShortcut($desktopShortcut)
        $storeShortcut.TargetPath = (Join-Path $env:WINDIR 'explorer.exe')
        $storeShortcut.Arguments = "shell:AppsFolder\$appUserModelId"
        $storeShortcut.WorkingDirectory = $env:WINDIR
        $storeIcon = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
        if (Test-Path -LiteralPath $storeIcon) {
            $storeShortcut.IconLocation = "$storeIcon,0"
        }
        $storeShortcut.Description = 'Microsoft Store Codex'
        $storeShortcut.Save()
        Write-Host 'Created a Microsoft Store Codex desktop shortcut using its AppUserModelID.'
    }
}

if (Test-Path -LiteralPath $ConfigPath) {
    $content = [IO.File]::ReadAllText($ConfigPath)
    $sectionMatch = [regex]::Match($content, '(?m)^\s*\[')
    $rootLength = if ($sectionMatch.Success) { $sectionMatch.Index } else { $content.Length }
    $root = $content.Substring(0, $rootLength)
    $sections = $content.Substring($rootLength)
    $tierMatches = [regex]::Matches($root, '(?m)^\s*service_tier\s*=.*$')
    if ($tierMatches.Count -eq 1) {
        $match = $tierMatches[0]
        $root = $root.Substring(0, $match.Index) + 'service_tier = "default"' + $root.Substring($match.Index + $match.Length)
        $temporaryPath = "$ConfigPath.codex-fast-restoring"
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temporaryPath, $root + $sections, $utf8)
        Copy-Item -LiteralPath $temporaryPath -Destination $ConfigPath -Force
        Remove-Item -LiteralPath $temporaryPath -Force
        Write-Host 'Restored root service_tier to default.'
    }
}

Write-Host "The copied files remain at: $fastRootFull"
Write-Host 'After closing Codex, that directory can be deleted manually if it is no longer needed.'
