#!/usr/bin/env pwsh
# Installs the native PowerShell fable-mode statusline (no Git Bash / python3).
# Copies the renderer to a stable path and points settings.json at it via
# powershell.exe. Refuses to replace a different statusline unless -Force.
#
# Only the "statusLine" key is edited, at the string level. A full re-serialize
# is avoided on purpose: Windows PowerShell 5.1's ConvertTo-Json collapses
# single-element arrays (which settings.json uses throughout its hooks) and would
# corrupt the file.
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$DataDir = (Join-Path $HOME '.claude/fable-mode'),
    [string]$SettingsPath = (Join-Path $HOME '.claude/settings.json')
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'statusline/statusline.ps1'
$target = Join-Path $DataDir 'statusline.ps1'

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Copy-Item -Force -LiteralPath $src -Destination $target

# Windows PowerShell ships on every Windows box; prefer it, fall back to pwsh.
$psExe = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { 'powershell.exe' }
         elseif (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' }
         else { 'powershell.exe' }
$targetWin = ($target -replace '/', '\')
$command = "$psExe -NoProfile -ExecutionPolicy Bypass -File `"$targetWin`""
$slJson = [ordered]@{ type = 'command'; command = $command } | ConvertTo-Json -Compress

# Read current statusline (read-only parse; never re-serialized).
$raw = ''
$existing = ''
if (Test-Path $SettingsPath) {
    $raw = Get-Content -LiteralPath $SettingsPath -Raw
    try { $parsed = $raw | ConvertFrom-Json } catch {
        throw "settings.json is not valid JSON: $SettingsPath (fix or move it, then re-run)"
    }
    if ($parsed.PSObject.Properties['statusLine']) { $existing = [string]$parsed.statusLine.command }
}

if ($existing -and ($existing -notlike '*statusline.ps1*') -and -not $Force) {
    Write-Output "A different statusline is configured:`n  $existing`nRe-run with -Force to replace it, or keep your current one - the fable renderer stays available at $targetWin"
    exit 0
}

if (-not $raw) {
    # No (or empty) settings file: create a minimal valid one.
    $new = "{`n  `"statusLine`": $slJson`n}`n"
} else {
    # statusLine value is a flat object (no nested braces), so a brace-free match
    # is safe and touches nothing else in the file.
    $pattern = '"statusLine"\s*:\s*\{[^{}]*\}'
    $replacement = [System.Text.RegularExpressions.MatchEvaluator] { param($m) '"statusLine": ' + $slJson }
    if ([regex]::IsMatch($raw, $pattern)) {
        $rx = [regex]::new($pattern)
        $new = $rx.Replace($raw, $replacement, 1)
    } else {
        # Insert the key right after the opening brace.
        $idx = $raw.IndexOf('{')
        if ($idx -lt 0) { throw "settings.json has no top-level object: $SettingsPath" }
        $new = $raw.Substring(0, $idx + 1) + "`n  `"statusLine`": $slJson," + $raw.Substring($idx + 1)
    }
}

if (Test-Path $SettingsPath) { Copy-Item -Force -LiteralPath $SettingsPath -Destination "$SettingsPath.bak" }
[IO.File]::WriteAllText($SettingsPath, $new, [System.Text.UTF8Encoding]::new($false))
Write-Output "fable-mode statusline installed -> $command`nRestart Claude Code (or start a new session) to see it."
