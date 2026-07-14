#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$fastRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex-Fast'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex.lnk'

$versions = @(Get-ChildItem -LiteralPath $fastRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
$backupShortcut = $null
foreach ($version in $versions) {
    $candidate = Join-Path $version.FullName 'Codex Store.lnk'
    if (Test-Path -LiteralPath $candidate) {
        $backupShortcut = $candidate
        break
    }
}

if ($backupShortcut) {
    Copy-Item -LiteralPath $backupShortcut -Destination $desktopShortcut -Force
    Write-Host "Restored the Microsoft Store Codex desktop shortcut."
}
else {
    Write-Warning 'No saved Microsoft Store desktop shortcut was found. Recreate it from the Start menu.'
}

$configPath = Join-Path $HOME '.codex\config.toml'
if (Test-Path -LiteralPath $configPath) {
    $content = [IO.File]::ReadAllText($configPath)
    $sectionMatch = [regex]::Match($content, '(?m)^\s*\[')
    $rootLength = if ($sectionMatch.Success) { $sectionMatch.Index } else { $content.Length }
    $root = $content.Substring(0, $rootLength)
    $sections = $content.Substring($rootLength)
    $tierMatches = [regex]::Matches($root, '(?m)^\s*service_tier\s*=.*$')
    if ($tierMatches.Count -eq 1) {
        $match = $tierMatches[0]
        $root = $root.Substring(0, $match.Index) + 'service_tier = "default"' + $root.Substring($match.Index + $match.Length)
        $temporaryPath = "$configPath.codex-fast-restoring"
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temporaryPath, $root + $sections, $utf8)
        Copy-Item -LiteralPath $temporaryPath -Destination $configPath -Force
        Remove-Item -LiteralPath $temporaryPath -Force
        Write-Host 'Restored root service_tier to default.'
    }
}

Write-Host "The copied files remain at: $fastRoot"
Write-Host 'After closing Codex, that directory can be deleted manually if it is no longer needed.'
