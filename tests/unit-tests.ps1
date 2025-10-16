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
    [switch]$Quick,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
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
    
    if ($Verbose) {
        $color = switch ($Level) {
            'INFO' { 'Cyan' }
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
            'SUCCESS' { 'Green' }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
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
        Write-Host "    Error: $ErrorMessage" -ForegroundColor Red
        Write-Log "Test failed: $($global:CurrentTest.name) - $ErrorMessage" -Level ERROR
    }
    
    $global:TestResults.tests += $global:CurrentTest
}

function Skip-Test {
    param([string]$TestName, [string]$Reason)
    
    $global:TestResults.totalTests++
    $global:TestResults.skippedTests++
    
    Write-Host "  ⊘ Skipped: $TestName" -ForegroundColor Gray
    Write-Host "    Reason: $Reason" -ForegroundColor Gray
    
    $global:TestResults.tests += @{
        name = $TestName
        status = 'skipped'
        reason = $Reason
        duration = 0
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message = "")
    
    if ($Actual -ne $Expected) {
        $errorMsg = if ($Message) { $Message } else { "Expected '$Expected' but got '$Actual'" }
        throw $errorMsg
    }
}

function Assert-True {
    param($Condition, [string]$Message = "Condition was false")
    
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-NotNull {
    param($Value, [string]$Message = "Value was null")
    
    if ($null -eq $Value) {
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
# Configuration Tests
# ═══════════════════════════════════════════════════════════════════════════

function Test-Configuration {
    Write-Host "`n📋 Configuration Tests" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    # Test 1: Config File Exists
    Start-Test "Config File Exists"
    try {
        Assert-FileExists -Path $CONFIG_FILE
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 2: Config Valid JSON
    Start-Test "Config Valid JSON"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Assert-NotNull -Value $config
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 3: Config Has Required Fields
    Start-Test "Config Has Required Fields"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        $requiredFields = @('version', 'vmConfig', 'masterElection', 'monitoring', 'alerting')
        
        foreach ($field in $requiredFields) {
            Assert-True -Condition ($config.PSObject.Properties.Name -contains $field) `
                       -Message "Missing required field: $field"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 4: VM Count Configuration Valid
    Start-Test "VM Count Configuration Valid"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Assert-True -Condition ($config.vmConfig.desiredVmCount -ge 1) `
                   -Message "desiredVmCount must be >= 1"
        Assert-True -Condition ($config.vmConfig.desiredVmCount -le 10) `
                   -Message "desiredVmCount must be <= 10"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 5: VM Lifetime Valid
    Start-Test "VM Lifetime Valid"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Assert-True -Condition ($config.vmConfig.vmLifetime -ge 60) `
                   -Message "vmLifetime must be >= 60 seconds"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 6: Thresholds Configuration Valid
    Start-Test "Thresholds Configuration Valid"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Assert-True -Condition ($config.alerting.thresholds.cpu.warning -lt $config.alerting.thresholds.cpu.critical) `
                   -Message "CPU warning must be < critical"
        Assert-True -Condition ($config.alerting.thresholds.memory.warning -lt $config.alerting.thresholds.memory.critical) `
                   -Message "Memory warning must be < critical"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 7: Master Election Strategy Valid
    Start-Test "Master Election Strategy Valid"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        $validStrategies = @('max-remaining-time', 'min-cpu-usage', 'min-memory-usage', 'random')
        Assert-True -Condition ($validStrategies -contains $config.masterElection.strategy) `
                   -Message "Invalid master election strategy"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 8: Election Weights Sum to 1
    Start-Test "Election Weights Valid"
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        $weights = $config.masterElection.weights
        $sum = $weights.remainingTime + $weights.cpuUsage + $weights.memoryUsage
        Assert-True -Condition ([math]::Abs($sum - 1.0) -lt 0.01) `
                   -Message "Election weights must sum to 1.0 (got $sum)"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# VMs Tests
# ═══════════════════════════════════════════════════════════════════════════

function Test-VMs {
    Write-Host "`n🖥️  VMs Tests" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    # Test 1: VMs State File Exists
    Start-Test "VMs State File Exists"
    try {
        Assert-FileExists -Path $VMS_STATE_FILE
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 2: VMs State Valid JSON
    Start-Test "VMs State Valid JSON"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        Assert-NotNull -Value $vmsState
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 3: VMs State Has Required Fields
    Start-Test "VMs State Has Required Fields"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $requiredFields = @('version', 'lastUpdated', 'vms', 'statistics')
        
        foreach ($field in $requiredFields) {
            Assert-True -Condition ($vmsState.PSObject.Properties.Name -contains $field) `
                       -Message "Missing required field: $field"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 4: VMs Array is Valid
    Start-Test "VMs Array is Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        Assert-NotNull -Value $vmsState.vms -Message "VMs array is null"
        Assert-True -Condition ($vmsState.vms.GetType().Name -eq 'Object[]' -or $vmsState.vms.Count -ge 0) `
                   -Message "VMs must be an array"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 5: Each VM Has Required Fields
    Start-Test "Each VM Has Required Fields"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $requiredVMFields = @('vmId', 'status', 'role', 'createdAt', 'performance')
        
        foreach ($vm in $vmsState.vms) {
            foreach ($field in $requiredVMFields) {
                Assert-True -Condition ($vm.PSObject.Properties.Name -contains $field) `
                           -Message "VM $($vm.vmId) missing field: $field"
            }
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 6: VM IDs are Unique
    Start-Test "VM IDs are Unique"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $vmIds = $vmsState.vms | ForEach-Object { $_.vmId }
        $uniqueIds = $vmIds | Select-Object -Unique
        Assert-Equal -Actual $uniqueIds.Count -Expected $vmIds.Count `
                    -Message "Duplicate VM IDs found"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 7: VM Performance Metrics Valid
    Start-Test "VM Performance Metrics Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        
        foreach ($vm in $vmsState.vms) {
            Assert-True -Condition ($vm.performance.cpuUsage -ge 0 -and $vm.performance.cpuUsage -le 100) `
                       -Message "Invalid CPU usage for VM $($vm.vmId)"
            Assert-True -Condition ($vm.performance.memoryUsage -ge 0 -and $vm.performance.memoryUsage -le 100) `
                       -Message "Invalid memory usage for VM $($vm.vmId)"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 8: VM Roles Valid
    Start-Test "VM Roles Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $validRoles = @('master', 'worker')
        
        foreach ($vm in $vmsState.vms) {
            Assert-True -Condition ($validRoles -contains $vm.role) `
                       -Message "Invalid role '$($vm.role)' for VM $($vm.vmId)"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 9: Statistics Calculation Correct
    Start-Test "Statistics Calculation Correct"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $actualTotal = $vmsState.vms.Count
        $statsTotal = $vmsState.statistics.totalVMs
        
        Assert-Equal -Actual $statsTotal -Expected $actualTotal `
                    -Message "Statistics totalVMs mismatch"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Master Tests
# ═══════════════════════════════════════════════════════════════════════════

function Test-Master {
    Write-Host "`n👑 Master Tests" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    # Test 1: Master Exists
    Start-Test "Master Exists"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $masters = $vmsState.vms | Where-Object { $_.role -eq 'master' }
        Assert-True -Condition ($masters.Count -ge 1) `
                   -Message "No master found in cluster"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 2: Only One Master
    Start-Test "Only One Master"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $masters = $vmsState.vms | Where-Object { $_.role -eq 'master' }
        Assert-Equal -Actual $masters.Count -Expected 1 `
                    -Message "Multiple masters found: $($masters.Count)"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 3: Master is Running
    Start-Test "Master is Running"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $master = $vmsState.vms | Where-Object { $_.role -eq 'master' } | Select-Object -First 1
        Assert-NotNull -Value $master
        Assert-Equal -Actual $master.status -Expected 'running' `
                    -Message "Master is not running"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 4: Master Performance Acceptable
    Start-Test "Master Performance Acceptable"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $master = $vmsState.vms | Where-Object { $_.role -eq 'master' } | Select-Object -First 1
        
        Assert-True -Condition ($master.performance.cpuUsage -lt 95) `
                   -Message "Master CPU usage too high: $($master.performance.cpuUsage)%"
        Assert-True -Condition ($master.performance.memoryUsage -lt 95) `
                   -Message "Master memory usage too high: $($master.performance.memoryUsage)%"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 5: Master Has Priority 1
    Start-Test "Master Has Priority 1"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $master = $vmsState.vms | Where-Object { $_.role -eq 'master' } | Select-Object -First 1
        Assert-Equal -Actual $master.priority -Expected 1 `
                    -Message "Master priority should be 1"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Jobs Tests
# ═══════════════════════════════════════════════════════════════════════════

function Test-Jobs {
    Write-Host "`n💼 Jobs Tests" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    # Test 1: Job Statistics Valid
    Start-Test "Job Statistics Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $stats = $vmsState.statistics
        
        Assert-True -Condition ($stats.totalJobsCompleted -ge 0) `
                   -Message "Invalid totalJobsCompleted"
        Assert-True -Condition ($stats.totalJobsRunning -ge 0) `
                   -Message "Invalid totalJobsRunning"
        Assert-True -Condition ($stats.totalJobsFailed -ge 0) `
                   -Message "Invalid totalJobsFailed"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 2: Success Rate Calculation
    Start-Test "Success Rate Calculation"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $completed = $vmsState.statistics.totalJobsCompleted
        $failed = $vmsState.statistics.totalJobsFailed
        $total = $completed + $failed
        
        if ($total -gt 0) {
            $expectedRate = [math]::Round(($completed / $total) * 100, 2)
            $actualRate = $vmsState.statistics.overallSuccessRate
            
            Assert-True -Condition ([math]::Abs($actualRate - $expectedRate) -lt 0.1) `
                       -Message "Success rate calculation incorrect"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 3: Job Counts per VM Valid
    Start-Test "Job Counts per VM Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        
        foreach ($vm in $vmsState.vms) {
            Assert-True -Condition ($vm.jobs.running -ge 0) `
                       -Message "Negative running jobs for VM $($vm.vmId)"
            Assert-True -Condition ($vm.jobs.running -le $config.jobManagement.maxJobsPerVM) `
                       -Message "Too many jobs on VM $($vm.vmId)"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Health Tests
# ═══════════════════════════════════════════════════════════════════════════

function Test-Health {
    Write-Host "`n🏥 Health Tests" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    # Test 1: System Health Status Valid
    Start-Test "System Health Status Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $validStatuses = @('good', 'degraded', 'critical')
        Assert-True -Condition ($validStatuses -contains $vmsState.statistics.systemHealth) `
                   -Message "Invalid system health status"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 2: VM Health Checks Present
    Start-Test "VM Health Checks Present"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        
        foreach ($vm in $vmsState.vms) {
            Assert-NotNull -Value $vm.health -Message "Missing health field for VM $($vm.vmId)"
            Assert-True -Condition ($vm.health.PSObject.Properties.Name -contains 'status') `
                       -Message "Missing health status for VM $($vm.vmId)"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 3: Health Check Timestamps Valid
    Start-Test "Health Check Timestamps Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $now = Get-Date
        
        foreach ($vm in $vmsState.vms) {
            $lastCheck = [DateTime]::Parse($vm.health.lastCheck)
            Assert-True -Condition ($lastCheck -le $now) `
                       -Message "Future health check timestamp for VM $($vm.vmId)"
        }
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 4: Cluster Efficiency Valid
    Start-Test "Cluster Efficiency Valid"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $efficiency = $vmsState.statistics.clusterEfficiency
        
        Assert-True -Condition ($efficiency -ge 0 -and $efficiency -le 100) `
                   -Message "Invalid cluster efficiency: $efficiency"
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Basic Tests (Quick)
# ═══════════════════════════════════════════════════════════════════════════

function Test-Basic {
    Write-Host "`n⚡ Basic Tests (Quick)" -ForegroundColor Yellow
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
        Assert-NotNull -Value $config
        Assert-NotNull -Value $vmsState
        Complete-Test -Passed $true
    } catch {
        Complete-Test -Passed $false -ErrorMessage $_.Exception.Message
    }
    
    # Test 4: System Has VMs
    Start-Test "System Has VMs"
    try {
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        Assert-True -Condition ($vmsState.vms.Count -gt 0) `
                   -Message "No VMs in system"
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
    Write-Host "  • Verbose: $(if($Verbose){'Enabled'}else{'Disabled'})" -ForegroundColor Cyan
    Write-Host "  • Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    
    # تنفيذ الاختبارات حسب الفئة
    switch ($TestCategory) {
        'all' {
            Test-Configuration
            Test-VMs
            Test-Master
            Test-Jobs
            Test-Health
        }
        'config' {
            Test-Configuration
        }
        'vms' {
            Test-VMs
        }
        'master' {
            Test-Master
        }
        'jobs' {
            Test-Jobs
        }
        'health' {
            Test-Health
        }
        'basic' {
            Test-Basic
        }
    }
    
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
    Write-Host "  • Skipped: $($global:TestResults.skippedTests)" -ForegroundColor Gray
    Write-Host "  • Pass Rate: $passRate%" -ForegroundColor $(if($passRate -eq 100){'Green'}elseif($passRate -ge 80){'Yellow'}else{'Red'})
    Write-Host "  • Duration: $([math]::Round($global:TestResults.duration, 2))s" -ForegroundColor Cyan
    
    if ($global:TestResults.failedTests -gt 0) {
        Write-Host "`n❌ Failed Tests:" -ForegroundColor Red
        $failedTests = $global:TestResults.tests | Where-Object { $_.status -eq 'failed' }
        foreach ($test in $failedTests) {
            Write-Host "  • $($test.name)" -ForegroundColor Red
            Write-Host "    Error: $($test.error)" -ForegroundColor Yellow
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
