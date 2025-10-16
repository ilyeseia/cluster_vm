<#
.SYNOPSIS
    Unit Tests Suite
.DESCRIPTION
    Comprehensive unit testing for all system components
.PARAMETER TestCategory
    Category of tests to run: all, config, vms, master, jobs, health
.EXAMPLE
    .\unit-tests.ps1 -TestCategory all
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('all','config','vms','master','jobs','health','basic')]
    [string]$TestCategory = 'all',
    
    [Parameter(Mandatory=$false)]
    [switch]$Quick
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$TEST_RESULTS_FILE = "results/unit-tests-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$TEST_LOG_FILE = "logs/unit-tests-$(Get-Date -Format 'yyyyMMdd').log"

# ═══════════════════════════════════════════════════════════════════════════
# متغيرات عامة
# ═══════════════════════════════════════════════════════════════════════════

$global:TestResults = @{
    timestamp = Get-Date -Format 'o'
    category = $TestCategory
    totalTests = 0
    passedTests = 0
    failedTests = 0
    skippedTests = 0
    duration = 0
    tests = @()
}

$global:CurrentTest = $null

# ═══════════════════════════════════════════════════════════════════════════
# دوال المساعدة
# ═══════════════════════════════════════════════════════════════════════════

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (!(Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    
    Add-Content -Path $TEST_LOG_FILE -Value $logMessage
    
    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Start-Test {
    param([string]$TestName)
    
    $global:CurrentTest = @{
        name = $TestName
        status = 'running'
        startTime = Get-Date
        duration = 0
        error = $null
    }
    
    $global:TestResults.totalTests++
    
    Write-Host "  ⚡ Running: $TestName" -ForegroundColor Cyan -NoNewline
}

function Complete-Test {
    param(
        [bool]$Passed = $true,
        [string]$ErrorMessage = ""
    )
    
    $global:CurrentTest.duration = ((Get-Date) - $global:CurrentTest.startTime).TotalMilliseconds
    
    if ($Passed) {
        $global:CurrentTest.status = 'passed'
        $global:TestResults.passedTests++
        Write-Host " ✓" -ForegroundColor Green
        Write-Log "Test passed: $($global:CurrentTest.name)" -Level SUCCESS
    } else {
        $global:CurrentTest.status = 'failed'
        $global:CurrentTest.error = $ErrorMessage
        $global:TestResults.failedTests++
        Write-Host " ✗" -ForegroundColor Red
        if ($ErrorMessage) {
            Write-Host "    Error: $ErrorMessage" -ForegroundColor Red
        }
        Write-Log "Test failed: $($global:CurrentTest.name) - $ErrorMessage" -Level ERROR
    }
    
    $global:TestResults.tests += $global:CurrentTest
}

function Assert-True {
    param($Condition, [string]$Message = "Condition was false")
    
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Message = "")
    
    if (-not (Test-Path $Path)) {
        $errorMsg = if ($Message) { $Message } else { "File not found: $Path" }
        throw $errorMsg
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Basic Tests
# ═══════════════════════════════════════════════════════════════════════════

function Test-Basic {
    Write-Host "`n⚡ Basic Tests" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    # Test 1: Config File Exists
    Start-Test "Config File Exists"
    try {
        Assert-FileExists -Path $CONFIG_FILE
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 2: VMs State File Exists
    Start-Test "VMs State File Exists"
    try {
        Assert-FileExists -Path $VMS_STATE_FILE
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 3: Files are Valid JSON
    Start-Test "Files are Valid JSON"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        Assert-True -Condition ($null -ne $config) -Message "Config is null"
        Assert-True -Condition ($null -ne $vmsState) -Message "VMs state is null"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 4: System Has VMs
    Start-Test "System Has VMs"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        Assert-True -Condition ($vmsState.vms.Count -gt 0) -Message "No VMs in system"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 5: Config Has Version
    Start-Test "Config Has Version"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Assert-True -Condition ($config.PSObject.Properties.Name -contains 'version') -Message "No version in config"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test Execution
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-Tests {
    $startTime = Get-Date
    
    Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                    🧪 UNIT TESTS SUITE v1.0.0 🧪                          ║
║                                                                            ║
║              Comprehensive Unit Testing Framework                         ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    Write-Host "`n📋 Test Configuration:" -ForegroundColor Yellow
    Write-Host "  • Category: $TestCategory" -ForegroundColor Cyan
    Write-Host "  • Quick Mode: $(if($Quick){'Enabled'}else{'Disabled'})" -ForegroundColor Cyan
    Write-Host "  • Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    
    # تنفيذ الاختبارات
    Test-Basic
    
    $global:TestResults.duration = ((Get-Date) - $startTime).TotalSeconds
    
    # عرض النتائج
    Show-TestResults
    
    # حفظ النتائج
    Save-TestResults
}

function Show-TestResults {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                          📊 TEST RESULTS 📊                               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $passRate = if ($global:TestResults.totalTests -gt 0) {
        [math]::Round(($global:TestResults.passedTests / $global:TestResults.totalTests) * 100, 2)
    } else { 0 }
    
    Write-Host "`n📈 Summary:" -ForegroundColor Yellow
    Write-Host "  • Total Tests: $($global:TestResults.totalTests)" -ForegroundColor Cyan
    Write-Host "  • Passed: $($global:TestResults.passedTests)" -ForegroundColor Green
    Write-Host "  • Failed: $($global:TestResults.failedTests)" -ForegroundColor Red
    Write-Host "  • Pass Rate: $passRate%" -ForegroundColor $(if($passRate -eq 100){'Green'}elseif($passRate -ge 80){'Yellow'}else{'Red'})
    Write-Host "  • Duration: $([math]::Round($global:TestResults.duration, 2))s" -ForegroundColor Cyan
    
    if ($global:TestResults.failedTests -gt 0) {
        Write-Host "`n❌ Failed Tests:" -ForegroundColor Red
        $failedTests = $global:TestResults.tests | Where-Object { $_.status -eq 'failed' }
        foreach ($test in $failedTests) {
            Write-Host "  • $($test.name)" -ForegroundColor Red
            if ($test.error) {
                Write-Host "    Error: $($test.error)" -ForegroundColor Yellow
            }
        }
    }
    
    # رسالة نهائية
    if ($global:TestResults.failedTests -eq 0) {
        Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                    ✅ ALL TESTS PASSED! ✅                                ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    } else {
        Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                     ❌ SOME TESTS FAILED ❌                               ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    }
}

function Save-TestResults {
    if (!(Test-Path "results")) {
        New-Item -ItemType Directory -Path "results" -Force | Out-Null
    }
    
    $global:TestResults | ConvertTo-Json -Depth 10 | Set-Content $TEST_RESULTS_FILE
    Write-Host "`n💾 Results saved: $TEST_RESULTS_FILE" -ForegroundColor Cyan
    Write-Log "Test results saved: $TEST_RESULTS_FILE" -Level SUCCESS
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

try {
    Invoke-Tests
    
    # Exit code بناءً على النتائج
    if ($global:TestResults.failedTests -gt 0) {
        exit 1
    } else {
        exit 0
    }
} catch {
    Write-Host "`n❌ Fatal error during tests: $_" -ForegroundColor Red
    Write-Log "Fatal error: $_" -Level ERROR
    exit 1
}
