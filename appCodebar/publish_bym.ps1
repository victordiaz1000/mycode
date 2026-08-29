# publish_bym.ps1 — Publie une MàJ BYM sur GitHub (bym-text)
# Wrapper PowerShell 5.1 autour de publish_bym.py + generate_manifest.py
# Usage :
#   .\appCodebar\publish_bym.ps1                          # dry-run
#   .\appCodebar\publish_bym.ps1 -Notes "corr Ge 1:1"
#   .\appCodebar\publish_bym.ps1 -Version 1.0.3 -Notes "x" -Full
#   .\appCodebar\publish_bym.ps1 -DryRun
#   .\appCodebar\publish_bym.ps1 -NoPush                  # genere sans pousser
param(
    [string]$Notes,
    [string]$Version,
    [switch]$Full,
    [switch]$DryRun,
    [switch]$NoPush,
    [string]$Clone = "",
    [string]$ManifestUrl = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot  # bym3/
$py = "python"
if (Get-Command python3 -ErrorAction SilentlyContinue) { $py = "python3" }

$args = @("$PSScriptRoot\publish_bym.py")
if ($Notes)   { $args += @("--notes", $Notes) }
if ($Version) { $args += @("--version", $Version) }
if ($Full)    { $args += "--full" }
if ($DryRun)  { $args += "--dry-run" }
if ($NoPush)  { $args += "--no-push" }
if ($Clone)   { $args += @("--clone", $Clone) }
if ($ManifestUrl) { $args += @("--manifest-url", $ManifestUrl) }

Write-Host "=== publish_bym.ps1 -> publish_bym.py ===" -ForegroundColor Cyan
& $py @args
exit $LASTEXITCODE
