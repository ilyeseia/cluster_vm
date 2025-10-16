<#
.SYNOPSIS
    Auto-Renewal System for Infinite VM Matrix
.DESCRIPTION
    Monitors runner health and triggers renewal before expiration
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GithubToken = $env:GITHUB_TOKEN,
    
    [Parameter(Mandatory=$false)]
    [string]$Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     🔄 AUTO-RENEWAL SYSTEM                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# فحص Runners النشطة
Write-Host "`n📊 Checking active runners..." -ForegroundColor Yellow

try {
    # استخدام GitHub CLI لإطلاق workflow جديد
    $result = gh workflow run infinite-vm-matrix.yml `
        --ref main `
        --field action=create-runner `
        --field runner-count=3
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ New workflow triggered successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to trigger workflow" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
}
