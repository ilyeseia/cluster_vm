<#
.SYNOPSIS
    Automated Health Check System
.DESCRIPTION
    Comprehensive system health monitoring and diagnostics
.PARAMETER CheckType
    Type of check: full, quick, deep, specific
.EXAMPLE
    .\health-check-automation.ps1 -CheckType full
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('full','quick','deep','specific','continuous')]
    [string]$CheckType = 'full',
    
    [Parameter(Mandatory=$false)]
    [string]$Component = "",
    
    [Parameter(Mandatory=$false)]
    [int]$Interval = 60,
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$HEALTH_LOG_FILE = "logs/health-check-$(Get-Date -Format 'yyyyMMdd').log"
$HEALTH_REPORT_FILE = "results/health-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

# ═══════════════════════════════════════════════════════════════════════════
# دوال المساعدة
# ═══════════════════════════════════════════════════════════════════════════

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS','CRITICAL')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (!(Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    
    Add-Content -Path $HEALTH_LOG_FILE -Value $logMessage
    
    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        'CRITICAL' { 'Magenta' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Load-Config {
    $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
    return $config
}

function Load-VMsState {
    $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
    return $vmsState
}

function Test-SystemFiles {
    Write-Log "Checking system files..." -Level INFO
    
    $requiredFiles = @(
        ".github/system-config.json",
        ".github/example-vms-state.json",
        "scripts/vm-lifecycle-manager.ps1",
        "scripts/master-election-engine.ps1",
        "scripts/job-distribution-manager.ps1"
    )
    
    $results = @{
        passed = 0
        failed = 0
        missing = @()
    }
    
    Write-Host "`n📁 System Files Check:" -ForegroundColor Yellow
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            Write-Host "  ✓ $file" -ForegroundColor Green
            $results.passed++
        } else {
            Write-Host "  ✗ $file (MISSING)" -ForegroundColor Red
            $results.failed++
            $results.missing += $file
        }
    }
    
    return $results
}

function Test-Configuration {
    Write-Log "Validating configuration..." -Level INFO
    
    $results = @{
        passed = 0
        failed = 0
        issues = @()
    }
    
    Write-Host "`n⚙️  Configuration Check:" -ForegroundColor Yellow
    
    try {
        $config = Load-Config
        
        # التحقق من الحقول المطلوبة
        $requiredFields = @(
            'version',
            'vmConfig',
            'masterElection',
            'monitoring',
            'alerting'
        )
        
        foreach ($field in $requiredFields) {
            if ($config.PSObject.Properties.Name -contains $field) {
                Write-Host "  ✓ $field exists" -ForegroundColor Green
                $results.passed++
            } else {
                Write-Host "  ✗ $field missing" -ForegroundColor Red
                $results.failed++
                $results.issues += "$field is missing"
            }
        }
        
        # التحقق من القيم
        if ($config.vmConfig.desiredVmCount -lt 1 -or $config.vmConfig.desiredVmCount -gt 10) {
            Write-Host "  ⚠️  desiredVmCount should be between 1-10" -ForegroundColor Yellow
            $results.issues += "desiredVmCount out of range"
        }
        
        if ($config.vmConfig.vmLifetime -lt 60) {
            Write-Host "  ⚠️  vmLifetime should be at least 60 seconds" -ForegroundColor Yellow
            $results.issues += "vmLifetime too short"
        }
        
    } catch {
        Write-Host "  ✗ Configuration validation failed: $_" -ForegroundColor Red
        $results.failed++
        $results.issues += "Configuration validation error: $_"
    }
    
    return $results
}

function Test-VMsHealth {
    Write-Log "Checking VMs health..." -Level INFO
    
    $results = @{
        totalVMs = 0
        healthyVMs = 0
        degradedVMs = 0
        failedVMs = 0
        issues = @()
    }
    
    Write-Host "`n🖥️  VMs Health Check:" -ForegroundColor Yellow
    
    try {
        $vmsState = Load-VMsState
        $config = Load-Config
        
        $results.totalVMs = $vmsState.vms.Count
        
        foreach ($vm in $vmsState.vms) {
            $vmHealth = "healthy"
            $vmIssues = @()
            
            # التحقق من الحالة
            if ($vm.status -ne "running") {
                $vmHealth = "failed"
                $vmIssues += "VM not running"
            }
            
            # التحقق من الأداء
            if ($vm.performance.cpuUsage -gt $config.alerting.thresholds.cpu.critical) {
                $vmHealth = "degraded"
                $vmIssues += "Critical CPU usage: $($vm.performance.cpuUsage)%"
            } elseif ($vm.performance.cpuUsage -gt $config.alerting.thresholds.cpu.warning) {
                if ($vmHealth -eq "healthy") { $vmHealth = "degraded" }
                $vmIssues += "High CPU usage: $($vm.performance.cpuUsage)%"
            }
            
            if ($vm.performance.memoryUsage -gt $config.alerting.thresholds.memory.critical) {
                $vmHealth = "degraded"
                $vmIssues += "Critical memory usage: $($vm.performance.memoryUsage)%"
            } elseif ($vm.performance.memoryUsage -gt $config.alerting.thresholds.memory.warning) {
                if ($vmHealth -eq "healthy") { $vmHealth = "degraded" }
                $vmIssues += "High memory usage: $($vm.performance.memoryUsage)%"
            }
            
            # التحقق من الوقت المتبقي
            if ($vm.remainingTime -lt 60) {
                $vmIssues += "VM expiring soon: $($vm.remainingTime)s remaining"
            }
            
            # عرض النتائج
            $statusIcon = switch ($vmHealth) {
                "healthy" { "✓" }
                "degraded" { "⚠️" }
                "failed" { "✗" }
            }
            
            $statusColor = switch ($vmHealth) {
                "healthy" { "Green" }
                "degraded" { "Yellow" }
                "failed" { "Red" }
            }
            
            Write-Host "`n  $statusIcon VM: $($vm.vmId)" -ForegroundColor $statusColor
            Write-Host "    ├─ Status: $vmHealth" -ForegroundColor $statusColor
            Write-Host "    ├─ CPU: $($vm.performance.cpuUsage)%" -ForegroundColor Cyan
            Write-Host "    ├─ Memory: $($vm.performance.memoryUsage)%" -ForegroundColor Cyan
            Write-Host "    └─ Remaining: $($vm.remainingTime)s" -ForegroundColor Cyan
            
            if ($vmIssues.Count -gt 0) {
                Write-Host "    Issues:" -ForegroundColor Yellow
                foreach ($issue in $vmIssues) {
                    Write-Host "      • $issue" -ForegroundColor Yellow
                }
            }
            
            # تحديث الإحصائيات
            switch ($vmHealth) {
                "healthy" { $results.healthyVMs++ }
                "degraded" { $results.degradedVMs++ }
                "failed" { $results.failedVMs++ }
            }
      
